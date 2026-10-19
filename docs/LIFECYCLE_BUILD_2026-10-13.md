# JANITRA lifecycle-only Android build

Date: October 13, 2026, Asia/Manila.

APK: `build/app/outputs/flutter-apk/janitra-lifecycle-fix.apk`.
Source snapshot: `build/app/outputs/flutter-apk/janitra-lifecycle-fix-source.zip`.

## Scope and verification

- Package `com.example.janitra`, version `1.0.0`, Android version code `5`.
- APK SHA-256: `c70a56c24aa24c0d592c27c44541fa135085b29b2bc1cbd8887e155adb9554c5`.
- APK signature verified. Certificate SHA-256 matches the preceding development APKs: `a812ea37a8d03d2565864ff0b012357b635b578f2da0730add4450f520d71219`.
- This APK combines the lifecycle fix with build 2's workspace UI. People and PIN screens are excluded. The workspace source matches the preserved build-2 file exactly. The earlier first-Supervisor setup flow is retained.
- Current repository lifecycle fix: clean analysis, 46 tests including 15 lifecycle tests. The isolated APK source: clean analysis, all 39 applicable tests passed, including the same 15 lifecycle cases and build-2 workspace tests.
- Routine resumes preserve the workspace, selected tab, dialog input and pushed routes during validation. Resumes coalesce over 300ms, concurrent requests share one check, and superseded/timed-out responses cannot restore access.
- Revalidation checks Auth identity and existing setup/profile/role APIs. Account suspension, revoked roles, expired sessions, changed identity and validation failure close protected views. Checks time out after 15 seconds. Existing RLS/grants are unchanged.
- No database, Edge Function, dependency, PIN, invitation, or production account changes occurred for this fix/build.
- The main project retains its prior candidate feature source unchanged. This separately preserved APK source avoids accidentally including that UI in a later rebuild.
- Existing APKs are retained. The standard `app-debug.apk` in the main project was not overwritten.
- Source archive excludes private client configuration, local paths, SDK caches, generated builds, signing credentials, backend files, and backups. Use the existing ignored public client config to rebuild locally.

## Physical phone check

No Android device was connected during this work, so native behavior is not yet confirmed.

1. Install this APK over the existing JANITRA development build. Do not uninstall first; an ordinary update retains app data/session storage.
2. Open Profile, open Edit Your Name, and type an unsaved name. Switch to Messenger, then return. The same dialog/input and selected tab should remain visible; cancel the edit afterward.
3. Select Workplaces and repeat several short app switches. It should retain that tab without flashing Account connected during successful background checks.
4. Temporarily disable connectivity and resume. A failed/timed-out validation must block protected access. Restore connectivity and choose Retry; authorized access should return. Navigation resets after unsafe/denied access intentionally.
5. Record any unexpected spinner, tab reset, crash or error with the installed version and circumstances. Session expiry/revocation are covered by automated tests; no real account was suspended or altered for a phone test.

This is a development/debug APK. Physical-device validation remains the next step; broader People/PIN deployment and new features remain outside the current scoped request.
