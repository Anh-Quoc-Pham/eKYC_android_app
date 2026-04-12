# Ops Readiness Runbook (Controlled Android Pilot)

## Objective
Define practical monitoring, incident response, and evidence collection steps for pilot operations.

## Operational Signals to Monitor

### Availability and safety
- /health response status and latency.
- /ready status transitions (ready vs not_ready).
- 5xx response rates on /enroll and /verify.

### Security and abuse indicators
- auth_denied event volume by path and time window.
- abuse_rate_limited and verify rate-limit spikes.
- unauthorized_client bursts from same source range.

### Integrity and decision quality
- integrity_check_result verification_status distribution.
- Decision status distribution (PASS/REVIEW/REJECT).
- Retry policy distribution drift (especially WAIT_BEFORE_RETRY spikes).

### Data and privacy safety
- Any log occurrence of raw token key material (must be zero).
- Redaction coverage checks for sensitive keys.

## Incident Classes
1. Availability incident
- symptoms: /health failures, elevated 5xx, request timeouts.

2. Auth/config incident
- symptoms: widespread 401 unauthorized_client, 503 client_auth_secret_missing.

3. Integrity verification incident
- symptoms: transient_error spike, configuration_error spike, trusted collapse.

4. Abuse/rate-limit incident
- symptoms: sudden 429 surge on /enroll or /verify.

5. Privacy/logging incident
- symptoms: suspected sensitive token leakage in logs.

## First-Response Steps
1. Confirm incident scope and start time.
2. Capture representative correlation ids from failing requests.
3. Confirm current backend env configuration snapshot (without secrets).
4. Check /ready checks and identify failed components.
5. Classify incident class and assign owner.

## Role-Based Ownership
- Backend engineer: service availability, auth config, verifier integration, rate limits.
- Android engineer: app-side config, request header/token behavior, release artifact mapping.
- Security reviewer: token leakage checks, abuse review, policy breach classification.
- Release owner: GO/NO-GO decisions, rollback authorization, stakeholder comms.

## Evidence Collection Checklist
For every incident capture:
- incident id and timestamp window
- affected environment and release artifact metadata
- at least 3 correlation ids per symptom class
- sample request/response status and reason fields
- sampled audit events:
  - final_decision_issued
  - integrity_check_result
  - auth_denied (if relevant)
  - abuse_rate_limited (if relevant)
  - internal_error (if relevant)
- root-cause hypothesis and confidence level

## Escalation Guidance
- Escalate immediately to security reviewer if any token leakage suspected.
- Escalate to release owner when:
  - /ready remains not_ready > 15 minutes in active pilot window,
  - 5xx or 401 spikes exceed agreed pilot threshold,
  - decision distribution changes abruptly without planned rollout.

## Known Limitations
- Rate limiting is in-memory and not cluster-wide.
- /ready currently reports posture but is not access-restricted in code.
- Alert routing destinations (PagerDuty/Slack/email) are external and must be configured by ops.

## Manual External Setup Required
- Centralized log sink and alert routing.
- Threshold tuning for pilot cohort size.
- On-call rotation and escalation contact matrix.
