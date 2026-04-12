# eKYC App (Privacy-First Demo)

Flutter app for OCR, face scan/liveness, and ZKP verification, with a local
FastAPI backend used for phase-3 proof verification.

## Repo Layout

- `lib/`: Flutter application code.
- `backend/`: FastAPI backend (`main.py`) and Python dependencies.

## Prerequisites

- Flutter SDK (stable channel) and Dart (managed by Flutter).
- Android Studio / Xcode for emulator or real device testing.
- Python 3.10+ for backend.

## 1) Run Backend (FastAPI)

From workspace root:

```powershell
cd backend
python -m venv ..\.venv
..\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

Health check:

```powershell
Invoke-WebRequest http://127.0.0.1:8000/health
```

Expected response body:

```text
{"status":"ok"}
```

Readiness check:

```powershell
Invoke-WebRequest http://127.0.0.1:8000/ready
```

Notes:

- `/health` reports liveness.
- `/ready` reports security/config posture (`ready` or `not_ready`) for pilot operations.

## 2) Environment Configuration (dev/staging/prod)

`lib/config/app_config.dart` now resolves API endpoint by environment:

- `EKYC_ENV=dev|staging|prod` (default is `dev`)
- `EKYC_API_BASE_URL` (global override, highest priority)
- `EKYC_API_BASE_URL_DEV`
- `EKYC_API_BASE_URL_STAGING`
- `EKYC_API_BASE_URL_PROD`

Rules:

- `dev` defaults to `http://10.0.2.2:8000` for Android emulator.
- `staging` and `prod` require `https` endpoints.
- If staging/prod URL is missing, app fails fast at startup with config error.

Play Integrity app-side settings:

- `EKYC_PLAY_INTEGRITY_ENABLED=true|false`
- `EKYC_PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER=<number>`
- `EKYC_DEVICE_TRUST_MODE=mock_trusted|mock_low|mock_unavailable` (dev only)
- `EKYC_API_KEY=<shared-api-key>` (optional, for backend auth mode `api_key` or `either`)
- `EKYC_API_BEARER_TOKEN=<shared-bearer-token>` (optional, for backend auth mode `bearer` or `either`)

Backend Play Integrity settings:

- `EKYC_BACKEND_ENV=dev|staging|prod`
- `EKYC_INTEGRITY_VERIFIER_MODE=mock|google`
- `EKYC_PLAY_INTEGRITY_ANDROID_PACKAGE=<applicationId>`
- `EKYC_PLAY_INTEGRITY_CREDENTIALS_FILE=<service-account-json-path>` or
	`EKYC_PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON=<inline-json>`

Backend hardening settings:

- `EKYC_CLIENT_AUTH_MODE=disabled|api_key|bearer|either`
- `EKYC_CLIENT_API_KEY=<shared-secret>`
- `EKYC_CLIENT_BEARER_TOKEN=<shared-token>`
- `EKYC_ALLOW_INSECURE_NO_AUTH_IN_NON_DEV=true|false` (default false)
- `EKYC_ALLOWED_ORIGINS=https://app.example.com,https://admin.example.com`
- `EKYC_CORS_ALLOW_CREDENTIALS=true|false`
- `EKYC_RATE_LIMIT_ENROLL_MAX_REQUESTS=<int>`
- `EKYC_RATE_LIMIT_ENROLL_WINDOW_SECONDS=<int>`
- `EKYC_RATE_LIMIT_VERIFY_MAX_REQUESTS=<int>`
- `EKYC_RATE_LIMIT_VERIFY_WINDOW_SECONDS=<int>`

Non-dev defaults are intentionally stricter:

- If auth mode is not configured securely, protected routes can return non-ready/denied behavior.
- Non-dev `disabled` auth mode requires explicit override via `EKYC_ALLOW_INSECURE_NO_AUTH_IN_NON_DEV=true`.

## 3) Run Flutter App

From workspace root:

```powershell
flutter pub get
flutter run --dart-define=EKYC_ENV=dev --dart-define=EKYC_API_BASE_URL_DEV=http://10.0.2.2:8000
```

Notes:

- `10.0.2.2` is correct for Android emulator to reach host machine backend.
- For a physical device, replace with host machine LAN IP, for example:
	`http://192.168.1.20:8000` in `dev`.
- Endpoint configuration is centralized at `lib/config/app_config.dart`.

Staging run example:

```powershell
flutter run --dart-define=EKYC_ENV=staging --dart-define=EKYC_API_BASE_URL_STAGING=https://staging.example.com
```

Production build example:

```powershell
flutter build apk --release --dart-define=EKYC_ENV=prod --dart-define=EKYC_API_BASE_URL_PROD=https://api.example.com
```

Staging with Play Integrity example:

```powershell
flutter run --dart-define=EKYC_ENV=staging --dart-define=EKYC_API_BASE_URL_STAGING=https://staging.example.com --dart-define=EKYC_PLAY_INTEGRITY_ENABLED=true --dart-define=EKYC_PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER=1234567890123
```

Staging with backend API-key protection example:

```powershell
flutter run --dart-define=EKYC_ENV=staging --dart-define=EKYC_API_BASE_URL_STAGING=https://staging.example.com --dart-define=EKYC_PLAY_INTEGRITY_ENABLED=true --dart-define=EKYC_PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER=1234567890123 --dart-define=EKYC_API_KEY=pilot-shared-key
```

## 4) Backend End-to-End Tests

From workspace root:

```powershell
..\.venv\Scripts\Activate.ps1
pip install -r backend/requirements.txt
pip install -r backend/requirements-dev.txt
pytest -q backend/tests/test_api_e2e.py
```

## 5) Quality Checks

```powershell
flutter analyze
flutter test
pytest -q backend/tests
```

Android native compile validation:

```powershell
flutter build apk --debug --dart-define=EKYC_ENV=dev --dart-define=EKYC_API_BASE_URL_DEV=http://10.0.2.2:8000
```

Release-signing guardrail example:

```powershell
flutter build apk --release -Pekyc.enforceReleaseSigning=true -Pekyc.allowDebugReleaseSigning=false --dart-define=EKYC_ENV=prod --dart-define=EKYC_API_BASE_URL_PROD=https://api.example.com
```

## 6) CI (GitHub Actions)

`.github/workflows/flutter-ci.yml` runs on push/PR to `main`:

- Flutter job: `flutter pub get`, `flutter analyze`, `flutter test`
- Backend job: install Python deps and run `pytest -q backend/tests/test_api_e2e.py`

## Security and Privacy Notes

- OCR and face processing run on device.
- App stores sensitive fields in secure storage.
- Avoid logging raw personal data in production builds.
