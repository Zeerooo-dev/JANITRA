# JANITRA Build 25: Motion and animated startup

## Approved direction

The user explicitly requested `design-motion-principles` and confirmed restrained, professional motion: Jakub Krehel's production polish as the primary lens, Emil Kowalski's speed/restraint as secondary. This is Flutter Android application work; native Flutter transitions and existing branding are reused. No motion dependency, redesign, backend deployment or permission change.

## Motion decisions

| Surface | Behavior | Purpose |
|---|---|---|
| Cold-start logo | One 600ms reveal: subtle opacity/scale/upward settle for 360ms, a brief hold, then a 162ms fade away | Establish JANITRA branding and hand off to the ready application |
| Android page opening/back | Native transitions at 220ms forward, 180ms reverse | Faster orientation between pages while preserving predictive back |
| Bottom navigation indicator | 180ms, or instant with reduced motion/traditional focus | Confirm selection without delaying task switching |
| One-time-code copy confirmation | Copy icon changes to a check using a 140ms fade, with an 80ms exit | Confirm that the clipboard operation actually succeeded |
| Tab contents, typing, lists, security state | Instant/unchanged | Preserve responsiveness, focus, scroll and authorization state |

The startup animation runs once per mounted app, not on every foreground/resume transition, tab switch, login, refresh or theme change. Authentication and workspace checks mount immediately underneath; they are not delayed or replaced with a new initialization flow. The startup surface covers interaction for up to 600ms and then leaves the existing child mounted. No workspace is recreated to complete the reveal.

Android's native launch window now shows the existing launcher logo on JANITRA's light/dark background while Flutter/Supabase initializes, including explicit Android 12+ splash resources. The animated portion runs in Flutter; the native icon is static. The native window follows the OS light/dark setting before the saved in-app appearance loads. Launcher/adaptive/monochrome icon assets themselves are unchanged.

Android predictive-back cancel/commit behavior remains provided by Flutter. Cupertino/macOS native transitions retain their platform timing and gesture behavior. Traditional keyboard/mouse focus mode skips route and copy transition visuals. Bottom-tab content stays in the existing `IndexedStack`; no per-tab loading or cascading card animations were added.

## Accessibility, security and performance

- All newly introduced motion obeys the existing **Appearance → Reduce motion** preference, including the system preference. Reduced startup shows the application immediately; enabling it mid-reveal stops the reveal immediately. Disabling it later does not replay startup.
- No spinning/bouncing logo, pulsing decoration, blur effect, recurring timers or animated list layout. The custom startup uses one finite controller with opacity and transforms. Existing child content does not rebuild on every animation tick.
- Copy success appears only after `Clipboard.setData` succeeds; clipboard failure still shows the existing error. Only icons transition. The sensitive code itself is still removed immediately on background/focus loss, including during the icon animation.
- Auth gates, resume revalidation, RLS, PINs, offline caches, schedules, approval deadlines, reports and account management retain their existing logic. There is no new auth-state crossfade keeping an old workspace alive.

## Verification

- **169/169 Flutter tests passed**, including nine new motion tests and all existing functional regressions.
- New tests verify startup child-state preservation, one-time completion and no resume replay; reduced startup and mid-animation cancellation; Android 220/180ms timings and predictive-back cancellation/commit; instant keyboard/reduced navigation; copy feedback with normal/reduced motion and immediate background hiding; and dark startup at 320px/200% text.
- Existing appearance tests now also assert that the bottom navigation indicator has zero duration with reduced motion.
- Flutter analysis: no errors or warnings; one existing informational `use_null_aware_elements` lint remains at `lib/features/work/personal_schedule_page.dart:151`.
- Rendered and inspected `test/goldens/startup-logo-dark-large-text.png`. Every existing screenshot baseline remains byte-identical to Build 24.
- Existing Supabase files, icon assets and `pubspec.lock` match Build 24. No backend tests/deployments were needed for this UI-only change.
- Android release built successfully as `1.0.0+25`, package `com.example.janitra`, minimum SDK 24 and target SDK 36. APK signature verifies with the existing Android debug certificate. Packaged resources include the light/night launch colors and default/night/API 31/night-API 31 launch theme variants.
- After-mode review: `anti-slop/audit-026-2026-10-19.md`.

## Modified files since Build 24

- `lib/core/startup_reveal.dart` (new) and `lib/app.dart` — one-time reveal around the unchanged auth gate.
- `lib/core/app_theme.dart` — platform-preserving transition durations and instant traditional-focus navigation.
- `lib/features/workspace/workspace_page.dart` — navigation indicator timing, retaining tab state.
- `lib/features/workspace/account_code_page.dart` — animated successful-copy icon, retaining security/error behavior.
- `android/app/src/main/res/drawable/launch_background.xml`, `drawable-v21/launch_background.xml`, `values/colors.xml` — branded native launch window.
- `android/app/src/main/res/values-night/colors.xml`, `values-v31/styles.xml`, `values-night-v31/styles.xml` (new) — dark background and Android 12+ native splash variants.
- `test/motion_test.dart`, `test/goldens/startup-logo-dark-large-text.png` (new), and `test/appearance_test.dart` — motion/gesture/accessibility regressions.
- `pubspec.yaml` — build 25 only. This report and the after-mode audit.

## Deliverables and limitations

- APK: `build/app/outputs/flutter-apk/janitra-build25-motion-startup.apk`.
- APK SHA-256: `777d0e09fd8b47c614c5866de83b1a402fe16cead8509a09e57f10eb0ecdea78`.
- Source: `JANITRA-Build25-Motion-Startup-Source.zip`, root `JANITRA-Build25-Motion-Startup-Source/janitra/`.
- Changes: `JANITRA-Build25-Motion-Startup-Changes.md`.

No production deployment is required. Physical-phone cold/warm launch, OEM splash behavior (including Nothing OS), actual frame timing and low-end-device GPU performance remain unverified. Existing Android debug signing is retained. Source packaging excludes runtime configuration, secrets, keystores, generated files, caches, builds, backups and screenshot failures.
