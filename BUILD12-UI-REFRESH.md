# JANITRA Build 12 — Team & Scheduling Popup Refresh

This is a UI-only derivative of the supplied Build 12 source (version remains 1.0.0+12). No production deployment, backend functions, migrations, RLS or account records were changed.

## What's changed

- Team three-dot menu is now a keyboard/small-screen-safe action sheet with icons for account setup/recovery, suspend/reactivate, PIN management, change agency and permanent deletion (availability remains governed by existing permissions).
- Team account-management forms now use a unified scrollable bottom-sheet design. PIN reset and team-member creation have coordinated sheet styling.
- Schedules & Activities creation/editing/confirmation uses scrollable bottom sheets instead of tall alert dialogs.
- Schedule date fields open Material calendar pickers and write the same `YYYY-MM-DD` values as before.
- Schedule times open Material dial clock pickers and write the same `HH:mm` values as before.
- Shift working hours and breaks use add/edit/remove time-range rows backed by the existing newline-separated `HH:mm-HH:mm` serialization. Times crossing midnight retain existing handling.
- Optional end time in an existing cleaning schedule no longer attempts to cast `null` to `int`.
- Destructive confirmation buttons are highlighted; very long primary action labels get a full-width button for legibility.
- Added widget tests for date/time picker invocation and editable time ranges.

## Verification carried out here

- `python tool/redesign_static_check.py`: PASS (structural brackets for 38 Dart library files).
- `node tool/check_design.mjs`: PASS (existing project design checks).
- Source ZIP comparison: backend and database files unchanged.

## NOT executed here

No Flutter or Dart SDK is installed in this environment. `dart format`, `flutter analyze`, `flutter test`, Android APK compilation and physical-device UI review were NOT RUN on the modified source. The previous Build 12 test results do not certify this UI derivative.

## On your own machine

```fish
cd ~/Projects/janitra
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter build apk --debug
```

Test the Add Person sheet; the Team three-dot actions including sensitive confirmation; Shift start/end dates and working-hours/break clocks; Cleaning Schedule dates/times; date exceptions; canceling a picker without saving; and schedule deletion confirmation. Real server operations still require current online authorization.

## Package organization

- Full source archive: `JANITRA-Build12-UI-Refreshed-Source.zip` contains `JANITRA-Build12-UI-Refreshed/janitra/`.
- Overlay archive: `JANITRA-Build12-UI-Only-Patch.zip` contains only modified `lib/` and new `test/` paths, plus these notes. BACK UP your current project before overlaying.
