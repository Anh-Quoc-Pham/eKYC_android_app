# Decision Engine Specification

## Scope
This document defines the normalized decision contract used between Flutter app and FastAPI backend for pilot-ready eKYC verification.

## Contract Goals
- Separate transport status from business decision.
- Return deterministic outcomes with explicit retry semantics.
- Preserve compatibility with legacy fields (`verified`, `reason`, `score`).

## Response Contract
`/verify` and rate-limit rejection responses include these fields:

- `verified`: boolean legacy signal.
- `reason`: backend verification reason.
- `score`: numeric verification score.
- `server_time`: UNIX timestamp.
- `decision_status`: `PASS | REVIEW | REJECT`.
- `reason_codes`: array of normalized reason codes.
- `user_message_key`: stable i18n-ready key.
- `retry_allowed`: boolean.
- `retry_reason`: machine-readable retry reason.
- `retry_policy`: `IMMEDIATE | USER_CORRECTION | WAIT_BEFORE_RETRY | MANUAL_REVIEW | NO_RETRY`.
- `correlation_id`: end-to-end request id.
- `risk_signals`: normalized risk signals snapshot used for decisioning.

## Decision States
- `PASS`: automatic approval for the current verification step.
- `REVIEW`: not auto-approved; may be retryable or manual-review-only.
- `REJECT`: hard reject for security or retry-limit conditions.

## Reason Codes
Current normalized reason codes:

- OCR quality: `OCR_LOW_CONFIDENCE`, `OCR_FIELD_MISMATCH`, `DOCUMENT_GLARE`, `DOCUMENT_BLUR`, `DOCUMENT_CROP_INVALID`
- Face/liveness: `FACE_MISMATCH`, `LIVENESS_LOW_CONFIDENCE`
- Device trust: `DEVICE_TRUST_UNAVAILABLE`, `DEVICE_TRUST_LOW`
- Session/network: `SESSION_RETRY_LIMIT`, `NETWORK_INTERRUPTED`
- Internal/fallback: `INTERNAL_REVIEW_REQUIRED`, `UNKNOWN_ERROR_SAFE_FALLBACK`

## Mapping Rules (Evaluation Order)
1. Verified with no reasons -> `PASS` + `NO_RETRY`.
2. Retry limit present -> `REJECT` + `NO_RETRY`.
3. Face mismatch or device trust low -> `REJECT` + `NO_RETRY`.
4. Document quality issues -> `REVIEW` + `USER_CORRECTION`.
5. Liveness low confidence -> `REVIEW` + `IMMEDIATE`.
6. Network interruption -> `REVIEW` + `IMMEDIATE`.
7. Device trust unavailable -> `REVIEW` + `WAIT_BEFORE_RETRY`.
8. Internal review required -> `REVIEW` + `MANUAL_REVIEW`.
9. Unknown cases -> safe fallback `REVIEW` + `IMMEDIATE`.

## Trust Safety Default
- Verify flow enforces trust-signal presence (`enforce_device_trust_signal=True`).
- If verify request is missing `risk_context.device_trust`, decision falls back to:
	- `decision_status=REVIEW`
	- `reason_codes` includes `DEVICE_TRUST_UNAVAILABLE`
	- `retry_policy=WAIT_BEFORE_RETRY`
- This prevents silent auto-pass when trust signal is absent.

## Risk Context Input
Client can submit risk context in both enroll and verify:

- `ocr`: confidence and mismatch/quality flags.
- `face`: match score and liveness confidence.
- `device_trust`: status, score, provider, detail.
- `retry`: attempt count and max attempts.
- `network_interrupted`: boolean.

## Client Parsing/Fallback Rules
Flutter parses decision payload and applies safe fallbacks:

- Missing/unknown `decision_status` -> infer from `verified`.
- Missing reason codes -> infer from `reason` and message.
- Network exceptions -> synthetic `REVIEW` with immediate retry policy.

## Test Coverage
- Backend policy tests: `backend/tests/test_decision_engine.py`.
- Backend contract tests: `backend/tests/test_api_e2e.py`.
- Flutter parser/retry tests: `test/decision_models_test.dart`.

## Change Management
Any future policy change must keep:
- Enum stability for external clients.
- Backward compatibility of existing fields.
- Updated tests for both backend and Flutter parsing paths.
