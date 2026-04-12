# Pilot Support Triage Guide

## Purpose
Help support and engineering teams quickly classify pilot issues, collect the right evidence, and route ownership correctly.

## Issue Categories

### Category A - App cannot complete verification
Likely causes:
- camera/permission flow interruption
- network failure
- backend auth rejection due to missing client header config

Collect:
- app build version and environment defines
- timestamp and device model
- correlation_id from app result payload
- backend response detail/reason fields

Owner:
- Android engineer first
- Backend engineer if response indicates auth/config or service errors

### Category B - Unexpected REVIEW/REJECT surge
Likely causes:
- integrity verifier transient/configuration degradation
- policy regression
- upstream cloud dependency instability

Collect:
- sample correlation ids across affected window
- integrity_check_result verification_status distribution
- decision_status and reason_codes samples
- recent config or deploy changes

Owner:
- Backend engineer + Security reviewer

### Category C - Frequent unauthorized_client responses
Likely causes:
- missing or incorrect EKYC_API_KEY / EKYC_API_BEARER_TOKEN in app build
- backend secret rotation without client update
- incorrect EKYC_CLIENT_AUTH_MODE

Collect:
- response status/detail
- correlation ids
- app env define snapshot (redacted)
- backend auth mode config state (redacted)

Owner:
- Backend engineer + Android engineer

### Category D - Rate-limit related failures
Likely causes:
- abuse burst
- client retry storm
- overly strict limits for current pilot volume

Collect:
- response 429 counts by endpoint
- correlation ids and source host patterns
- retry behavior evidence from app

Owner:
- Backend engineer
- Security reviewer if abuse suspected

### Category E - Privacy/logging concern
Likely causes:
- sanitizer bypass in new metadata field
- manual debug logging outside audit logger discipline

Collect:
- exact log sample and source
- timestamp and environment
- related correlation ids

Owner:
- Security reviewer (immediate)
- Backend engineer for containment/fix

## Suggested Severity Matrix
- SEV-1: token leakage, broad service outage, severe security bypass.
- SEV-2: major pilot flow degradation (sustained auth or verifier failure).
- SEV-3: intermittent failures with workaround available.
- SEV-4: documentation/process issues with no immediate user impact.

## Minimum Evidence Required Before Escalation
1. Environment (dev/staging/prod profile)
2. App build metadata and backend deployment version
3. Correlation id(s)
4. Endpoint and status code
5. Decision fields (decision_status, reason_codes, retry_policy) if available
6. Time window and reproduction steps

## Who Handles What
- Android engineer:
  - client config, build profile, token request behavior
- Backend engineer:
  - auth/rate-limit/readiness/integrity verification backend paths
- Security reviewer:
  - privacy, abuse pattern, policy breach or leakage
- Release owner:
  - incident communication and rollout hold/rollback decision
