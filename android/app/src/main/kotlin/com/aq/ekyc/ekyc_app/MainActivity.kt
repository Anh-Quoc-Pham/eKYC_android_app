package com.aq.ekyc.ekyc_app

import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.IntegrityServiceException
import com.google.android.play.core.integrity.StandardIntegrityManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	companion object {
		private const val CHANNEL_NAME = "ekyc/play_integrity"
	}

	private var tokenProvider: StandardIntegrityManager.StandardIntegrityTokenProvider? = null
	private var preparedProjectNumber: Long? = null

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"prepareProvider" -> handlePrepareProvider(call, result)
					"requestToken" -> handleRequestToken(call, result)
					else -> result.notImplemented()
				}
			}
	}

	private fun handlePrepareProvider(call: MethodCall, result: MethodChannel.Result) {
		val cloudProjectNumber = readCloudProjectNumber(call)
		if (cloudProjectNumber == null) {
			result.success(
				failurePayload(
					detail = "cloud_project_number_missing_or_invalid",
					errorCategory = "configuration_error",
					retryable = false,
				)
			)
			return
		}

		prepareProvider(
			cloudProjectNumber = cloudProjectNumber,
			onSuccess = {
				result.success(
					mapOf(
						"ok" to true,
						"detail" to "provider_prepared",
					)
				)
			},
			onFailure = { error ->
				result.success(mapIntegrityException(error))
			},
		)
	}

	private fun handleRequestToken(call: MethodCall, result: MethodChannel.Result) {
		val cloudProjectNumber = readCloudProjectNumber(call)
		if (cloudProjectNumber == null) {
			result.success(
				failurePayload(
					detail = "cloud_project_number_missing_or_invalid",
					errorCategory = "configuration_error",
					retryable = false,
				)
			)
			return
		}

		val requestHash = call.argument<String>("requestHash")?.trim().orEmpty()
		if (requestHash.isEmpty()) {
			result.success(
				failurePayload(
					detail = "request_hash_missing",
					errorCategory = "configuration_error",
					retryable = false,
				)
			)
			return
		}

		val existingProvider = tokenProvider
		if (existingProvider != null && preparedProjectNumber == cloudProjectNumber) {
			requestToken(existingProvider, requestHash, result)
			return
		}

		prepareProvider(
			cloudProjectNumber = cloudProjectNumber,
			onSuccess = {
				val preparedProvider = tokenProvider
				if (preparedProvider == null) {
					result.success(
						failurePayload(
							detail = "provider_not_ready",
							errorCategory = "provider_invalid",
							retryable = true,
						)
					)
					return@prepareProvider
				}

				requestToken(preparedProvider, requestHash, result)
			},
			onFailure = { error ->
				result.success(mapIntegrityException(error))
			},
		)
	}

	private fun prepareProvider(
		cloudProjectNumber: Long,
		onSuccess: () -> Unit,
		onFailure: (Exception) -> Unit,
	) {
		val standardIntegrityManager = IntegrityManagerFactory.createStandard(applicationContext)
		val request =
			StandardIntegrityManager.PrepareIntegrityTokenRequest.builder()
				.setCloudProjectNumber(cloudProjectNumber)
				.build()

		standardIntegrityManager.prepareIntegrityToken(request)
			.addOnSuccessListener { provider ->
				tokenProvider = provider
				preparedProjectNumber = cloudProjectNumber
				onSuccess()
			}
			.addOnFailureListener { error ->
				tokenProvider = null
				preparedProjectNumber = null
				onFailure(error as? Exception ?: Exception(error.toString()))
			}
	}

	private fun requestToken(
		provider: StandardIntegrityManager.StandardIntegrityTokenProvider,
		requestHash: String,
		result: MethodChannel.Result,
	) {
		val request =
			StandardIntegrityManager.StandardIntegrityTokenRequest.builder()
				.setRequestHash(requestHash)
				.build()

		provider.request(request)
			.addOnSuccessListener { tokenResponse ->
				result.success(
					mapOf(
						"ok" to true,
						"token" to tokenResponse.token(),
						"detail" to "token_issued",
					)
				)
			}
			.addOnFailureListener { error ->
				tokenProvider = null
				preparedProjectNumber = null
				result.success(mapIntegrityException(error as? Exception ?: Exception(error.toString())))
			}
	}

	private fun readCloudProjectNumber(call: MethodCall): Long? {
		val raw = call.argument<Number>("cloudProjectNumber") ?: return null
		val parsed = raw.toLong()
		return if (parsed > 0L) parsed else null
	}

	private fun mapIntegrityException(error: Exception): Map<String, Any> {
		if (error is IntegrityServiceException) {
			val code = error.errorCode

			val (category, retryable, detail) = when (code) {
				-1, -2, -6, -7, -9 -> Triple("play_services_unavailable", false, "play_services_or_store_unavailable")
				-3, -8, -12, -17, -18 -> Triple("transient_error", true, "transient_integrity_error")
				-10, -11, -13, -14, -15 -> Triple("configuration_error", false, "integrity_configuration_invalid")
				-16 -> Triple("provider_invalid", true, "integrity_provider_invalidated")
				else -> Triple("unexpected_error", true, "integrity_unexpected_failure")
			}

			return failurePayload(
				detail = detail,
				errorCategory = category,
				retryable = retryable,
				errorCode = code.toString(),
			)
		}

		return failurePayload(
			detail = "integrity_runtime_exception",
			errorCategory = "unexpected_error",
			retryable = true,
		)
	}

	private fun failurePayload(
		detail: String,
		errorCategory: String,
		retryable: Boolean,
		errorCode: String = "",
	): Map<String, Any> {
		return mapOf(
			"ok" to false,
			"detail" to detail,
			"errorCategory" to errorCategory,
			"retryable" to retryable,
			"errorCode" to errorCode,
		)
	}
}
