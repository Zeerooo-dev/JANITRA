# JANITRA Build 12 — employee work & form label update

UI-only changes on top of `JANITRA-Build12-UI-Verified-Source.zip`.

## Employee UI
- **Saved Offline Work**: status/sync summary, counters, prominent drafts and conflicts, compact task cards, non-submitted draft notice, and a shared schedule card for downloaded shifts.
- **My Work Schedule**: clear active/paused shift cards with weekly day indicators, date range, individual work/break times, refresh and empty/error states; pull-to-refresh works as before.
- Existing offline authorization, cache ownership, encrypted storage, draft saving, PIN submission and backend requests are unchanged.

## Cleaning activity & work shift forms
- The shared `WorkForm` now renders labels *above* selected dropdown, text, calendar and clock fields rather than floating inside a populated field. This avoids first-field text overlap when adding or editing cleaning activities/shifts, including at enlarged Android text settings.
- Date/time pickers, validation, field keys, and save payloads are unchanged.

## Verification
- `python tool/redesign_static_check.py`: passed (39 Dart files, bracket/quote scan only).
- `node tool/check_design.mjs`: passed (existing 23 static reference screens).
- Flutter SDK and Dart CLI were not installed in the editing environment. Therefore `flutter analyze`, `flutter test`, and an Android build **were not run** here.
- Added/updated widget tests: `test/employee_work_ui_test.dart`, `test/work_form_picker_test.dart`.

Run on your Flutter development machine:

```sh
flutter pub get
 dart format lib/features/work/offline_work_page.dart lib/features/work/personal_schedule_page.dart lib/features/work/work_form.dart test/employee_work_ui_test.dart test/work_form_picker_test.dart
flutter analyze
flutter test test/employee_work_ui_test.dart test/work_form_picker_test.dart
flutter test
flutter run
```

No remote Supabase resources or production records were changed.
