# JANITRA Build 15: password visibility update verified

## Result

Preserved the supplied Build 15 password, PIN and recovery-code visibility controls and the supplied two-step verification layout. Corrected the test errors that prevented analysis and the test suite from passing. No application source changes were needed to fix the reported errors.

## Fixes in this pass

- `test/password_visibility_test.dart`: inspect the inner `EditableText.obscureText`, rather than the nonexistent getter on `TextFormField`. Keep entry, visibility independence, unchanged values and background hiding checks. Added a regression for hiding when disabled or given another controller, including the disabled eye button.
- `test/mfa_test.dart`: correct the same getter in the MFA recovery/password-reset integration checks.
- `test/goldens/admin-access-large-text.png`: update the screenshot baseline for the supplied eye icon. Inspected the rendered 320px/200% text screenshot and isolated difference before updating: only the eye icon changed (224 pixels, 0.08%).

## Supplied update included in this release

- New shared `lib/core/secret_text_form_field.dart`.
- Existing forms use it in `lib/features/authentication/account_setup_page.dart`, `lib/features/authentication/reset_password_page.dart`, `lib/features/authentication/mfa_page.dart`, `lib/features/work/work_form.dart`, `lib/features/workspace/people_page.dart` and `lib/features/workspace/supervisor_access_sheet.dart`.
- Existing login and PIN-setup eye controls remain available. The supplied MFA layout and version `1.0.0+15` are retained.

## Validation

- All 125 Flutter tests pass, including visibility controls, MFA recovery, account setup, PIN checks, navigation/lifecycle, scoped permissions, offline drafts, scheduling and reports.
- Flutter analysis: zero errors and zero warnings. One existing informational lint remains at `lib/features/work/personal_schedule_page.dart:139` (`use_null_aware_elements`).
- Shared-field interactions: Show reveals only the chosen field; Hide obscures it; toggling preserves the value; backgrounding obscures a revealed code; disabling hides the password and disables its control; replacing the controller starts hidden.
- MFA recovery interaction: verify authenticator code, reveal one new-password field while its confirmation stays hidden, hide it, set matching passwords, and return to sign-in with the old session cleared.
- Existing narrow-screen tests pass, including the Supervisor editor screenshot at 320px/200% text and the MFA enrollment form at large text.
- After-mode UI review: `anti-slop/audit-016-2026-10-19.md`.
- Release APK built successfully, package `com.example.janitra`, version `1.0.0+15`. Signature verification passes with the same existing Android debug certificate used by prior builds.

## Deliverables

- APK: `build/app/outputs/flutter-apk/janitra-build15-password-visibility-fix.apk`.
- APK SHA-256: `a8a3f0742b6be3bedb6eaa4421ba104a636f94c45af3ae8add1d0864f4a535bf`.
- Source: `JANITRA-Build15-Password-Visibility-Fix-Source.zip` (contains `JANITRA-Build15-Password-Visibility-Fix-Source/janitra/`).
- Changes: `JANITRA-Build15-Password-Visibility-Fix-Changes.md`.

## Scope and limitations

No Supabase functions, migrations, SMTP settings, accounts, permissions or stored data were changed or deployed in this pass. Email delivery was not tested. Physical Android keyboard, autofill and device acceptance still need testing on the phone.

The source archive excludes the local runtime Supabase configuration, credentials, keystores, build output, caches, backups and screenshot failure output. Configure the project locally using its existing configuration example when building from source.
