# JANITRA Build 19: Supervisor agency visibility

## Fix

The workspace header previously showed the manpower company only when more than one agency was available. A Supervisor assigned to one agency therefore had no agency label above the dashboard, tasks or workplace screens.

Agency-wide and site-specific Supervisors now see their manpower company in a read-only header when only one agency is available. It remains visible across Home, Tasks, Team, Reports, Workplaces and Profile. Admin uses the same workspace UI. Accounts with multiple agencies retain the existing agency selector. Personnel screens are unchanged.

The header uses the existing company data returned by the authenticated Supabase query. Long names use up to two lines; long-press the name for its full tooltip. The company icon identifies the agency context without adding an action or implying it can be changed.

Agency-wide Supervisors retain their existing company-management rights. Site-specific Supervisors can read their company name but cannot edit the company or create agency-level workplaces. No authorization, RLS, migrations, backend functions, accounts or data were changed. No remote deployment is required.

## Verification

- Reproduced the missing single-agency header with failing regression tests for both Supervisor access types before applying the fix.
- **146/146 Flutter tests passed**, including all 143 previous tests and three new agency-visibility tests.
- New tests check the company header on Home, Workplaces and Profile for both Supervisor types, preserve the existing management restrictions, and verify a long company name at 320px and 200% system text. Viewing the company performs no writes.
- Existing multiple-agency switching, mixed-role restrictions, lifecycle/navigation, appearance, PIN, offline and account-management tests still pass.
- Visually inspected light and dark Supervisor screens, Team and the large-text Tasks screen. Nine affected Supervisor screenshot baselines updated.
- Flutter analysis: no errors or warnings. One existing informational `use_null_aware_elements` lint remains at `lib/features/work/personal_schedule_page.dart:151`.
- Android release APK built and verified: package `com.example.janitra`, version `1.0.0+19`, minimum Android API 24. Signature matches the existing Android debug certificate.
- `pubspec.lock` and all backend source/migration files are unchanged from Build 18.
- After-mode review: `anti-slop/audit-020-2026-10-19.md`.

## Modified files

- `lib/features/workspace/workspace_page.dart`: read-only single-agency header for the Supervisor/Admin workspace.
- `test/workspace_test.dart`: three regression tests.
- `pubspec.yaml`: build number 19.
- `test/goldens/supervisor-home.png`, `supervisor-tasks.png`, `supervisor-tasks-large-text.png`, `team-empty.png`, `reports.png`, and `dark-supervisor-{home,tasks,team,reports}.png`.
- This report and `anti-slop/audit-020-2026-10-19.md`.

## Deliverables

- APK: `build/app/outputs/flutter-apk/janitra-build19-agency-visibility.apk`.
- APK SHA-256: `788fc3ea7a72e21fe9edc1d84520775b75dea727a6f1ce4748476fc74c030b52`.
- Source: `JANITRA-Build19-Agency-Visibility-Source.zip`, root `JANITRA-Build19-Agency-Visibility-Source/janitra/`.
- Standalone report: `JANITRA-Build19-Agency-Visibility-Changes.md`.

The source excludes runtime Supabase configuration, credentials, keystores, generated output, caches, backups and screenshot failure output. Provide your own local build configuration as described in the project instructions.

Physical-phone acceptance and live-account verification remain pending. Backend policy behavior was inspected in the existing migrations; no production database query or deployment was performed. The APK retains the existing debug signing certificate.
