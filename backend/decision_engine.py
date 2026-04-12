from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Mapping


class DecisionStatus(str, Enum):
    PASS = "PASS"
    REVIEW = "REVIEW"
    REJECT = "REJECT"


class RetryPolicy(str, Enum):
    IMMEDIATE = "IMMEDIATE"
    USER_CORRECTION = "USER_CORRECTION"
    WAIT_BEFORE_RETRY = "WAIT_BEFORE_RETRY"
    MANUAL_REVIEW = "MANUAL_REVIEW"
    NO_RETRY = "NO_RETRY"


class ReasonCodes:
    OCR_LOW_CONFIDENCE = "OCR_LOW_CONFIDENCE"
    OCR_FIELD_MISMATCH = "OCR_FIELD_MISMATCH"
    DOCUMENT_GLARE = "DOCUMENT_GLARE"
    DOCUMENT_BLUR = "DOCUMENT_BLUR"
    DOCUMENT_CROP_INVALID = "DOCUMENT_CROP_INVALID"
    FACE_MISMATCH = "FACE_MISMATCH"
    LIVENESS_LOW_CONFIDENCE = "LIVENESS_LOW_CONFIDENCE"
    DEVICE_TRUST_UNAVAILABLE = "DEVICE_TRUST_UNAVAILABLE"
    DEVICE_TRUST_LOW = "DEVICE_TRUST_LOW"
    DEVICE_TRUST_INVALID_TOKEN = "DEVICE_TRUST_INVALID_TOKEN"
    DEVICE_TRUST_TRANSIENT_ERROR = "DEVICE_TRUST_TRANSIENT_ERROR"
    DEVICE_TRUST_CONFIGURATION_ERROR = "DEVICE_TRUST_CONFIGURATION_ERROR"
    SESSION_RETRY_LIMIT = "SESSION_RETRY_LIMIT"
    NETWORK_INTERRUPTED = "NETWORK_INTERRUPTED"
    INTERNAL_REVIEW_REQUIRED = "INTERNAL_REVIEW_REQUIRED"
    UNKNOWN_ERROR_SAFE_FALLBACK = "UNKNOWN_ERROR_SAFE_FALLBACK"


_CRYPTO_REJECT_REASONS = {
    "commitment_not_in_subgroup",
    "proof_out_of_range",
    "public_key_mismatch",
    "challenge_mismatch",
    "equation_failed",
    "replay_detected",
}


@dataclass(slots=True)
class DecisionResult:
    decision_status: DecisionStatus
    reason_codes: list[str] = field(default_factory=list)
    user_message_key: str = "decision.review.generic"
    retry_allowed: bool = False
    retry_reason: str = "none"
    retry_policy: RetryPolicy = RetryPolicy.NO_RETRY
    correlation_id: str = ""
    risk_signals: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return {
            "decision_status": self.decision_status.value,
            "reason_codes": self.reason_codes,
            "user_message_key": self.user_message_key,
            "retry_allowed": self.retry_allowed,
            "retry_reason": self.retry_reason,
            "retry_policy": self.retry_policy.value,
            "correlation_id": self.correlation_id,
            "risk_signals": self.risk_signals,
        }


def evaluate_decision(
    *,
    verified: bool,
    verify_reason: str,
    correlation_id: str,
    risk_context: Mapping[str, Any] | None = None,
    enforce_device_trust_signal: bool = False,
) -> DecisionResult:
    reason_codes: list[str] = []
    normalized_signals = _normalize_signals(risk_context)

    _append_signal_reason_codes(reason_codes, normalized_signals)
    _append_verify_reason_codes(reason_codes, verify_reason, verified)

    # Safety default for verify flow: if trust signal is missing, never auto-pass.
    if enforce_device_trust_signal and not _has_device_trust_signal(normalized_signals):
        reason_codes.append(ReasonCodes.DEVICE_TRUST_UNAVAILABLE)

    reason_codes = _dedupe_codes(reason_codes)

    if verified and not reason_codes:
        return DecisionResult(
            decision_status=DecisionStatus.PASS,
            reason_codes=[],
            user_message_key="decision.pass",
            retry_allowed=False,
            retry_reason="none",
            retry_policy=RetryPolicy.NO_RETRY,
            correlation_id=correlation_id,
            risk_signals=normalized_signals,
        )

    if ReasonCodes.SESSION_RETRY_LIMIT in reason_codes:
        return DecisionResult(
            decision_status=DecisionStatus.REJECT,
            reason_codes=reason_codes,
            user_message_key="decision.reject.retry_limit",
            retry_allowed=False,
            retry_reason="retry_limit_reached",
            retry_policy=RetryPolicy.NO_RETRY,
            correlation_id=correlation_id,
            risk_signals=normalized_signals,
        )

    if ReasonCodes.FACE_MISMATCH in reason_codes or ReasonCodes.DEVICE_TRUST_LOW in reason_codes:
        return DecisionResult(
            decision_status=DecisionStatus.REJECT,
            reason_codes=reason_codes,
            user_message_key="decision.reject.security_check_failed",
            retry_allowed=False,
            retry_reason="hard_reject",
            retry_policy=RetryPolicy.NO_RETRY,
            correlation_id=correlation_id,
            risk_signals=normalized_signals,
        )

    if _has_document_quality_issue(reason_codes):
        return DecisionResult(
            decision_status=DecisionStatus.REVIEW,
            reason_codes=reason_codes,
            user_message_key="decision.review.document_quality",
            retry_allowed=True,
            retry_reason="user_correction_required",
            retry_policy=RetryPolicy.USER_CORRECTION,
            correlation_id=correlation_id,
            risk_signals=normalized_signals,
        )

    if ReasonCodes.LIVENESS_LOW_CONFIDENCE in reason_codes:
        return DecisionResult(
            decision_status=DecisionStatus.REVIEW,
            reason_codes=reason_codes,
            user_message_key="decision.review.liveness_retry",
            retry_allowed=True,
            retry_reason="liveness_low_confidence",
            retry_policy=RetryPolicy.IMMEDIATE,
            correlation_id=correlation_id,
            risk_signals=normalized_signals,
        )

    if ReasonCodes.NETWORK_INTERRUPTED in reason_codes:
        return DecisionResult(
            decision_status=DecisionStatus.REVIEW,
            reason_codes=reason_codes,
            user_message_key="decision.review.network_retry",
            retry_allowed=True,
            retry_reason="network_interrupted",
            retry_policy=RetryPolicy.IMMEDIATE,
            correlation_id=correlation_id,
            risk_signals=normalized_signals,
        )

    if ReasonCodes.DEVICE_TRUST_UNAVAILABLE in reason_codes:
        return DecisionResult(
            decision_status=DecisionStatus.REVIEW,
            reason_codes=reason_codes,
            user_message_key="decision.review.device_trust_pending",
            retry_allowed=True,
            retry_reason="device_trust_unavailable",
            retry_policy=RetryPolicy.WAIT_BEFORE_RETRY,
            correlation_id=correlation_id,
            risk_signals=normalized_signals,
        )

    if ReasonCodes.INTERNAL_REVIEW_REQUIRED in reason_codes:
        return DecisionResult(
            decision_status=DecisionStatus.REVIEW,
            reason_codes=reason_codes,
            user_message_key="decision.review.internal_required",
            retry_allowed=False,
            retry_reason="manual_review_required",
            retry_policy=RetryPolicy.MANUAL_REVIEW,
            correlation_id=correlation_id,
            risk_signals=normalized_signals,
        )

    if ReasonCodes.UNKNOWN_ERROR_SAFE_FALLBACK not in reason_codes:
        reason_codes.append(ReasonCodes.UNKNOWN_ERROR_SAFE_FALLBACK)

    return DecisionResult(
        decision_status=DecisionStatus.REVIEW,
        reason_codes=reason_codes,
        user_message_key="decision.review.safe_fallback",
        retry_allowed=True,
        retry_reason="safe_fallback_retry",
        retry_policy=RetryPolicy.IMMEDIATE,
        correlation_id=correlation_id,
        risk_signals=normalized_signals,
    )


def rate_limited_decision(correlation_id: str) -> DecisionResult:
    return DecisionResult(
        decision_status=DecisionStatus.REJECT,
        reason_codes=[ReasonCodes.SESSION_RETRY_LIMIT],
        user_message_key="decision.reject.retry_limit",
        retry_allowed=False,
        retry_reason="retry_limit_reached",
        retry_policy=RetryPolicy.NO_RETRY,
        correlation_id=correlation_id,
        risk_signals={"rate_limited": True},
    )


def _normalize_signals(risk_context: Mapping[str, Any] | None) -> dict[str, Any]:
    if risk_context is None:
        return {}

    normalized: dict[str, Any] = {}

    ocr = risk_context.get("ocr")
    if isinstance(ocr, Mapping):
        normalized["ocr"] = {
            "confidence": _safe_float(ocr.get("confidence")),
            "field_mismatch": bool(ocr.get("field_mismatch", False)),
            "glare_detected": bool(ocr.get("glare_detected", False)),
            "blur_detected": bool(ocr.get("blur_detected", False)),
            "crop_invalid": bool(ocr.get("crop_invalid", False)),
        }

    face = risk_context.get("face")
    if isinstance(face, Mapping):
        normalized["face"] = {
            "match_score": _safe_float(face.get("match_score")),
            "liveness_confidence": _safe_float(face.get("liveness_confidence")),
        }

    device_trust = risk_context.get("device_trust")
    if isinstance(device_trust, Mapping):
        normalized["device_trust"] = {
            "status": str(device_trust.get("status", "unknown")).lower(),
            "score": _safe_float(device_trust.get("score")),
            "provider": str(device_trust.get("provider", "")).strip(),
            "detail": str(device_trust.get("detail", "")).strip(),
            "verification_status": str(
                device_trust.get("verification_status", "")
            ).strip(),
        }

    retry = risk_context.get("retry")
    if isinstance(retry, Mapping):
        normalized["retry"] = {
            "attempt_count": int(retry.get("attempt_count", 0) or 0),
            "max_attempts": max(int(retry.get("max_attempts", 3) or 3), 1),
        }

    if "network_interrupted" in risk_context:
        normalized["network_interrupted"] = bool(risk_context.get("network_interrupted"))

    return normalized


def _append_signal_reason_codes(reason_codes: list[str], signals: Mapping[str, Any]) -> None:
    ocr = signals.get("ocr")
    if isinstance(ocr, Mapping):
        confidence = _safe_float(ocr.get("confidence"))
        if confidence is not None and confidence < 0.65:
            reason_codes.append(ReasonCodes.OCR_LOW_CONFIDENCE)
        if bool(ocr.get("field_mismatch")):
            reason_codes.append(ReasonCodes.OCR_FIELD_MISMATCH)
        if bool(ocr.get("glare_detected")):
            reason_codes.append(ReasonCodes.DOCUMENT_GLARE)
        if bool(ocr.get("blur_detected")):
            reason_codes.append(ReasonCodes.DOCUMENT_BLUR)
        if bool(ocr.get("crop_invalid")):
            reason_codes.append(ReasonCodes.DOCUMENT_CROP_INVALID)

    face = signals.get("face")
    if isinstance(face, Mapping):
        match_score = _safe_float(face.get("match_score"))
        if match_score is not None and match_score < 0.65:
            reason_codes.append(ReasonCodes.FACE_MISMATCH)

        liveness_confidence = _safe_float(face.get("liveness_confidence"))
        if liveness_confidence is not None and liveness_confidence < 0.70:
            reason_codes.append(ReasonCodes.LIVENESS_LOW_CONFIDENCE)

    device_trust = signals.get("device_trust")
    if isinstance(device_trust, Mapping):
        status = str(device_trust.get("status", "unknown")).lower()
        detail = str(device_trust.get("detail", "")).lower()
        verification_status = str(device_trust.get("verification_status", "")).lower()

        if status in {"unavailable", "unknown"}:
            reason_codes.append(ReasonCodes.DEVICE_TRUST_UNAVAILABLE)
        elif status == "low":
            reason_codes.append(ReasonCodes.DEVICE_TRUST_LOW)

        if verification_status == "invalid" or "invalid" in detail or "mismatch" in detail:
            reason_codes.append(ReasonCodes.DEVICE_TRUST_INVALID_TOKEN)

        if verification_status == "transient_error":
            reason_codes.append(ReasonCodes.DEVICE_TRUST_TRANSIENT_ERROR)

        if verification_status == "configuration_error":
            reason_codes.append(ReasonCodes.DEVICE_TRUST_CONFIGURATION_ERROR)

    retry = signals.get("retry")
    if isinstance(retry, Mapping):
        attempt_count = int(retry.get("attempt_count", 0) or 0)
        max_attempts = max(int(retry.get("max_attempts", 3) or 3), 1)
        if attempt_count >= max_attempts:
            reason_codes.append(ReasonCodes.SESSION_RETRY_LIMIT)

    if bool(signals.get("network_interrupted", False)):
        reason_codes.append(ReasonCodes.NETWORK_INTERRUPTED)


def _append_verify_reason_codes(
    reason_codes: list[str],
    verify_reason: str,
    verified: bool,
) -> None:
    reason = (verify_reason or "").strip().lower()

    if not reason:
        if not verified:
            reason_codes.append(ReasonCodes.UNKNOWN_ERROR_SAFE_FALLBACK)
        return

    if reason == "ok" and verified:
        return

    if reason == "rate_limited":
        reason_codes.append(ReasonCodes.SESSION_RETRY_LIMIT)
        return

    if reason == "network_error":
        reason_codes.append(ReasonCodes.NETWORK_INTERRUPTED)
        return

    if reason in _CRYPTO_REJECT_REASONS:
        reason_codes.append(ReasonCodes.INTERNAL_REVIEW_REQUIRED)
        return

    if not verified:
        reason_codes.append(ReasonCodes.UNKNOWN_ERROR_SAFE_FALLBACK)


def _has_document_quality_issue(reason_codes: list[str]) -> bool:
    doc_codes = {
        ReasonCodes.OCR_LOW_CONFIDENCE,
        ReasonCodes.OCR_FIELD_MISMATCH,
        ReasonCodes.DOCUMENT_GLARE,
        ReasonCodes.DOCUMENT_BLUR,
        ReasonCodes.DOCUMENT_CROP_INVALID,
    }
    return any(code in doc_codes for code in reason_codes)


def _dedupe_codes(codes: list[str]) -> list[str]:
    deduped: list[str] = []
    seen: set[str] = set()
    for code in codes:
        if code in seen:
            continue
        seen.add(code)
        deduped.append(code)
    return deduped


def _has_device_trust_signal(signals: Mapping[str, Any]) -> bool:
    device_trust = signals.get("device_trust")
    if not isinstance(device_trust, Mapping):
        return False

    status = str(device_trust.get("status", "")).strip()
    return status != ""


def _safe_float(value: Any) -> float | None:
    try:
        if value is None:
            return None
        return float(value)
    except (TypeError, ValueError):
        return None
