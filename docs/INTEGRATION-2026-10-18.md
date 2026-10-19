# JANITRA build 9 integration

Date: October 18, 2026 (Asia/Manila). Development build: `1.0.0+9`.

## Verified feature workspace

The working source was recovered from `/home/zero/Janitra-Backups/janitra-features-20261014` after the original temporary folder disappeared. Development and tests ran in `/tmp/janitra-features-20261014`; the older backup is preserved.

- Username/password Personnel sign-in, optional contact email, Supervisor provisioning, mandatory personal password setup, expiring one-time setup/recovery codes and visible account state.
- Existing email sign-in, assignments, audit history, two roles, PIN confirmation and separate final approval remain supported.
- Routine resume retains the workspace, tab, dialogs and protected navigation. Temporary connectivity failures preserve context and block online operations. Confirmed access loss closes protected routes and seals downloaded data.
- Background verification is serialized and debounced. Stale token responses cannot replace a newer verified workspace. Failed foreground verification retries every 30 seconds while the app remains foregrounded.
- Encrypted personal task, schedule, shift and workplace snapshots, remarks/checklist draft autosave, last-sync/pending/conflict state and explicit conflict review. Reconnection refreshes the authorized snapshot and reconciles drafts; it never submits work or replays a PIN.
- Offline reopening requires the same restored unexpired session and encrypted proof, bounded by the earlier of session expiry and eight hours since verification. Clock rollback, corrupt storage, sign-out and confirmed revocation deny access. A disconnected device cannot learn about new remote revocation until reconnecting or its local limit expires.
- Supervisors add/edit/remove/reorder checklist items by editing the ordered lines in the activity form. Stable item IDs survive reordering. Activities, assigned tasks and official submissions retain their checklist versions; submitted history is immutable.

## Backend files awaiting deployment approval

- `supabase/migrations/20261013165018_personnel_usernames.sql`
- `supabase/migrations/20261013165019_task_checklists.sql`
- New public login/setup function: `personnel-auth` (`verify_jwt = false`, with no management capability).
- Updated authenticated functions: `manage-users`, `workflow`. Existing JWT settings remain enabled for these and `manage-pins`.
- New server-only `JANITRA_IDENTITY_PEPPER`, independent of the existing PIN pepper. No secret is generated, changed or deployed by this integration. The endpoint fails closed until configured.

The private identity record doubles as the durable provisioning reservation; no separate provisioning table is needed. Supabase Auth remains the password authority. Internal random Auth aliases are hidden in account/team presentation. Optional contact email is informational and is not an unverified recovery channel.

Recovery disables protected access immediately. A private revoked-session ledger prevents older Auth sessions, including sessions created while recovery was pending, from regaining RLS/workflow access after password completion. Role and issuer authority are rechecked and locked for account changes. Codes are claimed atomically and only their HMAC digests persist. Code screens suppress capture on Android and clear the code on background; passwords, codes and task PINs are separate.

If Auth explicitly rejects a new password with validation status 422, the claim is marked failed and audited, so the Supervisor can issue a replacement. If Auth may have changed the password but the response or subsequent database finalization is lost, access remains closed and replacement credential changes are blocked. That exceptional case needs trusted operator reconciliation of the Auth result and claimed grant before another code is issued. Do not manually reactivate the profile or revoke the claimed grant to bypass this safeguard.

## Verification

- Feature workspace Flutter tests: **91 passed**, including 17 lifecycle tests, Personnel account flows, checklist editing, offline expiry/clock rollback, encrypted draft preservation, both roles, narrow/large text, report exports and existing workflows.
- Edge Function tests: **38 passed** (manage-users 9, manage-pins 12, workflow 8, personnel-auth 9), with mocked Auth/SQL boundaries.
- Disposable PostgreSQL 17: **178 assertions passed**, plus simultaneous PIN-limit, final-review and recovery-redemption checks. Exactly one of four concurrent recovery requests claims a code. All migrations apply from the existing foundation; no production resources are accessed.
- The feature workspace Android debug APK built successfully. Existing release signing configuration is preserved; no release was published.
- Login and Team reference images were reviewed and updated for the new controls. The remaining reference screenshots are unchanged.

## Integration checkpoint

Integration into `/home/zero/Projects/janitra` **succeeded**. A complete recoverable archive was created at `/home/zero/Janitra-Backups/janitra-original-before-integration-20261018.tar.gz` before any source overwrite. Its gzip/tar integrity and 15,286 entries were verified, including application source and local configuration. The integration compared before/after SHA-256 hashes, aborted on intervening changes, copied only 55 reviewed files and verified every installed checksum. No source file was deleted. Credentials, project links, six historical migrations, prior builds and existing backups were retained.

The required checks then ran from the original directory: dependency resolution succeeded, **analysis found no issues**, **91 Flutter tests passed**, **38 Edge tests passed**, and the disposable database repeated **178 assertions and all three concurrency checks**. The original-directory **Android debug build succeeded**. `aapt` confirms package `com.example.janitra`, version `1.0.0`, build code `9`, minimum Android API 24. Its signing certificate matches the existing build 8 development APK.

Test APK: `build/app/outputs/flutter-apk/janitra-build9-integration-debug.apk`.
APK SHA-256: `1ea4cd0e7993fbf92f7ccafd3c3f05c3410b77d81a0f3ff9c83badd2e90cae7a`.

The verified feature source and test evidence are also preserved at `/home/zero/Janitra-Backups/janitra-features-verified-20261018`. The October 14 backup remains separate. These are development/test artifacts; production is unchanged.

## Remaining acceptance and rollout limits

No production database migration, Edge Function deployment, account conversion, password reset, invitation, PIN pepper change or release publication occurred. New username/checklist features cannot operate against the existing live backend until the matching approved deployment.

Real Supabase Auth end-to-end behavior and physical Android acceptance remain unverified for build 9. Verify proxy/ingress abuse controls before enabling the public endpoint, actual Auth password-policy failures, secure code handoff, lost-response reconciliation, both roles, offline cold reopen, account switching, checklist conflicts, PIN submission, final review, deadlines and report exports in an approved test environment. SQLite, platform secure-storage failure modes and Android capture protection still need physical-device testing. The isolated database image lacks pg_cron; hosted job health remains a deployment check.

Never reinvite/reset the original Supervisor or modify existing accounts as a test. Use consenting test accounts and explicitly approved backend changes. Database rollback cannot safely erase new audit/submission history; stop new use and roll forward with a reviewed migration if needed.

## Modified and added files

Paths are relative to the project root. This list includes the source recovered from the interrupted implementation and the integration's final fixes, tests and documentation.

```text
android/app/src/main/kotlin/com/example/janitra/MainActivity.kt
anti-slop/audit-008-2026-10-18.md
docs/AUTH-OFFLINE-ARCHITECTURE-PROPOSAL.md
docs/IMPLEMENTATION_STATUS.md
docs/INTEGRATION-2026-10-18.md
docs/NEXT_STEPS.md
lib/app.dart
lib/core/access_notice.dart
lib/core/access_policy.dart
lib/core/account_label.dart
lib/core/sensitive_screen.dart
lib/features/authentication/account_setup_page.dart
lib/features/authentication/login_page.dart
lib/features/authentication/mfa_page.dart
lib/features/work/checklist.dart
lib/features/work/local_work_store.dart
lib/features/work/offline_access.dart
lib/features/work/offline_work_page.dart
lib/features/work/personal_sync.dart
lib/features/work/scheduling_page.dart
lib/features/work/task_page.dart
lib/features/work/task_record.dart
lib/features/work/work_form.dart
lib/features/work/work_repository.dart
lib/features/workspace/account_code_page.dart
lib/features/workspace/function_message.dart
lib/features/workspace/people_page.dart
lib/features/workspace/username_account_dialog.dart
lib/features/workspace/workspace_page.dart
pubspec.lock
pubspec.yaml
supabase/config.toml
supabase/functions/_shared/identity_security.ts
supabase/functions/_shared/manage_identity.ts
supabase/functions/manage-users/index.ts
supabase/functions/personnel-auth/deno.json
supabase/functions/personnel-auth/deno.lock
supabase/functions/personnel-auth/index.ts
supabase/functions/personnel-auth/index_test.ts
supabase/functions/workflow/index.ts
supabase/migrations/20261013165018_personnel_usernames.sql
supabase/migrations/20261013165019_task_checklists.sql
supabase/tests/auth_fixture.sql
supabase/tests/identity_concurrency.sql
supabase/tests/new_features.sql
test/access_policy_test.dart
test/fixtures/workspace_backend.dart
test/goldens/login.png
test/goldens/team-empty.png
test/lifecycle_test.dart
test/personnel_account_test.dart
test/ui_reference_test.dart
test/widget_test.dart
test/workflows_test.dart
tool/test_database.sh
```
