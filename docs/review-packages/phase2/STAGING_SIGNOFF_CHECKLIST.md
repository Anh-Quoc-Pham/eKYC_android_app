# Staging Signoff Checklist - Play Integrity Phase 2

All roles must explicitly sign before moving beyond controlled staging validation.

## Android Engineer Signoff
- [ ] Staging build uses correct app env values (`EKYC_ENV`, API base URL, Play Integrity toggles).
- [ ] Real token acquisition path validated on required devices.
- [ ] Native error categories observed and mapped as expected.
- [ ] Retry UX behavior matches backend retry policy semantics.
- [ ] Correlation id is visible for support/debug workflow.

Name:
Date:
Decision (GO / NO-GO):
Notes:

## Backend Engineer Signoff
- [ ] Staging runtime uses `EKYC_BACKEND_ENV=staging` and `EKYC_INTEGRITY_VERIFIER_MODE=google`.
- [ ] Package name and credential configuration validated.
- [ ] Scenario matrix outcomes match expected decision mapping.
- [ ] Non-dev mock mode block behavior verified.
- [ ] No backend regression observed in existing verify and audit flows.

Name:
Date:
Decision (GO / NO-GO):
Notes:

## Security Reviewer Signoff
- [ ] Raw token data is not present in audit logs.
- [ ] Redaction policy covers integrity token key variants in sampled events.
- [ ] Failure behavior is fail-safe (no silent PASS on missing/ambiguous trust).
- [ ] Invalid/untrusted token paths produce non-pass outcomes.
- [ ] Evidence package includes correlation-traceable audit samples.

Name:
Date:
Decision (GO / NO-GO):
Notes:

## Release Owner / Project Owner Signoff
- [ ] PR review checklist completed.
- [ ] Staging validation plan and matrix fully executed.
- [ ] All blocking findings triaged and resolved or accepted with explicit risk.
- [ ] Rollback procedure rehearsed and owner assigned.
- [ ] Final rollout decision documented.

Name:
Date:
Decision (GO / NO-GO):
Notes: