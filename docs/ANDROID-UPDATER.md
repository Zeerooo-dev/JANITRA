# Android APK updates

JANITRA checks public GitHub Releases in `Zeerooo-dev/JANITRA` once, two seconds after startup. Authentication and normal operations continue independently. Missing releases, offline connections and API limits quietly skip the optional check. Later dismisses the popup for this app run without changing navigation, workspace data or authentication.

## Verification and installation

- Stable semantic versions only. Drafts, prereleases, equal versions and downgrades are not offered. Build metadata does not affect semantic precedence. Increase **both** semantic version and Android build number for every release.
- A release must have exactly one `janitra.apk` asset with GitHub's SHA-256 digest and a positive size below 512 MiB. The asset URL must belong to this repository. Redirects require HTTPS and approved GitHub asset hosts. The APK contains no GitHub token.
- Downloads use private `cache/updates/` with received-byte progress, storage checks, bounded network deadlines, size limits, concurrency protection and incomplete-file cleanup.
- Native code verifies SHA-256, size, package ID, exact version name, increasing version code, supported minimum SDK and cryptographic APK signatures using Google's `apksig`. The full signer set must match the installed application's current signer set. Verification runs off the UI thread and repeats immediately before installation. Invalid APKs fail closed.
- The APK becomes read-only. A non-exported FileProvider exposes only `cache/updates/`, with temporary content-URI read permission. No external-storage permission is requested.
- Only Update Now starts downloading. Installation waits for the foreground. When needed, Allow installation opens Android's per-app permission settings. Denial/cancellation remain recoverable. Android always controls the final installation confirmation; nothing silently installs.
- If Android restarts JANITRA when installation permission changes, a private record retains the verified download for 30 minutes. Startup revalidates the APK and offers Install update without downloading again. This restored state needs a fresh tap; it never launches an installer merely because the app reopened. Later clears the record. Stale, corrupt, wrong-repository or invalid records fail closed.
- The updater never signs out, clears secure storage/drafts, changes workplace permissions or calls Supabase. Compatible Android updates preserve app data.

The popup retains JANITRA's logo and theme, offers bounded scrollable release notes, and keeps errors separate from workplace authorization notices.

## First production signing key

Build 25 and earlier used the local Android debug key. Build 26 uses a dedicated production key. Back up `config/signing/` and `android/key.properties` securely offline: Git and source ZIPs exclude them, and GitHub Secrets are not a downloadable backup. Losing this key prevents future in-place updates.

The standard production APK supports Android 7+ but cannot directly replace a debug-signed installation. On Android 7/8 a one-time reinstall requires synchronizing drafts first; reinstalling removes local-only data and requires signing in again. Never uninstall automatically.

Android 9+ supports a one-time proof-of-rotation bridge. `python3 tool/create_signing_transition.py INPUT_APK OUTPUT_APK` creates a V3-only transition APK using the old local key and new production key; verify it with `apksigner verify --min-sdk-version 28`. Verify the installed legacy certificate and test first on a separate package. The old private key stays local. This transition APK is separate from normal release assets. Subsequent production-key updates must retain app data. The Build 26 report records actual device results.

## GitHub Actions and publication

The public source repository excludes keys, local config, environment files, databases, backups, binaries, caches and agent configuration. Required Actions secrets:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`
- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY` (client key only)

Manually run **Build signed Android release** with a tag matching `pubspec.yaml`, such as `v1.0.0` for `1.0.0+26`. Add `docs/releases/vX.Y.Z.md` first. Pinned actions run Flutter checks, require production signing, verify the APK and produce review artifacts: `janitra.apk`, `SHA256SUMS`, `release-info.json`, `CHANGES.md` and `JANITRA-Source.zip`. Signing files are removed after the job. Missing signing secrets fail the release build; debug signing is never a fallback.

The workflow **does not publish releases** or deploy Supabase changes. After separate user approval, publish the matching GitHub Release with reviewed notes and verified assets. Upload everything before publishing; do not replace reviewed assets. GitHub computes the digest consumed by the updater. No popup appears until a higher stable version is published.

## Validation

```sh
flutter analyze --no-pub --no-fatal-infos
flutter test --no-pub
flutter build apk --release --no-pub --dart-define-from-file=config/supabase.json --dart-define=JANITRA_RELEASE_REPOSITORY=Zeerooo-dev/JANITRA
(cd android && ./gradlew :app:testDebugUnitTest --console=plain)
python3 tool/test_android_release.py
RELEASE_TAG=v1.0.0 python3 tool/android_release.py package
```

`python3 tool/build_updater_smoke.py` creates isolated `com.example.janitra.updatertest` host/update APKs for physical testing. HTTP fixtures are controlled, while file writes, verification, Settings and installer use real Android APIs. The harness also checks the live GitHub feed without publishing a release. Its target displays a saved marker to confirm data retention. Never install fixtures over `com.example.janitra`. Live published-release acceptance waits for publication approval.

References: [GitHub asset digests](https://docs.github.com/en/rest/releases/assets), [Android content-URI sharing](https://developer.android.com/training/secure-file-sharing), [APK verification](https://android.googlesource.com/platform/tools/apksig/+/refs/heads/main/src/main/java/com/android/apksig/ApkVerifier.java).
