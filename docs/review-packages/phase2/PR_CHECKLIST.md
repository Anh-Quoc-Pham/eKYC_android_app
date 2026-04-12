# Reviewer Checklist

Use this checklist to review phase-2 Play Integrity integration before approving merge.

## Code Review Focus Points
- [ ] Verify Android -> Flutter -> backend trust data flow is contiguous with no skipped verification step.
- [ ] Confirm request hash formula is consistent between app and backend.
- [ ] Confirm verify flow still routes all final decisions through existing decision engine.
- [ ] Confirm no new silent PASS paths exist when trust evidence is missing or ambiguous.

## Android Integration Sanity
- [ ] `MainActivity` MethodChannel `ekyc/play_integrity` supports `prepareProvider` and `requestToken`.
- [ ] Native error mapping categories are stable and intentional.
- [ ] Provider lifecycle invalidation behavior on token request failure is correct.
- [ ] App config gating (`EKYC_PLAY_INTEGRITY_ENABLED`, project number) behaves as documented.

## Backend Verifier Sanity
- [ ] `integrity_verifier.py` mode behavior is correct (`mock` for dev only, `google` for non-dev).
- [ ] Non-dev `mock` mode is treated as configuration error and does not trust-pass.
- [ ] Google decode path checks package name and request hash.
- [ ] Verifier status normalization maps to expected trust signal fields.

## Decision Engine Behavior
- [ ] Reason codes for integrity states are mapped as intended:
  - `DEVICE_TRUST_LOW`
  - `DEVICE_TRUST_UNAVAILABLE`
  - `DEVICE_TRUST_INVALID_TOKEN`
  - `DEVICE_TRUST_TRANSIENT_ERROR`
  - `DEVICE_TRUST_CONFIGURATION_ERROR`
- [ ] Decision outcomes align with policy:
  - invalid/untrusted trust -> REJECT
  - unavailable/transient/config -> REVIEW with retry
  - trusted + clean risk -> PASS
- [ ] Retry policy values are stable and consumed correctly by app UX.

## Logging And Privacy Safety
- [ ] Raw integrity token is not logged in audit metadata.
- [ ] Redaction includes integrity token key variants.
- [ ] `integrity_check_result` contains only sanitized verifier metadata.
- [ ] Correlation id appears in response header, payload, and audit events.

## Config And Environment Correctness
- [ ] Staging/prod app endpoint config remains HTTPS only.
- [ ] Required backend env keys are documented and match runtime reader code.
- [ ] Optional policy toggles are documented with intended defaults.
- [ ] No hidden dependency on dev-only settings for non-dev behavior.

## Documentation Completeness
- [ ] README env section aligns with implementation.
- [ ] `PLAY_INTEGRITY_PHASE2.md` accurately separates implemented vs external setup.
- [ ] Specs (`DECISION_ENGINE_SPEC.md`, `AUDIT_AND_LOGGING_SPEC.md`) reflect phase-2 mapping and safeguards.

## Test Verification
- [ ] Run and confirm local checks:
  - `flutter analyze`
  - `flutter test`
  - `pytest -q backend/tests`
- [ ] Confirm Android debug build still compiles:
  - `flutter build apk --debug --dart-define=EKYC_ENV=dev --dart-define=EKYC_API_BASE_URL_DEV=http://10.0.2.2:8000`
- [ ] Spot-check integrity scenarios in backend tests and Flutter method-channel tests.