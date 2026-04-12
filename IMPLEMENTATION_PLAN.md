# IMPLEMENTATION_PLAN

## Phase
- Current phase: Phase 3 - Backend Hardening, Android Release Readiness, Operational Readiness.
- Goal: move the Android-first pilot baseline from feature-complete trust integration toward controlled pilot and pre-production readiness.
- Status: Completed in repository scope.

## 1. Findings Summary (Pre-implementation)

### FastAPI sensitive-surface baseline
- Sensitive routes were POST /enroll and POST /verify.
- Missing controls before phase-3:
   - no service-level endpoint auth,
   - no explicit CORS policy,
   - no readiness diagnostics endpoint,
   - rate limiting only existed for /verify.

### Config and safety baseline
- App and backend already had environment-driven integrity settings.
- Non-dev secure defaults were not enforced for endpoint access control.
- Error surfaces for unhandled exceptions were not normalized for pilot-safe responses.

### Android release baseline
- Release build used debug signing fallback by default.
- No explicit release-signing enforcement guardrail existed.

### Documentation baseline
- Integrity and staging docs existed from phase-2.
- Backend hardening spec, ops runbook, pilot triage, and release checklist were still missing.

## 2. Assumptions Used
- Android-only scope remains; iOS stays out of scope.
- Pilot needs practical hardening, not enterprise IAM architecture.
- Phase-1 and phase-2 behavior should stay backward-compatible unless secure non-dev defaults require explicit tightening.
- External ownership (secret governance, Play Console operations, signing custody, alert routing) remains outside repo scope.

## 3. What Was Implemented

### A) Backend hardening
- Added env-driven service security settings in backend/main.py.
- Added protected-route auth middleware for /enroll and /verify.
   - auth modes: disabled, api_key, bearer, either
   - non-dev defaults now tighten to secure behavior
- Added explicit CORS middleware with environment-driven origin policy.
- Added route-aware rate limiting for both /enroll and /verify.
- Added /ready endpoint for non-secret readiness posture checks.
- Added safer unhandled exception response with correlation_id preservation.
- Preserved privacy-safe audit behavior and correlation logging continuity.

### B) Android release readiness and app compatibility
- Added app env support for backend auth headers in lib/config/app_config.dart.
- Updated lib/services/zkp_service.dart to attach:
   - X-EKYC-API-Key when configured
   - Authorization Bearer token when configured
- Added release signing guardrails in android/app/build.gradle.kts:
   - optional keystore.properties-based release signing config
   - enforceable release-signing checks via gradle properties

### C) Operational readiness package
- Added new docs:
   - BACKEND_HARDENING_SPEC.md
   - ANDROID_RELEASE_READINESS.md
   - OPS_READINESS_RUNBOOK.md
   - PILOT_SUPPORT_TRIAGE.md
   - RELEASE_CHECKLIST.md
- Updated operational/readiness docs:
   - README.md
   - AUDIT_AND_LOGGING_SPEC.md
   - ANDROID_PILOT_READINESS.md
- Tightened CI backend coverage to run full backend tests.

## 4. Test and Validation Updates

### New and updated tests
- Added backend/tests/test_hardening_baseline.py for:
   - allow/deny auth behavior,
   - non-dev secure default enforcement,
   - CORS preflight behavior,
   - /enroll rate-limit behavior,
   - readiness posture checks.
- Updated backend/tests/test_api_e2e.py for compatibility with new auth middleware in non-dev configuration test.
- Added Flutter tests in test/zkp_service_test.dart for API key and bearer header attachment.

### Validation results
- flutter analyze: passed
- flutter test: passed (20 tests)
- pytest -q backend/tests: passed (37 tests)
- flutter build apk --debug: passed

## 5. Implemented vs Scaffolded vs External

### Implemented in repo
- Backend protected-route auth, CORS policy, dual-route rate limiting, readiness endpoint.
- App-to-backend auth header support.
- Android release-signing guardrails in Gradle.
- Ops runbook, pilot triage guide, release checklist, and updated readiness docs.

### Scaffolded only
- In-memory rate limiting suitable for single-instance pilot baseline.
- Shared-secret auth model suitable for pilot baseline, but not strong mobile client authentication.

### Requires human or external setup
- Secret provisioning and rotation process ownership.
- keystore.properties material and CI secret injection.
- Play Console release operations.
- Alert routing destinations and on-call ownership.
- Staging and pilot exercises for runtime verification.

## 6. Remaining Manual Tasks
1. Configure non-dev backend auth secrets and auth mode policy.
2. Configure EKYC_ALLOWED_ORIGINS for staging/prod domains if web-origin access is required.
3. Complete keystore management and enable strict release signing in CI.
4. Configure centralized logging/alert routing and incident ownership.
5. Execute controlled staging validation and pilot signoff runbooks.

## 7. Known Risks
- In-memory limiter is not multi-instance/distributed-safe.
- Shared-secret auth requires disciplined secret rotation and must not be treated as high-assurance app identity proof.
- /ready endpoint is not network-restricted in code; deployment controls should restrict exposure.
- External cloud/release operations remain critical path for production readiness.
