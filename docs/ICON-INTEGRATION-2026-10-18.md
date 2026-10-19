# JANITRA adaptive and themed Android icons

October 18, 2026, Asia/Manila. App version remains `1.0.0+12`.

## Scope

Integrated the supplied `JANITRA_Adaptive_Themed_Icon_Pack.zip` using its exact `flutter_launcher_icons.yaml` and original PNG assets. JANITRA's J-and-broom artwork, navy `#082853` background and existing adaptive safe-zone padding are preserved.

- Added the pinned development dependency `flutter_launcher_icons: 0.14.4`. Its only newly resolved dependencies are `checked_yaml: 2.0.4` and `cli_util: 0.4.2`; existing package versions were retained.
- Ran `dart run flutter_launcher_icons` to generate legacy Android launcher PNGs, transparent adaptive foregrounds, transparent monochrome drawables, the adaptive XML and background color resource.
- The generated foreground and monochrome inset remains `0%` because the supplied artwork is already padded.
- Both `android:icon` and `android:roundIcon` reference `@mipmap/ic_launcher`, so adaptive launchers apply their own circle, squircle or other supported mask to the same branded icon. Older Android versions use the density-specific legacy PNGs.
- Android 13+ compatible themed launchers receive the supplied white-on-transparent monochrome mask. Actual tint and themed display are controlled by the launcher, wallpaper and user settings. No launcher-specific icon-pack app or forced tint was added.
- No Flutter application feature, authentication, database, Edge Function or production record was changed for this integration. Existing newer employee/offline schedule and form-label changes were retained and tested as supplied.

## Verification

- All **115 Flutter tests passed**, including the newly supplied employee shift and form-label coverage.
- Flutter analysis found no errors or warnings and one existing informational style suggestion: `use_null_aware_elements` in `lib/features/work/personal_schedule_page.dart:139`. It remains unchanged to keep this task scoped to icons. The analyzer exits nonzero for that informational item under its default settings; a completely clean analysis is not claimed.
- Verified manifest references, XML foreground/background/monochrome references, the navy color and zero-percent inset.
- Verified all five densities: legacy PNGs are 48/72/96/144/192 px and adaptive/monochrome drawables are 108/162/216/324/432 px.
- Legacy icons are opaque. Adaptive foreground and monochrome resources retain transparent backgrounds. The source monochrome artwork is white wherever visible, with alpha carrying its silhouette.
- Every visible pixel of both source foreground layers fits within the central Android adaptive safe circle (33 dp radius in the 108 dp canvas).
- Byte comparisons confirmed that the installed YAML and all ten source PNGs match the supplied archive exactly. The bundled pre-generated Android resources were not overlaid onto the generator output.
- The pack's supplied circle/squircle and light/dark preview was inspected. This is artwork/resource verification, not a claim of a live Nothing OS device test.

## APK build

`flutter build apk --release --no-pub --dart-define-from-file=config/supabase.json` succeeded. The optimized universal APK is approximately 66.8 MB (64 MiB), saved as `build/app/outputs/flutter-apk/janitra-build12-adaptive-icons.apk`.

APK signature verification passed. It uses the project's existing debug signing certificate, including for the release build; this matches the prior testing APK. It is not a separately configured store-signing release. Package `com.example.janitra`, version `1.0.0` / code `12`, minimum Android API `24`, target API `36`.

The compiled APK resource table contains all five legacy, foreground and monochrome densities, the adaptive XML and navy color. The compiled manifest points normal and round icons to the same adaptive resource. The compiled adaptive XML retains foreground and monochrome references and zero inset.

SHA-256:

```text
325c07a032eecf5253ad15b2bc5c75da91f842e22fd62aaacb208fdd3e48c54f
```

## Modified and added paths

```text
pubspec.yaml
pubspec.lock
flutter_launcher_icons.yaml
assets/icons/*.png
android/app/src/main/AndroidManifest.xml
android/app/src/main/res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png
android/app/src/main/res/drawable-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher_foreground.png
android/app/src/main/res/drawable-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher_monochrome.png
android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml
android/app/src/main/res/values/colors.xml
docs/ICON-INTEGRATION-2026-10-18.md
anti-slop/audit-014-2026-10-18.md
```

Re-generate with `flutter pub get` followed by `dart run flutter_launcher_icons`. The icon assets are generator inputs, so they do not need to be added to Flutter's runtime asset bundle.

## Updated-code inspection

Compared with the prior verified UI source, the supplied changes affect the status-badge alignment, Team row layout, form labels, employee schedule/offline presentation and related tests. The complete Flutter suite passed on this integrated source. One informational lint is recorded above. No unrelated code was rewritten during icon integration, and no Supabase deployment was needed.

## References and remaining checks

- Generator configuration: https://pub.dev/packages/flutter_launcher_icons
- Android adaptive/themed icon behavior: https://developer.android.com/develop/ui/compose/system/icon_design_adaptive

Physical-device checks remain pending: install/update the APK and inspect standard and themed modes on your launcher, with themed icons enabled where supported. Nothing OS-specific visual acceptance requires a compatible phone/launcher. Launcher caching can delay icon updates; avoid uninstalling merely to refresh an icon because uninstalling can erase unsynchronized local drafts.

Source archives exclude local Supabase configuration, credentials, signing secrets, build/cache outputs and backups. The application was built with the existing local configuration; no privileged key was added to the app.
