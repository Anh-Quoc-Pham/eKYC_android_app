from pathlib import Path
import sys

# Ensure backend modules are importable when tests are run from repo root.
sys.path.append(str(Path(__file__).resolve().parents[1]))

from decision_engine import (  # noqa: E402
    DecisionStatus,
    ReasonCodes,
    RetryPolicy,
    evaluate_decision,
    rate_limited_decision,
)


def test_pass_decision_when_verified_and_no_risk_signals():
    result = evaluate_decision(
        verified=True,
        verify_reason="ok",
        correlation_id="corr-pass-001",
        risk_context=None,
    )

    assert result.decision_status == DecisionStatus.PASS
    assert result.reason_codes == []
    assert result.retry_allowed is False


def test_review_for_document_quality_risks():
    result = evaluate_decision(
        verified=True,
        verify_reason="ok",
        correlation_id="corr-doc-001",
        risk_context={
            "ocr": {
                "confidence": 0.42,
                "field_mismatch": True,
                "glare_detected": True,
                "blur_detected": False,
                "crop_invalid": False,
            }
        },
    )

    assert result.decision_status == DecisionStatus.REVIEW
    assert ReasonCodes.OCR_LOW_CONFIDENCE in result.reason_codes
    assert ReasonCodes.OCR_FIELD_MISMATCH in result.reason_codes
    assert ReasonCodes.DOCUMENT_GLARE in result.reason_codes
    assert result.retry_allowed is True
    assert result.retry_policy == RetryPolicy.USER_CORRECTION


def test_reject_for_face_mismatch():
    result = evaluate_decision(
        verified=True,
        verify_reason="ok",
        correlation_id="corr-face-001",
        risk_context={"face": {"match_score": 0.20, "liveness_confidence": 0.92}},
    )

    assert result.decision_status == DecisionStatus.REJECT
    assert ReasonCodes.FACE_MISMATCH in result.reason_codes
    assert result.retry_allowed is False


def test_review_when_device_trust_is_unavailable():
    result = evaluate_decision(
        verified=True,
        verify_reason="ok",
        correlation_id="corr-trust-001",
        risk_context={"device_trust": {"status": "unavailable", "provider": "mock"}},
    )

    assert result.decision_status == DecisionStatus.REVIEW
    assert ReasonCodes.DEVICE_TRUST_UNAVAILABLE in result.reason_codes
    assert result.retry_allowed is True
    assert result.retry_policy == RetryPolicy.WAIT_BEFORE_RETRY


def test_transient_integrity_verdict_emits_specific_reason_code():
    result = evaluate_decision(
        verified=True,
        verify_reason="ok",
        correlation_id="corr-trust-transient-001",
        risk_context={
            "device_trust": {
                "status": "unavailable",
                "provider": "play_integrity_server",
                "verification_status": "transient_error",
                "detail": "integrity_service_temporarily_unavailable",
            }
        },
    )

    assert result.decision_status == DecisionStatus.REVIEW
    assert ReasonCodes.DEVICE_TRUST_UNAVAILABLE in result.reason_codes
    assert ReasonCodes.DEVICE_TRUST_TRANSIENT_ERROR in result.reason_codes
    assert result.retry_policy == RetryPolicy.WAIT_BEFORE_RETRY


def test_invalid_integrity_verdict_maps_to_reject_with_specific_reason_code():
    result = evaluate_decision(
        verified=True,
        verify_reason="ok",
        correlation_id="corr-trust-invalid-001",
        risk_context={
            "device_trust": {
                "status": "low",
                "provider": "play_integrity_server",
                "verification_status": "invalid",
                "detail": "request_hash_mismatch",
            }
        },
    )

    assert result.decision_status == DecisionStatus.REJECT
    assert ReasonCodes.DEVICE_TRUST_LOW in result.reason_codes
    assert ReasonCodes.DEVICE_TRUST_INVALID_TOKEN in result.reason_codes
    assert result.retry_allowed is False


def test_verify_requires_device_trust_signal_when_enforced():
    result = evaluate_decision(
        verified=True,
        verify_reason="ok",
        correlation_id="corr-trust-required-001",
        risk_context=None,
        enforce_device_trust_signal=True,
    )

    assert result.decision_status == DecisionStatus.REVIEW
    assert ReasonCodes.DEVICE_TRUST_UNAVAILABLE in result.reason_codes
    assert result.retry_policy == RetryPolicy.WAIT_BEFORE_RETRY


def test_reject_when_retry_limit_is_reached():
    result = evaluate_decision(
        verified=False,
        verify_reason="rate_limited",
        correlation_id="corr-limit-001",
        risk_context={"retry": {"attempt_count": 3, "max_attempts": 3}},
    )

    assert result.decision_status == DecisionStatus.REJECT
    assert ReasonCodes.SESSION_RETRY_LIMIT in result.reason_codes
    assert result.retry_allowed is False


def test_network_interrupted_maps_to_retryable_review():
    result = evaluate_decision(
        verified=False,
        verify_reason="network_error",
        correlation_id="corr-network-001",
        risk_context={"network_interrupted": True},
    )

    assert result.decision_status == DecisionStatus.REVIEW
    assert ReasonCodes.NETWORK_INTERRUPTED in result.reason_codes
    assert result.retry_allowed is True
    assert result.retry_policy == RetryPolicy.IMMEDIATE


def test_rate_limited_decision_helper():
    result = rate_limited_decision("corr-429-001")

    assert result.decision_status == DecisionStatus.REJECT
    assert result.reason_codes == [ReasonCodes.SESSION_RETRY_LIMIT]
    assert result.correlation_id == "corr-429-001"
