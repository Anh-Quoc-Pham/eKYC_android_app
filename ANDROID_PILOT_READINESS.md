# Android Pilot Readiness

## Executive Summary
The repository now includes:
- phase-1 decision and audit baseline,
- phase-2 real Android Play Integrity integration,
- phase-3 backend hardening and release/ops readiness package.

The project is suitable for controlled Android pilot progression, but remains dependent on external security, release, and cloud ownership tasks before production-grade operation.

## Priority Status (A-G)

### A) Decision Engine Contract
Status: COMPLETE

- PASS/REVIEW/REJECT with retry policy remains stable.
- Integrity trust normalization still routes through the same decision engine.

### B) Integrity Integration (Android -> Backend)
Status: COMPLETE IN REPO, EXTERNAL VALIDATION PENDING

- Real token acquisition path and backend verifier integration implemented.
- External cloud and credential setup still required for real non-dev verification.

### C) Backend Protection Baseline
Status: COMPLETE FOR PILOT BASELINE

- Protected-route auth for /enroll and /verify.
- Environment-driven secure defaults for non-dev.
- Explicit CORS middleware policy.
- Route-aware rate limiting for sensitive endpoints.
- Readiness diagnostics endpoint (/ready).
- Shared-secret route auth is treated as pilot coarse gating, not strong client identity proof.

### D) Logging and Privacy Safety
Status: COMPLETE FOR PILOT BASELINE

- Correlation id propagation preserved.
- Redaction policy preserved for sensitive fields.
- Additional hardening events available for auth/rate-limit/error triage.

### E) Android Release Readiness
Status: IMPLEMENTED IN REPO, HUMAN SIGNING OWNERSHIP PENDING

- Gradle guardrails for release-signing enforcement added.
- Signing config path prepared via keystore.properties (not committed).
- Release checklist and rollback criteria documented.

### F) Operational Readiness Material
Status: COMPLETE IN REPO (DOCUMENTATION SCAFFOLD)

- Ops runbook added.
- Pilot support triage guide added.
- Release checklist with trigger-based rollback guidance added.

### G) External Ownership Dependencies
Status: PENDING (OUTSIDE REPO)

- Secret governance and rotation ownership.
- Play Console release track operations.
- Alert routing destinations and on-call ownership.
- Security and release governance approvals.

## Validation Snapshot
- Flutter analyze: pending phase-3 final rerun.
- Flutter tests: passed after phase-3 app changes.
- Backend pytest: passed (37 tests).
- Android debug build: pending phase-3 final rerun.

## Implemented vs Manual Split

### Implemented in repo
- Backend auth gate, CORS controls, rate limiting, readiness endpoint.
- App client support for backend auth headers.
- Android release signing guardrails in Gradle.
- Ops/runbook/triage/release checklist docs.

### Scaffolded only
- In-memory rate limiting suitable for pilot but not distributed.
- Shared-secret service auth suitable for pilot baseline but not strong mobile client authentication.

### Security model clarification
- The primary trust stack for pilot decisions is:
	- Play Integrity verdicts,
	- decision engine policy mapping,
	- rate limiting and abuse controls,
	- operational monitoring and alerting.
- Shared-secret headers are supportive coarse controls, not standalone high-assurance client auth.

### Requires human setup outside repo
- Real keystore material and CI secret injection.
- Cloud/Play Console ownership and verifier credentials.
- Alert integrations and incident ownership model.

## Recommendation
GO for controlled staging and pilot progression with explicit gate checks. Do not classify as production-ready until external ownership dependencies are complete and validated in staging operations.
