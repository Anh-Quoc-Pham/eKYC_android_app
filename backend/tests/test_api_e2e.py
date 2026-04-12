import hashlib
from pathlib import Path
import sys

import pytest
from fastapi.testclient import TestClient

# Ensure backend/main.py is importable when tests are run from repo root.
sys.path.append(str(Path(__file__).resolve().parents[1]))

import main as backend_main


def _build_valid_proof(
    *,
    id_hash: str,
    private_key: int,
    session_nonce: str,
    random_nonce: int,
) -> dict[str, str]:
    commitment = pow(backend_main.G, random_nonce, backend_main.P)
    challenge = backend_main._compute_challenge(id_hash, session_nonce, commitment)
    response = (random_nonce + (challenge * private_key)) % backend_main.Q

    return {
        "commitment": str(commitment),
        "challenge": str(challenge),
        "response": str(response),
        "session_nonce": session_nonce,
    }


@pytest.fixture
def client(tmp_path, monkeypatch):
    test_db = tmp_path / "ekyc_ci_e2e.db"
    monkeypatch.setattr(backend_main, "DB_PATH", test_db)
    backend_main._verify_rate_buckets.clear()
    backend_main._init_db()

    with TestClient(backend_main.app) as test_client:
        yield test_client


def test_health_endpoint_returns_ok(client: TestClient):
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_enroll_and_verify_success_then_replay_detected(client: TestClient):
    id_hash = hashlib.sha256(b"012345678901").hexdigest()
    private_key = 123456789
    public_key = pow(backend_main.G, private_key, backend_main.P)

    enroll_response = client.post(
        "/enroll",
        json={
            "id_hash": id_hash,
            "encrypted_pii": "ciphertext_payload_v1",
            "public_key": str(public_key),
        },
    )

    assert enroll_response.status_code == 200
    assert enroll_response.json()["status"] == "enrolled"

    proof = _build_valid_proof(
        id_hash=id_hash,
        private_key=private_key,
        session_nonce="nonce-e2e-001",
        random_nonce=987654321,
    )

    verify_payload = {
        "id_hash": id_hash,
        "encrypted_pii": "ciphertext_payload_v2",
        "public_key": str(public_key),
        "proof": proof,
        "risk_context": {
            "device_trust": {
                "status": "unknown",
                "provider": "play_integrity_native",
                "detail": "token_acquired_pending_server_verification",
                "integrity_token": "mock_trusted_token",
                "request_hash": "unused_in_mock_mode",
            }
        },
    }

    verify_response = client.post("/verify", json=verify_payload)
    assert verify_response.status_code == 200
    assert verify_response.json()["verified"] is True
    assert verify_response.json()["reason"] == "ok"
    assert verify_response.json()["decision_status"] == "PASS"
    assert verify_response.json()["retry_allowed"] is False
    assert isinstance(verify_response.json()["correlation_id"], str)
    assert verify_response.json()["correlation_id"]

    replay_response = client.post("/verify", json=verify_payload)
    assert replay_response.status_code == 200
    assert replay_response.json()["verified"] is False
    assert replay_response.json()["reason"] == "replay_detected"
    assert replay_response.json()["decision_status"] in {"REVIEW", "REJECT"}
    assert "INTERNAL_REVIEW_REQUIRED" in replay_response.json()["reason_codes"]


def test_verify_returns_challenge_mismatch_when_proof_challenge_is_tampered(
    client: TestClient,
):
    id_hash = hashlib.sha256(b"999999999999").hexdigest()
    private_key = 246813579
    public_key = pow(backend_main.G, private_key, backend_main.P)

    enroll_response = client.post(
        "/enroll",
        json={
            "id_hash": id_hash,
            "encrypted_pii": "ciphertext_payload_staging",
            "public_key": str(public_key),
        },
    )
    assert enroll_response.status_code == 200

    proof = _build_valid_proof(
        id_hash=id_hash,
        private_key=private_key,
        session_nonce="nonce-e2e-002",
        random_nonce=192837465,
    )

    challenge_value = int(proof["challenge"])
    tampered_challenge = challenge_value - 1 if challenge_value > 1 else 2
    proof["challenge"] = str(tampered_challenge)

    verify_response = client.post(
        "/verify",
        json={
            "id_hash": id_hash,
            "encrypted_pii": "ciphertext_payload_staging",
            "public_key": str(public_key),
            "proof": proof,
        },
    )

    assert verify_response.status_code == 200
    assert verify_response.json()["verified"] is False
    assert verify_response.json()["reason"] == "challenge_mismatch"
    assert verify_response.json()["decision_status"] in {"REVIEW", "REJECT"}
    assert "INTERNAL_REVIEW_REQUIRED" in verify_response.json()["reason_codes"]


def test_verify_rate_limit_returns_reject_contract(client: TestClient, monkeypatch):
    monkeypatch.setattr(backend_main, "VERIFY_RATE_LIMIT_MAX_REQUESTS", 1)
    monkeypatch.setattr(backend_main, "VERIFY_RATE_LIMIT_WINDOW_SECONDS", 60)
    backend_main._verify_rate_buckets.clear()

    first_response = client.post("/verify", json={})
    assert first_response.status_code == 422

    second_response = client.post("/verify", json={})
    assert second_response.status_code == 429

    payload = second_response.json()
    assert payload["verified"] is False
    assert payload["reason"] == "rate_limited"
    assert payload["decision_status"] == "REJECT"
    assert payload["retry_allowed"] is False
    assert "SESSION_RETRY_LIMIT" in payload["reason_codes"]
    assert second_response.headers["X-Correlation-ID"] == payload["correlation_id"]


def test_correlation_id_propagates_from_header_to_response_and_logs(
    client: TestClient,
    monkeypatch,
):
    captured_events: list[dict[str, str]] = []

    def _capture_audit_event(**kwargs):
        captured_events.append(
            {
                "event_name": kwargs.get("event_name", ""),
                "correlation_id": kwargs.get("correlation_id", ""),
            }
        )

    monkeypatch.setattr(backend_main, "log_audit_event", _capture_audit_event)

    id_hash = hashlib.sha256(b"555555555555").hexdigest()
    private_key = 987654321
    public_key = pow(backend_main.G, private_key, backend_main.P)

    enroll_response = client.post(
        "/enroll",
        json={
            "id_hash": id_hash,
            "encrypted_pii": "ciphertext_payload_correlation",
            "public_key": str(public_key),
        },
    )
    assert enroll_response.status_code == 200
    captured_events.clear()

    proof = _build_valid_proof(
        id_hash=id_hash,
        private_key=private_key,
        session_nonce="nonce-correlation-001",
        random_nonce=333444555,
    )

    correlation_id = "cid-e2e-propagation-001"

    verify_response = client.post(
        "/verify",
        headers={"X-Correlation-ID": correlation_id},
        json={
            "id_hash": id_hash,
            "encrypted_pii": "ciphertext_payload_correlation",
            "public_key": str(public_key),
            "proof": proof,
            "risk_context": {
                "device_trust": {
                    "status": "unknown",
                    "provider": "play_integrity_native",
                    "detail": "header_propagation",
                    "integrity_token": "mock_trusted_token",
                    "request_hash": "unused_in_mock_mode",
                }
            },
        },
    )

    assert verify_response.status_code == 200
    assert verify_response.headers["X-Correlation-ID"] == correlation_id
    assert verify_response.json()["correlation_id"] == correlation_id

    assert captured_events
    assert all(event["correlation_id"] == correlation_id for event in captured_events)


def test_verify_missing_integrity_token_returns_review(client: TestClient):
    id_hash = hashlib.sha256(b"101010101010").hexdigest()
    private_key = 135791113
    public_key = pow(backend_main.G, private_key, backend_main.P)

    enroll_response = client.post(
        "/enroll",
        json={
            "id_hash": id_hash,
            "encrypted_pii": "ciphertext_payload_missing_token",
            "public_key": str(public_key),
        },
    )
    assert enroll_response.status_code == 200

    proof = _build_valid_proof(
        id_hash=id_hash,
        private_key=private_key,
        session_nonce="nonce-missing-token-001",
        random_nonce=24682468,
    )

    verify_response = client.post(
        "/verify",
        json={
            "id_hash": id_hash,
            "encrypted_pii": "ciphertext_payload_missing_token",
            "public_key": str(public_key),
            "proof": proof,
            "risk_context": {
                "device_trust": {
                    "status": "unknown",
                    "provider": "play_integrity_native",
                    "detail": "token_missing",
                }
            },
        },
    )

    payload = verify_response.json()
    assert verify_response.status_code == 200
    assert payload["verified"] is True
    assert payload["decision_status"] == "REVIEW"
    assert payload["retry_allowed"] is True
    assert "DEVICE_TRUST_UNAVAILABLE" in payload["reason_codes"]


def test_verify_invalid_integrity_token_returns_reject(client: TestClient):
    id_hash = hashlib.sha256(b"202020202020").hexdigest()
    private_key = 445566778
    public_key = pow(backend_main.G, private_key, backend_main.P)

    enroll_response = client.post(
        "/enroll",
        json={
            "id_hash": id_hash,
            "encrypted_pii": "ciphertext_payload_invalid_token",
            "public_key": str(public_key),
        },
    )
    assert enroll_response.status_code == 200

    proof = _build_valid_proof(
        id_hash=id_hash,
        private_key=private_key,
        session_nonce="nonce-invalid-token-001",
        random_nonce=55667788,
    )

    verify_response = client.post(
        "/verify",
        json={
            "id_hash": id_hash,
            "encrypted_pii": "ciphertext_payload_invalid_token",
            "public_key": str(public_key),
            "proof": proof,
            "risk_context": {
                "device_trust": {
                    "status": "unknown",
                    "provider": "play_integrity_native",
                    "integrity_token": "mock_invalid_token",
                    "request_hash": "unused_in_mock_mode",
                }
            },
        },
    )

    payload = verify_response.json()
    assert verify_response.status_code == 200
    assert payload["decision_status"] == "REJECT"
    assert payload["retry_allowed"] is False
    assert "DEVICE_TRUST_LOW" in payload["reason_codes"]


def test_verify_transient_integrity_error_returns_review_retryable(client: TestClient):
    id_hash = hashlib.sha256(b"303030303030").hexdigest()
    private_key = 556677889
    public_key = pow(backend_main.G, private_key, backend_main.P)

    enroll_response = client.post(
        "/enroll",
        json={
            "id_hash": id_hash,
            "encrypted_pii": "ciphertext_payload_transient",
            "public_key": str(public_key),
        },
    )
    assert enroll_response.status_code == 200

    proof = _build_valid_proof(
        id_hash=id_hash,
        private_key=private_key,
        session_nonce="nonce-transient-token-001",
        random_nonce=66778899,
    )

    verify_response = client.post(
        "/verify",
        json={
            "id_hash": id_hash,
            "encrypted_pii": "ciphertext_payload_transient",
            "public_key": str(public_key),
            "proof": proof,
            "risk_context": {
                "device_trust": {
                    "status": "unknown",
                    "provider": "play_integrity_native",
                    "integrity_token": "mock_transient_token",
                    "request_hash": "unused_in_mock_mode",
                }
            },
        },
    )

    payload = verify_response.json()
    assert verify_response.status_code == 200
    assert payload["decision_status"] == "REVIEW"
    assert payload["retry_allowed"] is True
    assert payload["retry_policy"] == "WAIT_BEFORE_RETRY"
    assert "DEVICE_TRUST_UNAVAILABLE" in payload["reason_codes"]


def test_non_dev_mock_mode_returns_configuration_review(
    client: TestClient,
    monkeypatch,
):
    monkeypatch.setenv("EKYC_BACKEND_ENV", "prod")
    monkeypatch.setenv("EKYC_INTEGRITY_VERIFIER_MODE", "mock")
    monkeypatch.setenv("EKYC_CLIENT_AUTH_MODE", "disabled")
    monkeypatch.setenv("EKYC_ALLOW_INSECURE_NO_AUTH_IN_NON_DEV", "true")

    id_hash = hashlib.sha256(b"404040404040").hexdigest()
    private_key = 998877665
    public_key = pow(backend_main.G, private_key, backend_main.P)

    enroll_response = client.post(
        "/enroll",
        json={
            "id_hash": id_hash,
            "encrypted_pii": "ciphertext_payload_nondev_mock",
            "public_key": str(public_key),
        },
    )
    assert enroll_response.status_code == 200

    proof = _build_valid_proof(
        id_hash=id_hash,
        private_key=private_key,
        session_nonce="nonce-nondev-mock-001",
        random_nonce=77889911,
    )

    verify_response = client.post(
        "/verify",
        json={
            "id_hash": id_hash,
            "encrypted_pii": "ciphertext_payload_nondev_mock",
            "public_key": str(public_key),
            "proof": proof,
            "risk_context": {
                "device_trust": {
                    "status": "trusted",
                    "provider": "mock",
                    "integrity_token": "mock_trusted_token",
                }
            },
        },
    )

    payload = verify_response.json()
    assert verify_response.status_code == 200
    assert payload["decision_status"] == "REVIEW"
    assert payload["retry_allowed"] is True
    assert "DEVICE_TRUST_UNAVAILABLE" in payload["reason_codes"]
