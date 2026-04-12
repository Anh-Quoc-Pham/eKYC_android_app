from __future__ import annotations

from collections import defaultdict, deque
from contextlib import asynccontextmanager
from dataclasses import dataclass
import hashlib
import logging
import os
import secrets
import sqlite3
import time
from pathlib import Path
from threading import Lock
from typing import Any, Mapping
import uuid

from fastapi import FastAPI, HTTPException, Request, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from starlette.responses import JSONResponse

from audit_logging import log_audit_event
from decision_engine import evaluate_decision, rate_limited_decision
from integrity_verifier import (
    IntegrityVerifierMode,
    IntegrityVerifierSettings,
    verify_play_integrity,
)

# RFC 3526 - 2048-bit MODP Group prime.
_P_HEX = (
    "FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E08"
    "8A67CC74020BBEA63B139B22514A08798E3404DDEF9519B3CD"
    "3A431B302B0A6DF25F14374FE1356D6D51C245E485B576625E"
    "7EC6F44C42E9A637ED6B0BFF5CB6F406B7EDEE386BFB5A899F"
    "A5AE9F24117C4B1FE649286651ECE45B3DC2007CB8A163BF05"
    "98DA48361C55D39A69163FA8FD24CF5F83655D23DCA3AD961C"
    "62F356208552BB9ED529077096966D670C354E4ABC9804F174"
    "6C08CA18217C32905E462E36CE3BE39E772C180E86039B2783"
    "A2EC07A28FB5C55DF06F4C52C9DE2BCBF6955817183995497C"
    "EA956AE515D2261898FA051015728E5A8AACAA68FFFFFFFFFFFFFFFF"
)

P = int(_P_HEX, 16)
Q = (P - 1) // 2
G = 4

DB_PATH = Path(__file__).resolve().parent / "ekyc_phase3.db"

ENROLL_RATE_LIMIT_MAX_REQUESTS = 20
ENROLL_RATE_LIMIT_WINDOW_SECONDS = 60
VERIFY_RATE_LIMIT_MAX_REQUESTS = 30
VERIFY_RATE_LIMIT_WINDOW_SECONDS = 60
_SENSITIVE_PATHS = {"/enroll", "/verify"}
_DEFAULT_DEV_ALLOWED_ORIGINS = [
    "http://localhost",
    "http://127.0.0.1",
    "http://localhost:3000",
    "http://127.0.0.1:3000",
]

_service_logger = logging.getLogger("ekyc.service")
if not _service_logger.handlers:
    _service_handler = logging.StreamHandler()
    _service_handler.setFormatter(
        logging.Formatter("%(asctime)s %(levelname)s %(message)s")
    )
    _service_logger.addHandler(_service_handler)
_service_logger.setLevel(logging.INFO)
_service_logger.propagate = False

_verify_rate_buckets: dict[str, deque[float]] = defaultdict(deque)
_verify_rate_lock = Lock()


@dataclass(slots=True)
class ServiceSecuritySettings:
    backend_env: str
    auth_mode: str
    client_api_key: str
    client_bearer_token: str
    allow_insecure_no_auth_in_non_dev: bool
    allowed_origins: list[str]
    cors_allow_credentials: bool
    enroll_rate_limit_max_requests: int
    enroll_rate_limit_window_seconds: int
    verify_rate_limit_max_requests: int
    verify_rate_limit_window_seconds: int

    @classmethod
    def from_env(cls, env: Mapping[str, str] | None = None) -> "ServiceSecuritySettings":
        resolved_env = env or os.environ
        backend_env = resolved_env.get("EKYC_BACKEND_ENV", "dev").strip().lower() or "dev"
        default_auth_mode = "disabled" if backend_env == "dev" else "api_key"
        auth_mode = _normalize_auth_mode(
            resolved_env.get("EKYC_CLIENT_AUTH_MODE", default_auth_mode),
            default_value=default_auth_mode,
        )

        allowed_origins = _parse_allowed_origins(
            resolved_env.get("EKYC_ALLOWED_ORIGINS", ""),
            backend_env=backend_env,
        )

        return cls(
            backend_env=backend_env,
            auth_mode=auth_mode,
            client_api_key=resolved_env.get("EKYC_CLIENT_API_KEY", "").strip(),
            client_bearer_token=resolved_env.get("EKYC_CLIENT_BEARER_TOKEN", "").strip(),
            allow_insecure_no_auth_in_non_dev=_parse_bool(
                resolved_env.get("EKYC_ALLOW_INSECURE_NO_AUTH_IN_NON_DEV", "false"),
                default=False,
            ),
            allowed_origins=allowed_origins,
            cors_allow_credentials=_parse_bool(
                resolved_env.get("EKYC_CORS_ALLOW_CREDENTIALS", "false"),
                default=False,
            ),
            enroll_rate_limit_max_requests=_parse_positive_env_int(
                resolved_env.get(
                    "EKYC_RATE_LIMIT_ENROLL_MAX_REQUESTS",
                    str(ENROLL_RATE_LIMIT_MAX_REQUESTS),
                ),
                default=ENROLL_RATE_LIMIT_MAX_REQUESTS,
            ),
            enroll_rate_limit_window_seconds=_parse_positive_env_int(
                resolved_env.get(
                    "EKYC_RATE_LIMIT_ENROLL_WINDOW_SECONDS",
                    str(ENROLL_RATE_LIMIT_WINDOW_SECONDS),
                ),
                default=ENROLL_RATE_LIMIT_WINDOW_SECONDS,
            ),
            verify_rate_limit_max_requests=_parse_positive_env_int(
                resolved_env.get(
                    "EKYC_RATE_LIMIT_VERIFY_MAX_REQUESTS",
                    str(VERIFY_RATE_LIMIT_MAX_REQUESTS),
                ),
                default=VERIFY_RATE_LIMIT_MAX_REQUESTS,
            ),
            verify_rate_limit_window_seconds=_parse_positive_env_int(
                resolved_env.get(
                    "EKYC_RATE_LIMIT_VERIFY_WINDOW_SECONDS",
                    str(VERIFY_RATE_LIMIT_WINDOW_SECONDS),
                ),
                default=VERIFY_RATE_LIMIT_WINDOW_SECONDS,
            ),
        )


def _parse_bool(raw: str, *, default: bool) -> bool:
    normalized = raw.strip().lower()
    if normalized in {"1", "true", "yes", "on"}:
        return True
    if normalized in {"0", "false", "no", "off"}:
        return False
    return default


def _parse_positive_env_int(raw: str, *, default: int) -> int:
    try:
        parsed = int(raw)
    except (TypeError, ValueError):
        return default
    return parsed if parsed > 0 else default


def _normalize_auth_mode(raw: str, *, default_value: str) -> str:
    normalized = raw.strip().lower()
    if normalized in {"disabled", "api_key", "bearer", "either"}:
        return normalized
    return default_value


def _parse_allowed_origins(raw: str, *, backend_env: str) -> list[str]:
    origins = [item.strip() for item in raw.split(",") if item.strip()]

    if not origins:
        if backend_env == "dev":
            return _DEFAULT_DEV_ALLOWED_ORIGINS.copy()
        return []

    if backend_env != "dev" and "*" in origins:
        return []

    return origins


def _get_service_security_settings() -> ServiceSecuritySettings:
    return ServiceSecuritySettings.from_env()


@asynccontextmanager
async def lifespan(_: FastAPI):
    _init_db()
    yield


app = FastAPI(
    title="eKYC Phase 3 ZKP Backend",
    version="1.0.0",
    description="Privacy-first backend with Schnorr proof verification",
    lifespan=lifespan,
)

_initial_security_settings = _get_service_security_settings()
app.add_middleware(
    CORSMiddleware,
    allow_origins=_initial_security_settings.allowed_origins,
    allow_credentials=_initial_security_settings.cors_allow_credentials,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=[
        "Authorization",
        "Content-Type",
        "X-Correlation-ID",
        "X-EKYC-API-Key",
    ],
    expose_headers=["X-Correlation-ID"],
    max_age=600,
)


class OcrRiskSignals(BaseModel):
    confidence: float | None = Field(default=None, ge=0, le=1)
    field_mismatch: bool = False
    glare_detected: bool = False
    blur_detected: bool = False
    crop_invalid: bool = False


class FaceRiskSignals(BaseModel):
    match_score: float | None = Field(default=None, ge=0, le=1)
    liveness_confidence: float | None = Field(default=None, ge=0, le=1)


class DeviceTrustSignals(BaseModel):
    status: str = Field(default="unknown", min_length=1)
    score: float | None = Field(default=None, ge=0, le=1)
    provider: str | None = Field(default=None, min_length=1, max_length=128)
    detail: str | None = Field(default=None, max_length=256)
    integrity_token: str | None = Field(default=None, min_length=16, max_length=20000)
    request_hash: str | None = Field(default=None, min_length=16, max_length=256)
    token_source: str | None = Field(default=None, min_length=1, max_length=128)
    error_category: str | None = Field(default=None, min_length=1, max_length=64)
    error_code: str | None = Field(default=None, min_length=1, max_length=64)
    retryable: bool = False


class RetrySignals(BaseModel):
    attempt_count: int = Field(default=0, ge=0)
    max_attempts: int = Field(default=3, ge=1)


class VerificationRiskContext(BaseModel):
    ocr: OcrRiskSignals | None = None
    face: FaceRiskSignals | None = None
    device_trust: DeviceTrustSignals | None = None
    retry: RetrySignals | None = None
    network_interrupted: bool = False


class EnrollRequest(BaseModel):
    id_hash: str = Field(..., min_length=64, max_length=64)
    encrypted_pii: str = Field(..., min_length=8)
    public_key: str = Field(..., min_length=1)
    correlation_id: str | None = Field(default=None, min_length=8, max_length=128)
    risk_context: VerificationRiskContext | None = None


class SchnorrProof(BaseModel):
    commitment: str = Field(..., min_length=1)
    challenge: str = Field(..., min_length=1)
    response: str = Field(..., min_length=1)
    session_nonce: str = Field(..., min_length=8, max_length=128)


class VerifyRequest(BaseModel):
    id_hash: str = Field(..., min_length=64, max_length=64)
    encrypted_pii: str = Field(..., min_length=8)
    public_key: str | None = None
    proof: SchnorrProof
    correlation_id: str | None = Field(default=None, min_length=8, max_length=128)
    risk_context: VerificationRiskContext | None = None


def _get_connection() -> sqlite3.Connection:
    connection = sqlite3.connect(DB_PATH)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA foreign_keys = ON;")
    return connection


def _init_db() -> None:
    with _get_connection() as connection:
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS enrollments (
                id_hash TEXT PRIMARY KEY,
                encrypted_pii TEXT NOT NULL,
                public_key TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
            );
            """
        )
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS used_nonces (
                id_hash TEXT NOT NULL,
                session_nonce TEXT NOT NULL,
                used_at INTEGER NOT NULL,
                PRIMARY KEY (id_hash, session_nonce),
                FOREIGN KEY (id_hash) REFERENCES enrollments(id_hash) ON DELETE CASCADE
            );
            """
        )


def _is_valid_hex_sha256(value: str) -> bool:
    if len(value) != 64:
        return False
    lowered = value.lower()
    return all(char in "0123456789abcdef" for char in lowered)


def _parse_positive_int(raw_value: str, field_name: str) -> int:
    try:
        parsed = int(raw_value)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"{field_name} phải là số nguyên dương.",
        ) from exc

    if parsed <= 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"{field_name} phải lớn hơn 0.",
        )

    return parsed


def _is_subgroup_element(value: int) -> bool:
    if value <= 1 or value >= P:
        return False
    return pow(value, Q, P) == 1


def _compute_challenge(id_hash: str, session_nonce: str, commitment: int) -> int:
    payload = f"{id_hash}|{session_nonce}|{commitment}".encode("utf-8")
    digest = hashlib.sha256(payload).digest()
    return (int.from_bytes(digest, "big") % (Q - 1)) + 1


def _risk_context_to_dict(
    risk_context: VerificationRiskContext | None,
) -> dict[str, Any] | None:
    if risk_context is None:
        return None
    return risk_context.model_dump(exclude_none=True)


def _compute_integrity_request_hash(
    *,
    id_hash: str,
    correlation_id: str,
    attempt_count: int,
) -> str:
    payload = f"ekyc_integrity_v1|{id_hash}|{attempt_count}|{correlation_id}".encode(
        "utf-8"
    )
    return hashlib.sha256(payload).hexdigest()


def _resolve_verified_device_trust_signal(
    *,
    id_hash: str,
    correlation_id: str,
    risk_context_dict: dict[str, Any],
) -> dict[str, Any]:
    retry_signals = risk_context_dict.get("retry")
    if isinstance(retry_signals, dict):
        attempt_count = int(retry_signals.get("attempt_count", 0) or 0)
    else:
        attempt_count = 0

    expected_request_hash = _compute_integrity_request_hash(
        id_hash=id_hash,
        correlation_id=correlation_id,
        attempt_count=attempt_count,
    )

    evidence = risk_context_dict.get("device_trust")
    if not isinstance(evidence, dict):
        evidence = None

    verification_result = verify_play_integrity(
        evidence=evidence,
        correlation_id=correlation_id,
        expected_request_hash=expected_request_hash,
    )

    return verification_result.to_device_trust_signal()


def _device_trust_log_metadata(device_trust_signal: Mapping[str, Any]) -> dict[str, Any]:
    return {
        "status": str(device_trust_signal.get("status", "")),
        "score": device_trust_signal.get("score"),
        "provider": str(device_trust_signal.get("provider", "")),
        "detail": str(device_trust_signal.get("detail", "")),
        "verification_status": str(device_trust_signal.get("verification_status", "")),
        "verifier_mode": str(device_trust_signal.get("verifier_mode", "")),
        "retryable": bool(device_trust_signal.get("retryable", False)),
        "token_present": bool(device_trust_signal.get("token_present", False)),
        "error_code": str(device_trust_signal.get("error_code", "")),
    }


def _resolve_correlation_id(request: Request, body_correlation_id: str | None) -> str:
    state_correlation_id = getattr(request.state, "correlation_id", None)
    if isinstance(state_correlation_id, str) and state_correlation_id.strip():
        return state_correlation_id.strip()

    if body_correlation_id is not None and body_correlation_id.strip():
        return body_correlation_id.strip()

    generated = str(uuid.uuid4())
    request.state.correlation_id = generated
    return generated


def _build_verify_response(
    *,
    verified: bool,
    reason: str,
    score: float,
    correlation_id: str,
    risk_context: dict[str, Any] | None,
) -> dict[str, Any]:
    decision = evaluate_decision(
        verified=verified,
        verify_reason=reason,
        correlation_id=correlation_id,
        risk_context=risk_context,
        enforce_device_trust_signal=True,
    )

    log_audit_event(
        event_name="face_liveness_evaluated",
        correlation_id=correlation_id,
        decision_status=decision.decision_status.value,
        reason_codes=decision.reason_codes,
        metadata={"face": (risk_context or {}).get("face", {})},
    )
    log_audit_event(
        event_name="final_decision_issued",
        correlation_id=correlation_id,
        decision_status=decision.decision_status.value,
        reason_codes=decision.reason_codes,
        metadata={
            "verified": verified,
            "reason": reason,
            "retry_allowed": decision.retry_allowed,
            "retry_policy": decision.retry_policy.value,
        },
    )

    if decision.retry_allowed:
        log_audit_event(
            event_name="retry_requested",
            correlation_id=correlation_id,
            decision_status=decision.decision_status.value,
            reason_codes=decision.reason_codes,
            metadata={
                "retry_reason": decision.retry_reason,
                "retry_policy": decision.retry_policy.value,
            },
        )

    payload: dict[str, Any] = {
        "verified": verified,
        "reason": reason,
        "score": score,
        "server_time": int(time.time()),
    }
    payload.update(decision.to_dict())
    return payload


def _ensure_request_correlation_id(request: Request) -> str:
    existing = getattr(request.state, "correlation_id", None)
    if isinstance(existing, str) and existing.strip():
        return existing.strip()

    incoming_correlation_id = request.headers.get("X-Correlation-ID")
    if incoming_correlation_id is None or not incoming_correlation_id.strip():
        incoming_correlation_id = str(uuid.uuid4())

    correlation_id = incoming_correlation_id.strip()
    request.state.correlation_id = correlation_id
    return correlation_id


def _is_sensitive_path(path: str) -> bool:
    return path in _SENSITIVE_PATHS


def _extract_bearer_token(authorization_header: str) -> str:
    if not authorization_header:
        return ""

    normalized = authorization_header.strip()
    if len(normalized) < 8:
        return ""

    if not normalized.lower().startswith("bearer "):
        return ""

    return normalized[7:].strip()


def _is_client_auth_ready(settings: ServiceSecuritySettings) -> bool:
    if settings.auth_mode == "disabled":
        return settings.backend_env == "dev" or settings.allow_insecure_no_auth_in_non_dev

    if settings.auth_mode == "api_key":
        return settings.client_api_key != ""

    if settings.auth_mode == "bearer":
        return settings.client_bearer_token != ""

    if settings.auth_mode == "either":
        return settings.client_api_key != "" or settings.client_bearer_token != ""

    return False


def _is_request_authenticated(request: Request, settings: ServiceSecuritySettings) -> bool:
    if settings.auth_mode == "disabled":
        return True

    api_key_header = request.headers.get("X-EKYC-API-Key", "").strip()
    authorization_header = request.headers.get("Authorization", "")
    bearer_token = _extract_bearer_token(authorization_header)

    api_key_match = (
        settings.client_api_key != ""
        and api_key_header != ""
        and secrets.compare_digest(api_key_header, settings.client_api_key)
    )
    bearer_match = (
        settings.client_bearer_token != ""
        and bearer_token != ""
        and secrets.compare_digest(bearer_token, settings.client_bearer_token)
    )

    if settings.auth_mode == "api_key":
        return api_key_match
    if settings.auth_mode == "bearer":
        return bearer_match
    return api_key_match or bearer_match


def _enforce_sensitive_route_auth(request: Request, settings: ServiceSecuritySettings) -> None:
    if settings.auth_mode == "disabled":
        if settings.backend_env != "dev" and not settings.allow_insecure_no_auth_in_non_dev:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="client_auth_required_in_non_dev",
            )
        return

    if not _is_client_auth_ready(settings):
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="client_auth_secret_missing",
        )

    if _is_request_authenticated(request, settings):
        return

    response_headers: dict[str, str] | None = None
    if settings.auth_mode in {"bearer", "either"}:
        response_headers = {"WWW-Authenticate": "Bearer"}

    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="unauthorized_client",
        headers=response_headers,
    )


def _resolve_rate_limit_policy(
    path: str,
    settings: ServiceSecuritySettings,
) -> tuple[int, int]:
    if path == "/enroll":
        return (
            settings.enroll_rate_limit_max_requests,
            settings.enroll_rate_limit_window_seconds,
        )

    return (
        settings.verify_rate_limit_max_requests,
        settings.verify_rate_limit_window_seconds,
    )


def _is_integrity_verifier_ready(backend_env: str) -> bool:
    if backend_env == "dev":
        return True

    integrity_settings = IntegrityVerifierSettings.from_env()
    if integrity_settings.mode != IntegrityVerifierMode.GOOGLE:
        return False
    if integrity_settings.android_package_name == "":
        return False
    if integrity_settings.credentials_file == "" and integrity_settings.credentials_json == "":
        return False
    return True


def _is_cors_ready(settings: ServiceSecuritySettings) -> bool:
    if settings.backend_env == "dev":
        return True
    if not settings.allowed_origins:
        return False
    return "*" not in settings.allowed_origins


@app.middleware("http")
async def correlation_id_middleware(request: Request, call_next):
    correlation_id = _ensure_request_correlation_id(request)
    response = await call_next(request)
    response.headers["X-Correlation-ID"] = correlation_id
    return response


@app.middleware("http")
async def sensitive_auth_middleware(request: Request, call_next):
    if request.method == "OPTIONS" or not _is_sensitive_path(request.url.path):
        return await call_next(request)

    correlation_id = _ensure_request_correlation_id(request)
    settings = _get_service_security_settings()

    try:
        _enforce_sensitive_route_auth(request, settings)
    except HTTPException as error:
        detail = error.detail if isinstance(error.detail, str) else "request_denied"

        log_audit_event(
            event_name="auth_denied",
            correlation_id=correlation_id,
            metadata={
                "path": request.url.path,
                "method": request.method,
                "reason": detail,
            },
        )

        response_headers = {"X-Correlation-ID": correlation_id}
        if error.headers:
            response_headers.update(error.headers)

        return JSONResponse(
            status_code=error.status_code,
            content={"detail": detail, "correlation_id": correlation_id},
            headers=response_headers,
        )

    return await call_next(request)


@app.middleware("http")
async def sensitive_rate_limit_middleware(request: Request, call_next):
    if request.method == "OPTIONS" or not _is_sensitive_path(request.url.path):
        return await call_next(request)

    settings = _get_service_security_settings()
    max_requests, window_seconds = _resolve_rate_limit_policy(request.url.path, settings)

    if max_requests <= 0 or window_seconds <= 0:
        return await call_next(request)

    client_host = request.client.host if request.client else "unknown"
    bucket_key = f"{client_host}:{request.url.path}"
    now = time.time()

    with _verify_rate_lock:
        bucket = _verify_rate_buckets[bucket_key]

        while bucket and now - bucket[0] > window_seconds:
            bucket.popleft()

        if len(bucket) >= max_requests:
            correlation_id = _ensure_request_correlation_id(request)

            if request.url.path == "/verify":
                decision = rate_limited_decision(correlation_id)

                log_audit_event(
                    event_name="retry_requested",
                    correlation_id=correlation_id,
                    decision_status=decision.decision_status.value,
                    reason_codes=decision.reason_codes,
                    metadata={"reason": "rate_limited", "path": request.url.path},
                )

                content: dict[str, Any] = {
                    "verified": False,
                    "reason": "rate_limited",
                    "score": 0.0,
                    "server_time": int(time.time()),
                }
                content.update(decision.to_dict())
            else:
                log_audit_event(
                    event_name="abuse_rate_limited",
                    correlation_id=correlation_id,
                    metadata={"path": request.url.path, "client_host": client_host},
                )
                content = {
                    "detail": "rate_limited",
                    "correlation_id": correlation_id,
                }

            return JSONResponse(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                content=content,
                headers={
                    "Retry-After": str(window_seconds),
                    "X-Correlation-ID": correlation_id,
                },
            )

        bucket.append(now)

    return await call_next(request)


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, error: Exception):
    correlation_id = _ensure_request_correlation_id(request)
    _service_logger.exception("Unhandled backend error on %s", request.url.path)

    log_audit_event(
        event_name="internal_error",
        correlation_id=correlation_id,
        metadata={"path": request.url.path, "method": request.method},
    )

    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={"detail": "internal_server_error", "correlation_id": correlation_id},
        headers={"X-Correlation-ID": correlation_id},
    )


@app.get("/health")
def health_check() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/ready")
def readiness_check(request: Request) -> dict[str, Any]:
    correlation_id = _resolve_correlation_id(request, None)
    settings = _get_service_security_settings()

    checks = {
        "client_auth_ready": _is_client_auth_ready(settings),
        "cors_ready": _is_cors_ready(settings),
        "integrity_verifier_ready": _is_integrity_verifier_ready(settings.backend_env),
    }
    service_status = "ready" if all(checks.values()) else "not_ready"

    if service_status != "ready":
        log_audit_event(
            event_name="service_readiness_not_ready",
            correlation_id=correlation_id,
            metadata={"checks": checks, "backend_env": settings.backend_env},
        )

    return {
        "status": service_status,
        "backend_env": settings.backend_env,
        "checks": checks,
        "correlation_id": correlation_id,
    }


@app.post("/enroll")
def enroll(request: Request, payload: EnrollRequest) -> dict[str, Any]:
    correlation_id = _resolve_correlation_id(request, payload.correlation_id)
    id_hash = payload.id_hash.lower()

    log_audit_event(
        event_name="session_started",
        correlation_id=correlation_id,
        metadata={"stage": "enroll", "id_hash_prefix": id_hash[:8]},
    )

    if not _is_valid_hex_sha256(id_hash):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="id_hash phải là SHA-256 hex (64 ký tự).",
        )

    public_key = _parse_positive_int(payload.public_key, "public_key")
    if not _is_subgroup_element(public_key):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="public_key không hợp lệ trong nhóm Schnorr.",
        )

    risk_context_dict = _risk_context_to_dict(payload.risk_context)
    if risk_context_dict and "ocr" in risk_context_dict:
        log_audit_event(
            event_name="ocr_submitted",
            correlation_id=correlation_id,
            metadata={"ocr": risk_context_dict.get("ocr", {})},
        )

        ocr_decision = evaluate_decision(
            verified=True,
            verify_reason="ok",
            correlation_id=correlation_id,
            risk_context={"ocr": risk_context_dict.get("ocr", {})},
        )
        log_audit_event(
            event_name="ocr_evaluated",
            correlation_id=correlation_id,
            decision_status=ocr_decision.decision_status.value,
            reason_codes=ocr_decision.reason_codes,
            metadata={"ocr": risk_context_dict.get("ocr", {})},
        )

    now = int(time.time())
    with _get_connection() as connection:
        connection.execute(
            """
            INSERT INTO enrollments (id_hash, encrypted_pii, public_key, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(id_hash) DO UPDATE SET
                encrypted_pii = excluded.encrypted_pii,
                public_key = excluded.public_key,
                updated_at = excluded.updated_at;
            """,
            (id_hash, payload.encrypted_pii, str(public_key), now, now),
        )

    return {
        "status": "enrolled",
        "id_hash": id_hash,
        "updated_at": now,
        "correlation_id": correlation_id,
    }


@app.post("/verify")
def verify(request: Request, payload: VerifyRequest) -> dict[str, Any]:
    correlation_id = _resolve_correlation_id(request, payload.correlation_id)
    risk_context_dict = _risk_context_to_dict(payload.risk_context) or {}

    id_hash = payload.id_hash.lower()
    log_audit_event(
        event_name="session_started",
        correlation_id=correlation_id,
        metadata={"stage": "verify", "id_hash_prefix": id_hash[:8]},
    )

    if risk_context_dict and "ocr" in risk_context_dict:
        log_audit_event(
            event_name="ocr_submitted",
            correlation_id=correlation_id,
            metadata={"ocr": risk_context_dict.get("ocr", {})},
        )

    if risk_context_dict and "face" in risk_context_dict:
        log_audit_event(
            event_name="face_liveness_submitted",
            correlation_id=correlation_id,
            metadata={"face": risk_context_dict.get("face", {})},
        )

    if not _is_valid_hex_sha256(id_hash):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="id_hash phải là SHA-256 hex (64 ký tự).",
        )

    verified_device_trust = _resolve_verified_device_trust_signal(
        id_hash=id_hash,
        correlation_id=correlation_id,
        risk_context_dict=risk_context_dict,
    )
    risk_context_dict["device_trust"] = verified_device_trust

    log_audit_event(
        event_name="integrity_check_result",
        correlation_id=correlation_id,
        metadata={"device_trust": _device_trust_log_metadata(verified_device_trust)},
    )

    proof = payload.proof
    commitment = _parse_positive_int(proof.commitment, "proof.commitment")
    challenge = _parse_positive_int(proof.challenge, "proof.challenge")
    response = _parse_positive_int(proof.response, "proof.response")

    if not _is_subgroup_element(commitment):
        return _build_verify_response(
            verified=False,
            reason="commitment_not_in_subgroup",
            score=0.0,
            correlation_id=correlation_id,
            risk_context=risk_context_dict,
        )

    if challenge >= Q or response >= Q:
        return _build_verify_response(
            verified=False,
            reason="proof_out_of_range",
            score=0.0,
            correlation_id=correlation_id,
            risk_context=risk_context_dict,
        )

    with _get_connection() as connection:
        enrollment_row = connection.execute(
            "SELECT id_hash, encrypted_pii, public_key FROM enrollments WHERE id_hash = ?",
            (id_hash,),
        ).fetchone()

        if enrollment_row is None:
            return _build_verify_response(
                verified=False,
                reason="not_enrolled",
                score=0.0,
                correlation_id=correlation_id,
                risk_context=risk_context_dict,
            )

        stored_public_key = int(enrollment_row["public_key"])

        if payload.public_key is not None:
            claimed_public_key = _parse_positive_int(payload.public_key, "public_key")
            if claimed_public_key != stored_public_key:
                return _build_verify_response(
                    verified=False,
                    reason="public_key_mismatch",
                    score=0.0,
                    correlation_id=correlation_id,
                    risk_context=risk_context_dict,
                )

        replay_row = connection.execute(
            "SELECT 1 FROM used_nonces WHERE id_hash = ? AND session_nonce = ?",
            (id_hash, proof.session_nonce),
        ).fetchone()
        if replay_row is not None:
            return _build_verify_response(
                verified=False,
                reason="replay_detected",
                score=0.0,
                correlation_id=correlation_id,
                risk_context=risk_context_dict,
            )

        expected_challenge = _compute_challenge(
            id_hash=id_hash,
            session_nonce=proof.session_nonce,
            commitment=commitment,
        )
        if challenge != expected_challenge:
            return _build_verify_response(
                verified=False,
                reason="challenge_mismatch",
                score=0.0,
                correlation_id=correlation_id,
                risk_context=risk_context_dict,
            )

        lhs = pow(G, response, P)
        rhs = (commitment * pow(stored_public_key, challenge, P)) % P

        is_verified = lhs == rhs
        verification_score = 1.0 if is_verified else 0.0

        if is_verified:
            now = int(time.time())
            connection.execute(
                "INSERT INTO used_nonces (id_hash, session_nonce, used_at) VALUES (?, ?, ?)",
                (id_hash, proof.session_nonce, now),
            )
            connection.execute(
                "UPDATE enrollments SET encrypted_pii = ?, updated_at = ? WHERE id_hash = ?",
                (payload.encrypted_pii, now, id_hash),
            )

        return _build_verify_response(
            verified=is_verified,
            reason="ok" if is_verified else "equation_failed",
            score=verification_score,
            correlation_id=correlation_id,
            risk_context=risk_context_dict,
        )
