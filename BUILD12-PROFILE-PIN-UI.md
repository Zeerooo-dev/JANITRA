# JANITRA Build 12 - Supervisor Profile PIN UI

This source builds on `JANITRA-Build12-Task-Review-UI-Refreshed-Source.zip` and includes the previous Schedules, Team, and Task Review UI changes.

## Changed

- **Profile > Manage Your Supervisor PIN:** compact status card with PIN state, timestamp, and primary Set/Reset action.
- **Supervisor PIN setup/reset:** three-step bottom sheet: enter four digits with a numeric keypad, repeat them, then confirm with account password.
- Four masked dots, Clear/Backspace buttons, progress, inline errors, and responsive scrollable layout.
- Supervisor PIN input, confirmation, and password clear on background/inactive or protected-access invalidation, on failed requests, and on sheet disposal.
- Mismatched PIN confirmation does not send a network request. Backend failures show feedback and require fresh input.
- Updated `test/workspace_test.dart` with Supervisor keypad setup, scope, mismatch, and background-clear checks.

## Unchanged

- **Backend/API:** `manage-pins`, `action: set`, original scoped IDs, existing password verification, and online authorization are unchanged.
- Employee PIN editor remains on its existing flow; no changes to Personnel authentication, task PIN confirmation, final approval, migrations, or server deployment.

## Validation

- ZIP integrity and elementary source delimiter/request-contract checks performed.
- `flutter analyze`, `flutter test`, and APK builds **not run**: Flutter/Dart SDK unavailable in this environment.
- The updated tests have been authored but not executed, so Android behavior and small-screen layout require a local build and device check.

Run in the Flutter repository after applying the patch:

```sh
flutter pub get
# Optional: format only the changed files
dart format lib/features/workspace/pin_management_page.dart lib/features/workspace/supervisor_pin_setup_sheet.dart test/workspace_test.dart
flutter analyze
flutter test test/workspace_test.dart
flutter test
flutter run
```

UI-only patch ZIP contains paths relative to the project root. Back up the project before applying `unzip -o`.
