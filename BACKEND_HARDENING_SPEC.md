# Backend Hardening Spec (Phase 3)

## Objective
Establish a practical backend protection baseline for controlled Android pilot usage without introducing heavyweight IAM dependencies.

## Scope

### Implemented in repo
- Sensitive-route auth gate for POST /enroll and POST /verify.
- Environment-driven auth modes with safer non-dev defaults.
- Explicit CORS middleware policy.
- Route-aware in-memory rate limiting for /enroll and /verify.
- Readiness diagnostics endpoint: GET /ready.
- Safer unhandled-exception response contract with correlation id.

### Scaffolded only
- In-memory throttling is single-instance and not distributed.
- Shared-secret auth model is pilot-grade and intentionally lightweight.

### Requires human or external setup
- Secret provisioning and rotation process.
- Runtime env management in deployment platform.
- WAF/API gateway controls and distributed throttling.

### Not in scope
- Full enterprise IAM/SSO.
- mTLS rollout across all service hops.
- Full SIEM pipeline implementation.

## Protected Endpoints
- POST /enroll
- POST /verify

Protection behavior:
- Applies auth checks before endpoint business logic.
- Applies route-specific rate limiting.
- Preserves X-Correlation-ID in denied and limited responses.

## Authentication and Service Protection Model
Environment variables:
- EKYC_CLIENT_AUTH_MODE=disabled|api_key|bearer|either
- EKYC_CLIENT_API_KEY=<shared-secret>
- EKYC_CLIENT_BEARER_TOKEN=<shared-token>
- EKYC_ALLOW_INSECURE_NO_AUTH_IN_NON_DEV=true|false

Behavior:
- dev default: auth mode defaults to disabled.
- non-dev default: auth mode defaults to api_key.
- non-dev disabled mode is blocked unless EKYC_ALLOW_INSECURE_NO_AUTH_IN_NON_DEV=true.
- If auth mode requires secret but secret is missing: return 503 with config error detail.
- Invalid or missing credentials in protected routes: return 401 unauthorized_client.

Headers accepted:
- X-EKYC-API-Key for api_key mode.
- Authorization: Bearer <token> for bearer mode.

## CORS Policy
Environment variables:
- EKYC_ALLOWED_ORIGINS=comma,separated,origins
- EKYC_CORS_ALLOW_CREDENTIALS=true|false

Behavior:
- dev default origins: localhost and 127.0.0.1 common ports.
- non-dev with wildcard origin is treated as unsafe and effectively disabled.
- Methods allowed: GET, POST, OPTIONS.
- Headers allowed: Authorization, Content-Type, X-Correlation-ID, X-EKYC-API-Key.

## Rate Limiting Policy
Environment variables:
- EKYC_RATE_LIMIT_ENROLL_MAX_REQUESTS
- EKYC_RATE_LIMIT_ENROLL_WINDOW_SECONDS
- EKYC_RATE_LIMIT_VERIFY_MAX_REQUESTS
- EKYC_RATE_LIMIT_VERIFY_WINDOW_SECONDS

Defaults:
- /enroll: 20 requests / 60s per client host.
- /verify: 30 requests / 60s per client host.

Response behavior:
- /verify throttled: 429 with decision-contract-compatible payload and Retry-After.
- /enroll throttled: 429 with detail=rate_limited and correlation_id.

## Secret and Config Discipline
- No secrets are hardcoded in repository.
- Non-dev secure defaults prefer closed or degraded-safe behavior over permissive behavior.
- Readiness endpoint reports posture only (boolean checks), never secret values.

## Error-Handling Rules
- Unhandled server exceptions return:
  - status 500
  - detail=internal_server_error
  - correlation_id included
- Sensitive internal traces are not returned to clients.
- Correlation id is preserved through middleware for auditability.

## Audit and Logging Notes
New audit events introduced:
- auth_denied
- abuse_rate_limited
- service_readiness_not_ready
- internal_error

Privacy behavior is preserved:
- no raw Play Integrity token leakage in audit metadata.
- redaction policy remains active for sensitive keys.

## Open Questions
- Should production move from shared secret to gateway-issued signed tokens?
- Should route rate limiting be replaced by Redis/global limiter before larger pilot cohort?
- Should /ready be restricted to internal network only in deployment?

## Manual Tasks
- Provision and rotate EKYC_CLIENT_API_KEY or EKYC_CLIENT_BEARER_TOKEN in non-dev.
- Set EKYC_ALLOWED_ORIGINS per staging/prod frontend domains if web clients are used.
- Decide operational policy for EKYC_ALLOW_INSECURE_NO_AUTH_IN_NON_DEV (recommended false).
- Validate readiness posture in staging before pilot traffic.
