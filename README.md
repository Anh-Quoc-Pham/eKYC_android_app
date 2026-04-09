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

## 2) Run Flutter App

From workspace root:

```powershell
flutter pub get
flutter run --dart-define=EKYC_API_BASE_URL=http://10.0.2.2:8000
```

Notes:

- `10.0.2.2` is correct for Android emulator to reach host machine backend.
- For a physical device, replace with host machine LAN IP, for example:
	`http://192.168.1.20:8000`.
- Endpoint configuration is centralized at `lib/config/app_config.dart`.

## 3) Quality Checks

```powershell
flutter analyze
flutter test
```

## Security and Privacy Notes

- OCR and face processing run on device.
- App stores sensitive fields in secure storage.
- Avoid logging raw personal data in production builds.
