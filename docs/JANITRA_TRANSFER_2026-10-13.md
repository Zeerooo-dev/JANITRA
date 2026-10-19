# JANITRA transfer: complete workflow test build

Latest UI checkpoint: build 8 aligns the native app with `JANITRA_Complete_Polished_UI.zip`. See [UI notes](BUILD-8-UI-2026-10-13.md). Install `janitra-ui-build8.apk` for current testing. The build 7 backend/workflow checkpoint below remains applicable; build 8 changes no backend components.

Updated October 13, 2026, Asia/Manila. This is the current checkpoint and supersedes previous pending-implementation/deployment snapshots.

## Current state

- Actual project: `/home/zero/Projects/janitra`; the nominal chat cwd `/home/zero/Projects/JanitorialTask` does not exist. No Git repository is initialized.
- Version `1.0.0+7`, Flutter `3.47.5`, Dart `3.13.4`. Build 5 lifecycle was already confirmed on the user's physical phone. Build 7 preserves it.
- The user requested completion of remaining workflows together, followed by phone testing. Their final agency preference: only an authorized Supervisor edits Personnel agency assignment. Do not reopen the abandoned employee self-edit proposal.
- Existing first Supervisor and PIN pepper were preserved. No real invitation or account/password/PIN reset occurred during this checkpoint.
- Supabase project ref `pvjvgylzuhpskkrppyng`; public frontend configuration remains ignored, mode 600, outside Dart source. No privileged key belongs in the APK/source archive.

## Implemented

Supervisor People/invitations/suspension/reactivation, global-purpose PIN enrollment/reset, configured TOTP MFA and recovery from build 6 remain. Added agency creation and authorized transfers; source roles are retired, past records preserved and future old work cancelled. Both agencies require agency-wide Supervisor authority. Source/destination names are captured in history.

Operational tables and service-only workflow now cover activities, weekdays, split/overnight shifts and breaks, one-time/repeating cleaning, dated exceptions/substitution, configurable deadlines, generated task snapshots, submissions, Employee confirmation events, Supervisor verification, separate final approval/rejection, lock overrides, task history, in-app notifications, audit and report snapshots. Saturday means following Monday noon Manila; exact cutoff is enforced in every action and a scheduled job. Submitted history is preserved during future schedule edits.

Client protected requests propagate confirmed session/role loss to the existing fail-closed workspace gate. RLS validates current `auth.sessions` as well as active database roles. Server task status comes from a `security_invoker` view rather than phone time. Receipt retries recheck current authority and bind actor/request/action/payload. PIN attempts commit on rejected responses; raw PINs/passwords are never stored in task history or offline drafts.

Personnel-only offline drafts/task cache/schedules use AES-GCM encrypted SQLite, per-account Android secure-storage keys and a sealed authorization proof bound to the exact unexpired token fingerprint. No offline authoritative submission, approval or organization access is offered. Drafts survive logout encrypted, while their access proof is removed. Reconnection requires live revalidation and PIN submission.

Weekly/monthly/custom PDF and XLSX use authorized server snapshots with date/site/Personnel/Supervisor/status filters and explicit source limits. PDF is landscape A4, repeated heading/footer and long-note annexes; XLSX has five styled/frozen tabs, wrapped text, and text-safe remarks. Bundled Roboto fonts include their license.

## Deployment and validation

Applied and recorded migrations in order, without reset:

1. `20261012021018_phase1_foundation`
2. `20261012022056_first_supervisor_setup`
3. `20261012131324_user_management`
4. `20261012151246_pin_security`
5. `20261012191936_agency_transfers`
6. `20261012191938_operational_workflows`

Functions: `manage-users` v3, `manage-pins` v2, `workflow` v1, all ACTIVE with `verify_jwt=true` and pinned `@supabase/server@1.9.1`. `janitra-workflow-minute` is active every minute; recent live executions succeeded. Generation extends the horizon daily and on affected agency configuration/access changes, avoiding a full regeneration every minute.

Live verification: all public tables have RLS; view uses invoker security; anonymous/client workflow execution and direct client/service task UPDATE are denied; guarded service workflow execution allowed. Anonymous REST/RPC/functions returned 401. Existing Supervisor active scope/session checks passed. No task fixtures were seeded in production.

Automated results: clean Flutter analysis; 71 Flutter tests; 29 Deno tests; 150 isolated PostgreSQL PASS assertions including simultaneous conflicting final approvals, exact cutoff, concurrent PIN locking, revocation, receipt replay and transfers. PDF output was rendered; XLSX independently reopened with five valid A2-frozen tabs, navy headers and text-only formula-like remarks. See the build note for final package checksums and test artifacts.

Supabase advisors: no ERROR; four WARN (three intentional existing authenticated setup functions and leaked-password protection), five INFO for intentionally inaccessible private tables with RLS/no client policies. Leaked-password protection/production signing remain deployment-hardening decisions, not silently claimed resolved.

## Continue safely

Use [PHONE_TEST_GUIDE.md](PHONE_TEST_GUIDE.md) for the complete test sequence. No Android device was connected to this run. New live authenticated invitation/task/recovery/MFA/native storage/sharing round trips remain the user's phone acceptance checks. Notifications are in-app only. The APK is an optimized test build signed with the existing development certificate to preserve updates, not a Store-ready release.

Do not modify applied migration files. Any backend correction needs a new additive migration and isolated tests. Preserve the PIN pepper and the existing Supervisor; never regenerate/reset them. CLI database login initialization still stalls. The current Management API HTTPS helper uses the existing OS-keyring CLI login in memory; it is not part of source archives and never prints credentials. Local database tests use an isolated disposable PostgreSQL container, not production.

Skills remain Ponytail full and Supabase; Postgres rules guide schema/RLS. Anti Slop mode is Review afterward, already chosen by the user. Keep Flutter + Supabase, real values, no self-assigned agency/role permissions, and no fixture invitations/data in production. The supplied handoff is product reference; the user's later scoped instructions and approvals take precedence.
