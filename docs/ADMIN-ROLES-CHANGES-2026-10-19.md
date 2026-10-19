# JANITRA Build 13: Admin roles and permissions

## Implemented

- Added the explicit global `admin` role alongside `supervisor` and `personnel`. Existing accounts are not automatically promoted.
- Admin reuses the existing Supervisor dashboard, sees every agency, and has Admin-only Supervisor Management. Admin accounts are excluded from Team lists.
- Admin can invite Supervisors with agency-wide access or multiple selected sites, edit their name and scopes, suspend/reactivate them, and permanently remove their accounts. Changing Supervisor access revokes their sessions.
- Supervisors retain scoped Personnel invitations, name editing, suspension, PIN management and deletion. They cannot invite, edit, reset credentials for, suspend, or delete Supervisors/Admins. Scoped Supervisor visibility is retained for existing report filters.
- Deletion requires typed DELETE, password/MFA confirmation, and database authorization checked again when Auth deletes the account. Personnel deletion by a Supervisor requires authority over every assignment. Deleted accounts lose Auth access, sessions and PIN credentials; inactive profile references preserve tasks, submissions, approvals and immutable audit history.
- Protected the last active Admin from role removal or suspension, including concurrent attempts. Admin account deletion is not exposed.
- Extended workflow authorization and authority locks for Admin scheduling, reports and task reviews. Admin task notifications and Supervisor PIN verification use the existing workflow.
- Disabled the legacy self-service Supervisor bootstrap so it cannot bypass Admin-managed permissions. Existing completed setup data is retained.
- Blocked Personnel recovery codes from changing privileged accounts, including accounts with historical Personnel assignments.
- Filtered report/scheduling options to the selected agency. The new Delete controls require the history-preserving backend response, preventing use of the old erasure behavior during an interrupted upgrade.
- Preserved branding, adaptive/themed launcher icons, offline access rules, deadline locking and PDF/XLSX report generation. Version is `1.0.0+13`.

## Verified locally

- 121 Flutter tests passed, including lifecycle/navigation, invitations, scope editing, cancellation without refreshing, password clearing, report filters, offline drafts and PDF/XLSX exports.
- 47 Edge Function tests passed: manage-users 16, workflow/manage-pins 21, personnel-auth 10.
- Isolated PostgreSQL suite: 325 passing assertion notices and five passing regression/concurrency summaries. This covers the existing migration baseline and post-migration workflows, PINs, schedules, username recovery, history-preserving deletion, Admin scheduling/reporting/approval and the last-Admin race.
- Flutter analysis: no errors or warnings; one existing informational `use_null_aware_elements` lint at `lib/features/work/personal_schedule_page.dart:139`.
- New access editor rendered and exercised at 320px with 200% text; snapshot in `test/goldens/admin-access-large-text.png`. Password prompt wraps visibly above the input.
- The live role constraints and application foreign keys referencing Auth were inspected read-only and match the migration's assumptions. The nominated first Admin account exists and has a confirmed email.

## Production status

Completed October 19, 2026 after explicit approval: migration `20261018140000_admin_roles.sql` applied with its ledger record, `manage-users` deployed ACTIVE version 8 with JWT verification enabled, and `jeffirie12@gmail.com` granted the first Admin role using `supabase/provision/first_admin.sql`.

Verified exactly one active Admin. Account, task and approval counts remained unchanged. The schema migration also left audit counts unchanged; provisioning then added its audit records. Live grants deny client role writes, forged deletion approval and direct Supervisor management. The account-deletion trigger no longer erases task records. The deployed function rejects unauthenticated requests with HTTP 401. No live account was deleted and no other Supervisor was promoted.

Post-deployment security advisor: no ERROR findings, 11 INFO findings and three WARN findings. Two warnings flag the intentionally authenticated `needs_company_setup()` / `needs_password_setup()` setup RPCs; the former now returns false and the latter remains scoped to the signed-in user. The third flags the existing disabled leaked-password protection Auth setting. No Auth configuration was changed as part of this deployment.

The provisioning script aborts if a different first Admin already exists. Do not rerun it to add further Admin accounts without an explicit provisioning decision.

## APK

Release APK built successfully: `build/app/outputs/flutter-apk/janitra-build13-admin-roles.apk`, version `1.0.0+13`, Android minimum 24 / target 36. Signature verified with the existing certificate (`a812ea37a8d03d2565864ff0b012357b635b578f2da0730add4450f520d71219`).

APK SHA-256: `69eb014dd300eb46769362e413ee5e2cbe807fd859280aed32c744c0ccf9f70f`.

## Modified files

- `pubspec.yaml`
- `lib/app.dart`
- `lib/features/workspace/workspace_access.dart`
- `lib/features/workspace/workspace_page.dart`
- `lib/features/workspace/people_page.dart`
- `lib/features/workspace/supervisor_access_sheet.dart`
- `lib/features/reports/reports_page.dart`
- `lib/features/work/scheduling_page.dart`
- `supabase/functions/manage-users/index.ts`
- `supabase/functions/manage-users/index_test.ts`
- `supabase/migrations/20261018140000_admin_roles.sql`
- `supabase/provision/first_admin.sql`
- `supabase/tests/admin_roles.sql`
- `supabase/tests/admin_concurrency.sql`
- `tool/test_database.sh`
- `test/workspace_test.dart`
- `test/personnel_account_test.dart`
- `test/fixtures/workspace_backend.dart`
- `test/goldens/admin-access-large-text.png`
- `docs/ADMIN-ROLE-PLAN.md`
- `docs/ADMIN-ROLES-CHANGES-2026-10-19.md`
- `anti-slop/audit-015-2026-10-19.md`

## Remaining checks

Install Build 13 and refresh workplace access or sign in again as `jeffirie12@gmail.com` to load the Admin role. Test Admin/Supervisor/Personnel flows on the physical phone. Real external email invitations still need custom SMTP configuration; this change does not bypass email confirmation or provide email-provider credentials. APK signing uses the project's existing debug certificate; this is a test build, not a Play Store release.
