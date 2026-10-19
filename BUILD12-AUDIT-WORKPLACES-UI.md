# JANITRA Build 12 - Audit Log and Workplaces UI Refresh

Baseline: `JANITRA-Build12-Team-Employee-PIN-UI-Source.zip`. This is a Flutter UI-only change to the latest source from the previous patch in this conversation.

## Changes

- Audit Log: date-grouped event cards with filters (All / Added / Updated / Removed), compact action summaries, human-readable Philippine timestamps, and a scrollable Before/After details sheet. Only the existing audit field allowlist is displayed; no raw JSON, passwords, tokens, or IDs are revealed.
- Workplaces: Add and Edit forms use responsive Material bottom sheets with an icon header, a name field, a client-company dropdown during Add Workplace, a read-only client-company context during Edit Workplace, inline validation, and clear action buttons.
- The name editor also serves company name and profile name editing, which now use the same consistent sheet.
- Updated existing workspace widget tests and added audit-event filtering/details coverage.

## Unchanged

- Auth/access checks, Supabase read/write requests, workplace scoping, database migrations, Edge Functions, PIN management, scheduling and task approval remain unchanged.
- Edit Workplace remains **name-only** (does not reassign a workplace to a different client company).
- Audit logging remains read-only; the patch does not change audit event creation or retention.

## Verification

- Source comparison against previous ZIP: only `records_page.dart`, `name_editor.dart`, `workspace_page.dart`, and `workspace_test.dart` changed, plus this note.
- Static delimiter consistency and ZIP integrity were checked.
- Flutter/Dart SDKs are not available in the build environment: `flutter analyze`, widget tests, and Android build **not run**. They must be run on the development machine.

## Run on your CachyOS machine

```fish
cd ~/Projects/janitra
flutter pub get
dart format lib/features/work/records_page.dart lib/features/workspace/name_editor.dart lib/features/workspace/workspace_page.dart test/workspace_test.dart
flutter analyze
flutter test test/workspace_test.dart
flutter test
flutter run
```

## Install UI-only patch

Back up your worktree before extracting. Patch paths are project-relative:

```fish
cd ~/Projects/janitra
cp -a lib ../janitra-lib-backup-(date +%Y%m%d-%H%M%S)
unzip -o ~/Downloads/JANITRA-Build12-Audit-Workplaces-UI-Only-Patch.zip -d .
```

Do not apply this patch to a substantially different JANITRA revision without reviewing the diff.
