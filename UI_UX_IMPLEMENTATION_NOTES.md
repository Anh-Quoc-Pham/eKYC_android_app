# UI/UX Implementation Notes

## Scope Applied
- Refined Android-first eKYC UX in Flutter screens while preserving existing backend contracts and verification services.
- Updated user-facing copy to concise Vietnamese, removed technical diagnostics from result UI, and normalized progress treatment.

## Result State Separation
- `success`: clear completion with single continue action.
- `review retryable`: actionable retry guidance and retry CTA.
- `reject`: respectful failure with restart/support actions.
- `cooldown`: wait-before-retry messaging with remaining-time card.
- `manual review`: asynchronous review messaging with no retry CTA.

## Permission State Separation
- Added distinct UI for:
  - camera pre-ask
  - denied/permanently denied recovery (Open Settings flow)

## Test Coverage Added
- Welcome copy verification.
- Permission pre-ask vs denied screen separation.
- Review screen step/actions consistency.
- Result state mapping and copy rules:
  - retryable review vs manual review
  - reject without internal diagnostics
  - cooldown mapping
  - success step context

## Runtime Behaviors Not Fully Widget-Tested
- Live camera stream + OCR auto-capture quality behavior.
- ML face stream and liveness progression under real lighting conditions.
- Permission recovery after returning from Android Settings.

These should be validated with on-device QA on Android.
