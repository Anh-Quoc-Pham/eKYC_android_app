# IMPLEMENTATION_PLAN

## 1. Architecture Findings

### Frontend (Flutter)
- Android-first eKYC flow: `welcome -> ocr -> review -> face -> result`.
- Stateful session model in `lib/services/ekyc_session.dart` is the cross-screen source of truth.
- Backend integration is centralized in `lib/services/zkp_service.dart`.
- Decision UX now depends on normalized backend decision fields instead of legacy binary status.

### Backend (FastAPI)
- API surface remains: `GET /health`, `POST /enroll`, `POST /verify`.
- Decision normalization and retry policy are in `backend/decision_engine.py`.
- Structured audit logs with redaction are in `backend/audit_logging.py`.
- Correlation-id middleware + decisionized verify responses are in `backend/main.py`.

## 2. File And Module Targets

### Backend
- `backend/main.py`
- `backend/decision_engine.py`
- `backend/audit_logging.py`
- `backend/tests/test_api_e2e.py`
- `backend/tests/test_decision_engine.py`
- `backend/tests/test_audit_logging.py`

### Frontend
- `lib/models/decision_models.dart`
- `lib/services/zkp_service.dart`
- `lib/services/ekyc_session.dart`
- `lib/services/device_trust_service.dart`
- `lib/screens/face_scan_screen.dart`
- `lib/screens/review_screen.dart`
- `lib/screens/ocr_camera_screen.dart`
- `lib/screens/result_screen.dart`
- `test/decision_models_test.dart`
- `test/device_trust_service_test.dart`
- `test/zkp_service_test.dart`
- `test/result_screen_test.dart`

### Docs
- `DECISION_ENGINE_SPEC.md`
- `AUDIT_AND_LOGGING_SPEC.md`
- `INTEGRITY_INTEGRATION_NOTES.md`
- `ANDROID_PILOT_READINESS.md`
- `IMPLEMENTATION_PLAN.md` (this file)

## 3. Assumptions
- Keep API evolution additive and backward compatible with legacy fields.
- Android is the pilot platform; iOS trust integration is out-of-scope for this phase.
- Play Integrity production token verification is intentionally deferred to next phase.
- No secrets or signing credentials are committed to repository.

## 4. Risk Notes
- If trust signal is absent in verify flow, auto-pass must be prevented.
- Logs must never contain raw PII or sensitive crypto fields.
- Retry UX must remain deterministic and policy-driven to avoid user confusion.
- Manual operations (signing, Play Integrity cloud setup, SIEM wiring) remain external dependencies.

## 5. What Changed In This Hardening Pass
- Enforced verify-time trust-signal safety default in decision engine:
  - missing trust signal cannot auto-pass and maps to review/unavailable.
- Hardened app trust service with fail-safe unavailable fallback on provider exceptions.
- Added safety tests for:
  - audit log redaction,
  - correlation-id propagation,
  - retry-limit response contract,
  - network fallback decision behavior,
  - Result UI mapping for PASS/REVIEW/REJECT.
- Updated readiness docs with explicit manual step boundaries.

## 6. What Remains Manual
- Real Play Integrity activation (Android token flow + backend verification path).
- Cloud-side policy setup and key management for integrity verification.
- SIEM ingestion/retention setup for audit logs.
- Release signing, keystore custody, Play Console rollout workflow.
