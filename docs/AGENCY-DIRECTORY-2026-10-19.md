# JANITRA Build 20: Agency-wide Supervisor people directory

## Requested behavior

Agency-wide Supervisors can browse people across manpower agencies. This is directory access: account management remains within the Supervisor's authorized agencies/sites. Site-specific Supervisors retain their existing scoped visibility. Admin remains the highest authority and only Admin manages Supervisor permissions.

## App changes

- Team has a **Team agency** filter for agency-wide Supervisors, with their current agency selected initially, other agencies represented in the returned roster, and **All agencies**.
- Changing this filter changes the displayed roster and its assignment counts. It does not reassign the Supervisor or switch the agency used by tasks, schedules, reports or approvals.
- Other-agency Personnel and Supervisors are view-only. Add is hidden while viewing a different agency or All agencies; management actions remain subject to existing scopes and server authorization.
- Admin accounts stay hidden. Site-specific Supervisors and the existing Admin management UI are unchanged.
- The selected directory filter survives a successful roster refresh; if its agency no longer has rows, it returns to the current workplace agency. Selecting a filter performs no writes.

## Backend change

One pending migration: `supabase/migrations/20261019030542_agency_supervisor_directory.sql`.

It replaces the existing service-only `owner_list_accounts(uuid,uuid)` function. A current, active agency-wide Supervisor can read directory entries across agencies. Active site-specific Supervisors continue to receive their scoped rows. The function rechecks the caller's live session and current database role assignments for each request; a suspended account, expired session or revoked agency-wide role cannot keep requesting a global directory.

Foreign directory entries expose the existing display name, agency, workplace, role and status fields. Email and username are redacted outside the caller's management scope. Existing `can_delete_account` checks remain authoritative. Direct client/anonymous execution is denied. The existing `manage-users` function already calls this RPC with the authenticated caller and session, so no Edge Function deployment is needed.

No table RLS, account-management authority, role assignments, audit history, PIN, scheduling, approval or task data is changed. No existing account is promoted or migrated. Direct agency/site reads remain restricted to the caller's authorized scope.

## Verification

- **148/148 Flutter tests passed**, including all 146 previous tests and two directory tests for agency-wide/site-specific Supervisors.
- Tests exercise own/other/all agency filters, refresh retention, hidden Admins, foreign read-only actions even when a fixture supplies a deletion flag, scoped management controls, and no mutation requests while browsing.
- Existing large-text PIN test now scrolls to the visible action button below the new filter before opening it. All PIN/lifecycle/offline regressions still pass.
- **354 local PostgreSQL PASS checks**, including new directory checks and the complete existing migration, authorization and concurrency suite. Tests run in a disposable PostgreSQL container without network or exposed ports; no production records are changed.
- New database tests verify foreign Personnel/Supervisor visibility, real username/email redaction, unchanged site-specific and Personnel visibility, hidden Admins, denied cross-agency invite/delete/edit/PIN reset, denied Supervisor management, preserved Admin access, immediate role revocation, suspension and expired-session denial, service-only execution and unchanged agency/site RLS.
- Flutter analysis: no errors or warnings; one existing informational lint remains at `lib/features/work/personal_schedule_page.dart:151`.
- Light/dark Team screenshots updated and visually inspected. Existing narrow/large-text app tests pass.
- Android release APK built as `1.0.0+20`, package `com.example.janitra`; signature verifies with the existing Android debug certificate.
- Read-only inspection confirmed that the deployed RPC matches the previous migration and is service-only. Production security-advisor baseline has no ERROR findings and three existing WARN findings: two authenticated setup functions and disabled leaked-password protection. This update changes none of those settings.
- After-mode UI review: `anti-slop/audit-021-2026-10-19.md`.

## Modified files

- `lib/features/workspace/workspace_access.dart`: identifies verified agency-wide Supervisor assignments for the directory UI.
- `lib/features/workspace/people_page.dart`: directory filtering and scoped action visibility.
- `supabase/migrations/20261019030542_agency_supervisor_directory.sql`: directory-only read authorization.
- `supabase/tests/agency_supervisor_directory.sql`: database authorization regression tests.
- `tool/test_database.sh`: includes the new migration and tests.
- `test/workspace_test.dart`: directory tests and large-text scrolling adjustment.
- `test/goldens/team-empty.png`, `test/goldens/dark-supervisor-team.png`.
- `pubspec.yaml`: build number 20. Dependencies and `pubspec.lock` are unchanged.
- This report and `anti-slop/audit-021-2026-10-19.md`.

## Deliverables and activation

- APK: `build/app/outputs/flutter-apk/janitra-build20-agency-directory.apk`.
- APK SHA-256: `3e80dae3bed66530cbf47ee89723fb6895d7acbe2afc511774e0248131451f9f`.
- Source: `JANITRA-Build20-Agency-Directory-Source.zip`, root `JANITRA-Build20-Agency-Directory-Source/janitra/`.
- Changes: `JANITRA-Build20-Agency-Directory-Changes.md`.

**Production activation is pending approval.** The APK alone cannot expand directory visibility while the old database function is deployed. Approve the single migration to enable the tested cross-agency read permission. No account deletion, role grant or Edge Function deployment is part of activation.

The source archive excludes runtime Supabase configuration, credentials, keystores, generated output, caches, backups and screenshot failures. Physical-phone/live-account acceptance and post-deployment verification remain pending. This retains the existing whole-roster JSON API; large-directory pagination was not added. The APK retains the existing debug signing certificate.
