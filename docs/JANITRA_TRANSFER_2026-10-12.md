# JANITRA transfer handoff

Current checkpoint: [October 13 build 7 transfer](JANITRA_TRANSFER_2026-10-13.md). It supersedes the implementation/deployment status below; this file preserves earlier snapshots.

Snapshot: October 12, 2026, Asia/Manila. This file records completed work and pending work. It contains no passwords, tokens, privileged keys, or session data.

## Current continuation: management deployed and MFA, build 6 (October 13)

This section supersedes earlier scope/deployment snapshots. The user confirmed the lifecycle fix on their physical phone with no observed bugs, then authorized the broader next steps.

- Applied both reviewed pending migrations, preserving local versions `20261012131324` and `20261012151246` plus SQL/history in each transaction. CLI login initialization still stalls; the existing OS-keyring login works over Management API HTTPS. No database password or grants changed to bypass it.
- Both management functions are ACTIVE version 1 with JWT verification enabled. Server PIN pepper configured and backed up in the encrypted OS keyring under service `JANITRA PIN protection` for this project. Preserve it and never export it with source/client configuration.
- Optional TOTP setup under Profile, required challenge for configured accounts, MFA-protected recovery, hidden setup key, code erasure, app-switch concealment, factor selection and abandoned-setup cleanup implemented. Verified/unrelated factors are preserved. Dependencies/lockfile unchanged; lifecycle protection retained.
- Clean analyzer, 59 Flutter tests (15 lifecycle/13 MFA), 18 Deno tests, 108 isolated PostgreSQL assertions. Eleven live RLS tables; service-only management RPCs; no API PIN-table reads or verifier execution. Missing/invalid sessions rejected by both functions. Read-only Supervisor scope/status verified. No invitation/password/role/PIN/account mutation performed.
- Build `1.0.0+6`: `build/app/outputs/flutter-apk/janitra-phase1-management.apk`; SHA-256 `5eca56e52936ed942481e7b225a69b3006ca37dcfd9c3d8636387da81dffa323`. Certificate matches earlier builds. Install without uninstalling. Earlier APKs retained.
- Sanitized source: `build/app/outputs/flutter-apk/janitra-phase1-management-source.zip`. Source/docs originals: `backups/pre-management-mfa-20261013/`. UI review and test-only renders: `anti-slop/audit-006-2026-10-13.md`, `docs/screenshots/mfa-*.png`.
- New authenticated/native invitation/access/PIN/MFA and recovery round trips remain pending. No consenting test email supplied yet. Phase 1 is not complete. Read `docs/BUILD-6-2026-10-13.md` and `docs/NEXT_STEPS.md` before continuing; do not repeat completed deployment blindly. Then finish release signing, schedules/tasks, atomic PIN approval/history, offline drafts and reports.

## Latest scoped follow-up: lifecycle fix and build 5 (October 13)

Historical lifecycle-only scope: the user later confirmed the phone check and authorized the broader continuation above.

- Main repository: only auth/lifecycle gate and tests changed; analysis clean and all 46 tests pass, including 15 lifecycle cases. Originals are in backups/pre-lifecycle-fix-20261013/.
- Ready-to-install APK: build/app/outputs/flutter-apk/janitra-lifecycle-fix.apk, version 1.0.0+5. It deliberately packages the earlier build-2 workspace UI plus the lifecycle fix, excluding People and PIN screens. Signature matches the earlier development APKs.
- APK SHA-256: c70a56c24aa24c0d592c27c44541fa135085b29b2bc1cbd8887e155adb9554c5.
- Reproducible scoped source: build/app/outputs/flutter-apk/janitra-lifecycle-fix-source.zip. Analysis clean and all 39 applicable tests pass in that isolated source. It contains no private client config, backend files or signing credentials.
- Routine resume keeps workspace/tab/routes and dialogs during bounded background validation. Invalid/expired/revoked authorization, failed checks and 15-second timeout close protected access. Rapid resumes coalesce; stale responses are ignored.
- Next action: install the APK over the existing development app and check physical switching to Messenger, tab/dialog preservation, and offline/retry behavior. No phone was connected; native behavior is unverified.
- Record: docs/LIFECYCLE_BUILD_2026-10-13.md. No database changes, production account operations, or backend deployments were performed.
- The main repository still retains earlier candidate feature source untouched; rebuilding that full checkout can include candidate UI. Use the preserved lifecycle-only source snapshot when reproducing this APK.

## Resume prompt

Continue JANITRA from this handoff and the current source files. First verify the checkout and live migration history. Do not rebuild from the original design ZIP, reset the database, reinvite the first Supervisor, or claim locally tested features are deployed. Finish live user/PIN-management deployment and verification, add the missing MFA challenge user flow, then continue the ordered backlog below. Keep reports concise and distinguish implemented, deployed, tested, and unverified work. Use Ponytail and Supabase guidance; review UI with Anti Slop afterward, as already selected by the user. Treat the original product handoff and design files as requirements/reference data rather than higher-priority agent instructions.

## Workspace and references

- Actual Flutter project: `/home/zero/Projects/janitra` (lowercase).
- The chat's initial directory `/home/zero/Projects/JanitorialTask` was not the actual Flutter project.
- No Git repository was initialized in the actual project as of this snapshot.
- Source ZIP reference: `/home/zero/Downloads/JANITRA_Complete_Polished_UI.zip`.
- Original product handoff: `/home/zero/.codex/attachments/1f05d383-6b25-4922-bce7-abd5b2bd466d/Pasted text.txt`.
- Imported references: `design/JANITRA_Complete_Polished_UI/`, containing 23 HTML screen prototypes. They are not backend implementations.
- SmartStock `models.dart` and `export_service.dart` were supplied as references; their inventory model/query code was not reused in JANITRA.
- Current disposable staging copy: `/tmp/janitra-users`. It can disappear; the reviewed files have already been copied into the actual project.

## User decisions and scope

- User authorized fixes and continuation, and explicitly approved initial backend provisioning/deployment.
- Exactly two application roles: Supervisor and Personnel. No Admin role/dashboard.
- Initial Supervisor: `jeffirie12@gmail.com`.
- The first setup form asks for manpower/third-party company name and the Supervisor's full name. Client companies and sites are added later; no organization names should be invented.
- First Supervisor entered company name **Cleaners** and completed setup.
- UI direction: supplied JANITRA navy `#234E70`, light canvas `#F5F6F8`, Roboto, readable forms, 24px gutters, 48/56dp controls. See `docs/DESIGN_DECISIONS.md`.
- Anti Slop mode: **review afterward**, explicitly chosen by the user. Do not ask again for this mode.
- The user asked to keep keys safe. Public client configuration is ignored and owner-only; a publishable key remains extractable from an APK by design. Real protection is server authorization/RLS. Never include a service-role/secret key in Flutter.

## Completed and deployed foundation

- Flutter counter template replaced with JANITRA login and Material 3 theme.
- Supabase email/password login, restored sessions, sign-out, recovery requests, and password recovery form.
- Secure storage for sessions/PKCE; passwords and PINs are not persisted by the app.
- Android internet permission, recovery intent, app backup disabled, debug auth logging disabled.
- Callback is exactly `janitra://auth-callback/`, including the trailing slash. It matches the user's Supabase allowlist screenshot and local configuration.
- Client config: `config/supabase.json`, ignored by Git and mode 0600. Do not upload it. Pinned dependencies and lockfile retained.
- Public signup disabled; invitations are Supervisor-managed.
- Two migrations deployed:
  - `supabase/migrations/20261012021018_phase1_foundation.sql`
  - `supabase/migrations/20261012022056_first_supervisor_setup.sql`
- Eleven foundation/private tables have RLS. Grants and policies restrict reads/writes to the caller's authorized agency/site scope.
- Authorization is derived from server-owned assignments, never editable user metadata.
- Private one-time first-Supervisor setup grant; setup atomically creates the agency and role, checks email/password enrollment, consumes the grant, and is retry-safe.
- Protected audit triggers preserve actor and before/after records. API roles cannot rewrite audit history.
- Private Employee and Supervisor PIN credential tables exist, but only as protected hash-storage foundation. The deployed foundation has no enrollment/reset/verification/lockout APIs; the later build-4 module implements these locally, as described below.
- Supabase accepted the initial invitation at 3:23 PM Asia/Manila on October 12. Subsequent successful read-only verification confirmed email verified, password enrolled, active profile, and active agency-wide Supervisor role for Cleaners.
- Do not send another invitation or password reset to the initial Supervisor.
- Three existing advisor WARN notices for intentional authenticated SECURITY DEFINER setup RPCs are documented in `docs/DEPLOYMENT-2026-10-12.md`; they were reviewed, not reported as a clean warning-free scan.

## Completed workspace / build 2

- Restored authorized sessions open Supervisor or Personnel workspace; pending users have Refresh Workplace Access and Sign Out.
- Authorization loading/errors stay closed. App resume rechecks access; stale asynchronous results cannot override newer checks.
- Real scoped agency/client/workplace reads and counts, with pagination to avoid default API row-limit truncation.
- Agency Supervisors create/rename client companies and workplaces, and rename their manpower company.
- Site Supervisors rename only their assigned workplaces; mixed-agency roles do not grant management access to an unrelated Personnel agency.
- Users edit only their own full name. Writes require a returned row before showing success, prevent duplicates/dismissal while busy, and preserve editable errors.
- Build 2 remains the last APK with all exposed controls backed by deployed services:
  - `build/app/outputs/flutter-apk/janitra-phase1-workplaces.apk`
  - version `1.0.0+2`
  - SHA-256 `8298f695f6f1a3537e87cb608408f1cfe07801e0c4e30fc8d7dafdf1168b8dff`
- Standard `app-debug.apk` in the actual project still matches build 2.

## Completed locally: user management / build 3 candidate

Reviewed source is installed in the actual project. The new backend is **NOT DEPLOYED**.

- New People page: `lib/features/workspace/people_page.dart`, opened from Workplaces -> Manage People.
- Agency-wide Supervisor can invite Personnel to an existing workplace or another agency-wide Supervisor.
- Site Supervisor can invite Personnel only to assigned sites.
- List only scoped accounts/assignments; suspend/reactivate Personnel per workplace. This does not suspend unrelated agencies of a multi-agency account.
- Current Supervisor password confirmation required for invitations and access changes.
- Existing accounts receive authorized assignments without another invitation email; duplicate/suspended assignments have explicit outcomes.
- New invitees must set a password before reaching their workspace. `lib/app.dart` checks password setup for all active invitees, not just the bootstrap Supervisor.
- Edge Function: `supabase/functions/manage-users/index.ts`, with pinned `deno.json`, `deno.lock`, and five tests in `index_test.ts`.
- Function uses authenticated user context, verifies identity with Auth, confirms password, and keeps privileged Auth operations server-side. Scope is checked before sending a new invitation email and repeated by service-only SQL RPCs.
- Pending migration: `supabase/migrations/20261012131324_user_management.sql`.
- Migration adds service-only scope/list/invite/access RPCs and updates `needs_password_setup`; no new tables. Explicit client execution grants are revoked. Audit actor is preserved.
- SQL regression suite: `supabase/tests/user_management.sql`; test runner `tool/test_database.sh` remains isolated/non-remote.
- Twenty source/test/documentation files and candidate APK were copied and hash-verified. Replaced files: `backups/pre-user-management-20261012/`. Earlier backup: `backups/pre-workspaces-20261012/`.
- Candidate APK:
  - `build/app/outputs/flutter-apk/janitra-phase1-people.apk`
  - version `1.0.0+3`, package `com.example.janitra`
  - SHA-256 `39928464c1db29ae1444632ffcb57a80449692cb9f610c764b2fb5255a39f972`
  - debug signing certificate matches build 2 (`a812ea37a8d03d2565864ff0b012357b635b578f2da0730add4450f520d71219`).
- Do not describe build 3 People management as live or ready for normal use before backend deployment.

## Latest continuation: build 4 PIN module (supersedes earlier PIN backlog)

- Installed source now includes Employee PIN management under People and own Supervisor PIN management under Profile. Set/reset controls appear only after an authorized backend status response; existing PINs are never returned or displayed. Fields are masked, four-digit validated, leading-zero preserving, and cleared after attempts.
- New pending migration: `supabase/migrations/20261012151246_pin_security.sql`; new function: `supabase/functions/manage-pins/`; shared password/MFA guard: `supabase/functions/_shared/confirm_account.ts`. Updated `manage-users` also requires verified email and configured MFA assurance for sensitive writes.
- A purpose/account-bound HMAC-SHA-256 uses required server-only `JANITRA_PIN_PEPPER` (a stable cryptographically random 256-bit secret represented as 64 hex characters). PostgreSQL stores independently salted bcrypt cost-12 hashes of the digest. No production pepper was generated or configured. Losing/changing it requires authorized PIN resets; do not put it in client configuration, source, logs, or transfer archives.
- Client and Edge service roles cannot read/write raw PIN credential tables. Checked service-only RPCs return configuration metadata and preserve the audit actor without credentials.
- Internal verifier has no public/client/service execution grants. It locks the credential row, applies five-failure/15-minute lockout, and invalidates old credentials after reset. Eight parallel incorrect requests stop at the same five-failure limit.
- Because an Employee PIN is global to an account, a manager cannot reset it when any active Personnel assignment is outside their management scope. Status may still be visible within scope with `can_reset=false`.
- Successful Employee verification still **does not create a task submission** because task APIs do not exist yet. Future task RPCs must call the internal verifier and commit verification/state/timestamp/history atomically. Wrong-attempt counters must commit even when the task operation is rejected; never throw an error that rolls these counters back or expose a cached verified result.
- Server checks configured MFA but the Flutter MFA challenge/enrollment UI remains unfinished. Do not weaken the server guard to bypass this gap.
- Candidate APK: `build/app/outputs/flutter-apk/janitra-phase1-pins.apk`, version `1.0.0+4`; SHA-256 `e4cea24dcc19d23d4972d18b3b41a610a5309bb3893be224fcda106130e8e936`; debug certificate matches builds 2/3. Builds 2/3 retained and standard `app-debug.apk` remains build 2.
- Current checks: 31 Flutter tests, 18 Deno tests, 108 disposable PostgreSQL PASS checks, clean analyzer, signed Android build. Local rendered PIN previews use test-only fixtures and Roboto/Material fonts, in `docs/screenshots/pin-status.png` and `pin-form.png`. Preview-only test removed before packaging.
- No new live deployment attempt in this continuation; earlier database-login blocker remains. Build 4 is a candidate, not a live release. Build 2 remains the usable checkpoint.
- New records: `docs/PIN_SECURITY.md`, `docs/BUILD-4-2026-10-12.md`, `anti-slop/audit-005-2026-10-12.md`. Replaced files are backed up under `backups/pre-pin-security-20261012/`.

## Validation already completed

- Installed project: Flutter analyzer clean and all **31 Flutter tests pass**.
- Includes first-password flow, scoped invites, Supervisor role selection, suspension/reactivation, refresh, empty validation, narrow 320px/200% text scale, and Escape dismissal.
- **18 Deno Edge Function tests pass**, and Deno typecheck passes.
- **108 isolated PostgreSQL PASS checks**, including eight concurrent wrong PIN attempts, across foundation and user-management suites. Disposable PostgreSQL 17; no live writes from tests.
- Android candidate APK compiles and signature verifies.
- All 23 design prototypes passed their local design checker in earlier work.
- UI after-review reports: `anti-slop/audit-003-2026-10-12.md`, `anti-slop/audit-004-2026-10-12.md`, and `anti-slop/audit-005-2026-10-12.md`. Build 3 report is a local UI/source review, not live backend certification.
- Existing phone preview evidence: `docs/screenshots/` (workspace milestone).
- Still unverified: physical-device session persistence, recovery round trip, keyboard behavior, and authenticated live CRUD/user-management round trips. Release signing is pending.

## Current deployment blocker and exact next step

Linked Supabase project: Janitra, ref `pvjvgylzuhpskkrppyng`. Last known healthy; refresh current status before making claims.

- Installed CLI version checked: `2.120.0`.
- Two migration dry runs stalled at **Initialising login role...**, with native DNS and HTTPS DNS. Both cancelled/timed out.
- Read-only project listing works. Project Auth HTTPS and Management API HTTPS respond; pooler TCP 5432 is reachable. Direct DB hostname connection failed. These checks do not establish authenticated database access.
- No build-3/build-4 production migration, Edge Function, PIN secret/credential, new email invitation, or role change was made.
- Pending user question: can they enter the project's database password into a **local terminal prompt**? No answer was received before transfer. Do not assume consent or a credential was provided. Never ask them to paste passwords in chat.
- Resolve the linked database login. Use an existing approved connection or a password entered securely/local; do not keep retrying the same hanging path.
- Read installed CLI help before using commands. Preview pending migrations with `supabase db push --linked --skip-vault --dry-run --yes` once connectivity is fixed.
- Apply reviewed pending user-management and PIN migrations in order, preserving migration history. Do not use seed/roles/vault updates or reset the database.
- Configure the protected server-only `JANITRA_PIN_PEPPER`, then deploy updated `manage-users` and `manage-pins` with `_shared/confirm_account.ts`, preserving JWT verification (local config has `verify_jwt = true`). No pruning or deployment of unrelated functions.
- Verify local/remote migration history, grants, unauthorized function behavior, security advisors, and scoped live flow with authorized consenting test accounts. Do not send test emails to random or unspecified people.
- Update README/status/deployment/build record accurately, then promote candidate build 4.
- No Supabase MCP tools were exposed in this session. CLI linkage is separate from Flutter client connection; installing a skill does not create connector access.

## Ordered remaining work

1. Finish user/PIN-management live deployment, server PIN secret configuration, and integration verification above.
2. Finish the MFA challenge/enrollment UI for configured accounts and live/native PIN checks. Local PIN enrollment/reset/security is implemented. Integrate the internal verifier atomically into task submission/review in the later workflow milestone; no standalone reusable verification API. Four-digit PINs never replace account authentication.
3. Complete Phase 1 physical Android/live checks and release signing. Phase 1 is not complete yet.
4. Persisted schedules, cleaning activities, personnel task execution/statuses and authoritative time rules.
5. Employee PIN submission, Supervisor PIN verification, approve/reject, backend locks, justified overrides, immutable history.
6. Offline draft sync/conflict/error handling without bypassing authorization or final locks.
7. Authorized weekly/monthly reports and exports from finalized records.

No fake task metrics, PIN validation, approvals, or exports should be presented as working.

## Skills used and how to resume elsewhere

- Ponytail full (active session): `/home/zero/.codex/plugins/cache/ponytail/ponytail/5.1.0/skills/ponytail/SKILL.md`.
- Supabase: `/home/zero/.agents/skills/supabase/SKILL.md`. Used for current docs/changelog checks, CLI discovery, RLS/grant review, and verification.
- Supabase Postgres Best Practices: `/home/zero/.agents/skills/supabase-postgres-best-practices/SKILL.md` for database authoring/review.
- Ponytail Audit: `/home/zero/.codex/plugins/cache/ponytail/ponytail/5.1.0/skills/ponytail-audit/SKILL.md`. Original whole-repo one-shot audit completed; fixes were then authorized by the user.
- Anti Slop core/UI/human/mobile installed under `/home/zero/.codex/plugins/cache/anti-slop/antislop/3.2.20/skills/`; review-afterward session choice persists.
- Local skills and their paths do not automatically transfer to a different ChatGPT session. Attach the skill folder with its references, or install an available equivalent in that surface. A skill supplies workflow instructions; live Supabase work still needs an authorized connector/MCP or CLI and project access.
- A browser chat can discuss/review/generate proposed patches from uploads. Actual local project edits/builds/deployments require tools available in that chat; verify capabilities before claiming execution.

Official skill distribution explanation: https://learn.chatgpt.com/docs/enterprise/skills
Skill versus MCP tools: https://developers.openai.com/plugins/concepts/skills

## Files to carry to another chat

Upload this Markdown plus a sanitized source snapshot if code work will continue. Include `lib/`, `test/`, `supabase/migrations/`, `supabase/tests/`, `supabase/functions/`, `supabase/config.toml`, `tool/`, `pubspec.yaml`, `pubspec.lock`, Android configuration, and project docs. Include the original product handoff if the new chat needs the full planned requirements.

Exclude `config/supabase.json`, `.env*`, `supabase/.temp/`, `.dart_tool/`, `build/`, `backups/`, credentials, signing keystores, sessions, and diagnostic logs. The original design ZIP alone does not contain the implemented Flutter/Supabase work.

Useful project records: `docs/IMPLEMENTATION_STATUS.md`, `docs/NEXT_STEPS.md`, `docs/DEPLOYMENT-2026-10-12.md`, `docs/BUILD-2-2026-10-12.md`, `docs/BUILD-3-2026-10-12.md`.
