# Staging Validation Plan - Play Integrity Phase 2

## Objective
Validate real Android Play Integrity token acquisition and backend verification behavior in staging, with explicit evidence that:
- trust normalization is correct,
- decision outcomes are safe and deterministic,
- privacy/logging constraints are enforced,
- configuration errors fail safely.

## Scope Boundaries

### Implemented in repo
- Android MethodChannel token flow.
- Flutter trust signal transport with request hash and correlation id binding.
- Backend verifier integration and trust normalization.
- Decision engine mapping and audit redaction safeguards.

### Requires external human setup
- Google Cloud Play Integrity API enablement.
- Service account and permissions.
- Play Console linkage and package alignment.
- Staging secret provisioning and runtime credential injection.

### Validated locally already
- Flutter analyze/tests.
- Backend test suite.
- Android debug compile.

### Must be validated in real staging
- Live Google decode path.
- Real device integrity verdict behavior.
- Operational triage and rollback readiness.

## Prerequisites
- Approved PR branch with phase-2 commit stack.
- Staging backend deployment pipeline access.
- Staging Android build distribution mechanism.
- Access to staging logs and audit event stream.
- Access to test account data and repeatable test identity payload.

## Required External Setup
1. Enable Play Integrity API on target cloud project.
2. Confirm Android package name in cloud and Play Console mapping.
3. Provision service account with token decode permission.
4. Deliver service account credentials securely to staging runtime.
5. Confirm outbound connectivity from backend to Play Integrity API endpoint.

## Required Environment And Config Values

### App (staging build)
- `EKYC_ENV=staging`
- `EKYC_API_BASE_URL_STAGING=https://<staging-api-host>`
- `EKYC_PLAY_INTEGRITY_ENABLED=true`
- `EKYC_PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER=<cloud-project-number>`

### Backend (staging runtime)
- `EKYC_BACKEND_ENV=staging`
- `EKYC_INTEGRITY_VERIFIER_MODE=google`
- `EKYC_PLAY_INTEGRITY_ANDROID_PACKAGE=<applicationId>`
- `EKYC_PLAY_INTEGRITY_CREDENTIALS_FILE=<secret-file-path>` or
  `EKYC_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON=<secret-json>`
- Optional policy toggles:
  - `EKYC_PLAY_INTEGRITY_ALLOW_BASIC_INTEGRITY` (default false)
  - `EKYC_PLAY_INTEGRITY_REQUIRE_LICENSED_APP` (default true)

## Required Accounts And Permissions
- Android engineer:
  - access to staging app build/distribution
  - access to test devices
- Backend engineer:
  - access to staging env variables and logs
  - permission to deploy backend config changes
- Security reviewer:
  - access to audit logs for token redaction checks
  - access to policy and risk review artifacts
- Release owner:
  - approval authority for staging gate decisions

## Devices And Test Conditions
- At least 3 Android devices:
  - one modern Play-certified device
  - one older Play-certified device
  - one device/profile expected to produce weaker integrity or intermittent failures
- Network profiles:
  - stable wifi
  - degraded/high-latency network
  - temporary network interruption
- Ensure Play services and Play Store are available on primary validation devices.

## Exact Validation Sequence
1. Phase A - Environment preflight
   - Verify app and backend env values match required matrix.
   - Confirm backend `/health` is reachable over staging HTTPS.
   - Expected result: clean preflight checklist, no missing required keys.
2. Phase B - Baseline flow check
   - Run one nominal verify journey on certified device.
   - Confirm request/response correlation id continuity.
   - Expected result: integrity token acquired, backend verifies, decision path deterministic.
3. Phase C - Execute scenario matrix
   - Run all scenarios in `STAGING_TEST_MATRIX.md` (S1-S10).
   - Expected result: each scenario outcome matches expected decision and audit behavior.
4. Phase D - Failure path and retry verification
   - Repeat transient and unavailable scenarios to validate retry policy behavior.
   - Expected result: review-with-retry behavior, no silent pass.
5. Phase E - Privacy and audit verification
   - Inspect sampled logs for raw token leakage and redaction compliance.
   - Expected result: no raw token values in emitted metadata.
6. Phase F - Signoff and go/no-go
   - Complete `STAGING_SIGNOFF_CHECKLIST.md` with role-based approvals.
   - Expected result: explicit GO or NO-GO with evidence links.

## Failure Handling And Triage Path
- Symptom: token not acquired on app
  - First owner: Android engineer
  - Check: native error category, Play services availability, cloud project number config
- Symptom: backend reports configuration/transient verification error
  - First owner: Backend engineer
  - Check: verifier mode, credentials presence, package name, network egress, API permissions
- Symptom: decision outcome mismatch with expected policy
  - First owner: Backend engineer + Security reviewer
  - Check: normalized trust signal fields and reason code mapping
- Symptom: token leakage in logs
  - First owner: Security reviewer
  - Action: immediate NO-GO, stop staging rollout, open blocking fix

## Evidence To Capture During Validation
- Build metadata:
  - app version/build id
  - backend image/tag and config snapshot (without secrets)
- Per scenario evidence:
  - scenario id and device id
  - request correlation id
  - response payload excerpt (`decision_status`, `reason_codes`, `retry_policy`)
  - corresponding audit events (`integrity_check_result`, `final_decision_issued`, `retry_requested` when applicable)
- Security evidence:
  - sampled logs proving no raw `integrity_token` leakage
- Signoff evidence:
  - completed checklist with owner/date/decision