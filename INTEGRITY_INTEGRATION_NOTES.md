# Integrity Integration Notes

## Current State
Play Integrity phase-2 is implemented with a real end-to-end path:

- Android app requests integrity token through native MethodChannel bridge (`MainActivity`).
- Flutter trust service attaches integrity evidence to backend verify requests.
- Backend verifies evidence through `integrity_verifier.py` and normalizes verdict into existing decision engine trust signal.

The code path is production-capable, but full production activation still depends on external Google/credentials setup.

## Runtime Modes
App-side runtime controls:

- `EKYC_DEVICE_TRUST_MODE=mock_trusted`
- `EKYC_DEVICE_TRUST_MODE=mock_low`
- `EKYC_DEVICE_TRUST_MODE=mock_unavailable`
- `EKYC_PLAY_INTEGRITY_ENABLED=true|false`
- `EKYC_PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER=<number>`

Backend runtime controls:

- `EKYC_BACKEND_ENV=dev|staging|prod`
- `EKYC_INTEGRITY_VERIFIER_MODE=mock|google`
- `EKYC_PLAY_INTEGRITY_ANDROID_PACKAGE=<applicationId>`
- `EKYC_PLAY_INTEGRITY_CREDENTIALS_FILE=<service-account-json-path>` or
	`EKYC_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON=<inline-json>`
- Optional policy toggles:
	- `EKYC_PLAY_INTEGRITY_ALLOW_BASIC_INTEGRITY=true|false`
	- `EKYC_PLAY_INTEGRITY_REQUIRE_LICENSED_APP=true|false`

## Safe Defaults And Fallback Behavior
- Dev uses explicit mock behavior only via `EKYC_DEVICE_TRUST_MODE`:
- `mock_trusted`, `mock_low`, `mock_unavailable`
- unknown mode safely falls back to `mock_unavailable`
- Staging/prod never treat missing trust as trusted:
	- app non-dev provider requires valid Play Integrity config to obtain token,
	- backend verify flow enforces trust-signal presence and blocks auto-pass when missing,
	- non-dev backend in `mock` mode is treated as configuration error.
- Provider/runtime failure fallback:
	- if token acquisition fails, app emits structured unavailable/transient/config_error evidence,
	- if backend verification fails or is ambiguous, normalized trust is non-trusted (`unavailable` or `low`).

## Signals Sent To Backend
`risk_context.device_trust` includes:

- `status`: `trusted | low | unavailable | unknown`
- `score`: optional confidence score
- `provider`: signal source label
- `detail`: compact status detail
- `integrity_token`: Play Integrity token (only in request payload, never logged)
- `request_hash`: hash bound to protected verify action
- `token_source`: acquisition path metadata
- `error_category`, `error_code`, `retryable`

Backend mapping impact:
- `trusted` -> normal decision evaluation continues.
- `low` -> hard `REJECT` (`DEVICE_TRUST_LOW`).
- `invalid/untrusted verifier verdict` -> normalized to `low` and rejects.
- `unavailable/transient/configuration verdict` -> normalized to `unavailable` and yields review (`WAIT_BEFORE_RETRY`).

## Failure Categories
App/native and backend classify failures into stable categories:

- `play_services_unavailable`
- `transient_error`
- `provider_invalid`
- `configuration_error`
- `unexpected_error`

These categories feed internal detail/reason mapping without exposing raw token data.

## External Setup Still Required
1. Enable Play Integrity API in Google Cloud project.
2. Link Play app package and cloud project correctly.
3. Provision service account with permission to decode integrity tokens.
4. Deliver credentials securely to backend runtime.
5. Configure non-dev env vars (`EKYC_INTEGRITY_VERIFIER_MODE=google`, package name, credentials).

## Tested In Repository
- Flutter unit/widget tests for trust provider and token payload attachment.
- Backend unit tests for verifier modes and verdict mapping.
- Backend e2e tests for missing/invalid/transient/config integrity behavior.

## Not Fully Testable Without External Setup
- Real Google Play Integrity decode calls in staging/prod runtime.
- Credential/permission validation against actual cloud project and Play Console linkage.
