# Release Checklist (Phase 3)

## Pre-merge Checks
- [ ] IMPLEMENTATION_PLAN.md updated with phase-3 outcomes and risks.
- [ ] BACKEND_HARDENING_SPEC.md reviewed by backend and security owners.
- [ ] Android release readiness guardrails reviewed.
- [ ] New tests for hardening behavior added and passing.
- [ ] No unresolved blocker in PR checklist and staging docs.

## Pre-staging Checks
- [ ] Backend env configured:
  - EKYC_BACKEND_ENV=staging
  - EKYC_CLIENT_AUTH_MODE configured
  - required auth secret configured
  - EKYC_ALLOWED_ORIGINS configured for staging policy
  - integrity verifier staging config present
- [ ] App staging build defines configured (API endpoint, integrity settings, auth header values if used).
- [ ] /ready returns expected posture (prefer ready).
- [ ] Staging validation matrix execution plan agreed.

## Pre-release Checks
- [ ] flutter analyze
- [ ] flutter test
- [ ] pytest -q backend/tests
- [ ] Release signing present and validated (no debug-signing fallback for production-intended build).
- [ ] Release artifact metadata recorded (version, commit SHA, environment profile).
- [ ] Rollback owner and communication channel confirmed.

## Post-release Checks
- [ ] Monitor /health and /ready outcomes.
- [ ] Monitor auth_denied and abuse_rate_limited trends.
- [ ] Monitor decision distribution and integrity verification status drift.
- [ ] Sample logs to confirm token redaction remains intact.
- [ ] Confirm no unexpected spike in REVIEW/REJECT caused by config regressions.

## Rollback Trigger Points
Trigger immediate rollback consideration when any occurs:
- [ ] Sensitive data/token leakage detected in logs.
- [ ] sustained /ready not_ready in active pilot window.
- [ ] prolonged 5xx spike on /enroll or /verify.
- [ ] widespread unauthorized_client due to release configuration mismatch.
- [ ] integrity verifier degradation causing major pilot blockage without rapid mitigation.

## Rollback Actions
1. Stop rollout traffic intake.
2. Revert backend/app artifact to last known-good versions.
3. Capture correlation ids and timeline evidence.
4. Open blocking incident and fix PR.
5. Re-run pre-staging and pre-release checks before retry.
