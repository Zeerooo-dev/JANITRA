# JANITRA build 9 backend deployment

Deployed October 18, 2026, approximately 2:14–2:16 PM Asia/Manila, to the existing Janitra project `pvjvgylzuhpskkrppyng`. The user explicitly approved items 1 and 2 of the remaining-work list, then separately approved configuring the required identity secret.

## Applied changes

- `20261013165018_personnel_usernames.sql`
- `20261013165019_task_checklists.sql`
- `manage-users`: ACTIVE, version 5, JWT verification enabled.
- `workflow`: ACTIVE, version 3, JWT verification enabled.
- `personnel-auth`: ACTIVE, version 1, JWT verification disabled intentionally for public login/setup; management capability remains on authenticated functions and service-only SQL routines.
- `JANITRA_IDENTITY_PEPPER`: generated securely, configured server-side, SHA-256 digest verified against the secret-list API, and backed up in the encrypted OS keyring under service `JANITRA identity protection`, project `pvjvgylzuhpskkrppyng`. Never printed or written to application source, client configuration, a plaintext secret file or the source ZIP.

The existing PIN pepper was retained. `manage-pins` source/bundle was not redeployed; its bundle checksum and updated timestamp remain unchanged. Its reported version advanced from 2 to 3 when the project environment changed. Current JWT verification remains enabled.

The CLI dry run selected exactly the two pending migrations. The approved push applied them in order without seeds, custom-role changes or Vault updates. A subsequent dry run reports the remote database is up to date. All six historical migration versions remain, with the two new versions bringing the total to eight. CLI database query/push now completed successfully; the historical login-initialization stall did not block this deployment.

## Live verification

- Read-only SQL assertions passed for private identity-table RLS and client denial, public history-table RLS and immutable client grants, service-only management/workflow RPC grants, denied workflow-wrapper bypass, the security-invoker task view, invalid-session denial and the active minute deadline job.
- No public application table has RLS disabled.
- Existing row counts stayed at two profiles, three role assignments, zero tasks and zero submissions. No account was created, invited, migrated, suspended or reset during verification.
- The latest observed deadline-job run succeeded after the migration (2026-10-18 06:14 UTC).
- Live unauthenticated POSTs to `manage-users`, `workflow` and `manage-pins` returned HTTP 401.
- Live `personnel-auth` GET returned HTTP 405; malformed action returned HTTP 400; a nonexistent username with an invalid password returned the generic HTTP 401 response. All three public-endpoint responses used `Cache-Control: no-store`. The nonexistent-login probe only exercised rate-limit counters and an unsuccessful Auth request.
- All four functions report ACTIVE with the intended JWT settings.
- Security advisors show the same four pre-existing warnings: the three intentionally caller-bound company/password-setup SECURITY DEFINER helpers, and disabled leaked-password protection. No new warning appeared. Project Auth policies and subscription settings were not changed.

The previously completed 91 Flutter tests, 38 Edge tests, 178 isolated PostgreSQL assertions and three concurrency checks remain the build 9 automated baseline. They were not rerun for this deployment because application/function source did not change. Live deployment checks above ran against the actual project.

## Physical testing next

Use `build/app/outputs/flutter-apk/janitra-build9-integration-debug.apk` (version `1.0.0+9`). Install over the existing app to preserve app storage.

1. Use the existing Supervisor login. In Team, create a consenting Personnel test account with username and an authorized workplace, privately hand over the one-time setup code, complete password setup, then sign in by username.
2. Check agency assignment, suspension/reactivation, session expiration and recovery with consenting test accounts. Preserve the original Supervisor.
3. Add an activity checklist, schedule a task, edit a draft offline and reconnect. Confirm official submission still requires online authorization and the Personnel PIN; Supervisor PIN confirmation and final approval remain separate actions.
4. Test app switching, selected tabs/navigation, offline reopening within the cached session limit, account switching, conflicts and reports on a physical phone.

Real successful Personnel provisioning/login/recovery, physical secure-storage behavior and full task acceptance have not been exercised in this rollout. Broader ingress abuse testing remains a public-distribution check. Ambiguous interrupted password recovery still requires trusted operator reconciliation; it must not be bypassed by manually activating the profile. No Android release was published.

This deployment supersedes the pending-backend status in `INTEGRATION-2026-10-18.md` and the original build 9 source ZIP. The code in that ZIP still matches the deployed implementation; it contains no production identity secret.
