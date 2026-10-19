# JANITRA Build 12 – Supervisor Task Review UI Refresh

This is a **Flutter UI-only** update based on `JANITRA-Build12-UI-Refreshed-Source.zip`.
It does not deploy or modify Supabase SQL, Edge Functions, roles, approvals, or data.

## Changes

- **Task Details** uses compact, labeled cards for task identity, scheduled time, workplace, instructions, checklist, remarks, and history.
- **Official submission / review** is one card with distinct submission, confirmation, decision, reason, and review-deadline fields, formatted in Philippine time.
- **Supervisor Confirm Work** opens a scrollable bottom-sheet keypad with four masked digits, Clear, Backspace, Close, and a disabled-until-four-digits confirm button. Digits clear on app backgrounding, access invalidation, failure, and after submission attempts.
- **Final Work Approval / Reject** remains a distinct action, preserving the existing two-step workflow and server action names.
- **Reopen Locked Work** uses the existing interactive calendar / clock pickers instead of typed date and time strings.
- **Tests** adapted to enter Supervisor PIN digits through the keypad, assert submission/review context, and exercise PIN clearing/correction under 320 px width and 200% text scale.

## Files edited

- `lib/features/work/task_page.dart`
- `test/work_ui_test.dart`

## Checks in this environment

- PASS: design prototype source check (`node tool/check_design.mjs`), which checks the reference HTML, **not** the Flutter app.
- PASS: source structure / delimiter check and manual backend call/flow review.
- NOT RUN: Dart formatting, Flutter analysis, Flutter widget tests, Android build, phone acceptance — Flutter/Dart SDK absent here.

## Run in your JANITRA project

```sh
flutter pub get
dart format lib/features/work/task_page.dart test/work_ui_test.dart
flutter analyze
flutter test test/work_ui_test.dart
flutter test
flutter run --dart-define-from-file=config/supabase.json
```

For a full Android build use your normal existing configuration/signing process.
The source archive excludes secrets and real Supabase configuration as before.
