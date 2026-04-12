from __future__ import annotations

from datetime import datetime, timezone
import json
import logging
from typing import Any, Mapping


_SENSITIVE_FIELD_KEYWORDS = {
    "encrypted_pii",
    "full_name",
    "date_of_birth",
    "cccd",
    "proof",
    "ciphertext",
    "iv",
    "tag",
    "aad_hash",
    "integrity_token",
    "play_integrity_token",
    "attestation_token",
}


_logger = logging.getLogger("ekyc.audit")
if not _logger.handlers:
    handler = logging.StreamHandler()
    handler.setFormatter(logging.Formatter("%(message)s"))
    _logger.addHandler(handler)
_logger.setLevel(logging.INFO)
_logger.propagate = False


def log_audit_event(
    *,
    event_name: str,
    correlation_id: str,
    decision_status: str | None = None,
    reason_codes: list[str] | None = None,
    metadata: Mapping[str, Any] | None = None,
) -> None:
    payload: dict[str, Any] = {
        "timestamp": datetime.now(tz=timezone.utc).isoformat(),
        "event_name": event_name,
        "correlation_id": correlation_id,
    }

    if decision_status:
        payload["decision_status"] = decision_status

    if reason_codes:
        payload["reason_codes"] = reason_codes

    if metadata:
        payload["metadata"] = _sanitize_mapping(metadata)

    _logger.info(json.dumps(payload, ensure_ascii=False, sort_keys=True))


def _sanitize_mapping(data: Mapping[str, Any]) -> dict[str, Any]:
    sanitized: dict[str, Any] = {}

    for key, value in data.items():
        lowered = key.lower()
        if any(token in lowered for token in _SENSITIVE_FIELD_KEYWORDS):
            sanitized[key] = "[redacted]"
            continue

        if isinstance(value, Mapping):
            sanitized[key] = _sanitize_mapping(value)
            continue

        if isinstance(value, list):
            sanitized[key] = [
                _sanitize_mapping(item) if isinstance(item, Mapping) else item
                for item in value
            ]
            continue

        sanitized[key] = value

    return sanitized
