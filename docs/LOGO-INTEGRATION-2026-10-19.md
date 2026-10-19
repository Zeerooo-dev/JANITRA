# JANITRA Build 16: in-app branding

## Changes

- Replaced the login checkmark placeholder with the existing JANITRA logo at the same 80px size.
- Added the same logo beside the JANITRA name in the workplace-access and company-setup app bars at 32px.
- Reused the original `assets/icons/janitra_launcher_1024.png` from the approved icon pack, without modifying its artwork or colors. Registered it as a bundled Flutter asset.
- Added a shared `JanitraLogo` widget to the existing UI helpers, with proportional rounded corners, preserved aspect ratio and a screen-reader label.
- Retained task-status checks, security shields, navigation icons and personal avatars: these convey state or identity rather than JANITRA branding. Existing Android standard/adaptive/monochrome launcher resources already use the supplied logo.
- Version: `1.0.0+16`.

## Modified files

- `lib/core/app_theme.dart`
- `lib/features/authentication/login_page.dart`
- `lib/features/authentication/company_setup_page.dart`
- `lib/app.dart`
- `pubspec.yaml`
- `test/widget_test.dart`
- `test/workspace_test.dart`
- `test/ui_reference_test.dart`
- `test/goldens/login.png`
- This report and `anti-slop/audit-017-2026-10-19.md`.

## Verification

- All 125 Flutter tests pass, including assertions that login, company setup and pending-access screens use the real bundled logo.
- Inspected the rendered 390px login screenshot and isolated difference before updating its golden: only the 80px logo region changed.
- Login and company setup still pass the existing 320px/200% text tests. Empty sign-in validates without making a request; password Show/Hide still works; pending access can refresh into the authorized workspace.
- Flutter analysis has no errors or warnings. The existing informational `use_null_aware_elements` lint remains at `lib/features/work/personal_schedule_page.dart:139`.
- After-mode UI review is recorded in `anti-slop/audit-017-2026-10-19.md`.
- Release APK built successfully. Verified version code 16, its signature against the existing Android debug certificate, and that it contains the exact original logo bytes.

## Deliverables

- APK: `build/app/outputs/flutter-apk/janitra-build16-logo.apk`.
- APK SHA-256: `c79effdbb2d8402e3b7c7dd831fb1eb85b383a44894981c3f78386e2de0f6c08`.
- Source: `JANITRA-Build16-Logo-Source.zip`, containing `JANITRA-Build16-Logo-Source/janitra/`.
- Changes: `JANITRA-Build16-Logo-Changes.md`.

## Limitations

Physical-phone acceptance is pending. No backend, SMTP, accounts, permissions, PIN behavior or data were changed. The source archive excludes local runtime configuration, credentials, keystores, generated files, caches, backups and screenshot failure output.
