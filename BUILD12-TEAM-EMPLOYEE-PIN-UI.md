# JANITRA Build 12 - Team Employee PIN UI

This update builds on JANITRA-Build12-Profile-Supervisor-PIN-UI-Source.zip and includes all earlier Build 12 UI updates.

## Scope

- Team > employee three-dot menu > Manage PIN > Set/Reset PIN now uses the existing secure, scrollable keypad sheet shared with the Profile Supervisor PIN screen.
- The sheet displays the selected employee name, four masked indicators, a large 0-9 keypad, Clear and Backspace, and a three-step flow: Choose PIN, repeat PIN, Supervisor account password.
- A mismatch is rejected locally and no backend call is sent. PINs are cleared on inactivity/background and protected-authorization invalidation. Failed requests clear the PIN and password, requiring a fresh attempt.
- The existing `manage-pins` function and request contract remain unchanged (`action=set`, `kind=employee`, existing user/agency/site scope, `pin`, `password`). Supervisor permissions, server verification and auditing remain in force. The old PIN is invalidated by the server only after successful save.
- Profile Supervisor PIN UI remains the same visually, now sharing the configurable sheet implementation.
- Added and updated widget tests in `test/workspace_test.dart` covering PIN mismatch, server rejection, correct scope, reset UI and background security; added 320px/200% text-scale scenario.

## Verification and limitations

- Compared with the previous full source: only two Flutter source files and one test file changed. SQL, Supabase Edge Functions, migrations, packages and other screens were not modified.
- Source and ZIP structural checks completed; ZIP integrity verified.
- `dart format`, `flutter analyze`, `flutter test` and Android build NOT RUN because Flutter/Dart SDK is unavailable here. Run these on the development machine.
- This is NOT a tested APK and does not change production Supabase.

## Applying UI-only patch

Back up the current project first. From your JANITRA project root (Fish shell):

```fish
unzip -o ~/Downloads/JANITRA-Build12-Team-Employee-PIN-UI-Only-Patch.zip -d .
dart format lib/features/workspace/pin_management_page.dart lib/features/workspace/supervisor_pin_setup_sheet.dart test/workspace_test.dart
flutter analyze
flutter test test/workspace_test.dart
flutter run
```

Use the UI-only patch on top of the **Profile Supervisor PIN UI source** rather than the original Build 12. The full source ZIP is supplied as another option.
