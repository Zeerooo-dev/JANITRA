# JANITRA implementation status

Current development update: October 18, 2026. Build 9 is safely integrated into the original `janitra` project, with a complete pre-integration backup. It adds local username accounts, one-time setup/recovery, checklist snapshots and encrypted offline synchronization, and completes the connectivity/resume fixes. The original project passed clean analysis, 91 Flutter tests, 38 Edge Function tests and 178 isolated database assertions plus concurrency checks; its debug APK compiled and its signing certificate matches build 8. Remote deployment, real Auth and physical acceptance are pending. See [build 9 integration and limitations](INTEGRATION-2026-10-18.md). Earlier entries below describe historical milestones.

Current update: October 13, 2026 (Asia/Manila). Build 7 implements/deploys the remaining workflows and Supervisor-only agency transfers, preserving the phone-verified lifecycle fix. Analysis is clean; 71 Flutter tests, 29 Deno tests and 150 isolated database assertions pass, including simultaneous conflicting approvals. Live RLS/guarded functions/JWT denial, scheduled-job health and preserved Supervisor session checks passed. PDF/XLSX artifacts were rendered/reopened. New native acceptance checks and public release signing remain pending. See [build 7](BUILD-7-2026-10-13.md), [phone guide](PHONE_TEST_GUIDE.md) and [current transfer](JANITRA_TRANSFER_2026-10-13.md). Sections below preserve October 12 snapshots and are historical.

The Flutter application lives in `/home/zero/Projects/janitra`. The chat originally referenced `/home/zero/Projects/JanitorialTask`; the actual Flutter project is the janitra directory above.

## Completed in this milestone

- Imported the 23 HTML design references, retaining all original and polished screenshots.
- Fixed the six original audit findings: inaccessible hidden success content, keyboard activation, placeholder navigation, retained demo PINs, contradictory screen inventories, and unused task scripts.
- Replaced the Flutter counter template with the approved JANITRA login layout and Material 3 theme.
- Added real Supabase email/password sign-in, session restoration, sign-out, recovery request handling, and a password-recovery screen.
- Stored session tokens and PKCE verifiers through platform secure storage. Passwords and PINs are not persisted by the app.
- Accepted only publishable/legacy anon client keys. Debug authentication logging is disabled.
- Added Android internet permission, the recovery callback intent, and disabled app backup to protect encrypted session storage.
- Pinned direct dependencies and retained the generated lockfile.
- Disabled local public sign-up and included the Android callback in local Supabase configuration.
- Matched the callback exactly to the supplied remote allowlist: `janitra://auth-callback/`. Request construction, Android intent, session callback filter, and local config share this address.
- Selected the actual publishable client key without printing or saving the privileged key response. The ignored config has owner-only permissions; publishable keys remain extractable from client binaries by design.
- Added a company-name/full-name form shown only when the backend approves first-Supervisor setup. No client-company or site names are required during this step.

## Deployed after explicit approval

- Two versioned migrations: ten foundation tables plus a private one-time Supervisor bootstrap-grant table; foreign keys constrain agency/site relationships.
- Database grants and RLS enforce own-account/personnel access and authorized Supervisor scope. Authorization comes from server-owned assignments, not editable user metadata.
- Active-profile lookups revoke workplace access for suspended accounts even with an existing access token. Authorized Supervisors can still read their suspended personnel's profiles.
- Employee and Supervisor PIN credential tables are private and have no client read/write grants. They contain hash-storage constraints only; PIN enrollment/reset, reauthentication, and attempt-limiting APIs remain unfinished.
- Protected audit triggers record agency/client/site/contract/role/personnel writes and scoped profile updates, including suspension. API roles cannot update, delete, or truncate audit history. Trusted database owners retain administrative powers.
- Approved, verified first-Supervisor setup creates the entered agency and Supervisor role in one transaction, locks the one-time grant, and returns the same company on retry. Unapproved, anonymous, unverified, and suspended accounts cannot use it.
- Supabase accepted the invitation for `jeffirie12@gmail.com` at 3:23 PM Asia/Manila on October 12, 2026. The account's one-time Supervisor setup grant is verified. The user subsequently accepted the invitation and completed setup. A read-only check during this work confirmed a verified account, enrolled password, active profile, and agency-wide Supervisor role for the entered company Cleaners. No organization name was invented.
- The first-password screen reuses the password form and advances only after Auth accepts the password update. The server refuses company setup for an invited account without an enrolled password. Password and confirmation fields are cleared after attempts.

## Live checks

The existing CLI link points to the Supabase project named Janitra, which reports `ACTIVE_HEALTHY`. A read-only request to its Auth settings returned HTTP 200 using the saved public client configuration. Email authentication is enabled and remote public sign-up is disabled.

Before deployment, live catalog queries confirmed no application tables in public or janitra_private. The authenticated CLI connection then succeeded. Both approved migrations were applied, and local/remote migration history match. Live checks confirm 11 tables with RLS, no anonymous profile access, no client PIN-hash access or role creation, and no API audit rewriting. Anonymous HTTP requests to profiles and company-setup status receive permission-denied responses.

Security advisors completed with three WARN notices for the intentionally authenticated SECURITY DEFINER setup RPCs. They use fixed empty search paths, derive identity from auth.uid(), reject anonymous/unapproved/suspended accounts, and restrict sensitive work to the one-time grant. These notices were reviewed, not hidden or reported as a warning-free scan. See DEPLOYMENT-2026-10-12.md.

## Workspace milestone

- AuthGate loads the active own profile and active server-owned roles. It routes restored sessions and completed setup into a Supervisor or Personnel workspace; editable metadata never grants access.
- Loading/errors stay closed, pending users can refresh access, and resuming the app rechecks access. Stale asynchronous checks cannot override newer results.
- Home displays complete visible client/workplace counts for the selected agency, or assigned workplaces for Personnel. Real task APIs are unfinished and the UI says so.
- Agency-wide Supervisors create and rename client companies/workplaces, and rename their manpower company. Site Supervisors rename only their authorized workplaces. Mixed-agency roles cannot grant management privileges in a Personnel agency.
- Profile edits update only the caller's full name. Updates require a returned row before the form reports success; rejected writes remain editable. Loading prevents duplicate writes and dismissal during a write.
- Organization/role reads paginate with stable ID ordering and an exact server count, avoiding silent truncation at the default Data API row limit.
- The live schema and accounts were not changed for this increment. Existing deployed grants, RLS, and audit triggers support these writes. Source files were backed up before installation.
- Development build `1.0.0+2`: `build/app/outputs/flutter-apk/janitra-phase1-workplaces.apk`.

## Remaining foundation work

The scoped user-management code is complete locally but its migration and Edge Function are not deployed. Build 3 shows People management; its live list, invitation, suspension, and reactivation controls cannot succeed until the matching backend is deployed. Newly invited users are routed to Set Your Password before workspace access. No new invitation was sent during development.

Phase 1 is still incomplete. Live user/PIN-management deployment, server PIN secret setup, MFA challenge UI, and native/live verification remain. PIN enrollment/reset/rate limiting are now implemented locally as described below. Scheduling, authoritative Employee PIN submissions, Supervisor verification/approval, workflow locks, offline drafts, and report generation are later milestones. See `docs/NEXT_STEPS.md` for the ordered backlog.

The user's Android screenshot confirms the invitation connected the account. Its temporary pending screen came from the unfinished app route; the account already had a password and completed setup, so no reset or additional invitation was sent. Recovery and secure-storage persistence still need a physical-device round trip. No production recovery email or password was changed during validation.

## Validation

- Flutter: all 24 checks passed, including restored-session routing, denied access/retry, suspension on resume, metadata escalation prevention, agency/site/mixed-role scope, trimmed writes, confirmed updates, duplicate prevention, rejection handling, 320px/200% text, keyboard dismissal, and pagination. Existing login/company/password checks remain passing.
- Analyzer: no issues.
- Disposable PostgreSQL 17: 58 PASS checks across both migrations and both authorization suites. Added client/site creation/rename, actor/history, own profile rename, cross-agency insert denial, and site Supervisor restrictions. No remote writes.
- Design checker: all 23 design references passed local-link, syntax, navigation, hidden-state, PIN-erasure, and Escape checks.
- Android debug APK: production `lib/main.dart` compiled with the existing ignored public configuration. Test-only preview sources are removed and excluded from the installed project.
- Phone preview at 393x852: actual Flutter widgets with an isolated mock API passed navigation, empty validation, client/workplace creation, updated counts, and profile cancellation. Screenshots are in `docs/screenshots/`. Browser runtime changed during the session; final review used a local headless Chromium instance.
- Physical-device verification of the new screens, session persistence, recovery, and authenticated live Data API CRUD is still unverified. Release signing remains pending. The existing reviewed SECURITY DEFINER advisor warnings remain documented in the deployment record.

## User-management build 3

- Agency-wide Supervisors can invite Personnel to an existing workplace or another agency-wide Supervisor. Site Supervisors can invite Personnel only to assigned workplaces. The server confirms the caller's current password before an invite or access change and checks current database scope before sending email.
- Existing accounts receive an authorized assignment without a duplicate invitation email. The People screen lists only roles in the Supervisor's scope and permits Personnel suspension/reactivation per workplace. Audit triggers retain the real Supervisor actor.
- The client uses only the ignored publishable-key configuration. The privileged Auth API is confined to the Edge Function; no privileged key was added to Dart, tests, or tracked configuration.
- Local validation: analyzer clean; all 28 Flutter tests passed; five Deno function tests passed; 78 disposable PostgreSQL PASS checks passed. The 320px/200% People form test passed. Android debug APK `1.0.0+3` built and its signing certificate matches build 2.
- The linked CLI's migration dry run stalled at `Initialising login role` on two DNS settings and was cancelled. Project HTTPS and pooler TCP are reachable; no production migration or function deployment happened. Live authenticated user management and physical-device flow remain unverified.

## PIN build 4 candidate

- Employee PIN management is under People for active authorized Personnel; own Supervisor PIN management is under Profile. Status exposes only configured/time/reset permission. Masked PIN/confirmation/password fields validate four digits, preserve leading zeroes, and clear after write attempts.
- A global Employee PIN cannot be reset by a Supervisor who lacks authority over any of the account's other active Personnel assignments. Supervisor PIN enrollment/reset is own-account only.
- `manage-pins` authenticates verified accounts, checks server-owned scope, requires current account password and configured MFA assurance, and sends a purpose/user-bound HMAC digest to a checked SQL RPC. A separate required server pepper protects four-digit codes; salted bcrypt cost 12 stores only the protected digest's hash.
- Updated `manage-users` shares the same password/MFA confirmation guard. Unverified accounts cannot manage users/PINs. Existing client configuration remains ignored and owner-only; no production PIN pepper or privileged key was added.
- Internal PIN verifier serializes account/purpose attempts; five failures lock for 15 minutes. Eight concurrent wrong requests cannot bypass the limit. Correct input cannot bypass a current lock. Reset invalidates the old credential. No standalone verification API is exposed.
- Future task submission/review must call the internal verifier and commit task transition/history atomically, including committed failure counters on rejected attempts. This integration and the full MFA challenge user flow are not implemented.
- Validation: clean analyzer, 31 Flutter tests, 18 Deno function tests, 108 isolated PostgreSQL PASS checks. The 320px/200% PIN test and rendered 393x852 previews passed. Build `1.0.0+4` compiles and its debug signing certificate matches the preceding builds.
- No new remote deployment was attempted in this continuation. Both pending migrations/functions and the new PIN secret need deployment. See `docs/PIN_SECURITY.md`, `docs/BUILD-4-2026-10-12.md`, and `anti-slop/audit-005-2026-10-12.md`.

## Reference limitations

Missing task-detail and Personnel account-profile designs show explicit preview notices instead of silently opening a different employee task or a Supervisor management screen. Original PNG previews remain historical; corrected HTML is authoritative for the fixes.
