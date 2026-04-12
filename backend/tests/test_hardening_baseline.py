import hashlib
from pathlib import Path
import sys

import pytest
from fastapi.testclient import TestClient

# Ensure backend/main.py is importable when tests are run from repo root.
sys.path.append(str(Path(__file__).resolve().parents[1]))

import main as backend_main


@pytest.fixture
def client(tmp_path, monkeypatch):
    test_db = tmp_path / "ekyc_hardening.db"
    monkeypatch.setattr(backend_main, "DB_PATH", test_db)
    backend_main._verify_rate_buckets.clear()
    backend_main._init_db()

    with TestClient(backend_main.app) as test_client:
        yield test_client


def test_dev_default_keeps_sensitive_routes_accessible_without_auth(client, monkeypatch):
    monkeypatch.setenv("EKYC_BACKEND_ENV", "dev")
    monkeypatch.delenv("EKYC_CLIENT_AUTH_MODE", raising=False)
    monkeypatch.delenv("EKYC_CLIENT_API_KEY", raising=False)

    response = client.post("/verify", json={})

    assert response.status_code == 422


def test_non_dev_default_requires_auth_secret(client, monkeypatch):
    monkeypatch.setenv("EKYC_BACKEND_ENV", "staging")
    monkeypatch.delenv("EKYC_CLIENT_AUTH_MODE", raising=False)
    monkeypatch.delenv("EKYC_CLIENT_API_KEY", raising=False)

    response = client.post("/verify", json={})

    assert response.status_code == 503
    assert response.json()["detail"] == "client_auth_secret_missing"


def test_non_dev_api_key_mode_denies_missing_key_and_allows_valid_key(client, monkeypatch):
    monkeypatch.setenv("EKYC_BACKEND_ENV", "staging")
    monkeypatch.setenv("EKYC_CLIENT_AUTH_MODE", "api_key")
    monkeypatch.setenv("EKYC_CLIENT_API_KEY", "pilot-shared-key")

    denied_response = client.post("/verify", json={})
    assert denied_response.status_code == 401
    assert denied_response.json()["detail"] == "unauthorized_client"

    allowed_response = client.post(
        "/verify",
        json={},
        headers={"X-EKYC-API-Key": "pilot-shared-key"},
    )
    assert allowed_response.status_code == 422


def test_non_dev_bearer_mode_allows_when_valid_token_present(client, monkeypatch):
    monkeypatch.setenv("EKYC_BACKEND_ENV", "staging")
    monkeypatch.setenv("EKYC_CLIENT_AUTH_MODE", "bearer")
    monkeypatch.setenv("EKYC_CLIENT_BEARER_TOKEN", "pilot-bearer-token")

    denied_response = client.post("/verify", json={})
    assert denied_response.status_code == 401

    allowed_response = client.post(
        "/verify",
        json={},
        headers={"Authorization": "Bearer pilot-bearer-token"},
    )
    assert allowed_response.status_code == 422


def test_non_dev_disabled_auth_is_blocked_without_explicit_override(client, monkeypatch):
    monkeypatch.setenv("EKYC_BACKEND_ENV", "staging")
    monkeypatch.setenv("EKYC_CLIENT_AUTH_MODE", "disabled")
    monkeypatch.delenv("EKYC_ALLOW_INSECURE_NO_AUTH_IN_NON_DEV", raising=False)

    blocked_response = client.post("/verify", json={})
    assert blocked_response.status_code == 503
    assert blocked_response.json()["detail"] == "client_auth_required_in_non_dev"

    monkeypatch.setenv("EKYC_ALLOW_INSECURE_NO_AUTH_IN_NON_DEV", "true")
    allowed_response = client.post("/verify", json={})
    assert allowed_response.status_code == 422


def test_cors_preflight_allows_dev_localhost_origin(client):
    response = client.options(
        "/verify",
        headers={
            "Origin": "http://localhost",
            "Access-Control-Request-Method": "POST",
        },
    )

    assert response.status_code == 200
    assert response.headers.get("access-control-allow-origin") == "http://localhost"


def test_cors_preflight_blocks_unknown_origin(client):
    response = client.options(
        "/verify",
        headers={
            "Origin": "https://malicious.example",
            "Access-Control-Request-Method": "POST",
        },
    )

    assert response.status_code == 400
    assert response.headers.get("access-control-allow-origin") is None


def test_enroll_rate_limit_is_enforced(client, monkeypatch):
    monkeypatch.setenv("EKYC_BACKEND_ENV", "dev")
    monkeypatch.setenv("EKYC_RATE_LIMIT_ENROLL_MAX_REQUESTS", "1")
    monkeypatch.setenv("EKYC_RATE_LIMIT_ENROLL_WINDOW_SECONDS", "60")

    id_hash = hashlib.sha256(b"enroll_rate_limit").hexdigest()
    payload = {
        "id_hash": id_hash,
        "encrypted_pii": "ciphertext_payload_for_rate_limit",
        "public_key": str(pow(backend_main.G, 3, backend_main.P)),
    }

    first_response = client.post("/enroll", json=payload)
    assert first_response.status_code == 200

    second_response = client.post("/enroll", json=payload)
    assert second_response.status_code == 429
    assert second_response.json()["detail"] == "rate_limited"


def test_readiness_reports_not_ready_in_non_dev_without_required_security_config(
    client,
    monkeypatch,
):
    monkeypatch.setenv("EKYC_BACKEND_ENV", "staging")
    monkeypatch.setenv("EKYC_CLIENT_AUTH_MODE", "api_key")
    monkeypatch.delenv("EKYC_CLIENT_API_KEY", raising=False)
    monkeypatch.setenv("EKYC_INTEGRITY_VERIFIER_MODE", "mock")
    monkeypatch.setenv("EKYC_ALLOWED_ORIGINS", "")
    monkeypatch.setenv("EKYC_READY_EXPOSE_DETAIL", "true")

    response = client.get("/ready")

    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "not_ready"
    assert payload["checks"]["client_auth_ready"] is False
    assert payload["checks"]["integrity_verifier_ready"] is False
    assert payload["checks"]["cors_ready"] is False


def test_readiness_hides_detailed_checks_by_default_in_non_dev(client, monkeypatch):
    monkeypatch.setenv("EKYC_BACKEND_ENV", "staging")
    monkeypatch.delenv("EKYC_READY_EXPOSE_DETAIL", raising=False)

    response = client.get("/ready")

    assert response.status_code == 200
    payload = response.json()
    assert "checks" not in payload
    assert "backend_env" not in payload


def test_readiness_reports_ready_in_dev_default(client, monkeypatch):
    monkeypatch.setenv("EKYC_BACKEND_ENV", "dev")
    monkeypatch.delenv("EKYC_CLIENT_AUTH_MODE", raising=False)
    monkeypatch.delenv("EKYC_CLIENT_API_KEY", raising=False)

    response = client.get("/ready")

    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "ready"
    assert payload["checks"]["client_auth_ready"] is True
    assert payload["checks"]["integrity_verifier_ready"] is True
    assert payload["checks"]["cors_ready"] is True
