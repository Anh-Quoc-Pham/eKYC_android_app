# Summary
This PR packages phase-2 work that implements a real Android Play Integrity token flow and backend trust normalization, while preserving the existing phase-1 decision and audit baseline.

The result is a production-capable code path with strict safe defaults. Real activation in staging and production still depends on external Google Cloud and Play Console setup.

## Why This Phase Was Needed
- Phase-1 established decision engine and auditability but did not complete real non-dev attestation verification.
- Non-dev environments needed a real token acquisition and server-side verification path to avoid trust scaffolding drift.
- Rollout required deterministic behavior for missing, invalid, transient, and misconfigured integrity states.

## What Changed
## Architecture Changes
- Added Android native token acquisition via MethodChannel and wired it into verify flow.
- Added backend verifier module that normalizes Play Integrity outcomes to existing decision engine risk signals.
- Kept decisioning centralized in the existing policy engine, with no parallel policy path.

## Android-Side Changes
- Added Play Integrity dependency in Android app module.
- Implemented MethodChannel `ekyc/play_integrity` in `MainActivity` with:
  - `prepareProvider`
  - `requestToken`
  - structured failure categories (`play_services_unavailable`, `transient_error`, `provider_invalid`, `configuration_error`, `unexpected_error`)
- Extended app config for non-dev real integration gating:
  - `EKYC_PLAY_INTEGRITY_ENABLED`
  - `EKYC_PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER`
- Extended trust signal model to carry token evidence metadata:
  - `integrity_token`, `request_hash`, `token_source`, `error_category`, `error_code`, `retryable`, `token_present`
- Bound integrity evidence to protected verify request using deterministic request hash and shared correlation id.

## Backend-Side Changes
- Added `backend/integrity_verifier.py` with verifier modes:
  - `mock` for local deterministic testing
  - `google` for staging/prod decode path
- Added normalized verification statuses:
  - `trusted`, `untrusted`, `unavailable`, `invalid`, `transient_error`, `configuration_error`
- Added request binding validation:
  - request package name check
  - request hash check against server-computed expected hash
- Integrated verifier into `/verify` before decision evaluation.
- Injected normalized trust signal into `risk_context.device_trust` so existing decision engine remains the only policy source.

## Trust Policy And Decision Mapping Summary
- `trusted` -> `device_trust.status=trusted` -> normal policy evaluation, can PASS if no other blocking reasons.
- `untrusted` or `invalid` -> normalized to `status=low` -> mapped to `DEVICE_TRUST_LOW` and REJECT path.
- `transient_error` or `configuration_error` or token missing -> normalized to `status=unavailable` -> REVIEW with retry policy (`WAIT_BEFORE_RETRY`).
- Verify flow enforces trust signal presence; missing signal cannot silently auto-pass.
- Non-dev backend with verifier mode `mock` is treated as configuration error (safe non-pass).

## Privacy And Logging Safeguards
- Raw integrity token is never emitted in audit metadata.
- Redaction keywords expanded to include integrity token fields.
- `integrity_check_result` event logs only sanitized verifier metadata (status, detail, mode, retryable, token_present, error_code).
- Correlation id remains end-to-end across request header, response payload, and audit logs.

## Test Evidence
Validated locally on current commit stack:

- `flutter analyze` passed
- `flutter test` passed (18 tests)
- `pytest -q backend/tests` passed (27 tests)
- `flutter build apk --debug ...` passed (Android native compile validation)

Key scenario coverage added/expanded:
- backend verifier unit tests (`backend/tests/test_integrity_verifier.py`)
- backend e2e integrity scenarios (`backend/tests/test_api_e2e.py`)
- decision reason mapping extensions (`backend/tests/test_decision_engine.py`)
- Flutter trust provider and token transport tests (`test/device_trust_service_test.dart`, `test/zkp_service_test.dart`)

## Remaining Manual Tasks (Outside Repo)
- Enable Play Integrity API in Google Cloud.
- Ensure app package linkage between Play Console and cloud project.
- Provision service account with decode permission and deliver credentials securely to staging/prod runtime.
- Configure non-dev env variables (`google` verifier mode, package, credentials, policy toggles).
- Execute staging validation with real devices and real token decode.

## Known Risks
- External configuration drift (package mismatch, credentials, permissions) can cause configuration/transient trust outcomes.
- Real-world integrity verdict distribution may require threshold/policy review after staging evidence.
- Runtime dependency on Play services and Play Store availability may increase transient errors on unsupported devices.

## Not In Scope
- iOS integrity implementation.
- SIEM onboarding and org-level alert routing operations.
- Production release signing workflow ownership and release governance beyond staging gate.

## Local Commit Stack Included
- `6b31280` Add Android real Play Integrity token acquisition path
- `d4c1f8e` Add backend Play Integrity verifier and trust normalization
- `c6de246` Expand phase-2 safety tests for integrity flow and mapping
- `707eb7b` Document phase-2 Play Integrity activation and manual prerequisites