# Approved foundation deployment

October 13 follow-up: after the user confirmed the lifecycle phone check and authorized broader continuation, both pending management migrations, `manage-users`, `manage-pins`, and the server-only PIN pepper were deployed. Original migration versions/history preserved transactionally over Management API HTTPS; no credential or grants changed to bypass stalled CLI login. Both functions are ACTIVE version 1 with `verify_jwt=true`. No invitation, existing account/password/role/PIN mutation performed. See [build 6](BUILD-6-2026-10-13.md) for live checks and current limitations. Pending-deployment sections below are historical.

Date: October 12, 2026, Asia/Manila. User explicitly approved the two migrations and first-Supervisor invitation.

Target: Janitra project `pvjvgylzuhpskkrppyng`.

Applied and verified against migration history:
- `20261012021018_phase1_foundation`
- `20261012022056_first_supervisor_setup`

Before deployment, the second migration gained the first-password check required for invited users. The app reuses its password form before company registration, and the backend refuses company setup until a password is enrolled. Twelve Flutter tests, analyzer, both isolated PostgreSQL suites, and the updated Android debug build passed. The database test runner now waits for the final TCP listener rather than the temporary initialization socket.

## First Supervisor

- Email: `jeffirie12@gmail.com`
- Supabase accepted the invitation at `2026-10-12T07:23:02.57027488Z` (3:23 PM Asia/Manila).
- Callback: `janitra://auth-callback/`.
- One-time setup grant: verified present.
- Email verified: false at final check.
- Company setup completed: false at final check.

Install `build/app/outputs/flutter-apk/app-debug.apk`, then open the invitation on that Android phone, choose a password, and enter the manpower company name and full name. A Supervisor role scoped to that company is created when setup succeeds. No client company or site is prefilled.

Backend credentials were used only in process memory for the project's Auth API. They were neither printed nor saved in the application. The invitation's acceptance by Supabase is confirmed; inbox delivery and the user's device round trip are not.

## Live security verification

- Eleven application/private tables have RLS enabled.
- Anonymous profile reads: denied by table grants and by actual HTTP requests.
- Anonymous company-setup RPC: denied by actual HTTP request.
- Authenticated client PIN-hash reads and role creation: denied by grants.
- API-role audit update/delete/truncate: denied.
- Local and remote migration versions match.

Security advisors returned three WARN notices for authenticated SECURITY DEFINER RPCs: `needs_company_setup`, `needs_password_setup`, and `setup_manpower_company`. Their elevated access is intentional: clients cannot read Auth password state/private grants or create their own roles directly. Each operation is caller-bound, uses an empty search path, and checks the approved setup grant through the status helper or transaction. Anonymous execution is revoked. The mutating RPC serializes setup on the grant row and checks email verification, password enrollment, profile suspension, and existing role assignments. The helper returns only a boolean, never a credential hash.

These warnings remain visible. This review does not certify unfinished PIN APIs, user-management endpoints, physical-device storage, or operational workflows. Phase 1 is still incomplete.

## Subsequent account and workspace follow-up

The invitation-state bullets above are the deployment-time snapshot. The user later accepted the invitation and completed setup. A read-only follow-up during this work confirmed email verification, an enrolled password, an active profile, and an active agency-wide Supervisor assignment for Cleaners. The user's Android screenshot also confirms the account connection. No new invitation or password reset was sent.

The workspace milestone uses the already-deployed schema; no new production migration was applied. Build 2 replaces the temporary account-connected route with the authorized workspace. New client/site write checks run only in disposable local PostgreSQL. An additional CLI refresh after the temporary session workspace reset did not finish and was cancelled; the account status above comes from the earlier successful follow-up in this work.

## User-management deployment pending

The next migration, `20261012131324_user_management`, and `manage-users` Edge Function passed local database/function tests and were compiled into candidate build 3. Neither has been deployed. Two bounded `supabase db push --linked --skip-vault --dry-run --yes` attempts, the second with HTTPS DNS, stopped at `Initialising login role` and were cancelled after a timeout. The project and Management API respond over HTTPS, and the database pooler TCP port is reachable; this does not establish an authenticated database session. No new invitation or production role change was made.

Deploy the migration before the Edge Function, preserving JWT verification. Then check migration history, service-only RPC grants, the function's unauthorized response, security advisors, and one authorized live invite/suspension flow with consenting test accounts. Do not reinvite or reset the existing first Supervisor.

## PIN continuation pending

The local candidate now also includes migration `20261012151246_pin_security`, `manage-pins`, and an updated `manage-users` sharing password/MFA confirmation. Neither pending migration nor function is deployed. No production PIN secret, account PIN, or new invitation was created.

After restoring database login, deploy user management then PIN security; configure server-only `JANITRA_PIN_PEPPER`; deploy both functions with their shared helper and JWT verification enabled. Verify grants/advisors and live/native behavior before promoting build 4. The PIN pepper must remain stable and securely backed up; losing/changing it requires authorized credential resets. See `docs/PIN_SECURITY.md` for the full deployment and future atomic-task integration contract.
