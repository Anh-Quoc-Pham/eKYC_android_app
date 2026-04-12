# Audit And Logging Specification

## Scope
This document specifies structured audit events, correlation-id propagation, and sensitive-data redaction for the eKYC backend.

## Objectives
- Provide traceability for pilot operations and incident review.
- Avoid logging raw PII or cryptographic proof payloads.
- Support deterministic event correlation across app and backend.

## Log Format
Audit logs are emitted as JSON objects with stable fields:

- `timestamp`: UTC ISO-8601.
- `event_name`: event identifier.
- `correlation_id`: request/session trace id.
- `decision_status` (optional): normalized decision state.
- `reason_codes` (optional): normalized reason list.
- `metadata` (optional): sanitized context payload.

## Correlation ID Rules
- App sends `X-Correlation-ID` header and `correlation_id` in body.
- Backend middleware resolves/generates a correlation id.
- Backend echoes `X-Correlation-ID` response header.
- Final response payload includes `correlation_id`.

## Audit Events
Current event names:

- `session_started`
- `ocr_submitted`
- `ocr_evaluated`
- `face_liveness_submitted`
- `integrity_check_result`
- `face_liveness_evaluated`
- `final_decision_issued`
- `retry_requested`

## Redaction Policy
Metadata sanitization redacts keys containing sensitive tokens:

- `encrypted_pii`, `full_name`, `date_of_birth`, `cccd`
- `proof`, `ciphertext`, `iv`, `tag`, `aad_hash`
- `integrity_token`, `play_integrity_token`, `attestation_token`

Any key matching those keywords is replaced with `[redacted]` recursively.

## Operational Guidance
- Keep structured logs in immutable storage for pilot retention period.
- Pipe JSON logs to SIEM (Cloud Logging, ELK, Datadog, etc.).
- Build dashboards for:
  - Decision distribution (`PASS/REVIEW/REJECT`).
  - Retry policy trends.
  - Device trust availability and quality.
  - Rate-limit rejection spikes.

## Security Notes
- Do not log decrypted user attributes.
- Do not log private keys or raw proof internals.
- Do not log raw Play Integrity tokens.
- Treat correlation id as operational metadata, not user identity.

## Integrity Event Metadata Policy
- `integrity_check_result` logs verifier status metadata only:
  - status, provider, detail, verifier mode, retryable, token_present, error_code.
- Raw token material is excluded from emitted metadata and from normalized risk signals.

## Validation
- Confirm every `/verify` outcome emits `final_decision_issued`.
- Confirm retryable outcomes emit `retry_requested`.
- Confirm metadata redaction in sampled logs before pilot go-live.
