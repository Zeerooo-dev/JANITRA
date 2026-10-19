# JANITRA Build 26: GitHub APK updater

Version: `1.0.0+26`. Public repository: https://github.com/Zeerooo-dev/JANITRA

Implemented and pushed. No GitHub Release, version tag, Supabase deployment or database change was made. The user asked to stop additional checks after the completed verification below; unfinished checks remain listed explicitly.

## App changes

- Nonblocking startup update check against public GitHub Releases. Stable semantic version ordering supports tags such as `v1.0.0`, `v1.1.0`, `v1.2.0`; drafts, prereleases and equal/older versions are skipped.
- JANITRA-branded popup with version, actual release notes, Update Now and Later. Later preserves workspace/navigation and never initiates installation. Theme and accessible large-text layout are retained.
- In-app APK downloads with real received-byte progress. Offline errors, HTTP limits, interrupted/oversized downloads, insufficient storage and concurrent requests fail safely without triggering workplace authorization overlays.
- SHA-256, size, package, version name, increasing Android version code, minimum SDK and cryptographic signer verification before installation, repeated on a native worker immediately before launch.
- Dedicated Android installer action avoids file-browser/SHAREit choosers. Installation requires Android's visible confirmation. Unknown-source permission is requested through native Settings; no silent installation or security-prompt bypass.
- Private APK cache and narrow, non-exported FileProvider with temporary content-URI read access.
- A verified download survives an Android process restart during installation settings for up to 30 minutes. It is reverified and offered as Install update, requiring a new tap after restart. Later clears the continuation. Stale/corrupt/foreign records are rejected.
- Updater code does not sign out, clear app data, change workplace roles, or alter RLS, PINs, scheduling, offline tasks, approvals or reports.

## Repository and release builds

Created the public `Zeerooo-dev/JANITRA` repository and connected this local folder to its `main` branch. Source and existing project assets are pushed. The source scan excludes local Supabase configuration, signing keys/passwords, environment files, agent configuration, databases, dumps, backups, caches, APKs and source ZIPs. No privileged credentials were committed.

Created a dedicated production signing key. Required key material/passwords and client build configuration are stored in GitHub Actions Secrets. Local private signing files remain ignored under `config/signing/` and `android/key.properties`. Back them up securely outside the source archive. GitHub Secrets are not a downloadable key backup.

The pinned, manually triggered Android workflow runs checks, builds a signed APK and creates review artifacts. It cannot publish a release. Missing production signing fails the release build rather than using debug signing. Publishing requires separate approval.

Final implementation commit tested by CI: `5aca595`.

Successful final-code build: https://github.com/Zeerooo-dev/JANITRA/actions/runs/39257961162

The earlier baseline build also succeeded: https://github.com/Zeerooo-dev/JANITRA/actions/runs/39255750535

## Verified results

- **198 Flutter tests passed**, including startup, semantic ordering, progress, network/storage failures, secure redirects, concurrency, Later preserving navigation, permission denial, installer retry, process-restart confirmation and cancellation races.
- **9 native APK-verifier tests passed**, including checksum/size/package/version mismatch, downgrade/reinstall rejection, signer mismatch and modified APK content even with a recomputed checksum.
- **2 release-tool tests passed** for tag/build validation.
- Flutter analysis: no errors or warnings. One existing informational lint remains in `lib/features/work/personal_schedule_page.dart:151`.
- Production APK built and its certificate/package/version verified. GitHub Actions signed-build workflow succeeded for the implementation commit.
- Physical Nothing A065, Android 16/API 36, using only isolated package `com.example.janitra.updatertest`: valid signed APK accepted; 5 unsafe checks rejected; real public GitHub feed checked; Later preserved the screen; real progress captured at 30% / 13.8 MiB of 44.6 MiB; native installation permission denied/granted; native installer confirmation opened directly; Cancel returned to the test screen.
- Simulated process loss during Android permission settings restored the existing verified APK as Install update without downloading again. A new explicit tap opened the installer. Android's visible Update button was confirmed; the isolated package advanced from `1.0.0+26` to `1.1.0+27`. A previous completed fixture update displayed its retained saved-data marker.
- The real `com.example.janitra` installation remained Build 25. No real account was used for test fixtures. No Supabase infrastructure or accounts were modified.

## Important first-install signing boundary

Existing Build 25 uses debug certificate SHA-256:

`a812ea37a8d03d2565864ff0b012357b635b578f2da0730add4450f520d71219`

Build 26 production certificate SHA-256:

`6b5614d841d5859b7f69d251012b1c98d565267901db8de9779a70c34f76c660`

The standard production APK **cannot directly update the old debug-signed installation**. Do not uninstall JANITRA automatically or discard unsynchronized drafts.

A separate Android 9+ one-time signing-transition APK was prepared using Android's proof-of-rotation mechanism. Its V3 signature verifies for API 28+, and the legacy certificate was checked against the phone's installed JANITRA. **That signing transition itself has not been installed/tested on the phone.** It is supplied separately as an unverified transition artifact, not a published normal update. Existing account/session retention across that transition is therefore not claimed as physically verified. Android 7/8 cannot use this V3-only bridge; a one-time reinstall requires synchronization first and removes local-only data and the local login session.

Normal future production-key updates preserve app data through Android's standard in-place installation. Never lose or replace the production private key without a separately reviewed rotation plan.

## Modified files

- `lib/app.dart`; new `lib/features/updates/release_version.dart`, `apk_updater.dart`, `update_prompt.dart`.
- `android/app/build.gradle.kts`, `android/app/src/main/AndroidManifest.xml`, `android/app/src/main/kotlin/com/example/janitra/MainActivity.kt`; new `UpdateChannel.kt`, `ApkUpdateVerifier.kt`, `android/app/src/main/res/xml/update_paths.xml`, and native verifier tests.
- `.gitignore`, `android/.gitignore`, `pubspec.yaml`, `.github/workflows/android-release.yml`.
- `test/apk_updater_test.dart`, `test/update_prompt_test.dart`, `test/support/update_fixtures.dart`.
- `tool/android_release.py`, `test_android_release.py`, `check_source_secrets.py`, `build_updater_smoke.py`, `updater_smoke.dart`, `updater_smoke_target.dart`, `create_signing_transition.py`.
- `README.md`, `docs/ANDROID-UPDATER.md`, `docs/releases/v1.0.0.md`, this report and `anti-slop/audit-027-2026-10-19.md`.

## Artifacts

- `JANITRA-Build26-GitHub-Updater.apk`: standard production-key APK, Android 7+ for fresh installs or existing production-key installations.
- `JANITRA-Build26-Android9-Transition-UNVERIFIED.apk`: separate V3-only initial key transition for compatible old installations; physical acceptance pending.
- `JANITRA-Build26-GitHub-Updater-Source.zip`: complete tracked source, excluding private/local files.
- `JANITRA-Build26-GitHub-Updater-Changes.md`: this report.

Standard APK SHA-256: `8360b32fb911b5cea0cb391ac538886cbf3a272e7eccb0307423d740b3011184`

Transition APK SHA-256: `b1d2b054db8c275b7a8f2b119dce34ec43f643f94041319cd96235ed8325c3fb`

Remaining: physical signing-transition and encrypted-session-retention acceptance, older Android/OEM coverage, and a real published GitHub-release download/install after publication approval. Current production Releases list is empty, so no update is offered until a newer approved stable version is published.
