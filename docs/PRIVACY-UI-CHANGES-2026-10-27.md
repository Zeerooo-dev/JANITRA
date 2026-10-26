# Privacy Policy, contrast and manual update check

Implements the supplied Privacy Policy with verified corrections and the operator's confirmed developer name/contact. A single bundled JSON source drives the offline, selectable policy screen and generated public HTML. Privacy Policy is available in Profile → Settings for every role, on the login page without authentication, and on the startup connection-failure screen. No consent or Terms of Service screens were added. The local candidate is **1.0.2+29**; GitHub's published version remains 1.0.1.

Fixes the high-contrast Home setup hero's explicit text colors: a solid dark surface now uses the matching surface foreground instead of the dark foreground intended for a light gradient. Adds accent-derived color to top/bottom bars and checks their foreground and selected-indicator contrast, including saturated custom accents. Existing appearance preferences and layouts remain.

About JANITRA gains **Check for Updates**. It reuses the existing updater, release dialog, signing/checksum checks, download progress and native installer. Manual checks report no update or a connection failure, suppress duplicate requests, and can be repeated after Later. Startup checks remain optional and retain their existing route safeguards.

## Files

- `assets/privacy/policy.json`, `lib/features/privacy/privacy_policy_page.dart`, `lib/app.dart`, login and workspace pages, `pubspec.yaml`.
- `lib/core/app_theme.dart`, `lib/features/workspace/home_setup_panel.dart`.
- `lib/features/about/about_page.dart`, `lib/features/updates/update_prompt.dart`.
- `tool/build_privacy_policy.py`, `tool/test_privacy_policy.py`, `docs/privacy/index.html`, hosting/content verification documentation, and policy validation in the release workflow.
- Privacy, About/manual-update, appearance and visual regression tests.

## Validation and limits

Run Flutter analysis and the full test suite, policy generator consistency/escaping tests, and the Android release build/verifier before distributing the candidate APK. Visual checks cover phone-width HTML, light/dark screens, high-contrast setup and large text.

Verified locally: **241 Flutter tests**, **3 policy generator tests**, **2 release-tool tests**, matching bundled/public policy content, source exclusion checks, and zero Flutter analysis errors or warnings. The single existing informational `use_null_aware_elements` note in `personal_schedule_page.dart:151` remains. Policy access covers login, all roles and backend-initialization failure; new update checks cover Later/retry/no-update/network failure and duplicate suppression. The candidate APK's signature/version/source metadata and checksums are verified during artifact packaging.

Retention periods, formal controller/legal arrangements and a complete erasure-request process remain operator decisions; see [verification](PRIVACY-VERIFICATION-2026-10-27.md). The supplied draft's unverified statements were removed or narrowed to observed behavior. No production data, roles, RLS, credentials, deadlines, PIN workflow or backend function was changed. Neither the GitHub release nor Pages was published by this task. Physical-phone acceptance remains outstanding.
