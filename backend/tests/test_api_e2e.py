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
    }

    verify_response = client.post("/verify", json=verify_payload)
    assert verify_response.status_code == 200
    assert verify_response.json()["verified"] is True
    assert verify_response.json()["reason"] == "ok"

    replay_response = client.post("/verify", json=verify_payload)
    assert replay_response.status_code == 200
    assert replay_response.json()["verified"] is False
    assert replay_response.json()["reason"] == "replay_detected"


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
