# Android Pilot Readiness

## Executive Summary
The project now has a pilot-grade decision/audit foundation plus a real Play Integrity code path from Android app to backend verifier. The integration is implemented in-repo and test-covered, while full production activation still requires external Google Cloud/Play Console credential setup.

## Priority Status (A-E)

### A) Decision Engine (PASS/REVIEW/REJECT)
Status: COMPLETE

- Normalized backend decision engine with retry policy.
- Stable reason-code taxonomy.
- Compatibility retained with legacy response fields.
- Flutter parser and session model updated to consume structured outcomes.

### B) Auditability And Explainability
Status: COMPLETE

- Structured JSON audit events with correlation id.
- Sensitive metadata redaction for PII and cryptographic fields.
- Verify/rate-limit paths emit traceable decision events.

### C) Android Integrity/Trust Signals
Status: IMPLEMENTED IN REPO, EXTERNAL SETUP PENDING

- Native MethodChannel bridge requests real Play Integrity tokens on Android.
- Flutter trust provider attaches integrity evidence to verify flow.
- Backend verifies token via verifier module (`mock`/`google`) and normalizes verdict.
- Non-dev mock mode is treated as configuration error (safe non-pass).
- Final production verification still depends on cloud/package/credentials setup.

### D) Retry UX And User Flow
Status: COMPLETE (pilot scope)

- Result screen maps decision status + retry policy to actions.
- Retry options now depend on backend policy:
  - Face retry for immediate/wait policies.
  - OCR correction flow for user-correction policy.
- Correlation id and retry policy are visible for support diagnostics.

### E) Documentation And Operational Specs
Status: COMPLETE

- Decision contract spec.
- Audit/logging spec.
- Integrity integration notes.
- This readiness summary.

## Validation Results
- Flutter analyze: pass.
- Flutter tests: pass.
- Backend pytest suite: pass.
- Android debug build: pass.

## Manual Actions Required Before External Production Launch
1. Enable/configure Play Integrity API in Google Cloud and Play Console linkage.
2. Provision backend service account and secure credential delivery.
3. Configure non-dev backend env (`EKYC_INTEGRITY_VERIFIER_MODE=google`, package, credentials).
4. Route audit logs to centralized SIEM with retention/access controls.
5. Add staged penetration and abuse testing on Android builds.

## Manual Steps Matrix

### Fully implemented in repository
- Decision contract (`PASS/REVIEW/REJECT`) with retry policies.
- Correlation id propagation through request, response, and audit events.
- Audit logging with recursive sensitive-field redaction.
- Retry/failure UI mapping by decision status and policy.
- Safety tests for contract, redaction, correlation, rate limit, and network fallback.
- Real Play Integrity app-side token acquisition path (Android native bridge).
- Backend integrity verifier module and verdict normalization path.

### Scaffolded only (not production-complete)
- Dev mock trust modes (`mock_trusted`, `mock_low`, `mock_unavailable`).
- Optional fallback placeholder provider for explicit configuration-missing cases.

### Requires human setup outside repository
- Cloud/GCP setup for Play Integrity verification backend trust chain.
- Environment secret provisioning and key rotation policy.
- SIEM pipeline onboarding for audit events and alert routing.
- Manual review operations process and incident escalation ownership.

### Required for real Play Integrity activation
1. Google Cloud project setup and Play Integrity API enablement.
2. Service account creation and permission grant for decode API.
3. Configure backend credentials and package-name verification env vars.
4. Run staging verification against real tokens/devices.
5. Security sign-off for trust thresholds and rollout criteria.

### Required for release/signing completion
1. Production keystore creation and secured custody.
2. Gradle signing configuration for release build variants.
3. Play Console app signing and internal testing track configuration.
4. Release checklist: versioning, changelog, rollback plan, approvers.
5. Final human approval gate for pilot cohort rollout.

## Pilot Go/No-Go
Recommendation: GO for controlled Android pilot with explicit phase-2 scope. Treat real production activation as conditional on external Play Integrity setup completion and staging verification sign-off.

## Suggested Pilot Gate Checklist
- [ ] Staging uses HTTPS-only backend endpoint.
- [ ] Correlation id appears in client and backend logs for sampled sessions.
- [ ] Retry policy behavior verified for all major reason families.
- [ ] Manual review handling path is operationally documented.
- [ ] Integrity integration roadmap and owner/date are committed.
