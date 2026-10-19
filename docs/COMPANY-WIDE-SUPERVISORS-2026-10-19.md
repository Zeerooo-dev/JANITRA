# JANITRA Build 22: Company-Wide Supervisor management

## Final scope

**Company-Wide Supervisor** means a Supervisor who can view every manpower company and manage Personnel, tasks, schedules, approvals and reports across all of them, including companies created later. This replaces the earlier interpretation of Agency-Wide as one company's sites and supersedes the read-only directory behavior in Builds 20 and 21.

**Site-Specific Supervisor** keeps access to the assigned company/sites. **Admin** keeps exclusive authority to invite, edit, suspend, delete or change the permissions of Supervisors. Company-Wide is a Supervisor access option, not a fourth application role or an Admin promotion.

The existing active Supervisor assignment with a null site now represents Company-Wide access. Its agency remains the person's affiliation; switching the displayed company does not reassign the Supervisor. No role-assignment rows are inserted or modified by the migration. On activation, existing Agency-Wide Supervisors gain the newly requested all-company authority. Read-only production inspection found **two active non-Admin Supervisors** in that scope on October 19.

## App behavior

- The existing manpower-company selector receives all companies through RLS for Company-Wide accounts. Selecting a company opens its normal workplaces, tasks, schedules and reports with Supervisor controls.
- Initial selection preserves the Supervisor's affiliated company instead of automatically selecting the alphabetically first company.
- Team continues to show all companies' people automatically. Company-Wide Supervisors can manage Personnel directly from those entries, including name editing, suspension/reactivation, setup/recovery codes, PIN management, transfers and confirmed history-preserving deletion.
- Supervisor rows have no Supervisor-management actions for a Supervisor; Admin accounts remain absent from Team.
- The Admin invite/access forms now say **Company-Wide** and explain that this covers all manpower companies. The Site-Specific option continues to require selected workplaces.
- Cross-company account recovery no longer silently stops because the selected workspace's site list belongs to another company. It uses the target Personnel assignment and verified management scope; the backend repeats the authorization checks.
- Existing UI, navigation, resume behavior, offline Personnel drafts and PDF/XLSX styling remain.

## Backend implementation

Pending migrations:

1. `supabase/migrations/20261019030542_agency_supervisor_directory.sql` (previously prepared directory migration).
2. `supabase/migrations/20261019040713_company_wide_supervisors.sql` (new Company-Wide authority).

The second migration centralizes Company-Wide recognition in a private, non-client-executable helper. Existing RLS helpers and service-only management RPCs then use the current active profile and assignments. Live-session checks, anonymous-session rejection, explicit Personnel/Supervisor distinctions and Admin-only management guards remain in place. The global Admin assignment is not exposed through the Company-Wide company scope.

Supervisor PIN enrollment/verification now recognizes Company-Wide scope across companies while retaining the existing account PIN, hashing, lockout and separate verification/approval steps. Personnel PIN resets still require valid Personnel assignments and cannot target privileged accounts.

Workflow and transfer authority locks include the Company-Wide role across companies. Migration guard checks verify the expected existing function definitions before changing their scope predicates; task, checklist, idempotency, deadline and immutable-history logic is retained. Company-Wide Supervisors receive submission notifications across companies.

No Edge Function deployment, new secret, Auth configuration change or database reset is needed. No accounts or historical work are deleted by activation.

## Verification

- **150/150 Flutter tests passed**, including new tests for Company-Wide scope and company switching; existing site-specific, Admin, authentication, PIN, offline, lifecycle, scheduling, reporting and appearance regressions remain.
- Cross-company UI tests check Personnel management controls, setup/recovery form opening, correctly scoped suspension requests, hidden privileged actions and unchanged Supervisor affiliation after switching companies.
- **406 local PostgreSQL PASS checks:** 354 historical/migration and concurrency checks, **50 checks against the final Company-Wide schema**, and two concurrent-revocation checks. The final-schema tests exercise all-company RLS, unchanged site-specific isolation, Personnel invitation/assignment/edit/suspension/reactivation/recovery/deletion, cross-company PINs, activity/shift/schedule creation, Personnel submission, separate Supervisor verification and final approval, reports, deadline locking/reopening, schedule deletion, notifications, retained history, future companies, suspension, downgrade and session expiry. A cross-company mutation waits on a concurrent scope revocation and is then denied without writing data. Privileged-role management and forged client execution remain denied.
- Tests use a disposable PostgreSQL container without network or exposed ports; no production records are changed.
- Flutter analysis: no errors or warnings; one existing informational `use_null_aware_elements` lint remains at `lib/features/work/personal_schedule_page.dart:151`.
- Updated and inspected light/dark Team and the 320px/200% text Supervisor-access screenshots.
- Android release built as `1.0.0+22`, package `com.example.janitra`; signature verifies with the existing Android debug certificate.
- Read-only production checks confirm the migration ledger still ends at `20261018140000` and expected workflow/PIN scope guards match. Both proposed migrations remain undeployed.
- Production security-advisor baseline has no ERROR findings and three existing WARN findings: two authenticated setup functions and disabled leaked-password protection. Those settings were not changed.
- After-mode review: `anti-slop/audit-023-2026-10-19.md`.

## Modified files since Build 21

- `lib/features/workspace/workspace_access.dart`, `workspace_page.dart`, `people_page.dart`, `supervisor_access_sheet.dart`, `username_account_dialog.dart`.
- `supabase/migrations/20261019040713_company_wide_supervisors.sql` (new).
- `supabase/tests/company_wide_supervisors.sql`, `supabase/tests/company_wide_concurrency.sql` (new), `tool/test_database.sh`.
- `test/workspace_test.dart`, `test/personnel_account_test.dart`.
- `test/goldens/team-empty.png`, `dark-supervisor-team.png`, `admin-access-large-text.png`.
- `pubspec.yaml`: build number 22. Dependencies and lockfile are unchanged.
- This report and `anti-slop/audit-023-2026-10-19.md`.

## Deliverables and remaining activation

- APK: `build/app/outputs/flutter-apk/janitra-build22-company-wide.apk`.
- APK SHA-256: `16cf6a34f5a8202308a52af87fda6bb02bc05241ab1b1586810957ba79f82bcc`.
- Source: `JANITRA-Build22-Company-Wide-Source.zip`, root `JANITRA-Build22-Company-Wide-Source/janitra/`.
- Changes: `JANITRA-Build22-Company-Wide-Changes.md`.

**Production activation requires approval for the two pending migrations.** The APK alone cannot expand server permissions. Install Build 22 to use the matching all-company management UI once activated. Admin can restrict a Supervisor again through Site-Specific access; existing session revocation and current-role checks apply.

Physical-phone/live-account acceptance and post-deployment verification remain pending. The existing whole-roster JSON API and debug signing certificate are retained. Source packaging excludes runtime configuration, credentials, keystores, generated files, caches, backups and screenshot failures.
