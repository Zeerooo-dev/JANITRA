# Background-based glass navigation refresh

Approved October 27, 2026. Replaces the existing v1.0.2 APK at the owner's explicit request; both version name and Android build number remain **1.0.2+29**. No new release tag is created or existing tag moved.

## Behavior

- Top and bottom bar fills follow the scaffold/custom background independently of the accent color. The selected navigation indicator uses a neutral foreground tint.
- The existing workspace background now paints behind the scaffold so the two navigation surfaces can blur the actual background. The header retains its layout and actions; the bottom bar is inset 16 logical pixels, rounded by 26, and keeps the existing tab labels, callbacks and semantics.
- Safe-area spacing keeps the floating bar clear of Android's gesture region. Scaffold still reserves its height, so scrollable work content is not placed underneath it.
- Blur is clipped to each bar. Dark/light opacity differs; both black and white backdrop extremes are checked against bar text before translucency is used. Unsafe custom colors fall back to the solid background. High Contrast uses solid surfaces without blur and retains 7:1 control contrast.
- Status-bar icon brightness is derived from the actual bar background, including custom colors, rather than the transparent AppBar material.

## Changed files

- `lib/core/app_theme.dart`: background-based navigation colors, neutral indicator and readable status-bar icons.
- `lib/core/aurora_glass.dart`: small shared clipped navigation surface with contrast fallback.
- `lib/features/workspace/workspace_page.dart`: background placement, transparent bar materials and floating bottom safe area.
- `test/navigation_surface_test.dart`, `test/privacy_policy_test.dart`: interaction, clipping, custom background/accent independence, normal/high contrast and safe-area bounds.
- `test/ui_reference_test.dart`: scroll the task into view before tapping at 320px/200% text; the floating bar reduces the visible list area. No task logic was changed.
- Updated affected light/dark and large-text screenshot baselines, README and release notes; visual review in `anti-slop/audit-033-2026-10-27.md`.

## Verification

All **247 Flutter tests passed** against the reviewed screenshot baselines. Analysis has no errors or warnings; the existing informational `use_null_aware_elements` note in `personal_schedule_page.dart:151` remains. Reviewed snapshots include light/dark Supervisor Home, appearance settings and 320px large-text Tasks. Tests cover background/accent combinations, contrast, clipping, navigation taps, safe-area inset and content clearance. The production release gate also requires GitHub Actions, native APK verifier tests, signer/package/version checks, exact source ZIP verification and public asset hashes before replacement.

No dependency, database, RLS, role, PIN, authentication, schedule, task, approval, offline-draft or report behavior was changed. Physical-device appearance/performance and manual installation of this refreshed APK have not been re-tested. The original release's owner-reported phone acceptance is historical, not acceptance of this refresh.

## Distribution

The refreshed APK, matching source ZIP, changes, release metadata and checksums replace the corresponding assets in the existing GitHub v1.0.2 release. The original tag remains at its original source commit. Use the attached source ZIP for this refreshed APK rather than GitHub's automatic tag archives. Same-version installations require manual download; no updater version/signature checks are weakened. Existing production-signed installs can install the same-version APK through Android without clearing app data.
