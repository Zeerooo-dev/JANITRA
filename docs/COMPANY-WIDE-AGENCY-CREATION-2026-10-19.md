# JANITRA Build 23: Company-Wide agency creation

## Requested behavior

Company-Wide Supervisors can see every manpower company, including Cleaners and LSERVE, manage Personnel/tasks/schedules/approvals/reports across those companies, and add more manpower agencies. Site-Specific Supervisors retain their assigned company/workplace scope. Admin retains exclusive Supervisor management. These are three existing application roles; Company-Wide remains a Supervisor access option.

Build 23 completes the agency-creation permission on top of Build 22's all-company management. The existing **Profile → Manpower companies → Add Manpower Agency** action is now available to both Admin and Company-Wide Supervisor. The existing company selector lists every RLS-authorized company and can switch the displayed workspace. Team shows all-company assignments for Company-Wide accounts.

## What changed

- Reused the existing creation form and account-password confirmation; no additional screen or dependencies.
- Creation selects and loads the new company immediately. It reloads workplace data without refreshing account authorization or changing the Supervisor's affiliation or roles.
- Cancel and empty forms make no request and show no loading/refresh screen.
- The service-only `create_manpower_agency` RPC now permits a current Admin or Company-Wide Supervisor. It locks the session, profile and qualifying role rows, rechecks current authorization/session validity, validates and trims the name, and uses the existing immutable agency audit trigger to record the verified actor.
- No role assignments are inserted by creation. The all-company RLS from Build 22 automatically includes companies created later.
- Direct client RPC access remains denied. Site-Specific, Personnel, suspended/revoked accounts, invalid/missing/expired sessions, and invalid names remain denied. Existing password/MFA confirmation and verified actor/session binding in the Edge Function remain.
- Updated the creation-denial message to name Admin and Company-Wide Supervisor correctly. No other account-management logic changed.
- Existing Site-Specific boundaries, Admin-only Supervisor actions, PINs, deadlines, task history, approvals, reports, offline work, resume behavior, branding and appearance remain.

## Verification

- **154/154 Flutter tests passed**, including company creation/selection, cross-company management, hidden creation actions for Site-Specific/Personnel, Admin visibility, no request/spinner on empty or canceled forms, no authorization refresh after creation, and unchanged Supervisor affiliation. Existing visual, lifecycle, offline, authentication, PIN, scheduling and reporting regressions passed without changing screenshot baselines.
- **18/18 manage-users Edge Function tests passed**, including fresh password/MFA confirmation, verified actor/session binding, invalid-name rejection and authorization-revocation error handling.
- **433 isolated PostgreSQL PASS checks**, including 25 new agency-creation checks and four concurrency checks for cross-company workflow/agency writes waiting on authority revocation and then being denied without writing. New tests cover agency creation/audit, unchanged roles, service-only execution, Admin-only Supervisor controls, invalid names, forged/expired/missing sessions, suspension/revocation, immediate new-company RLS/workplace management, and unchanged Site-Specific isolation. All pre-existing migration, PIN, task, deadline, history and deletion tests remain in the suite.
- Database tests ran in a disposable local container without network or exposed ports. No production data was changed.
- Flutter analysis: no errors or warnings. One existing informational `use_null_aware_elements` lint remains at `lib/features/work/personal_schedule_page.dart:151`.
- Android release built successfully: `1.0.0+23`, package `com.example.janitra`, minimum SDK 24, target SDK 36. APK signature verifies with the existing Android debug certificate.
- Before approval, read-only live inspection confirmed the production migration ledger ended at `20261018140000` and agency creation remained Admin-only. This explained why installing the previous APK alone did not expand Supervisor access. After the user's explicit deployment approval on October 19, all three migrations were applied and the updated function was deployed; verification is recorded below.
- After-mode review: `anti-slop/audit-024-2026-10-19.md`.

## Modified files since Build 22

- `lib/features/workspace/workspace_page.dart` — creation visibility, guard, and local selection/reload.
- `supabase/migrations/20261019043557_company_wide_agency_creation.sql` — new service-only creation authorization.
- `supabase/functions/manage-users/index.ts` — creation error wording only.
- `supabase/functions/manage-users/index_test.ts` — creation validation/revocation regressions.
- `supabase/tests/company_wide_agency_creation.sql` — new final-schema tests.
- `supabase/tests/company_wide_concurrency.sql`, `tool/test_database.sh` — include new migration/tests and concurrent creation/revocation coverage.
- `test/workspace_test.dart`, `test/fixtures/workspace_backend.dart` — UI and fixture coverage.
- `pubspec.yaml` — build 23; no dependency or lockfile change.
- This report and `anti-slop/audit-024-2026-10-19.md`.

## Production activation completed

The user explicitly approved deployment on October 19, 2026. The following were deployed to JANITRA project `pvjvgylzuhpskkrppyng`, in order:

1. `supabase/migrations/20261019030542_agency_supervisor_directory.sql`.
2. `supabase/migrations/20261019040713_company_wide_supervisors.sql`.
3. `supabase/migrations/20261019043557_company_wide_agency_creation.sql`.
4. `manage-users` with the corrected creation error message — version **10**, **ACTIVE**, JWT verification enabled.

The second migration gives existing active Supervisor assignments with a null site Company-Wide authority across all current and future manpower companies. The previous read-only inspection counted two non-Admin Supervisors in that scope. This changes their live permissions; it does not promote them to Admin. Site-Specific assignments stay restricted. The third migration adds company-creation authority to that same Company-Wide scope.

No reset, account deletion, role-row insertion, secret change or account migration was performed. Supervisor-management permissions and historical records are preserved.

Post-deployment verification:

- The live migration ledger contains exactly the three approved additions, ending at `20261019043557`; prior migration versions remain unchanged.
- Account, profile, company, assignment, task, approval and audit counts match the snapshot taken immediately before deployment. No application records were created or deleted by deployment or verification.
- Exactly the 12 expected function definitions were added/changed; no functions were removed. All eight directly declared function bodies match the approved SQL source.
- Both existing active Company-Wide Supervisor accounts have cross-company management scope, cannot invite Supervisors, retain no Admin authority, and cannot read company records using a missing session. Direct client agency-creation execution and access to the private authority helper remain denied.
- Every public table retains RLS. Existing local tests verify Site-Specific isolation, creation, Personnel management, PINs, schedules, approvals and reports. No active signed-in Company-Wide sessions were available during production verification, so signed-in phone acceptance remains pending; no test sessions or accounts were manufactured in production.
- Downloaded `manage-users` source and its five supporting files match the reviewed local files byte for byte. The deployed HTTPS endpoint returns HTTP 401 for both missing and invalid authorization. Only `manage-users` was deployed; other Edge Functions remain unchanged.
- Security advisors report the same three existing WARN findings and no ERROR findings: two intentional authenticated setup RPCs and disabled leaked-password protection. No Auth settings were changed.

Install **Build 23** for the matching Company-Wide UI and **Profile → Manpower companies → Add Manpower Agency** action. Reopen/sign in to load current authorization and the company list. Physical-phone acceptance remains pending.

## Deliverables

- APK: `build/app/outputs/flutter-apk/janitra-build23-company-agencies.apk`.
- APK SHA-256: `be0d5db45f5ae7b489ee087048294cba657a87515459c9d993c93275ba1c9aaf`.
- Source: `JANITRA-Build23-Company-Agencies-Source.zip`, root `JANITRA-Build23-Company-Agencies-Source/janitra/`.
- Changes: `JANITRA-Build23-Company-Agencies-Changes.md`.

The source archive excludes runtime Supabase configuration, secrets, signing keys, generated files, caches, build outputs, backups and screenshot failures. The existing Android debug signing identity is retained for compatibility with prior APKs. The pre-existing whole-roster JSON API remains unchanged.
