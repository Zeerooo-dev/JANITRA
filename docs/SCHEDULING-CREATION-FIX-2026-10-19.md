# JANITRA Build 24: Work shift and cleaning schedule creation

## Problem and verified cause

Admin and Supervisor users reported that they could not add work shifts or cleaning schedules. Read-only production inspection found:

| Manpower company | Active Personnel | Enabled activities | Work shifts | Cleaning schedules |
|---|---:|---:|---:|---:|
| Cleaners | 0 | 3 | 0 | 0 |
| LSERVE Corp. | 1 | 0 | 0 | 0 |

The previous scheduling screen silently inherited the parent workspace's company and offered no company switcher. Its Add buttons were disabled when that company lacked active Personnel or activities. Consequently, someone viewing Cleaners could see activities but could not schedule its transferred Personnel; LSERVE had Personnel but no activity to schedule. A cleaning activity must belong to the same workplace as the assigned Personnel. This is an assignment/prerequisite distinction, not a reason to bypass authorization or reactivate transferred assignments.

The live migration ledger ends at `20261019043557`, so the approved Build 23 Company-Wide permissions are already active. No backend changes are needed for this fix.

## Changes

- Added the existing manpower-company dropdown pattern directly to **Schedules & activities**. Admin and Company-Wide Supervisors can choose any currently authorized company without leaving this page. A single-company/Site-Specific account sees its company label and keeps its existing scope.
- Switching companies reloads that company's workplaces, activities, shifts, schedules and eligible Personnel. Saves use the selected company's actual agency and workplace IDs; switching does not change the Supervisor's assignment or permissions.
- Personnel choices require an active Personnel assignment in a workplace the current account manages. Inactive, transferred, privileged-role and unavailable-workplace entries cannot be selected as active Personnel.
- New cleaning schedules offer Personnel only when an enabled activity exists at their workplace. Activity and optional work-shift dropdowns remain bound to that selected person/workplace. A work shift remains optional for cleaning schedules.
- Replaced ambiguous disabled-button states with company-specific instructions: add Personnel in Team, select another company, create an enabled activity at the Personnel workplace, or add a workplace first.
- Added refresh version checks so an older asynchronous load cannot overwrite a newer company selection. Failed saves remain editable and do not appear successful. Cancel and invalid submissions cause no save or refresh.
- Preserved the existing forms, dates/time pickers, recurring days, shift/break parsing, delete confirmations, immutable work history, PIN verification, approvals, deadline enforcement, reports, offline features, appearance and app lifecycle behavior.

## How to test on the phone

1. Install Build 24 and open **Schedules & activities**.
2. Select **LSERVE Corp.** in **Manpower company**. Its active Personnel should be available for **Work shifts → Add**.
3. Create an enabled cleaning activity at that Personnel's LSERVE workplace. Then use **Cleaning schedules → Add**, choose the Personnel and activity, and optionally link the work shift.
4. For **Cleaners**, assign active Personnel to an authorized workplace in that company through Team before creating their shifts/schedules. Transferred assignment history remains historical; the app does not silently restore it or move Personnel/activities between companies.
5. Check the created records, cancel an unused form, and confirm a Site-Specific Supervisor cannot select another company's Personnel.

## Verification

- **160/160 Flutter tests passed.** Six new focused tests cover actual form creation and reloading as Admin and Company-Wide Supervisor; correct selected-company/Personnel/workplace payloads; dependent activity and optional shift choices; Site-Specific creation within scope and exclusion of foreign companies/Personnel; empty submission/cancel without requests or loading; rejected saves retaining the form and successful retry; and 320px/200% text layout. Existing lifecycle, auth, PIN, deletion, scheduling, offline, reporting, appearance and visual regressions passed.
- **433 local PostgreSQL PASS checks**, including current scheduling and authorization regressions. The production schema/functions were not modified. Tests used the existing disposable, network-isolated database fixture and did not write production records.
- Flutter analysis: no errors or warnings; one existing informational `use_null_aware_elements` lint remains at `lib/features/work/personal_schedule_page.dart:151`.
- Rendered and inspected the new 320px/200% text scheduling screenshot. Existing screenshot baselines were unchanged.
- All Supabase migrations, Edge Function files and `pubspec.lock` byte-match the deployed Build 23 source archive. No dependency, secret, database, account, assignment or production configuration change was made.
- Android release built successfully as `1.0.0+24`, package `com.example.janitra`, minimum SDK 24, target SDK 36. APK signature verifies with the existing JANITRA Android debug certificate.
- After-mode review: `anti-slop/audit-025-2026-10-19.md`.

## Modified files since Build 23

- `lib/features/work/scheduling_page.dart` — company context/switching, eligible choices, prerequisites and load version checks.
- `test/scheduling_creation_test.dart` — six focused regressions.
- `test/fixtures/workspace_backend.dart` — return stored shift/schedule fixture rows so creation/reload tests verify visible saved records.
- `test/goldens/scheduling-company-large-text.png` — new visual reference.
- `pubspec.yaml` — build 24 only; dependencies and lockfile unchanged.
- This report and `anti-slop/audit-025-2026-10-19.md`.

## Deliverables and limitations

- APK: `build/app/outputs/flutter-apk/janitra-build24-scheduling-fix.apk`.
- APK SHA-256: `60185aebefecb63470446c488dabbf99155e2a23cfc7dbcbf05095b480fb3a1c`.
- Source: `JANITRA-Build24-Scheduling-Fix-Source.zip`, root `JANITRA-Build24-Scheduling-Fix-Source/janitra/`.
- Changes: `JANITRA-Build24-Scheduling-Fix-Changes.md`.

No new backend deployment is required. Physical-phone acceptance and a real signed-in production creation test remain pending. Production Personnel and activities were inspected but not created, moved or reassigned for testing. The source archive excludes runtime Supabase configuration, secrets, signing keys, generated files, caches, builds, backups and screenshot failures. Existing Android debug signing is retained for compatibility with prior JANITRA APKs.
