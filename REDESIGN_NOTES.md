# JANITRA Build 8 - UI redesign pass

This is an **edited Flutter source project**, not a compiled APK. The original ZIP was not modified.

## What changed

- `lib/core/app_theme.dart`: cohesive premium navy Material 3 appearance, smaller text fields and buttons, quieter cards and navigation; shared responsive section headings and empty states.
- `lib/features/workspace/workspace_page.dart`: Workplaces reorganized into client companies, workplaces, and one compact management menu. 'Add' actions move into section headers and have descriptive accessible tooltips.
- `lib/features/workspace/people_page.dart`: streamlined member cards with per-person action menus, team counts, smaller status displays, pull-to-refresh and a responsive bottom sheet for adding a member.
- `lib/features/work/scheduling_page.dart`: compact activity, shift and cleaning schedule lists; collapsible approval settings; exception management retained.
- `lib/app.dart`: separate checking, access pending and error states; clearer retry, offline work and sign-out controls.
- `lib/features/work/work_overview.dart`: smaller metrics and review cards.
- `lib/features/work/work_form.dart` and `lib/features/workspace/name_editor.dart`: tighter, more consistent editable dialogs.
- UI test selectors for changed navigation and controls were updated where applicable.

## NOT changed

All `supabase/` migrations, Edge Functions, SQL tests, authorization rules, audit logging, PIN handling, review deadlines and offline persistence are **byte-for-byte unchanged** from the supplied ZIP. Supabase credential/session logic and Flutter backend request payloads were preserved.

**Username + password with optional email is not implemented.** The current `manage-users` Edge Function validates email and calls `inviteUserByEmail`, so making the email field optional would create broken accounts. That requires a coordinated auth/database/Edge Function migration and end-to-end tests, not a cosmetic change.

## Validation and limitations

- Executed structural source integrity checks over the 30 `lib/*.dart` files and verified the intended view components are present: passed.
- Verified all `supabase/` files match the input archive: passed.
- This environment lacks Flutter/Dart, so `flutter analyze`, `flutter test`, Android APK builds and on-device checks **could not run**. Do not treat this as production-ready without those checks.
- Previous screenshot golden baselines under `test/goldens/` still show the old UI; after visually reviewing the new screens, regenerate and review intentionally using `flutter test --update-goldens test/ui_reference_test.dart`.

## Run locally

```bash
flutter pub get
flutter analyze
flutter test test/workspace_test.dart test/widget_test.dart test/lifecycle_test.dart
flutter test test/ui_reference_test.dart --update-goldens # review resulting images before committing
flutter build apk --debug --dart-define-from-file=config/supabase.json
```

If the project uses a different private Supabase configuration setup, follow `README.md` rather than committing credentials. On a real phone, test at 320dp, large display fonts, keyboard open/closed, app resume/offline, changing assignments, PIN and approval workflows, and the new invitation bottom sheet.
