# JANITRA Build 27: About, licensing and production release

Version: **1.0.0+27**, release tag **v1.0.0**. This follows the user's approval to sign and release, and their request to add About and license notices before publication.

## App changes

- Profile now opens About JANITRA for Admin, Supervisor and Personnel using the same shared menu.
- About reuses the app logo and theme and displays the installed version and Android build number. Missing platform metadata does not block license access.
- Third-party licenses are readable offline through Flutter's standard license browser. Flutter's generated dependency notices now include all nine bundled fonts and 82 native runtime artifacts. Original texts and provenance are preserved in `NOTICES`, `licenses/` and the existing font assets.
- No new dependency, app-source license grant, backend migration, role change or redesign was introduced.

## Modified files

- `lib/features/about/about_page.dart`: About page and standard license browser entry.
- `lib/features/workspace/workspace_page.dart`: shared Profile entry.
- `lib/features/updates/apk_updater.dart` and `android/app/src/main/kotlin/com/example/janitra/UpdateChannel.kt`: expose the installed build number alongside existing version metadata.
- `pubspec.yaml`: Android Build 27.
- `NOTICES`, `licenses/`: font and Android notices with provenance.
- `test/about_test.dart`, `test/appearance_test.dart`, `test/workspace_test.dart`, affected Profile/About goldens: license bundle, light/dark large-text UI, navigation preservation, metadata failure, and Admin access/agency setup with an empty workplace.
- `README.md`, release notes and scoped Anti Slop audit: updated release documentation.

## Verification

- Flutter analysis: no errors or warnings; the pre-existing `use_null_aware_elements` information message at `personal_schedule_page.dart:151` remains.
- All 202 Flutter tests pass, including compiled font/native license presence, light/dark license detail navigation, platform metadata failure and empty-workplace Admin access.
- Native APK verification: 9 tests pass. Release-tool version checks: 2 tests pass.
- Production APK built and its package, version/build, SHA-256, production signing certificate and bundled notices verified.
- No repeated phone installation was performed. The prior Build 26 updater/device results remain documented in its report.

## Installation and signing

The standard `janitra.apk` uses the production key and retains application ID `com.example.janitra`. It is suitable for fresh installs and future production-key upgrades. Old debug-signed installs require the separately labeled Android 9+ signing-transition APK or a one-time reinstall. The transition signature/lineage verifies locally; actual legacy transition and encrypted session retention were not tested on the physical phone. Do not uninstall an old app with unsynchronized local drafts.

## Authorized post-release cleanup

The user explicitly selected: keep only Admin access for `jeffirie12@gmail.com`; delete all other accounts, agency/site setup and activity. This is a one-time operator reset after publication, not an APK feature or a change to normal history-preserving deletion.

The reset must preserve the Admin's Auth identity, global Admin role and active profile; retain security configuration, migrations, RLS, functions and scheduled jobs; back up data privately; remove other Auth access and all application work/notification/history rows; and verify empty workplace setup plus Admin access afterward. Operational Supabase/GitHub logs, private recovery backups and data already cached on disconnected devices are separate from live application records. A completion report will record actual results; this section alone does not claim the reset has occurred.
