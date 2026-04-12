# Play Integrity Phase 2

## Scope
This document describes phase-2 implementation of real Play Integrity integration for the Android-first eKYC project.

## Implemented In Repository

### Android app
- Native bridge in `MainActivity` via MethodChannel `ekyc/play_integrity`.
- Supported native operations:
  - `prepareProvider`
  - `requestToken`
- Structured native failure categories:
  - `play_services_unavailable`
  - `transient_error`
  - `provider_invalid`
  - `configuration_error`
  - `unexpected_error`

### Flutter layer
- `DeviceTrustService` chooses provider by environment/config.
- Dev keeps explicit mock behavior (`mock_trusted`, `mock_low`, `mock_unavailable`).
- Non-dev uses real MethodChannel provider when configured.
- Token evidence is attached in `risk_context.device_trust` for verify flow.
- Correlation-id and deterministic request-hash are bound to the protected action.

### Backend
- New verifier module: `backend/integrity_verifier.py`.
- Verifier modes:
  - `mock` (dev/testing)
  - `google` (staging/prod when configured)
- Normalized verifier statuses:
  - `trusted`
  - `untrusted`
  - `unavailable`
  - `invalid`
  - `transient_error`
  - `configuration_error`
- Verify flow integrates verifier output before decision engine.
- Device trust signal is normalized and fed into existing decision policy.
- Raw token is not emitted in audit metadata.

## Request Hash Binding
Phase-2 uses request hash formula:

`sha256("ekyc_integrity_v1|{id_hash}|{attempt_count}|{correlation_id}")`

- App computes and passes this hash when requesting token.
- Backend recomputes expected hash and validates decoded `requestDetails.requestHash`.

## Environment Matrix

### Dev
- App: mock trust mode only.
- Backend: `EKYC_INTEGRITY_VERIFIER_MODE=mock` allowed.
- Purpose: local deterministic testing without external cloud dependencies.

### Staging/Prod
- App: real token acquisition path enabled when config is provided.
- Backend: should run `EKYC_INTEGRITY_VERIFIER_MODE=google`.
- Backend in non-dev with mock mode is treated as configuration error (safe non-pass).

## Required External Setup (Not In Repo)
1. Enable Play Integrity API in Google Cloud.
2. Ensure Play app package is linked correctly.
3. Create service account with decode permission.
4. Provide credentials to backend runtime (`file` or `json` env path).
5. Configure backend env:
   - `EKYC_BACKEND_ENV=staging|prod`
   - `EKYC_INTEGRITY_VERIFIER_MODE=google`
   - `EKYC_PLAY_INTEGRITY_ANDROID_PACKAGE=<applicationId>`
   - `EKYC_PLAY_INTEGRITY_CREDENTIALS_FILE=<path>` or
     `EKYC_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON=<json>`
6. Configure app env:
   - `EKYC_PLAY_INTEGRITY_ENABLED=true`
   - `EKYC_PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER=<number>`

## Tested Locally
- Flutter analyze and Flutter tests.
- Backend pytest suite including verifier/mapping tests.
- Android debug build compiling native bridge.

## Contract-Only / External Validation Pending
- Real token decode against live Google endpoint and cloud credentials.
- Staging/prod policy threshold validation against real device verdict distributions.
- Operational rollout and monitoring sign-off.

## Known Limitations
- Without external credentials/setup, non-dev verification cannot produce trusted real-google verdict.
- Phase-2 does not include iOS integrity implementation.
- Phase-2 does not include SIEM deployment or release operations ownership.
