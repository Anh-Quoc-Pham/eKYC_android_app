from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
import json
import os
from typing import Any, Callable, Mapping

PLAY_INTEGRITY_SCOPE = "https://www.googleapis.com/auth/playintegrity"
PLAY_INTEGRITY_DECODE_ENDPOINT = (
    "https://playintegrity.googleapis.com/v1/{package_name}:decodeIntegrityToken"
)


class IntegrityVerifierMode(str, Enum):
    MOCK = "mock"
    GOOGLE = "google"


class IntegrityVerificationStatus(str, Enum):
    TRUSTED = "trusted"
    UNTRUSTED = "untrusted"
    UNAVAILABLE = "unavailable"
    INVALID = "invalid"
    TRANSIENT_ERROR = "transient_error"
    CONFIGURATION_ERROR = "configuration_error"


@dataclass(slots=True)
class IntegrityVerifierSettings:
    mode: IntegrityVerifierMode
    backend_env: str
    android_package_name: str
    credentials_file: str
    credentials_json: str
    request_timeout_seconds: float
    allow_basic_integrity: bool
    require_licensed_app: bool

    @classmethod
    def from_env(cls, env: Mapping[str, str] | None = None) -> "IntegrityVerifierSettings":
        resolved_env = env or os.environ

        mode_raw = resolved_env.get("EKYC_INTEGRITY_VERIFIER_MODE", "mock").strip().lower()
        if mode_raw == IntegrityVerifierMode.GOOGLE.value:
            mode = IntegrityVerifierMode.GOOGLE
        else:
            mode = IntegrityVerifierMode.MOCK

        backend_env = resolved_env.get("EKYC_BACKEND_ENV", "dev").strip().lower() or "dev"

        return cls(
            mode=mode,
            backend_env=backend_env,
            android_package_name=resolved_env.get(
                "EKYC_PLAY_INTEGRITY_ANDROID_PACKAGE",
                "",
            ).strip(),
            credentials_file=resolved_env.get(
                "EKYC_PLAY_INTEGRITY_CREDENTIALS_FILE",
                resolved_env.get("GOOGLE_APPLICATION_CREDENTIALS", ""),
            ).strip(),
            credentials_json=resolved_env.get(
                "EKYC_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON",
                "",
            ).strip(),
            request_timeout_seconds=_safe_float(
                resolved_env.get("EKYC_PLAY_INTEGRITY_TIMEOUT_SECONDS", "8.0"),
                fallback=8.0,
            ),
            allow_basic_integrity=_parse_bool(
                resolved_env.get("EKYC_PLAY_INTEGRITY_ALLOW_BASIC_INTEGRITY", "false"),
                default=False,
            ),
            require_licensed_app=_parse_bool(
                resolved_env.get("EKYC_PLAY_INTEGRITY_REQUIRE_LICENSED_APP", "true"),
                default=True,
            ),
        )


@dataclass(slots=True)
class IntegrityVerificationResult:
    status: IntegrityVerificationStatus
    detail: str
    mode: IntegrityVerifierMode
    provider: str = "play_integrity_server"
    retryable: bool = False
    token_present: bool = False
    error_code: str = ""
    score: float | None = None
    app_recognition_verdict: str = ""
    device_recognition_verdicts: list[str] = field(default_factory=list)
    licensing_verdict: str = ""
    request_hash: str = ""
    request_package_name: str = ""

    def to_device_trust_signal(self) -> dict[str, Any]:
        if self.status == IntegrityVerificationStatus.TRUSTED:
            mapped_status = "trusted"
        elif self.status in {
            IntegrityVerificationStatus.UNTRUSTED,
            IntegrityVerificationStatus.INVALID,
        }:
            mapped_status = "low"
        else:
            mapped_status = "unavailable"

        return {
            "status": mapped_status,
            "score": self.score,
            "provider": self.provider,
            "detail": self.detail,
            "verification_status": self.status.value,
            "verifier_mode": self.mode.value,
            "retryable": self.retryable,
            "token_present": self.token_present,
            "error_code": self.error_code,
            "app_recognition_verdict": self.app_recognition_verdict,
            "device_recognition_verdicts": self.device_recognition_verdicts,
            "licensing_verdict": self.licensing_verdict,
            "request_hash": self.request_hash,
            "request_package_name": self.request_package_name,
        }


class _IntegrityConfigurationError(RuntimeError):
    pass


class _IntegrityTransientError(RuntimeError):
    pass


class _IntegrityInvalidError(RuntimeError):
    pass


def verify_play_integrity(
    *,
    evidence: Mapping[str, Any] | None,
    correlation_id: str,
    expected_request_hash: str,
    settings: IntegrityVerifierSettings | None = None,
    decoder: Callable[[str, IntegrityVerifierSettings], Mapping[str, Any]] | None = None,
) -> IntegrityVerificationResult:
    del correlation_id  # correlation_id is handled at caller log layer.

    active_settings = settings or IntegrityVerifierSettings.from_env()
    token = _read_token(evidence)

    if (
        active_settings.backend_env != "dev"
        and active_settings.mode == IntegrityVerifierMode.MOCK
    ):
        return IntegrityVerificationResult(
            status=IntegrityVerificationStatus.CONFIGURATION_ERROR,
            detail="mock_mode_not_allowed_in_non_dev",
            mode=active_settings.mode,
            retryable=False,
            token_present=bool(token),
        )

    if active_settings.mode == IntegrityVerifierMode.MOCK:
        return _verify_mock(
            evidence=evidence,
            token=token,
            mode=active_settings.mode,
        )

    return _verify_google(
        evidence=evidence,
        token=token,
        expected_request_hash=expected_request_hash,
        settings=active_settings,
        decoder=decoder,
    )


def _verify_mock(
    *,
    evidence: Mapping[str, Any] | None,
    token: str,
    mode: IntegrityVerifierMode,
) -> IntegrityVerificationResult:
    mock_verdict = str((evidence or {}).get("mock_verdict", "")).strip().lower()
    status_hint = str((evidence or {}).get("status", "")).strip().lower()

    if token.startswith("mock_trusted") or mock_verdict == "trusted" or status_hint == "trusted":
        return IntegrityVerificationResult(
            status=IntegrityVerificationStatus.TRUSTED,
            detail="mock_trusted",
            mode=mode,
            score=0.95,
            token_present=bool(token),
            app_recognition_verdict="PLAY_RECOGNIZED",
            device_recognition_verdicts=["MEETS_DEVICE_INTEGRITY"],
            licensing_verdict="LICENSED",
        )

    if token.startswith("mock_untrusted") or mock_verdict == "untrusted" or status_hint == "low":
        return IntegrityVerificationResult(
            status=IntegrityVerificationStatus.UNTRUSTED,
            detail="mock_untrusted",
            mode=mode,
            score=0.25,
            token_present=bool(token),
            app_recognition_verdict="UNRECOGNIZED_VERSION",
            device_recognition_verdicts=[],
            licensing_verdict="UNLICENSED",
        )

    if token.startswith("mock_invalid") or mock_verdict == "invalid":
        return IntegrityVerificationResult(
            status=IntegrityVerificationStatus.INVALID,
            detail="mock_invalid_token",
            mode=mode,
            retryable=False,
            token_present=bool(token),
        )

    if token.startswith("mock_transient") or mock_verdict == "transient_error":
        return IntegrityVerificationResult(
            status=IntegrityVerificationStatus.TRANSIENT_ERROR,
            detail="mock_transient_error",
            mode=mode,
            retryable=True,
            token_present=bool(token),
        )

    if token.startswith("mock_config") or mock_verdict == "configuration_error":
        return IntegrityVerificationResult(
            status=IntegrityVerificationStatus.CONFIGURATION_ERROR,
            detail="mock_configuration_error",
            mode=mode,
            retryable=False,
            token_present=bool(token),
        )

    if status_hint == "unavailable":
        return IntegrityVerificationResult(
            status=IntegrityVerificationStatus.UNAVAILABLE,
            detail="mock_client_unavailable",
            mode=mode,
            retryable=False,
            token_present=bool(token),
        )

    return IntegrityVerificationResult(
        status=IntegrityVerificationStatus.UNAVAILABLE,
        detail="mock_token_missing",
        mode=mode,
        retryable=False,
        token_present=bool(token),
    )


def _verify_google(
    *,
    evidence: Mapping[str, Any] | None,
    token: str,
    expected_request_hash: str,
    settings: IntegrityVerifierSettings,
    decoder: Callable[[str, IntegrityVerifierSettings], Mapping[str, Any]] | None,
) -> IntegrityVerificationResult:
    if settings.android_package_name == "":
        return IntegrityVerificationResult(
            status=IntegrityVerificationStatus.CONFIGURATION_ERROR,
            detail="android_package_name_missing",
            mode=settings.mode,
            retryable=False,
            token_present=bool(token),
        )

    if token == "":
        category = str((evidence or {}).get("error_category", "")).strip().lower()
        if category == "transient_error":
            return IntegrityVerificationResult(
                status=IntegrityVerificationStatus.TRANSIENT_ERROR,
                detail="token_not_acquired_transient",
                mode=settings.mode,
                retryable=True,
                token_present=False,
                error_code=str((evidence or {}).get("error_code", "")).strip(),
            )
        if category == "configuration_error":
            return IntegrityVerificationResult(
                status=IntegrityVerificationStatus.CONFIGURATION_ERROR,
                detail="token_not_acquired_configuration",
                mode=settings.mode,
                retryable=False,
                token_present=False,
                error_code=str((evidence or {}).get("error_code", "")).strip(),
            )
        return IntegrityVerificationResult(
            status=IntegrityVerificationStatus.UNAVAILABLE,
            detail="token_missing",
            mode=settings.mode,
            retryable=False,
            token_present=False,
        )

    decode_fn = decoder or _decode_with_google_api

    try:
        decoded = decode_fn(token, settings)
    except _IntegrityInvalidError as error:
        return IntegrityVerificationResult(
            status=IntegrityVerificationStatus.INVALID,
            detail=str(error),
            mode=settings.mode,
            retryable=False,
            token_present=True,
        )
    except _IntegrityConfigurationError as error:
        return IntegrityVerificationResult(
            status=IntegrityVerificationStatus.CONFIGURATION_ERROR,
            detail=str(error),
            mode=settings.mode,
            retryable=False,
            token_present=True,
        )
    except _IntegrityTransientError as error:
        return IntegrityVerificationResult(
            status=IntegrityVerificationStatus.TRANSIENT_ERROR,
            detail=str(error),
            mode=settings.mode,
            retryable=True,
            token_present=True,
        )
    except Exception:
        return IntegrityVerificationResult(
            status=IntegrityVerificationStatus.TRANSIENT_ERROR,
            detail="integrity_decoder_unexpected_error",
            mode=settings.mode,
            retryable=True,
            token_present=True,
        )

    token_payload = decoded.get("tokenPayloadExternal")
    if isinstance(token_payload, Mapping):
        payload_external: Mapping[str, Any] = token_payload
    else:
        payload_external = decoded

    request_details = payload_external.get("requestDetails", {})
    request_hash = str(
        request_details.get("requestHash", ""),
    ).strip()
    request_package_name = str(
        request_details.get("requestPackageName", ""),
    ).strip()

    if request_package_name == "":
        return IntegrityVerificationResult(
            status=IntegrityVerificationStatus.INVALID,
            detail="request_package_missing",
            mode=settings.mode,
            retryable=False,
            token_present=True,
            request_hash=request_hash,
            request_package_name=request_package_name,
        )

    if request_package_name != settings.android_package_name:
        return IntegrityVerificationResult(
            status=IntegrityVerificationStatus.INVALID,
            detail="request_package_mismatch",
            mode=settings.mode,
            retryable=False,
            token_present=True,
            request_hash=request_hash,
            request_package_name=request_package_name,
        )

    if request_hash == "":
        return IntegrityVerificationResult(
            status=IntegrityVerificationStatus.INVALID,
            detail="request_hash_missing",
            mode=settings.mode,
            retryable=False,
            token_present=True,
            request_hash=request_hash,
            request_package_name=request_package_name,
        )

    if request_hash != expected_request_hash:
        return IntegrityVerificationResult(
            status=IntegrityVerificationStatus.INVALID,
            detail="request_hash_mismatch",
            mode=settings.mode,
            retryable=False,
            token_present=True,
            request_hash=request_hash,
            request_package_name=request_package_name,
        )

    app_integrity = payload_external.get("appIntegrity", {})
    app_recognition_verdict = str(
        app_integrity.get("appRecognitionVerdict", ""),
    ).strip()

    device_integrity = payload_external.get("deviceIntegrity", {})
    device_recognition_verdicts_raw = device_integrity.get("deviceRecognitionVerdict", [])
    if isinstance(device_recognition_verdicts_raw, list):
        device_recognition_verdicts = [str(item) for item in device_recognition_verdicts_raw]
    else:
        device_recognition_verdicts = []

    account_details = payload_external.get("accountDetails", {})
    licensing_verdict = str(account_details.get("appLicensingVerdict", "")).strip()

    if app_recognition_verdict != "PLAY_RECOGNIZED":
        return IntegrityVerificationResult(
            status=IntegrityVerificationStatus.UNTRUSTED,
            detail="app_not_play_recognized",
            mode=settings.mode,
            retryable=False,
            token_present=True,
            score=0.15,
            app_recognition_verdict=app_recognition_verdict,
            device_recognition_verdicts=device_recognition_verdicts,
            licensing_verdict=licensing_verdict,
            request_hash=request_hash,
            request_package_name=request_package_name,
        )

    if settings.require_licensed_app and licensing_verdict not in {"", "LICENSED"}:
        return IntegrityVerificationResult(
            status=IntegrityVerificationStatus.UNTRUSTED,
            detail="app_not_licensed",
            mode=settings.mode,
            retryable=False,
            token_present=True,
            score=0.15,
            app_recognition_verdict=app_recognition_verdict,
            device_recognition_verdicts=device_recognition_verdicts,
            licensing_verdict=licensing_verdict,
            request_hash=request_hash,
            request_package_name=request_package_name,
        )

    allowed_device_verdicts = {
        "MEETS_DEVICE_INTEGRITY",
        "MEETS_STRONG_INTEGRITY",
    }
    if settings.allow_basic_integrity:
        allowed_device_verdicts.add("MEETS_BASIC_INTEGRITY")

    if not any(verdict in allowed_device_verdicts for verdict in device_recognition_verdicts):
        return IntegrityVerificationResult(
            status=IntegrityVerificationStatus.UNTRUSTED,
            detail="device_integrity_requirements_not_met",
            mode=settings.mode,
            retryable=False,
            token_present=True,
            score=0.20,
            app_recognition_verdict=app_recognition_verdict,
            device_recognition_verdicts=device_recognition_verdicts,
            licensing_verdict=licensing_verdict,
            request_hash=request_hash,
            request_package_name=request_package_name,
        )

    return IntegrityVerificationResult(
        status=IntegrityVerificationStatus.TRUSTED,
        detail="integrity_verified",
        mode=settings.mode,
        retryable=False,
        token_present=True,
        score=0.95,
        app_recognition_verdict=app_recognition_verdict,
        device_recognition_verdicts=device_recognition_verdicts,
        licensing_verdict=licensing_verdict,
        request_hash=request_hash,
        request_package_name=request_package_name,
    )


def _decode_with_google_api(token: str, settings: IntegrityVerifierSettings) -> Mapping[str, Any]:
    import requests

    credentials = _resolve_google_credentials(settings)

    endpoint = PLAY_INTEGRITY_DECODE_ENDPOINT.format(
        package_name=settings.android_package_name,
    )

    response = requests.post(
        endpoint,
        json={"integrity_token": token},
        headers={
            "Authorization": f"Bearer {credentials.token}",
            "Content-Type": "application/json",
        },
        timeout=settings.request_timeout_seconds,
    )

    if response.status_code == 400:
        raise _IntegrityInvalidError("integrity_token_invalid")

    if response.status_code in {401, 403, 404}:
        raise _IntegrityConfigurationError("integrity_verifier_permission_or_config_invalid")

    if response.status_code in {408, 409, 429, 500, 502, 503, 504}:
        raise _IntegrityTransientError("integrity_service_temporarily_unavailable")

    if response.status_code < 200 or response.status_code >= 300:
        raise _IntegrityTransientError("integrity_service_unexpected_status")

    try:
        decoded = response.json()
    except ValueError as error:
        raise _IntegrityTransientError("integrity_decode_response_not_json") from error

    if not isinstance(decoded, Mapping):
        raise _IntegrityTransientError("integrity_decode_response_invalid")

    return decoded


def _resolve_google_credentials(settings: IntegrityVerifierSettings):
    try:
        from google.auth.transport.requests import Request
        from google.oauth2 import service_account
    except ImportError as error:
        raise _IntegrityConfigurationError("google_auth_dependency_missing") from error

    credentials = None
    if settings.credentials_json:
        try:
            service_account_info = json.loads(settings.credentials_json)
        except ValueError as error:
            raise _IntegrityConfigurationError("service_account_json_invalid") from error

        credentials = service_account.Credentials.from_service_account_info(
            service_account_info,
            scopes=[PLAY_INTEGRITY_SCOPE],
        )
    elif settings.credentials_file:
        credentials = service_account.Credentials.from_service_account_file(
            settings.credentials_file,
            scopes=[PLAY_INTEGRITY_SCOPE],
        )
    else:
        raise _IntegrityConfigurationError("service_account_credentials_missing")

    try:
        credentials.refresh(Request())
    except Exception as error:  # noqa: BLE001
        raise _IntegrityConfigurationError("service_account_refresh_failed") from error

    return credentials


def _read_token(evidence: Mapping[str, Any] | None) -> str:
    if evidence is None:
        return ""

    raw = evidence.get("integrity_token")
    if raw is None:
        return ""

    return str(raw).strip()


def _safe_float(raw: str, *, fallback: float) -> float:
    try:
        return float(raw)
    except (TypeError, ValueError):
        return fallback


def _parse_bool(raw: str, *, default: bool) -> bool:
    normalized = raw.strip().lower()
    if normalized in {"1", "true", "yes", "on"}:
        return True
    if normalized in {"0", "false", "no", "off"}:
        return False
    return default
