# Rollout Notes - Phase 2 Play Integrity

## Recommended Merge And Release Order
1. Keep current commit order in review context:
   - app/native integration
   - backend verifier integration
   - tests
   - docs
2. Merge as one reviewed PR into main after approvals and checklist completion.
3. Deploy backend staging configuration first.
4. Distribute staging Android build with Play Integrity enabled.
5. Execute staging validation matrix and signoff before any production consideration.

## Suggested Branch And PR Flow
1. Create review branch from current local HEAD:
   - `git checkout -b review/phase2-play-integrity`
2. Push review branch and open one PR targeting main.
3. Use this PR package as canonical review context.
4. Do not push directly to main outside the reviewed PR path.

## Staging-Only Rollout Guidance
- Enable real verifier only in staging runtime first (`EKYC_INTEGRITY_VERIFIER_MODE=google`).
- Use staging app build with explicit `EKYC_ENV=staging` and valid project number.
- Gate rollout on matrix evidence for trusted, unavailable, invalid, and transient flows.
- Keep pilot cohort controlled and observed during first staging pass.

## Must Be Configured Before Staging Validation

### External setup
- Play Integrity API enabled in Google Cloud.
- Service account provisioned with decode permission.
- Play Console and package linkage validated.

### Backend env
- `EKYC_BACKEND_ENV=staging`
- `EKYC_INTEGRITY_VERIFIER_MODE=google`
- `EKYC_PLAY_INTEGRITY_ANDROID_PACKAGE=<applicationId>`
- `EKYC_PLAY_INTEGRITY_CREDENTIALS_FILE=<path>` or `EKYC_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON=<json>`
- Optional policy toggles:
  - `EKYC_PLAY_INTEGRITY_ALLOW_BASIC_INTEGRITY`
  - `EKYC_PLAY_INTEGRITY_REQUIRE_LICENSED_APP`

### App env
- `EKYC_ENV=staging`
- `EKYC_API_BASE_URL_STAGING=https://...`
- `EKYC_PLAY_INTEGRITY_ENABLED=true`
- `EKYC_PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER=<number>`

## Rollback Guidance If Staging Validation Fails
1. Stop pilot test intake immediately.
2. Capture correlation ids and failing scenario evidence from matrix.
3. Revert staging backend to prior stable image/config.
4. If issue is integrity-specific only, temporarily disable app-side real integrity in staging builds (`EKYC_PLAY_INTEGRITY_ENABLED=false`) while root cause is addressed.
5. Open fix PR against review branch; do not hot-edit main.

## Expected Safe Failure Behavior
- Missing token or unavailable verifier -> REVIEW, retry allowed, no silent PASS.
- Invalid/untrusted verifier verdict -> REJECT with trust-low reason.
- Non-dev mock mode misconfiguration -> configuration error path, non-pass decision.
- Transient verification failure -> REVIEW with wait-before-retry semantics.
- Audit logs remain privacy-safe with token redaction and correlation tracking intact.