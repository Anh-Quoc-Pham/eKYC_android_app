# IMPLEMENTATION_PLAN

## Phase
- Current phase: **Phase 2 - Real Play Integrity Integration**
- Goal: replace non-dev trust scaffold with real Android -> backend Play Integrity verification path while preserving phase-1 decision/audit baseline.
- Status: **Implemented in repository with external setup dependencies still required for production activation**.

## 1. Findings From Current Baseline

### Frontend insertion points
- Verify trigger is in `lib/screens/face_scan_screen.dart` via `ZkpService.submitPhase3(...)`.
- Existing trust path is `DeviceTrustService.evaluate()` in `lib/services/device_trust_service.dart`.
- Current trust model does not carry raw integrity token; only status/score/provider/detail in `lib/models/decision_models.dart`.
- Config is centralized in `lib/config/app_config.dart` with env separation (`dev/staging/prod`).
- Android native entrypoint exists only as `MainActivity` with no platform channel yet.

### Backend insertion points
- Request models and verify orchestration are in `backend/main.py`.
- Decision mapping is centralized in `backend/decision_engine.py` and already enforces trust-signal presence for verify.
- Structured audit logging and redaction are in `backend/audit_logging.py`.
- There is currently no server-side Play Integrity token verification module.

## 2. Architecture Insertion Points

- Android-side token acquisition is inserted at trust provider layer (`DeviceTrustService`) and invoked only in verify flow entrypoint (`FaceScanScreen`).
- Backend-side token verification is inserted at `/verify` orchestration before ZKP decision evaluation.
- Existing decision engine remains the only policy engine; Play Integrity verdict is normalized into `device_trust` signal consumed by decision logic.

## 3. File/Module Targets

### App / Android
- `android/app/build.gradle.kts`
- `android/app/src/main/kotlin/com/aq/ekyc/ekyc_app/MainActivity.kt`
- `lib/config/app_config.dart`
- `lib/models/decision_models.dart`
- `lib/services/device_trust_service.dart`
- `lib/services/zkp_service.dart`
- `lib/screens/face_scan_screen.dart`
- `test/device_trust_service_test.dart`
- `test/zkp_service_test.dart`

### Backend
- `backend/main.py`
- `backend/decision_engine.py`
- `backend/integrity_verifier.py` (new)
- `backend/requirements.txt`
- `backend/tests/test_decision_engine.py`
- `backend/tests/test_api_e2e.py`
- `backend/tests/test_integrity_verifier.py` (new)

### Documentation
- `IMPLEMENTATION_PLAN.md`
- `INTEGRITY_INTEGRATION_NOTES.md`
- `ANDROID_PILOT_READINESS.md`
- `DECISION_ENGINE_SPEC.md`
- `PLAY_INTEGRITY_PHASE2.md` (new)

## 4. Assumptions
- Android-only scope continues; iOS integrity path remains out-of-scope.
- External Google Cloud/Play Console setup may be absent during local testing.
- Repo code must remain mergeable and safe when production credentials are missing.
- Existing decision and audit contracts remain backward compatible.

## 5. Risk Notes
- Native Play Integrity API integration may fail without Play services/Play Store runtime support.
- Misconfiguration in non-dev must result in non-pass outcomes, never implicit trust.
- Token decode failures must map to deterministic review/reject policy.
- External setup dependencies must be explicit in docs to avoid false completion claims.

## 6. What Changed (Implemented In Repo)

### Android / Flutter
- Added real native Play Integrity bridge through MethodChannel in `MainActivity` with:
   - provider preparation lifecycle,
   - token request lifecycle,
   - structured failure categories (`play_services_unavailable`, `transient_error`, `provider_invalid`, `configuration_error`, `unexpected_error`).
- Extended trust model (`DeviceTrustSignal`) to carry integrity evidence and failure metadata.
- Extended `DeviceTrustService`:
   - dev: explicit mock mode preserved,
   - non-dev: real MethodChannel provider if configured,
   - fail-safe unavailable when configuration missing or provider fails.
- Added deterministic integrity request-hash binding helpers in `ZkpService` and wired correlation-id + request-hash usage from `FaceScanScreen`.

### Backend
- Added `backend/integrity_verifier.py`:
   - verifier modes: `mock` and `google`,
   - normalized verdicts: `trusted`, `untrusted`, `unavailable`, `invalid`, `transient_error`, `configuration_error`,
   - request hash/package validation and verdict normalization into existing trust signal.
- Integrated verifier into `backend/main.py` verify flow before decision evaluation.
- Preserved privacy guarantees:
   - no raw integrity token in audit metadata,
   - dedicated metadata filtering for integrity log events,
   - redaction rules expanded defensively.
- Extended decision taxonomy with integrity-specific reason codes while preserving existing policy structure.

### Tests
- Added backend verifier unit tests (`test_integrity_verifier.py`).
- Extended backend e2e tests for missing/invalid/transient/config integrity scenarios.
- Extended Flutter tests for:
   - MethodChannel provider behavior,
   - token attachment in service payload,
   - existing decision mapping regressions.

## 7. What Remains Manual (Outside Repo)
- Google Cloud and Play Console setup for Play Integrity API trust chain.
- Service account provisioning and secure credentials distribution to backend runtime.
- Non-dev environment variable rollout for verifier mode/package/credentials.
- Security sign-off for integrity verdict thresholds and rollout policy.
- Release signing/Play Console operational steps (separate from code integration).

## 8. Validation Status
- Flutter analyze: passed.
- Flutter tests: passed.
- Backend tests: passed.
- Android debug build: passed (`flutter build apk --debug`).
