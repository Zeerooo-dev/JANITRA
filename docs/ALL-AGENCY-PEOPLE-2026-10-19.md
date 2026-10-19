# JANITRA Build 21: Automatically show all agencies' people

## Behavior

Agency-wide Supervisors open Team and immediately see Personnel and Supervisors across all agencies. There is no Team agency dropdown and no agency-selection step. Each person's existing agency/workplace labels identify where they belong. The heading and assignment counts cover the complete returned directory.

The Supervisor's own agency assignment does not change. Tasks, schedules, reports and approvals retain their existing authorized scope. People outside the Supervisor's authorized agencies are view-only; management actions retain the existing restrictions. Add continues to create accounts in the current authorized workplace agency. Admin accounts remain hidden from the roster. Site-specific Supervisors keep their existing scoped list and company label.

This supersedes Build 20's Team filter behavior. The filter and its selection state were removed rather than adding another preference.

## Backend activation

The pending migration `supabase/migrations/20261019030542_agency_supervisor_directory.sql` is unchanged from Build 20. It enables the service-only directory RPC to return people across agencies to an active agency-wide Supervisor with a valid session. Foreign email and username fields remain redacted; account-management checks and table RLS are unchanged.

**Production deployment still requires approval.** Nothing was deployed during this follow-up. Installing the APK alone cannot enable foreign roster entries until the pending read-only backend permission is activated. No agency reassignment, role grant, account modification or Edge Function deployment is required.

## Verification

- **148/148 Flutter tests passed.** The directory tests now verify that foreign Personnel and Supervisors appear immediately without a dropdown, remain visible after refresh, have no foreign management actions, and do not cause mutation requests. The site-specific test verifies unchanged scoped visibility.
- The existing PIN, invitation, authorization, lifecycle, offline, appearance, scheduling and report tests remain in the suite.
- Light/dark Team screenshot baselines updated and visually inspected. Existing narrow/large-text tests pass.
- Flutter analysis: no errors or warnings; one existing informational `use_null_aware_elements` lint remains at `lib/features/work/personal_schedule_page.dart:151`.
- The unchanged backend migration and database tests retain the completed **354 local PostgreSQL PASS checks** from Build 20. Database tests were not rerun for this UI-only correction.
- Android release built as `1.0.0+21`, package `com.example.janitra`; signature verifies with the existing Android debug certificate.
- After-mode review: `anti-slop/audit-022-2026-10-19.md`.

## Modified files since Build 20

- `lib/features/workspace/people_page.dart`: automatic all-agency roster, removed filter state/UI, preserved existing Add scope.
- `test/workspace_test.dart`: immediate visibility, refresh and role-restriction checks; scrolls through roster entries before checking them.
- `test/goldens/team-empty.png`, `test/goldens/dark-supervisor-team.png`.
- `pubspec.yaml`: build number 21; dependencies and lockfile unchanged.
- This report and `anti-slop/audit-022-2026-10-19.md`.

## Deliverables

- APK: `build/app/outputs/flutter-apk/janitra-build21-all-agency-people.apk`.
- APK SHA-256: `4bbfa5435dbac68c13726cf843d28cb4249a7fe3aa5826d361c93ec41ddaa165`.
- Source: `JANITRA-Build21-All-Agency-People-Source.zip`, root `JANITRA-Build21-All-Agency-People-Source/janitra/`.
- Changes: `JANITRA-Build21-All-Agency-People-Changes.md`.

The source excludes runtime configuration, credentials, keystores, generated output, caches, backups and screenshot failures. Physical-phone/live-account verification and production activation remain pending. The existing whole-roster JSON API and debug signing certificate are retained.
