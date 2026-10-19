# JANITRA Build 17: Appearance

## How to use

Open **Profile > Appearance**, or tap the palette icon beside the logo on the sign-in screen. Preferences apply immediately across the app and are saved on this device.

- Mode: System, Light or Dark. System follows the phone's brightness setting.
- Accent: JANITRA, Ocean, Forest, Plum, Copper or a custom six-digit hex color.
- Background and text: customize the current mode, with separate saved pairs for light and dark. Unreadable pairs below 4.5:1 contrast are rejected. Accent and error colors are adjusted for readable controls on the chosen surface.
- Font: bundled Roboto or the platform default.
- Text size: 100% to 140%, added to the phone's text scaling without flattening its nonlinear scale.
- Higher contrast: stronger foreground colors and borders, with a 7:1 target where the chosen background permits it.
- Reduce motion: System, On or Off. Reduces theme/page transitions, keyboard-driven sheet padding motion and PIN-indicator animation while keeping functional loading indicators.
- Reset to default: restores System mode, JANITRA accent, Roboto, 100% added text size and System motion. It clears only appearance choices.

The desktop reference's code-font, diff-marker and code-page settings do not apply to JANITRA's workforce screens. No code editor, theme import service or extra font dependency was added.

## Implementation

Uses the existing Flutter theme, Material controls and secure-storage dependency. Preferences use the separate `janitra.appearance.v1` key; resetting them does not touch sessions, PINs or offline records. Writes are serialized to prevent an older save from overwriting a newer choice. Invalid or corrupt stored values fall back safely; storage failures preserve the current visual choice and show a save error.

App-level theme updates retain the navigator, existing authenticated workspace, selected tab and form state. Shared widgets and hardcoded screen colors now follow the theme, including tasks, reports, schedules, People and offline work. Existing status badges keep their explicit readable status colors. Normal navigation retains the platform's standard transitions. JANITRA logo artwork remains unchanged.

## Verification

- **139 Flutter tests pass**, including all previous 125 tests and 14 new Appearance tests.
- New tests cover persistence/reopening, rapid writes, reset without clearing session storage, malformed settings, storage failure and recovery, mode/accent/font/text/contrast/motion controls, custom-color validation, cancellation, system brightness and reduced-motion preferences, overrides, preserved login input, and retained Supervisor/Personnel navigation state.
- Checked color contrast across 96 brightness/accent/background/contrast combinations, including white, black and yellow custom accents. Main text, muted text, primary controls and errors remain readable in those cases.
- Rendered and inspected light/dark Appearance screens, a 320px screen at 200% system text plus 140% app text, and dark Supervisor/Personnel home, task, Team, report and profile screens. Ten new screenshot baselines cover these views. Existing login/profile baselines now include the Appearance entry points.
- Flutter analysis: no errors or warnings. One existing informational `use_null_aware_elements` lint remains in `personal_schedule_page.dart` (now line 151).
- Android release build completed. Verified package version `1.0.0+17` and its signature with the existing Android debug certificate.
- After-mode UI review: `anti-slop/audit-018-2026-10-19.md`.

## Modified files

New files:

- `lib/core/appearance_settings.dart`
- `lib/features/appearance/appearance_page.dart`
- `test/appearance_test.dart`
- Ten new images in `test/goldens/` named `appearance-*` and `dark-*`.

Updated application files:

- `lib/main.dart`, `lib/app.dart`, `lib/core/app_theme.dart`
- `lib/features/authentication/login_page.dart`
- `lib/features/workspace/workspace_page.dart`, `people_page.dart`, `name_editor.dart`, `supervisor_pin_setup_sheet.dart`
- `lib/features/work/work_overview.dart`, `task_page.dart`, `scheduling_page.dart`, `personal_schedule_page.dart`, `offline_work_page.dart`
- `lib/features/reports/reports_page.dart`
- `pubspec.yaml`

Updated validation files: `test/widget_test.dart`, `test/mfa_test.dart`, `test/goldens/login.png`, `test/goldens/employee-profile.png`, plus this report and the after-mode audit. Keyboard traversal now accounts for the sign-in Appearance control; MFA tests scroll to the existing verification entry after the added Profile row. `pubspec.lock` is unchanged.

## Deliverables and limitations

- APK: `build/app/outputs/flutter-apk/janitra-build17-appearance.apk`.
- APK SHA-256: `d17f0b9270462603298cfba07dff6991ec59b2f059e3035e8e003fefb18ceab9`.
- Source: `JANITRA-Build17-Appearance-Source.zip`, containing `JANITRA-Build17-Appearance-Source/janitra/`.
- Changes: `JANITRA-Build17-Appearance-Changes.md`.

No database, backend, SMTP, account or permission changes were made or deployed. PDF/XLSX exports keep their existing document styling. Preferences are device-wide and do not synchronize between phones. Physical-phone acceptance, OEM font behavior and OS accessibility settings still need device testing. The source ZIP excludes runtime configuration, credentials, keystores, generated files, caches, backups and screenshot failure output.
