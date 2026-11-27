# Password recovery focus/resume fix

November 27, 2026. Initially verified as a local **1.0.2+29** Android test build. The owner subsequently approved a GitHub Actions build and public release as **1.0.3+30**, so the installed app's updater can detect a newer version. No database, RLS, Auth configuration, dependency or backend function was changed.

## Reproduced cause

The account gate sets `_checking` while it revalidates authorization on resume. The password branch previously required `!_checking`, so every such check replaced an already-verified Reset Password / Set Your Password page with Checking your access. Disposing that page disposed its text controllers. A delayed mocked authorization response reproduced the reported screen replacement before the fix.

The Personnel setup/recovery page had a separate focus issue: it cleared its code and passwords on every lifecycle state other than resumed, including transient inactive events.

## Changes

- `lib/app.dart`: retain the verified password page during background revalidation, as the workspace already does. Initial verification still shows loading; explicit authorization errors and session loss still remove the form. MFA precedence, expiry guards, request coalescing and stale-response checks are unchanged.
- `lib/features/authentication/reset_password_page.dart`: explicitly clear passwords on hidden, paused and detached states, submission completion and disposal. Brief inactive/resumed transitions preserve typing; the shared secret field still re-hides visible text on focus loss.
- `lib/features/authentication/account_setup_page.dart`: preserve Personnel code/password fields during brief inactive focus changes, while retaining actual-background, submission and disposal cleanup and the existing sensitive-screen protection.
- `test/password_recovery_lifecycle_test.dart`: regression coverage through real Supabase SDK recovery/session events with a mocked server. Covers keyboard insets and repeated focus interruptions, initial password setup, delayed and stale checks, token refresh, successful password save/sign-out, expiry, rejected sessions, offline failures and background secret cleanup.
- `test/personnel_account_test.dart`: verify that transient focus preserves input and re-hides the password, then actual backgrounding clears all secrets before server-confirmed setup.

## Security behavior

| Event | Behavior |
| --- | --- |
| Ordinary typing / keyboard resize | Does not trigger authorization requests or reset the form. |
| Brief inactive/resumed focus change | Form and text remain; visible secrets are masked. Existing background auth checks continue. |
| Hidden / paused / detached | Sensitive fields clear; no credentials are persisted for restoration. |
| Token renewal / late authorization result | Current session guards and coalescing remain; stale results cannot replace the recovery state. |
| Expired/rejected session, sign-out or failed verification | Recovery access fails closed; protected workspace access is not granted. |
| Save password | Existing online Supabase update and post-recovery sign-out remain unchanged. |

## Verification

The pre-fix regression failed because the ResetPasswordPage disappeared during a pending focus-triggered check. All **258 Flutter tests**, including **11 new recovery regressions**, passed against the existing screenshot baselines. Analysis has no errors or warnings and only the pre-existing informational `use_null_aware_elements` note in `personal_schedule_page.dart:151`. The signed Android APK build, **9 fresh native APK verifier tests**, **3 policy tests** and **2 release-tool tests** passed. No visual baselines were changed.

The expiry regression renews an already-open recovery session with a short-lived test token, then verifies that expiry removes the form and its delayed check cannot restore it. Initial recovery-link refresh behavior is distinct from that editing-state test.

The APK and attached source are packaged with SHA-256 checksums, exact source-commit verification, package/version checks and a signing-certificate comparison with JANITRA's established production signer. No private configuration, keystore, local database or cached credential files are included in the source archive.

The affected physical phone has not been retested and its actual IME/lifecycle event trace has not been captured. Tests reproduce the reported form-reset path using keyboard-inset and focus/resume events. No current user passwords, recovery codes or production account records were used. Production data/settings remain unchanged. The approved GitHub release distributes the client fix only; signing, package/version, source and public checksum verification are required before publication.
