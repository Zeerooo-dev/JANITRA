# JANITRA authentication and offline architecture proposal

Status: original design proposal, retained as a decision record. Build 9 now has a tested local implementation; see [the October 18 integration report](INTEGRATION-2026-10-18.md) for actual table/function names, verification and remaining limits. Proposed components below are not a claim of the deployed schema. Remote deployments and account migrations still require separate approval.

## Verified starting point

- Actual project: `/home/zero/Projects/janitra`, Flutter + Supabase, version `1.0.0+8`.
- After Dart formatting, the premium redesign archive's `lib/` and `test/` source matches the current project. The archive is reference material, not a source of deployment instructions.
- Live read-only schema inspection found six applied migrations, 29 application tables, exactly `supervisor` and `personnel` roles, and RLS on every public table. No schema writes or account changes occurred.
- Existing Auth uses email/password and email invitation. `manage-users` validates a live session, Supervisor scope, password confirmation and configured MFA before sensitive management.
- `janitra_private.live_auth_session` and service-only workflow RPCs already protect current sessions/active roles. Task verification, final decisions, immutable history, deadlines, version checks and UUID request receipts already exist.
- Existing local storage is AES-GCM encrypted SQLite with per-user secure-storage keys and owner/bucket authenticated data. It caches personal tasks/schedules and remarks drafts. The encrypted cache proof is bound to a session fingerprint and expiry.
- Gaps: username provisioning/login/recovery; checklist data; complete workplace/cache snapshots; last-sync/pending-change UI; explicit sync coordination; safe network-degraded workspace presentation. Offline reopening currently depends on a still-valid restored session.

## 1. Identity and account lifecycle

### Username mapping

Keep Supabase Auth as the only password/session authority. Add a private Personnel identity map containing immutable Auth user ID, canonical username, display username, optional contact email, provisioning state, and audit metadata. Unique usernames are global, case-insensitive ASCII `a-z`, digits, `.`, `_`, `-`, 3–32 characters, without `@`; this distinguishes them from existing email login. Reserve retired usernames to prevent reassignment impersonation. Do not derive roles from this table or user-editable metadata.

New email-less Personnel receive an opaque random internal email alias, such as a random identifier under a reserved `.invalid` domain, created through the server-only Auth Admin API with email confirmation handled administratively. No SMTP is attempted for the alias. This is a technical Auth identity, never a contact address or a username-derived public lookup. Optional contact email is stored separately and must be verified before it becomes a recovery channel. Existing users keep their Auth IDs/emails and assignments; binding a username is an explicit authorized operation, never a bulk automatic conversion or email-based account merge.

A new public login endpoint accepts username/password and returns an ordinary Supabase session only after Auth password verification and current account/provisioning checks. It does not return the identity map or a lookup-only response. Flutter installs the verified session using the SDK; existing email/password paths stay available. Internal aliases must not appear in login/profile/team/report UI.

The username login endpoint must necessarily be reachable before a user has a JWT. Its public configuration is isolated from all existing management/PIN/workflow endpoints, whose JWT verification remains enabled. Public access provides no management capability. Privileged keys and identity lookups stay server-side.

### Enumeration protection and rate limits

Use the same failure status/body for an unknown username, wrong password, pending setup, disabled account and invalid credential. Run a failed Auth attempt against a reserved nonexistent identity for unknown usernames rather than immediately returning a lookup failure; measure and minimize timing differences in integration tests. Do not offer anonymous username availability or account-status queries.

Persist bounded attempt counters in private storage, indexed by HMAC of the canonical identifier and an independently enforced trusted ingress/device/network budget. Do not trust a client-supplied IP or device ID as the sole limit. Initial policy proposal: five failed credential attempts per username per 15-minute window, with progressive backoff rather than permanent lockout; an additional network/global budget prevents distributed enumeration and database resource exhaustion. The trusted IP source/proxy behavior must be verified in the deployment environment before enabling the endpoint. Use generic 429 retry guidance, short-lived counters and capped request bodies. Audit abuse aggregates without passwords, token bodies or raw sensitive request headers.

### Supervisor provisioning

Add an explicitly Personnel-only operation to `manage-users`: full name, username, optional contact email, authorized agency/site. Require the same live session, current Supervisor scope, password confirmation and MFA as existing invitations. Username uniqueness is enforced atomically in Postgres. Use a durable provisioning operation/receipt for cross-service retries: reserve identity, create/reconcile Auth user, record inactive assignment, issue setup token, finalize only after password setup. A retry must not create duplicate users, grant a different scope, or overwrite an existing person's password.

Do not grant active workplace access to an unfinished account. Auth Admin calls and database changes cannot share a transaction, so interrupted provisioning remains a resumable inactive state, never a false success. Recheck the sponsoring Supervisor's current authority and the requested site at final activation. Existing email invitations for Supervisors and existing accounts remain unchanged.

### One-time setup and recovery

Use a cryptographically random 256-bit setup token, not a permanent password or task PIN. Store only a hash with purpose, owner, issuer, expiry, consumed/revoked state and operation ID. Proposed expiry: 30 minutes. Display once through a protected Supervisor handoff screen for in-person delivery; optional verified-email delivery can be added through the approved channel. Suppress screen capture where supported, clear the token on dismissal/background, do not write it to logs, notifications, audit payloads, screenshots or local drafts, and do not copy it automatically to the clipboard.

Personnel enter the setup token and choose their own password online. Redemption claims the token atomically, validates live provisioning scope, sets the password through Auth, completes enrollment and activates the authorized assignment. Concurrent redemptions allow one winner. Interrupted Auth/database operations remain locked until reconciled; never release a protected session based only on the possession of an unfinished grant. Idempotency records exclude passwords and plaintext setup tokens. Passwords meet the project's Auth password policy; current PINs remain separate.

Recovery uses a distinct expiring token and requires an authorized Supervisor to verify identity, confirm password/MFA, and provide a reason. Recheck authority over all active affected assignments before an account-wide credential reset. Revoke current sessions/cache grants, set recovery pending, and prevent protected access until the person chooses a new password. Record request, issuance, redemption, expiry and cancellation as append-only security events, excluding secrets. Email-less Personnel must not depend on email links or security questions. Existing verified-email recovery remains available for existing email identities. Account changes and recovery require online access.

## 2. Additive database design

All names below are proposed; no migration has been created or applied. Never edit an applied migration.

| Proposed component | Purpose | Client access |
| --- | --- | --- |
| `janitra_private.personnel_identities` | Unique username → existing Auth user, optional verified contact, lifecycle state | No direct client lookup; scoped server responses only |
| `janitra_private.account_provisioning_operations` | Resumable Auth/database provisioning and request receipts | Service-only checked routines |
| `janitra_private.account_setup_grants` | Hashed one-time setup/recovery tokens and atomic claims | Service-only checked routines |
| `janitra_private.identity_attempt_windows` | Bounded login/redemption abuse counters | Service-only checked routines |
| `public.account_security_events` | Append-only provisioning/recovery history, actor/scope/reason, no secrets | Scoped Supervisor RLS; own sanitized events where appropriate |
| Activity/task checklist snapshots | Ordered checklist definition and immutable per-task version snapshot | Existing activity/task scope, never raw permission grants |
| Submission checklist snapshot | Officially submitted item results | Written only with existing online PIN submission transaction |

Use explicit foreign keys, uniqueness constraints, indexes on username, user, grant expiry and scoped event queries. Enable RLS on public additions; private additions have no anonymous/authenticated table grants and repeat authorization in narrowly granted server routines. New checklist data must not rewrite historical submissions. Existing audit/task/PIN event rows remain immutable.

If a longer independent cache lease is selected, add a private device/cache-grant ledger and permission epoch; otherwise retain the bounded current-session proof model. It does not introduce a third application role.

## 3. Offline data and access policy

### Proposed conservative initial policy

Cache access is Personnel-only, device-bound, user-bound and limited to the earlier of the restored session expiry or eight hours after the last successful online authorization/synchronization. Cold reopening needs the matching encrypted proof and unexpired session. An expired, missing, changed-user or known-revoked session cannot unlock the cache. Clock rollback or corrupt proof/storage fails closed. Cache access never implies current server authorization.

This preserves current fail-closed session behavior, but a short project JWT lifetime can shorten the offline window. A separate eight-hour cache lease with platform device unlock is an alternative awaiting the user's policy preference. That alternative needs a server-issued signed lease, device binding, revocation epoch, expiry/clock checks and local unlock validation; expired online tokens still cannot authorize server operations. Do not silently extend offline access by editing a local expiry timestamp.

A disconnected device cannot learn about a new backend revocation instantly. Bound the exposure by the explicit cache policy and expire it automatically. As soon as a trusted online response confirms expiry/suspension/role loss, discard the grant, close protected routes, erase decrypted state, quarantine incompatible drafts and disable cache access. Reconnect must validate the current account and roles before revealing new data or syncing.

### Cache and drafts

Extend the existing encrypted SQLite store instead of adding another database. Store only the active user's assigned tasks, schedule/shift/break information, relevant workplace names/locations, task checklist snapshots, schema/version metadata, last successful synchronization time and draft records. No team directory, other people's tasks, credentials, raw tokens or PINs are cached as task content. Keep the existing authenticated owner/bucket encryption and keys in platform secure storage. Add a versioned local migration with old-draft compatibility tests.

A draft records task ID, source task/version/checklist version, local revision, remarks, per-item checkbox values, last edit time and request UUID. Labels remain Saved on this device / Pending sync / Conflict, never Submitted or Approved. Changing the task base version or draft content creates a new request binding; retrying identical content preserves its UUID. Checklist editing changes only local drafts.

Display Offline, Checking connection, Online verified, or Sync failed according to actual requests/authorization, not merely Wi-Fi availability. Show last successful sync and pending/conflict counts. A connectivity plugin can trigger checks if needed, but cannot certify Internet access or permission. Use lifecycle/retry/sync coordination first, and add a pinned plugin only if the current architecture lacks a reliable reconnect trigger.

### Reconnect and official actions

One coordinator per account serializes sync and coalesces lifecycle/reconnect requests. Capture account/device/session epoch; stale callbacks cannot update a new account's cache or resurrect revoked state. Cache snapshots commit transactionally only after a complete authorized download. A failed sync retains the last complete snapshot and dirty drafts.

After fresh online session/role verification, fetch the task and compare owner, agency/site, assignment, task version, checklist snapshot, status and server deadline. Local draft synchronization updates/reconciles the on-device cache; it does not submit work automatically. Unchanged drafts remain pending for explicit online review and Employee PIN confirmation. Changed/cancelled/locked/expired tasks create a visible conflict or unavailable state, retaining local evidence rather than silently overwriting it. Use existing server receipts/version checks/deadline enforcement for the final submission, including checklist results in that same protected transaction.

No offline PIN verification, official submission, Supervisor approval, role/site/agency change or account recovery. Previously entered PINs are cleared on background, failed attempts and connectivity/security invalidation. Reconnect never replays a stored PIN or permanent password.

### Sign-out and device sharing

Explicit sign-out invalidates cache proof/leases, closes stores and clears decrypted state. Remove downloaded workplace/task snapshots; retain unsent encrypted drafts only in a sealed, inaccessible recovery state so existing work is not silently lost. Only the same user after fresh online authentication may recover them. Another user or an offline reopen after sign-out cannot read them. Offer an explicit clear-device-data operation that destroys the relevant encryption key. Tests must cover logout racing with cache writes, switching accounts, key corruption and failed deletion; a cleanup failure never restores authorization.

## 4. Connectivity versus revocation

Replace the generic authorization catch with explicit outcomes: verified, transient verification unavailable, confirmed session ended, confirmed suspension/role loss, setup required, MFA required, malformed/inconsistent response.

- A transport timeout/offline/5xx/`verification_unavailable` is not proof that the account is revoked. Preserve the last verified screen/tab/navigation as a stale/read-only context while its bounded policy allows it, show a reconnect banner, and fail closed for every protected operation. Personnel local draft editing remains available only through the authorized cache path.
- Confirmed 401/session loss or an authenticated backend response declaring suspension/role loss immediately invalidates access. A random transport exception or an empty/partial/malformed read is not enough to label a person suspended; those stay blocked pending successful verification.
- Cold start with no verified cache/access proof shows a full-screen state. A changed identity, expired session, setup/MFA requirement or unsafe response never inherits the old workspace's authority.
- Centralize operation gating so direct table writes in workplace/name editors and Edge commands are both blocked during unverified connectivity. Preserve server RLS; an enabled-looking button must not be the only safeguard.
- Carry user/token/version through every check, keep existing 300ms resume debounce and single in-flight validation, and guard after awaits. Clear sensitive dialogs without unnecessarily destroying safe navigation.

## 5. Independently testable milestones

| Milestone | Deliverable | Required evidence | Remote action |
| --- | --- | --- | --- |
| M0 | Finish premium UI validation | Clean analysis, updated reviewed screenshots, complete Flutter tests, local APK | None |
| M1 | Explicit authorization outcomes and safe stale context | Offline/timeout/5xx versus revocation, protected-operation blocking, route/tab retention, expiry/MFA/account-switch/race tests | None if existing RPC contracts suffice |
| M2 | Versioned personal cache, connectivity/sync UI, offline reopening | SQLite upgrade, encryption/tamper checks, incomplete-download recovery, expiry/clock/logout/shared-device tests | Approval only if independent lease needs server support |
| M3 | Username identity/provisioning/setup/recovery in local Supabase | SQL grants/RLS/concurrency, real Auth integration, generic failures/rate limits, secret redaction, inactive-then-active setup | Deploy additive migration/functions only after approval |
| M4 | Checklist snapshots and reconnect conflicts | Old task/draft compatibility, assignment revocation, exact deadline, stable receipts, interrupted submission and concurrent review tests | Approval before schema/functions deployment |
| M5 | Deployment and consenting phone acceptance | Reviewed deployment checklist, existing-account regression, both roles, offline reopen/reconnect, recovery and sharing | Explicit approval; no automatic account conversion |

Before every remote step, present the exact migrations/function names, secrets configuration, rollout/rollback limits and tests. Apply only approved additive changes. Never modify production users to make a test pass, reinvite/reset the first Supervisor, rotate the PIN pepper, or seed demonstration records.

## Reference checks and unresolved deployment prerequisites

- Supabase's [password Auth documentation](https://supabase.com/docs/guides/auth/passwords) provides email/phone password identities; the username mapping above is application-owned.
- [Auth Admin createUser](https://supabase.com/docs/reference/javascript/auth-admin-createuser) is server-only. Privileged keys remain off the Flutter client.
- The current [changelog](https://supabase.com/changelog) and [observability guidance](https://supabase.com/docs/guides/observability) were reviewed; no SDK migration is needed for this proposal.
- Resolve the cache-window preference, verify trusted login ingress/rate-limit identity, review password/recovery delivery policy, and prove activation/recovery against a local Auth server before a production deployment request. These are implementation prerequisites, not claims that the new features already work.
