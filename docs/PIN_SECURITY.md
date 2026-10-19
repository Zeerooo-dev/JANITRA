# PIN implementation and deployment contract

October 13 build 7 update: PIN management and the atomic task-workflow API are deployed with JWT verification, current-session checks and the preserved protected server pepper. Employee PIN submission creates Pending Approval and a separate confirmation event. Supervisor verification and final decisions are distinct, with task locks/versions, authoritative deadlines, guarded overrides and reauthorized idempotent receipts. New native round trips remain phone acceptance checks. See `BUILD-7-2026-10-13.md` and `PHONE_TEST_GUIDE.md`. Later pending-integration notes in this file preserve earlier contract history.

## Implemented

- `manage-pins` accepts only authenticated, email-verified accounts. Service-only RPCs repeat current active profile, role, agency, site, and target checks.
- A Supervisor manages Employee PINs only for active Personnel in scope. Because the credential belongs to the whole account, a manager of only some of its active Personnel assignments cannot reset it. Status can be viewed in the caller's scope, but `can_reset` is false when any assignment is outside their management scope.
- A Supervisor sets/resets only their own Supervisor PIN. It is separate from Employee PINs and never implies final task approval.
- Set/reset requires current account password confirmation and completed AAL2 when the account has configured MFA. Assurance is checked on the original verified request token before password reauthentication.
- Four ASCII numeric characters are required, preserving leading zeroes. Flutter masks new PIN, confirmation, and password fields and clears all three after a write attempt; no PIN is cached or persisted locally.
- The Edge Function derives HMAC-SHA-256 over purpose, canonical user ID, and PIN using `JANITRA_PIN_PEPPER`. Only the resulting 64-character hex digest reaches the SQL RPC. PostgreSQL stores a randomly salted bcrypt hash at cost 12. The pepper is not stored in the database or app.
- PIN credential tables have no client or Edge service-role table grants. Checked SECURITY DEFINER RPCs use an empty search path and explicitly revoked public/client execution privileges.
- Configuration status contains a boolean, last-change timestamp, and reset permission. Audit entries contain actor/scope/change metadata, never raw PIN, hash, digest, or password.
- Internal verification serializes attempts with a credential-row lock. Five wrong attempts lock the account/purpose for 15 minutes; attempts during the lock do not extend it. Correct input cannot bypass a current lock. Expiry or successful reset clears the counter; a reset invalidates the previous credential.

## No standalone confirmation endpoint

`janitra_private.verify_pin` is not executable by anonymous, authenticated, or service-role callers. Future trusted task submission/review RPCs must call it internally after validating task ownership, state, scope, and deadline.

The future operation must commit failed-attempt counters when a PIN is wrong or locked, returning a rejected result rather than raising an exception that rolls the counter back. On success, task transition, authoritative timestamp, and event history must commit in the same transaction. Never expose or cache a reusable verified response. This workflow integration is still pending.

## Deployment prerequisites

These deployment steps were completed October 13 using Management API HTTPS, preserving original migration versions in each transaction. The pepper's encrypted backup is in the OS keyring under service `JANITRA PIN protection` for project `pvjvgylzuhpskkrppyng`; it is absent from source, logs, Flutter configuration and archives. Preserve it during maintenance. The CLI login-role path remains unavailable; do not repeatedly retry it or reset the database/password.

1. Restore authenticated database access. The earlier CLI dry runs stalled while initializing the login role; no new migration was applied.
2. Review/apply pending migrations in order: user management `20261012131324`, then PIN security `20261012151246`. The PIN migration requires `pgcrypto` in `extensions` and fails explicitly if the expected function is unavailable. It does not move an existing extension automatically.
3. Generate a cryptographically random 256-bit secret as 64 hexadecimal characters and save it as `JANITRA_PIN_PEPPER` in Supabase Edge Function secrets through a protected local/server process. Do not print it, commit it, upload it, or include it in Dart/client configuration. No production pepper was generated during this work.
4. Preserve this secret in approved secure backup storage. Changing or losing it makes existing PINs unverifiable and requires authorized PIN resets. Secret rotation needs a deliberate operational plan.
5. Deploy `manage-pins` and the updated `manage-users`, including `_shared/confirm_account.ts`, pinned import maps, and lockfiles. Preserve JWT verification. No prune/reset/seed operations are required.
6. Run live grant/advisor checks and verify enrollment/reset/metadata using authorized test accounts. Physical-device password/MFA/session/deep-link checks remain pending.

The app now challenges configured accounts before workspace access and password recovery; Profile offers optional TOTP setup using a manually entered authenticator key. Sensitive APIs still require AAL2 when configured. Lost-authenticator recovery/removal is not offered in the app; use the authorized Supabase recovery process. Other factor types remain closed with help text and are currently disabled remotely. Native verification is still pending.

## Local evidence

- 31 Flutter tests and clean analyzer, including masked fields, leading-zero input, mismatches, rejected credential clearing, per-account/purpose routing, scope-denied resets, Cancel/Escape, and 320px/200% text scale.
- 18 Deno tests across both functions, including wrong passwords, scoped access, missing secret, four-digit validation, HMAC purpose/account binding, required/completed MFA, and assurance failure.
- 108 disposable PostgreSQL PASS checks. Eight concurrent wrong attempts produced four incorrect and four locked outcomes with exactly five recorded failures.
- PIN status and form rendered at 393x852 using the actual Flutter widgets, an isolated backend fixture, and local Roboto/Material fonts. Preview-only test removed before the APK build.
