import 'package:flutter/services.dart';

import '../config/app_config.dart';
import '../models/decision_models.dart';

abstract class DeviceTrustProvider {
  Future<DeviceTrustSignal> evaluate({required String requestHash});
}

class DeviceTrustService {
  DeviceTrustService({
    DeviceTrustProvider? devProvider,
    DeviceTrustProvider? productionProvider,
  }) : _devProvider = devProvider,
       _productionProvider = productionProvider;

  final DeviceTrustProvider? _devProvider;
  final DeviceTrustProvider? _productionProvider;

  Future<DeviceTrustSignal> evaluate({required String requestHash}) async {
    if (AppConfig.environment == AppEnvironment.dev) {
      final provider =
          _devProvider ??
          MockDeviceTrustProvider(mode: AppConfig.deviceTrustMode);
      return _safeEvaluate(
        provider,
        providerLabel: 'dev_mock',
        requestHash: requestHash,
      );
    }

    final provider = _productionProvider ?? _resolveProductionProvider();
    return _safeEvaluate(
      provider,
      providerLabel: 'prod_play_integrity',
      requestHash: requestHash,
    );
  }

  DeviceTrustProvider _resolveProductionProvider() {
    if (!AppConfig.shouldUseRealPlayIntegrity) {
      return const PlayIntegrityScaffoldProvider(
        reason: 'play_integrity_disabled_by_config',
      );
    }

    final cloudProjectNumber = AppConfig.playIntegrityCloudProjectNumber;
    if (cloudProjectNumber == null) {
      return const PlayIntegrityScaffoldProvider(
        reason: 'play_integrity_project_number_missing',
      );
    }

    return PlayIntegrityMethodChannelProvider(
      cloudProjectNumber: cloudProjectNumber,
      channelName: AppConfig.playIntegrityChannel,
    );
  }

  Future<DeviceTrustSignal> _safeEvaluate(
    DeviceTrustProvider provider, {
    required String providerLabel,
    required String requestHash,
  }) async {
    try {
      return await provider.evaluate(requestHash: requestHash);
    } catch (_) {
      return DeviceTrustSignal(
        status: DeviceTrustStatus.unavailable,
        provider: providerLabel,
        detail: 'provider_error_fallback',
        requestHash: requestHash,
        errorCategory: 'unexpected_error',
      );
    }
  }
}

class MockDeviceTrustProvider implements DeviceTrustProvider {
  const MockDeviceTrustProvider({required this.mode});

  final String mode;

  @override
  Future<DeviceTrustSignal> evaluate({required String requestHash}) async {
    switch (mode) {
      case 'mock_trusted':
        return DeviceTrustSignal(
          status: DeviceTrustStatus.trusted,
          score: 0.95,
          provider: 'mock',
          detail: 'mock_trusted_for_dev',
          integrityToken: 'mock_trusted_token',
          requestHash: requestHash,
          tokenSource: 'mock',
        );
      case 'mock_low':
        return DeviceTrustSignal(
          status: DeviceTrustStatus.low,
          score: 0.35,
          provider: 'mock',
          detail: 'mock_low_for_dev',
          integrityToken: 'mock_untrusted_token',
          requestHash: requestHash,
          tokenSource: 'mock',
        );
      case 'mock_unavailable':
      default:
        return DeviceTrustSignal(
          status: DeviceTrustStatus.unavailable,
          provider: 'mock',
          detail: 'mock_unavailable_for_dev',
          requestHash: requestHash,
          errorCategory: 'configuration_error',
        );
    }
  }
}

class PlayIntegrityScaffoldProvider implements DeviceTrustProvider {
  const PlayIntegrityScaffoldProvider({
    this.reason = 'integration_not_configured',
  });

  final String reason;

  @override
  Future<DeviceTrustSignal> evaluate({required String requestHash}) async {
    return DeviceTrustSignal(
      status: DeviceTrustStatus.unavailable,
      provider: 'play_integrity_scaffold',
      detail: reason,
      requestHash: requestHash,
      errorCategory: 'configuration_error',
      retryable: false,
    );
  }
}

class PlayIntegrityMethodChannelProvider implements DeviceTrustProvider {
  PlayIntegrityMethodChannelProvider({
    required this.cloudProjectNumber,
    required this.channelName,
    MethodChannel? methodChannel,
  }) : _methodChannel = methodChannel ?? MethodChannel(channelName);

  final int cloudProjectNumber;
  final String channelName;
  final MethodChannel _methodChannel;

  bool _prepared = false;

  @override
  Future<DeviceTrustSignal> evaluate({required String requestHash}) async {
    if (requestHash.trim().isEmpty) {
      return DeviceTrustSignal(
        status: DeviceTrustStatus.unavailable,
        provider: 'play_integrity_native',
        detail: 'request_hash_missing',
        errorCategory: 'configuration_error',
        retryable: false,
      );
    }

    final prepareResult = await _prepareIfNeeded();
    if (!prepareResult.ok) {
      return _mapFailure(
        requestHash: requestHash,
        detailOverride: prepareResult.detail,
        categoryOverride: prepareResult.errorCategory,
        retryable: prepareResult.retryable,
        errorCode: prepareResult.errorCode,
      );
    }

    final response = await _invoke(
      method: 'requestToken',
      arguments: {
        'cloudProjectNumber': cloudProjectNumber,
        'requestHash': requestHash,
      },
    );

    if (!response.ok) {
      _prepared = false;
      return _mapFailure(
        requestHash: requestHash,
        detailOverride: response.detail,
        categoryOverride: response.errorCategory,
        retryable: response.retryable,
        errorCode: response.errorCode,
      );
    }

    final token = response.token;
    if (token.isEmpty) {
      return _mapFailure(
        requestHash: requestHash,
        detailOverride: 'token_missing_from_native_response',
        categoryOverride: 'unexpected_error',
        retryable: true,
      );
    }

    return DeviceTrustSignal(
      status: DeviceTrustStatus.unknown,
      provider: 'play_integrity_native',
      detail: 'token_acquired_pending_server_verification',
      integrityToken: token,
      requestHash: requestHash,
      tokenSource: 'play_integrity_standard',
      retryable: false,
    );
  }

  Future<_NativePlayIntegrityResult> _prepareIfNeeded() async {
    if (_prepared) {
      return const _NativePlayIntegrityResult(ok: true);
    }

    final response = await _invoke(
      method: 'prepareProvider',
      arguments: {'cloudProjectNumber': cloudProjectNumber},
    );
    if (response.ok) {
      _prepared = true;
    }

    return response;
  }

  Future<_NativePlayIntegrityResult> _invoke({
    required String method,
    required Map<String, dynamic> arguments,
  }) async {
    try {
      final raw = await _methodChannel.invokeMethod<dynamic>(method, arguments);
      if (raw is! Map) {
        return const _NativePlayIntegrityResult(
          ok: false,
          detail: 'native_invalid_response',
          errorCategory: 'unexpected_error',
          retryable: true,
        );
      }

      final data = raw.map((key, value) => MapEntry(key.toString(), value));

      return _NativePlayIntegrityResult(
        ok: data['ok'] == true,
        token: data['token']?.toString() ?? '',
        detail: data['detail']?.toString() ?? '',
        errorCategory: data['errorCategory']?.toString() ?? '',
        errorCode: data['errorCode']?.toString() ?? '',
        retryable: data['retryable'] == true,
      );
    } on PlatformException catch (error) {
      return _NativePlayIntegrityResult(
        ok: false,
        detail: error.message ?? 'native_platform_exception',
        errorCategory: 'unexpected_error',
        errorCode: error.code,
        retryable: true,
      );
    }
  }

  DeviceTrustSignal _mapFailure({
    required String requestHash,
    required String detailOverride,
    required String categoryOverride,
    required bool retryable,
    String errorCode = '',
  }) {
    return DeviceTrustSignal(
      status: DeviceTrustStatus.unavailable,
      provider: 'play_integrity_native',
      detail: detailOverride.isEmpty
          ? 'play_integrity_request_failed'
          : detailOverride,
      requestHash: requestHash,
      errorCategory: categoryOverride.isEmpty
          ? 'unexpected_error'
          : categoryOverride,
      errorCode: errorCode.isEmpty ? null : errorCode,
      retryable: retryable,
    );
  }
}

class _NativePlayIntegrityResult {
  const _NativePlayIntegrityResult({
    required this.ok,
    this.token = '',
    this.detail = '',
    this.errorCategory = '',
    this.errorCode = '',
    this.retryable = false,
  });

  final bool ok;
  final String token;
  final String detail;
  final String errorCategory;
  final String errorCode;
  final bool retryable;
}
