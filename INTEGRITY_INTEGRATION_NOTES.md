# Integrity Integration Notes

## Current State
Device integrity is integrated as a safe scaffold:

- Flutter service abstraction: `DeviceTrustService` with provider interface.
- Dev provider: `MockDeviceTrustProvider`.
- Production placeholder: `PlayIntegrityScaffoldProvider` returns `unavailable` until real integration is configured.

This allows decision policy and UX behavior to operate now without blocking pilot hardening work.

## Runtime Modes
Configure via Dart define:

- `EKYC_DEVICE_TRUST_MODE=mock_trusted`
- `EKYC_DEVICE_TRUST_MODE=mock_low`
- `EKYC_DEVICE_TRUST_MODE=mock_unavailable`

`dev` environment uses mock provider mode.
`staging` and `prod` use the Play Integrity scaffold provider by default.

## Safe Defaults And Fallback Behavior
- Dev uses explicit mock behavior only via `EKYC_DEVICE_TRUST_MODE`:
	- `mock_trusted`, `mock_low`, `mock_unavailable`
	- unknown mode safely falls back to `mock_unavailable`
- Staging/prod never treat missing trust as trusted:
	- app default provider returns `unavailable`
	- verify decision logic enforces trust-signal presence and blocks auto-pass when missing
- Provider/runtime failure fallback:
	- if trust provider throws, service returns `unavailable` with `provider_error_fallback`

## Signals Sent To Backend
`risk_context.device_trust` includes:

- `status`: `trusted | low | unavailable | unknown`
- `score`: optional confidence score
- `provider`: signal source label
- `detail`: compact status detail

Backend mapping impact:
- `low` -> hard `REJECT` (`DEVICE_TRUST_LOW`).
- `unavailable/unknown` -> `REVIEW` with `WAIT_BEFORE_RETRY` (`DEVICE_TRUST_UNAVAILABLE`).

## Required Work Before Production Rollout
1. Integrate Play Integrity API in Android layer and wire token verification path.
2. Add backend attestation verification endpoint/service.
3. Define trust scoring policy and anti-replay constraints for integrity tokens.
4. Add test fixtures for success/low/unavailable attestation scenarios.
5. Add monitoring alert for sudden integrity failure spikes.

## Pilot Recommendation
For internal Android pilot:
- Keep scaffold enabled.
- Use `mock_trusted` for controlled success-path validation.
- Include one negative test run with `mock_low` and `mock_unavailable`.

Do not treat scaffold mode as production-grade device trust.
