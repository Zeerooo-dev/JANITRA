# JANITRA

Android janitorial workforce management with Flutter, Material 3, and Supabase.

Build 27 includes Profile > About JANITRA, installed version information, and [third-party license notices](licenses/README.md), alongside the optional [GitHub Releases APK updater](docs/ANDROID-UPDATER.md). Its [same-version maintenance update](docs/ADMIN-UNASSIGNED-ACCOUNTS-2026-10-20.md) allows Admin to create accounts before company setup. The public repository excludes signing keys and local configuration. [Release notes](docs/releases/v1.0.0.md) describe the first production-key release. GitHub Actions builds review artifacts only; publishing a release requires separate approval. Older Build 7 details below are historical.

Authentication, scoped workspaces, People/PIN management, MFA, schedules/tasks, PIN submission, separate Supervisor confirmation/final approval, deadlines/overrides, encrypted personal offline drafts, history/notifications/audit, PDF/XLSX reports and Supervisor-only agency transfers are implemented. Six migrations and all three guarded functions are deployed. See [build 7](docs/BUILD-7-2026-10-13.md), [phone test guide](docs/PHONE_TEST_GUIDE.md) and [current transfer](docs/JANITRA_TRANSFER_2026-10-13.md).

Build 7, `build/app/outputs/flutter-apk/janitra-all-workflows.apk` (`1.0.0+7`), is the optimized workflow test build. It retains development signing for update compatibility. Earlier APKs are preserved; build 5 is the phone-verified lifecycle checkpoint. New authenticated/native acceptance checks remain. Configured MFA must be verified before workspace access; unassigned accounts retain Refresh Workplace Access and Sign Out.

## Run

`config/supabase.json` contains only the existing project's URL and public client key and is ignored by Git. For another checkout, copy `config/supabase.example.json` to `config/supabase.json` and supply a publishable or legacy anon key. Never use a service-role or secret key.

```sh
flutter pub get
flutter run --dart-define-from-file=config/supabase.json
```

Supabase CLI linking is separate from Flutter initialization. Run with the client configuration above. Existing account credentials are supplied by an authorized Supervisor; there is no public registration UI.

Recovery uses `janitra://auth-callback/`, matching the supplied Supabase redirect screenshot. The Android intent, request URL, callback filter, and local allowlist use this same URL. The screenshot confirms the configured remote URL; a physical-device recovery round trip still needs verification.

The public client configuration is kept out of Dart source, logs, and Git and uses owner-only file permissions. It is still included in compiled apps, as required for Supabase access. RLS and authenticated server authorization protect data; hiding a publishable key does not provide database security.

## Validate

```sh
flutter analyze --no-pub
flutter test --no-pub
node tool/check_design.mjs
bash tool/test_database.sh
deno test --allow-env --config supabase/functions/workflow/deno.json supabase/functions/manage-users/index_test.ts supabase/functions/manage-pins/index_test.ts supabase/functions/workflow/index_test.ts
flutter build apk --release --dart-define-from-file=config/supabase.json
```

The optimized test APK retains development signing. Public release signing/distribution is still pending.

The database test script requires Docker and starts a disposable PostgreSQL 17 container with no network or exposed ports. Its Auth fixture emulates Supabase request claims; it does not certify the live Auth/Data API integration.

## First Supervisor setup

The approved initial account is `jeffirie12@gmail.com`. Supabase accepted its invitation on October 12, 2026 at 3:23 PM Asia/Manila, and the trusted provisioning script authorized its one-time setup. The invitation and one-time company setup are now completed. Install the latest development APK to open the dashboard. The callback is `janitra://auth-callback/`.

After email verification, the invited Supervisor chooses a password in the app, then enters their manpower/third-party company name and full name. The backend requires password enrollment before creating an agency-scoped Supervisor assignment, consumes the one-time grant, and makes retries return the same company. Client companies and sites are added later; no example organization names are seeded. Existing accounts with passwords skip password enrollment.

Applied migrations: [foundation](supabase/migrations/20261012021018_phase1_foundation.sql), [first company](supabase/migrations/20261012022056_first_supervisor_setup.sql), [People](supabase/migrations/20261012131324_user_management.sql), and [PIN security](supabase/migrations/20261012151246_pin_security.sql). Local versions match live history checked over Management API HTTPS. CLI database-login initialization still stalls; no password or grants were changed to bypass it.

All three authenticated functions and the protected server PIN pepper are deployed with JWT verification enabled. Atomic PIN-backed transitions include authorization, idempotent receipts, task versions and deadlines. Preserve the pepper; never include it in client configuration or transfer archives. Do not reinvite the first Supervisor. See [PIN security contract](docs/PIN_SECURITY.md).

## Design references

Open `design/JANITRA_Complete_Polished_UI/index.html` through a local static server. The 23 HTML screens are design prototypes only. They never implement authentication, real PIN validation, authoritative approvals, or report generation. Original ZIP content and supplied PNG previews remain reference history; corrected HTML contains the audit fixes.

Roboto, navy `#234E70`, and the supplied light surfaces follow the application handoff. No inventory models or queries from SmartStock were reused.
