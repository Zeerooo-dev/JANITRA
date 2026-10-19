# JANITRA Build 18: Fonts, Profile icons and visual color picker

## Changes

Open **Profile > Appearance** to change the app's appearance. The Appearance button has been removed from the login screen; the JANITRA logo remains centered there.

- Ten font choices: Roboto, System font, Geist, Geist Mono, Inter, Noto Sans, Open Sans, Poppins, Atkinson Hyperlegible and Lora. The nine named families include bundled regular and bold faces and work without downloading fonts. Font choices preview their own typeface and survive reopening.
- Custom accent, background and text colors now open a visual picker. Drag the color area, adjust hue/saturation/brightness sliders, or enter a six-digit hex value. The controls stay synchronized. Background and text have separate selectable swatches, a text preview and a contrast reading. Pairs below 4.5:1 cannot be applied.
- Color changes remain a draft until **Apply colors**. Cancel or dismiss leaves the saved colors unchanged.
- Profile actions now have matching icons for editing the name, Appearance, verification, Supervisor PIN, agencies, notifications, agency history, offline work, schedules, refreshing access and signing out. Existing role visibility and action handlers are retained.

Existing themes, device-local preferences, text scaling, contrast controls, reduced motion and navigation preservation continue to work. No dependency was added; `pubspec.lock` is identical to Build 17. No backend, database, SMTP, permissions, PIN or report changes were made or deployed.

## Verification

- **143/143 Flutter tests passed**, including 18 Appearance tests. All earlier regression tests remain in the suite.
- Tests cover font asset loading and preference persistence; interactive color changes and hex synchronization; invalid hex and unreadable color rejection; cancellation; retained Supervisor/Personnel navigation; login keyboard traversal; Profile icons; storage failures; and existing appearance settings.
- Narrow-screen checks cover 320px, 200% system text and 140% app text, including the longest font option and the scrollable color dialog.
- Updated and visually inspected screenshot baselines for the light/dark accent and background/text pickers, login, Profile and large text.
- Flutter analysis: no errors or warnings. One existing informational `use_null_aware_elements` lint remains at `lib/features/work/personal_schedule_page.dart:151`.
- Android release APK built successfully as `1.0.0+18`, package `com.example.janitra`. Its signature verifies with the existing Android debug certificate.
- APK contents checked against source: all 18 regular/bold font files and all eight added SIL Open Font Licenses are present and byte-identical.
- After-mode UI review: `anti-slop/audit-019-2026-10-19.md`.

## Modified files since Build 17

Application and configuration:

- `lib/core/app_theme.dart`
- `lib/core/appearance_settings.dart`
- `lib/features/appearance/appearance_page.dart`
- `lib/features/appearance/color_picker_dialog.dart` (new)
- `lib/features/authentication/login_page.dart`
- `lib/features/workspace/workspace_page.dart`
- `pubspec.yaml` (font declarations, license assets and build number)

Assets and validation:

- Sixteen new font files in `assets/fonts/`, eight licenses in `assets/fonts/licenses/`, and `assets/fonts/SOURCES.md` with provenance.
- `test/appearance_test.dart`, `test/widget_test.dart`, `test/workspace_test.dart`.
- Four new color-picker screenshot baselines; updated `appearance-large-text.png`, `dark-personnel-profile.png`, `employee-profile.png` and `login.png` in `test/goldens/`.
- This report and `anti-slop/audit-019-2026-10-19.md`.

## Deliverables

- APK: `build/app/outputs/flutter-apk/janitra-build18-fonts-color-picker.apk`.
- APK SHA-256: `fb08daa501d70f0cbab2cba21960e8122da3d4998a0f4636a35eee320eab1e0f`.
- Source: `JANITRA-Build18-Fonts-Color-Picker-Source.zip`, root `JANITRA-Build18-Fonts-Color-Picker-Source/janitra/`.
- Standalone report: `JANITRA-Build18-Fonts-Color-Picker-Changes.md`.

The source archive excludes runtime Supabase configuration, secrets, keystores, build output, caches, backups and screenshot failure output. Supply your own local configuration when building from source, following the existing project instructions.

## Remaining limitations

Physical-phone acceptance, OEM font rendering and real-device accessibility behavior still need testing. Preferences are device-wide. Fonts include regular and bold faces; intermediate weights use Flutter's available-face matching. PDF/XLSX exports keep their existing document typography. The APK retains the project's existing debug signing certificate; production signing is outside this update.
