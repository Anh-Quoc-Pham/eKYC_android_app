# Staging Test Matrix - Play Integrity

This matrix defines mandatory staging scenarios for phase-2 integrity validation.

## S1 - Valid Token / Trusted Path
- Setup:
  - staging app config enabled (`EKYC_PLAY_INTEGRITY_ENABLED=true`)
  - backend verifier mode `google`
  - valid credentials and package configuration
- Steps:
  1. Run full verify flow on Play-certified device.
  2. Capture correlation id from response.
  3. Trace matching audit events.
- Expected app behavior:
  - verify completes without trust acquisition error.
  - result screen reflects successful or policy-clean outcome.
- Expected backend behavior:
  - verifier status `trusted`.
  - normalized trust signal status `trusted`.
- Expected decision outcome:
  - PASS when no other independent risk reasons are triggered.
- Expected logs/audit behavior:
  - `integrity_check_result` and `final_decision_issued` present.
  - no raw token in metadata.
- Pass/Fail criteria:
  - pass only if trusted mapping and final decision align with policy and logs are redacted.

## S2 - Missing Token
- Setup:
  - app staging build where Play Integrity is disabled or token not acquired path is reproducible.
- Steps:
  1. Execute verify flow and force no token in `device_trust` evidence.
  2. Capture response and audit trail.
- Expected app behavior:
  - flow completes with non-pass decision; retry guidance shown.
- Expected backend behavior:
  - verifier status `unavailable`.
  - trust signal normalized to `status=unavailable`.
- Expected decision outcome:
  - REVIEW.
  - reason includes `DEVICE_TRUST_UNAVAILABLE`.
  - retry policy `WAIT_BEFORE_RETRY`.
- Expected logs/audit behavior:
  - integrity event includes `token_present=false`.
  - no token material in logs.
- Pass/Fail criteria:
  - fail if any silent PASS occurs with missing trust token.

## S3 - Invalid Token
- Setup:
  - use controlled backend test hook/request replay method to submit malformed or tampered token evidence.
- Steps:
  1. Submit verify request with invalid integrity token payload.
  2. Capture decision response and reason codes.
- Expected app behavior:
  - receives hard security failure outcome.
- Expected backend behavior:
  - verifier status `invalid`.
  - normalized trust status `low`.
- Expected decision outcome:
  - REJECT.
  - reason includes `DEVICE_TRUST_LOW` and/or `DEVICE_TRUST_INVALID_TOKEN`.
- Expected logs/audit behavior:
  - integrity event records invalid detail, token redacted.
- Pass/Fail criteria:
  - fail if invalid token leads to PASS or retryable REVIEW without policy justification.

## S4 - Transient Verification Failure
- Setup:
  - induce temporary verifier/API failure (network disruption, controlled service interruption, or mapped transient error).
- Steps:
  1. Run verify while transient condition is active.
  2. Retry after condition is removed.
- Expected app behavior:
  - initial attempt returns retry-oriented outcome.
  - follow-up attempt can recover.
- Expected backend behavior:
  - initial verifier status `transient_error` -> normalized unavailable.
  - retry attempt processes normally.
- Expected decision outcome:
  - first result REVIEW with retry allowed and wait-before-retry policy.
- Expected logs/audit behavior:
  - transient category captured in integrity event metadata.
  - retry event emitted when retry policy allows.
- Pass/Fail criteria:
  - fail if transient condition causes hard reject without matching trust-low evidence.

## S5 - Configuration Missing Or Misconfigured
- Setup:
  - staging config missing package name or credentials, or invalid project linkage.
- Steps:
  1. Deploy misconfigured staging backend.
  2. Execute verify flow once.
  3. Restore correct config.
- Expected app behavior:
  - non-pass decision with retry guidance.
- Expected backend behavior:
  - verifier status `configuration_error`.
  - normalized trust status `unavailable`.
- Expected decision outcome:
  - REVIEW with `DEVICE_TRUST_CONFIGURATION_ERROR` and `DEVICE_TRUST_UNAVAILABLE`.
- Expected logs/audit behavior:
  - configuration error detail visible in sanitized metadata.
- Pass/Fail criteria:
  - fail if misconfiguration still allows trusted/PASS outcomes.

## S6 - Non-Dev Mock Path Blocked
- Setup:
  - set backend non-dev env with `EKYC_INTEGRITY_VERIFIER_MODE=mock` intentionally.
- Steps:
  1. Run verify with otherwise valid payload.
  2. Inspect response reason codes and metadata.
- Expected app behavior:
  - non-pass response.
- Expected backend behavior:
  - mock mode in non-dev is treated as configuration error.
- Expected decision outcome:
  - REVIEW (safe non-pass), trust unavailable reasons present.
- Expected logs/audit behavior:
  - integrity event indicates configuration problem, no token leakage.
- Pass/Fail criteria:
  - fail if non-dev mock mode results in trusted/PASS.

## S7 - Retry Behavior After Transient Trust Failure
- Setup:
  - induce transient error once, then recover environment.
- Steps:
  1. Run verify during transient failure.
  2. Retry same user journey after recovery.
  3. Compare both responses and logs.
- Expected app behavior:
  - first attempt exposes retry path.
  - second attempt can proceed and settle according to trust and other risks.
- Expected backend behavior:
  - first attempt transient -> unavailable mapping.
  - second attempt reflects current verifier result.
- Expected decision outcome:
  - first REVIEW with retry allowed.
  - second outcome may be PASS/REVIEW/REJECT depending on trust and risk context.
- Expected logs/audit behavior:
  - first attempt includes `retry_requested` event.
  - both attempts share traceable correlation ids.
- Pass/Fail criteria:
  - fail if retry path is blocked despite transient classification.

## S8 - Decision Outcome Coverage (PASS / REVIEW / REJECT)
- Setup:
  - prepare controlled datasets to trigger each category:
    - trusted clean path -> PASS
    - unavailable/transient/config -> REVIEW
    - invalid/untrusted trust -> REJECT
- Steps:
  1. Execute one representative scenario for each target outcome.
  2. Record reason codes and retry policies.
- Expected app behavior:
  - UI state and action options match backend decision contract.
- Expected backend behavior:
  - outputs include deterministic `decision_status`, `reason_codes`, `retry_policy`.
- Expected decision outcome:
  - all three outcomes observed with policy-consistent reasons.
- Expected logs/audit behavior:
  - final decision event matches response payload per scenario.
- Pass/Fail criteria:
  - fail if any outcome bucket cannot be reproduced under expected conditions.

## S9 - Correlation ID Visibility Through Request/Response/Logs
- Setup:
  - send fixed `X-Correlation-ID` from app/test client.
- Steps:
  1. Execute verify request with known correlation id.
  2. Confirm response header and payload.
  3. Query audit logs for same id.
- Expected app behavior:
  - correlation id retained for support diagnostics.
- Expected backend behavior:
  - correlation id preserved and echoed.
- Expected decision outcome:
  - independent of correlation id test itself; decision follows scenario conditions.
- Expected logs/audit behavior:
  - all emitted events for request carry exact same correlation id.
- Pass/Fail criteria:
  - fail if any hop loses or mutates correlation id.

## S10 - Privacy-Safe Logging (No Raw Token Leakage)
- Setup:
  - run scenarios that include token-bearing requests and failure paths.
- Steps:
  1. Capture representative audit log samples.
  2. Search for raw token key/value leakage patterns.
  3. Validate redaction output for sensitive keys.
- Expected app behavior:
  - unaffected functionally.
- Expected backend behavior:
  - metadata sanitizer redacts sensitive fields recursively.
- Expected decision outcome:
  - unchanged by logging checks; follows scenario conditions.
- Expected logs/audit behavior:
  - sensitive fields are `[redacted]`.
  - no raw `integrity_token`, `play_integrity_token`, or `attestation_token` values present.
- Pass/Fail criteria:
  - immediate fail and NO-GO if any raw token leakage is observed.