# Android Pilot Readiness

## Executive Summary
The project now has a pilot-grade decision and audit foundation with deterministic retry behavior and correlation tracing. Core architecture priorities are implemented; device integrity is intentionally scaffolded and requires final production integration.

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
Status: SCAFFOLDED

- Device trust abstraction and dev mocks are active.
- Production path currently uses safe placeholder provider.
- Verify decision path enforces trust-signal presence as safe default.
- Real Play Integrity attestation verification is still required.

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

## Manual Actions Required Before External Production Launch
1. Implement real Play Integrity integration and backend token verification.
2. Route audit logs to centralized SIEM with retention/access controls.
3. Add runbook for manual review queue and escalation SLA.
4. Add staged penetration and abuse testing on Android builds.

## Manual Steps Matrix

### Fully implemented in repository
- Decision contract (`PASS/REVIEW/REJECT`) with retry policies.
- Correlation id propagation through request, response, and audit events.
- Audit logging with recursive sensitive-field redaction.
- Retry/failure UI mapping by decision status and policy.
- Safety tests for contract, redaction, correlation, rate limit, and network fallback.

### Scaffolded only (not production-complete)
- Android trust integration layer (`DeviceTrustService` + provider abstraction).
- Non-dev default trust provider (`PlayIntegrityScaffoldProvider`) returning unavailable.
- Decision behavior for unavailable/low trust signals.

### Requires human setup outside repository
- Cloud/GCP setup for Play Integrity verification backend trust chain.
- Environment secret provisioning and key rotation policy.
- SIEM pipeline onboarding for audit events and alert routing.
- Manual review operations process and incident escalation ownership.

### Required for real Play Integrity activation
1. Android token acquisition flow (nonce, request, token retrieval) in app layer.
2. Backend verification path against Google integrity verdict.
3. Binding of token to session correlation and anti-replay checks.
4. Trust-score mapping signed off with security owner.
5. Staging soak validation with monitoring and rollback criteria.

### Required for release/signing completion
1. Production keystore creation and secured custody.
2. Gradle signing configuration for release build variants.
3. Play Console app signing and internal testing track configuration.
4. Release checklist: versioning, changelog, rollback plan, approvers.
5. Final human approval gate for pilot cohort rollout.

## Pilot Go/No-Go
Recommendation: GO for controlled Android pilot with internal/staged users, with explicit acknowledgment that device integrity is scaffolded (not final production attestation).

## Suggested Pilot Gate Checklist
- [ ] Staging uses HTTPS-only backend endpoint.
- [ ] Correlation id appears in client and backend logs for sampled sessions.
- [ ] Retry policy behavior verified for all major reason families.
- [ ] Manual review handling path is operationally documented.
- [ ] Integrity integration roadmap and owner/date are committed.
