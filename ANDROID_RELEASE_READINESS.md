# Android Release Readiness (Phase 3)

## Objective
Provide repo-side release guardrails and clear operator guidance for controlled Android pilot builds.

## Current Repo Baseline

### Implemented in repo
- Release build minification and resource shrinking enabled.
- Optional release signing config via android/keystore.properties.
- Guardrail gradle properties:
  - ekyc.enforceReleaseSigning
  - ekyc.allowDebugReleaseSigning
- App env separation for dev, staging, prod.
- App-to-backend auth header support via dart-define values.

### Scaffolded only
- Release signing integration is prepared but actual keystore material is not in repo.
- Artifact naming convention is documented; pipeline-level artifact management remains external.

### Requires human or external setup
- Real release keystore generation and custody.
- Play Console release track operations.
- Final release approval workflow.

## Release Config Expectations

### Gradle signing setup
- Place signing file at android/keystore.properties (local or CI secret-mounted).
- Expected keys:
  - storeFile
  - storePassword
  - keyAlias
  - keyPassword

Gradle guardrails:
- -Pekyc.enforceReleaseSigning=true
  - fails release build if release signing config is missing.
- -Pekyc.allowDebugReleaseSigning=false
  - blocks fallback to debug signing in release builds.

Recommended CI release command:
- flutter build apk --release -Pekyc.enforceReleaseSigning=true -Pekyc.allowDebugReleaseSigning=false --dart-define=EKYC_ENV=prod --dart-define=EKYC_API_BASE_URL_PROD=https://api.example.com

## Environment and Flavor Expectations
No multi-flavor matrix is added in this phase. Environment behavior remains dart-define driven.

Required app defines by environment:
- dev:
  - EKYC_ENV=dev
  - EKYC_API_BASE_URL_DEV=http://<host>:8000
- staging:
  - EKYC_ENV=staging
  - EKYC_API_BASE_URL_STAGING=https://<staging-host>
  - EKYC_PLAY_INTEGRITY_ENABLED=true
  - EKYC_PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER=<number>
- prod:
  - EKYC_ENV=prod
  - EKYC_API_BASE_URL_PROD=https://<prod-host>
  - EKYC_PLAY_INTEGRITY_ENABLED=true
  - EKYC_PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER=<number>

Backend auth compatibility defines (optional but recommended in non-dev):
- EKYC_API_KEY=<shared-key>
- EKYC_API_BEARER_TOKEN=<shared-token>

Security note:
- These shared-secret headers are coarse pilot traffic gates only.
- They must not be treated as strong mobile client authentication.

## Versioning Approach
- Source of truth remains pubspec.yaml version field (versionName + versionCode).
- Use semantic versioning with monotonically increasing build number.
- Recommended pilot progression:
  - 1.0.x for controlled pilot patches
  - bump build number every distributed artifact

## Artifact Expectations
- Keep immutable record per artifact:
  - git commit SHA
  - pubspec version
  - dart-define profile used
  - backend target environment
- Store release notes alongside artifact metadata in release process repository or CI artifacts.

## Pre-release Checks
1. flutter analyze
2. flutter test
3. pytest -q backend/tests
4. flutter build apk --debug with target env defines
5. flutter build apk --release with signing guardrails enabled
6. Validate no debug signing fallback is used in production-intended build

## Rollback Notes
Rollback triggers:
- elevated verification failures linked to release build
- repeated auth_denied spikes caused by client config mismatch
- integrity verifier readiness regressions in staging/prod

Rollback actions:
1. stop rollout of current artifact
2. switch to previous known-good artifact
3. capture correlation ids and error signatures
4. open fix PR and re-run release checklist before retry

## Manual Tasks
- Create and secure release keystore.
- Configure CI secret injection for keystore and passwords.
- Configure Play Console track and phased rollout settings.
- Assign explicit release owner and rollback approver.
