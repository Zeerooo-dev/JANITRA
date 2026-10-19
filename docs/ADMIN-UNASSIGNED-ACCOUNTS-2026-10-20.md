# Admin account creation before company setup

Maintenance update for **1.0.0+27**, keeping the existing version and release tag as requested.

## Behavior

- Admin can open Team and Add when no manpower company exists.
- Admin can invite a Supervisor or Personnel by email, or create Personnel with a username and expiring one-time setup code, without choosing a company or workplace.
- These accounts are labeled **Unassigned**. Their role records remain inactive and have no company/site scope. They cannot access workplaces, tasks, PIN verification, scheduling, approvals, reports or account management until assigned.
- An unassigned person can finish password setup. Username sign-in can reach the existing access-pending screen; authentication does not grant workplace authorization.
- Once a real company/workplace exists, Admin uses **Assign workplace** for Personnel or **Edit Supervisor access** for Supervisors. Assignment preserves the existing account and audit history. A Personnel account still awaiting password setup remains inactive until setup completes.
- Cancel and empty-form validation do not refresh the team. The existing Add button, branding, profile, appearance and other features are retained.
- Admin can also create the first manpower agency without submitting a nonexistent company ID.

## Architecture and security

The existing three-role model is retained. No placeholder company, new role or client secret is introduced. A database constraint prohibits active non-Admin roles with null company/site scope. Existing scoped role requirements remain unchanged.

The new migration permits null scope only where needed for provisioning, setup grants and their audit events. The existing secure identity flow retains username uniqueness, rate limits, account-password confirmation, one-time grant expiry, replay protection, session revocation and issuer-authority checks. Unassigned records are visible only to Admin. Later Personnel assignment is an Admin-only, session-checked backend operation; Supervisor assignment reuses the existing Admin-controlled editor. RLS and service-only SQL grants remain enforced.

## Files

- `lib/features/workspace/workspace_page.dart`: empty-company Team entry.
- `people_page.dart`, `supervisor_access_sheet.dart`, `username_account_dialog.dart` in the same folder: nullable company, clear unassigned status, creation and later assignment.
- `supabase/migrations/20261019211907_admin_unassigned_accounts.sql`: constrained unassigned role state and guarded provisioning/assignment changes. The local filename matches the version recorded by Supabase's migration API.
- `supabase/functions/manage-users/index.ts`, `_shared/manage_identity.ts`, `personnel-auth/index.ts`: Admin-only null-scope requests and authentication without workplace authorization.
- Corresponding Flutter, Edge and SQL tests; `tool/test_database.sh` includes the new migration and regression cases.

## Verification

- **207 Flutter tests passed**, including empty-company Team/Add, cancellation, all three account-creation paths and later Personnel assignment.
- Flutter analysis: no errors or warnings; the existing informational lint at `personal_schedule_page.dart:151` remains.
- **21 manage-users and 12 personnel-auth tests passed**.
- Isolated SQL tests cover Admin-only unassigned invites, no Company-Wide authority, denied null-scope activation, code expiry, setup after the issuer signs out, username authentication without protected access, later assignment and directory privacy. Existing migration/security checks also pass.
- The user approved production activation. The migration was applied through Supabase's official migration API after the CLI pooler connection was unavailable; existing migration history is retained. No real account is created or invited as part of deployment.
- `manage-users` and `personnel-auth` are ACTIVE with their intended JWT settings. Live checks confirm Admin-only null-scope invitations, enabled RLS, denied direct client execution of the assignment RPC, unchanged record counts and no new security-advisor findings.

## Same-version GitHub replacement

The updated signed APK and source archive will replace the current release downloads only after verification and approved backend activation. The existing `v1.0.0` tag remains unchanged. Replacement release metadata and notes identify the maintenance source commit, since the original tag points to the original publication.

Because version **and build number** remain `1.0.0+27`, this replacement will not trigger the app's automatic newer-version popup. Download and install it manually over a compatible production-signed installation. The updater's strict version/signature checks remain unchanged. Legacy debug-signed installations still require the separately labeled Android 9+ signing-transition APK or a one-time reinstall.

Physical acceptance of this maintenance UI and the legacy signing transition is not claimed; automated verification and local signed build results are reported separately from phone testing.
