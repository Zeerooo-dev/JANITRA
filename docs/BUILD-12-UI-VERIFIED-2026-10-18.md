# JANITRA Build 12 UI: inspected and built

October 18, 2026, Asia/Manila. Version remains `1.0.0+12`.

## Inspected changes

Compared the current source with the previously tested Build 12 source archive. The supplied UI work includes:

- Team action menus and account-management forms presented in scrollable bottom sheets.
- Scheduling bottom sheets with native calendar and clock pickers, and editable working-hour/break ranges. Existing optional schedule end times accept null safely.
- Task Details cards for work context, instructions, checklist, submission/review and history; a masked Supervisor confirmation keypad; separate final approval/rejection actions.
- Shared three-step Supervisor and Employee PIN setup/reset: choose PIN, repeat it, confirm the Supervisor account password. PINs and password input clear on backgrounding and access invalidation; backend failures require fresh entry.
- Grouped Audit Log events, action filters and details limited to the existing field allowlist.
- Workplace/company/profile name editors in responsive sheets, with client-company context for workplaces.

The backend source, migrations, workflow contracts and package versions match the prior Build 12 source. No remote deployment, account change or live data mutation was performed during this inspection.

## Corrections made during inspection

- Fixed the Team member metadata/status row overflowing at 320px width with 200% text. The status badge now receives bounded width and can reflow.
- Disabled swipe dismissal on mutation sheets. A swipe must not bypass the form's busy-state protection and hide an in-flight save. Close, Cancel, system Back and barrier dismissal retain the existing busy-state guard. The workplace editor's native drag handle was removed along with swipe dismissal.
- Resolved the three analyzer findings: two missing conditional blocks and one redundant import. Formatted the changed Dart files.
- Updated lifecycle coverage to assert the new name editor instead of the removed alert dialog. Updated picker tests to use their native Cancel action, and corrected localized date, renamed-company context and password-validation expectations.
- Extended the pending-write regression test to attempt a downward swipe while a save is pending; the sheet stays mounted and the single write completes normally.
- Visually inspected the Supervisor and Employee Task Details renders and updated only `supervisor-detail.png` and `employee-detail.png`. All other reference images remain unchanged.

## Verified results

- `flutter analyze --no-pub`: **no issues**.
- `flutter test --no-pub --reporter expanded`: **111 passed**, no failures.
- Includes lifecycle/resume and navigation preservation, session/access invalidation, offline drafts, scheduling deletion and cancellation, account invitation/setup/recovery, PIN mismatch/failure/background clearing, review/approval, and 320px/200% layouts.
- `flutter build apk --debug --no-pub --dart-define-from-file=config/supabase.json`: **successful**.
- APK signature verification: **passed**, certificate matches the prior JANITRA debug APK.
- Package: `com.example.janitra`; version name `1.0.0`; version code `12`; minimum Android API `24`; target API `36`.
- Byte comparisons confirmed that Supabase functions, migrations, database tests and tooling were unchanged. Backend regression tests and remote security advisors were not rerun for this UI build.

APK SHA-256:

```text
b03d0c03accd8561efd43ea18f732dd6d335439fa2b0090ccd47e09c410d09a6
```

## Changed files compared with the tested Build 12 source

```text
lib/features/work/records_page.dart
lib/features/work/scheduling_page.dart
lib/features/work/task_page.dart
lib/features/work/work_form.dart
lib/features/workspace/name_editor.dart
lib/features/workspace/people_page.dart
lib/features/workspace/pin_management_page.dart
lib/features/workspace/supervisor_pin_setup_sheet.dart
lib/features/workspace/username_account_dialog.dart
lib/features/workspace/workspace_page.dart
test/lifecycle_test.dart
test/work_form_picker_test.dart
test/work_ui_test.dart
test/workspace_test.dart
test/goldens/employee-detail.png
test/goldens/supervisor-detail.png
docs/BUILD-12-UI-VERIFIED-2026-10-18.md
anti-slop/audit-013-2026-10-18.md
```

The supplied root-level UI handoff notes remain in the source archive. This report records the Flutter checks and build now completed on their integrated source; their earlier "not run" statements describe the earlier environment.

## Deliverables and remaining checks

- APK: `build/app/outputs/flutter-apk/janitra-build12-ui-refresh-debug.apk` (debug build, approximately 198 MiB).
- Source ZIP: `JANITRA-Build12-UI-Verified-Source.zip`.
- Standalone report: `JANITRA-Build12-UI-Changes.md`.
- UI review: `anti-slop/audit-013-2026-10-18.md`.

The source archive includes Flutter sources, backend source/migrations, tests and documentation. It excludes real local Supabase configuration, private credentials, signing files, generated build/cache directories and backups. Use `config/supabase.example.json` to supply local build configuration.

Physical-phone acceptance remains pending. Check the Team actions and Add/Cancel flows, schedule pickers and deletion confirmation, both PIN setup flows, Supervisor confirmation followed by separate approval, Audit Log filters/details and workplace editing. Actual invitations, PIN changes and destructive actions were tested with mocks rather than live accounts during this run. This APK is for testing; it has not been published.
