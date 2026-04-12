import json
from pathlib import Path
import sys

# Ensure backend modules are importable when tests are run from repo root.
sys.path.append(str(Path(__file__).resolve().parents[1]))

from audit_logging import _logger, _sanitize_mapping, log_audit_event  # noqa: E402


def test_sanitize_mapping_redacts_sensitive_fields_recursively():
    payload = {
        'full_name': 'NGUYEN VAN A',
        'metadata': {
            'encrypted_pii': 'ciphertext',
            'profile': {'date_of_birth': '1990-01-01'},
            'items': [
                {'proof': {'challenge': '123'}},
                {'safe_key': 'safe_value'},
            ],
        },
    }

    sanitized = _sanitize_mapping(payload)

    assert sanitized['full_name'] == '[redacted]'
    assert sanitized['metadata']['encrypted_pii'] == '[redacted]'
    assert sanitized['metadata']['profile']['date_of_birth'] == '[redacted]'
    assert sanitized['metadata']['items'][0]['proof'] == '[redacted]'
    assert sanitized['metadata']['items'][1]['safe_key'] == 'safe_value'


def test_log_audit_event_emits_json_with_redaction_and_correlation_id(monkeypatch):
    correlation_id = 'cid-audit-001'
    captured: dict[str, str] = {}

    def _capture(message: str) -> None:
        captured['payload'] = message

    monkeypatch.setattr(_logger, 'info', _capture)

    log_audit_event(
        event_name='final_decision_issued',
        correlation_id=correlation_id,
        decision_status='REVIEW',
        reason_codes=['DEVICE_TRUST_UNAVAILABLE'],
        metadata={
            'encrypted_pii': 'secret',
            'cccd': '012345678901',
            'safe_hint': 'keep',
        },
    )

    assert 'payload' in captured
    payload = json.loads(captured['payload'])

    assert payload['correlation_id'] == correlation_id
    assert payload['decision_status'] == 'REVIEW'
    assert payload['reason_codes'] == ['DEVICE_TRUST_UNAVAILABLE']
    assert payload['metadata']['encrypted_pii'] == '[redacted]'
    assert payload['metadata']['cccd'] == '[redacted]'
    assert payload['metadata']['safe_hint'] == 'keep'
