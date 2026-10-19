# Build 7 review

What this repo does: JANITRA manages scoped workforce assignments, schedules, cleaning submissions and reviews, with protected Supabase authorization. This review assumes a small team testing the complete workflow. It does not certify a public release or years of high-volume history.

Reviewed the Flutter entrypoint/authorization gate, workspace and work screens, encrypted cache, report exporters, three function paths, shared guards, all six migrations and corresponding tests. Existing HTML prototypes remain design references, not working backend pages. The audit itself changes nothing; issues found during implementation were fixed under the user's existing authorization.

## Should fix before public distribution

1. **The package still uses development signing** (`android/app/build.gradle.kts`).
   - What this is: the optimized APK uses the same development certificate as installed test builds.
   - Problem: development signing is not suitable for public store distribution; anyone with that development key can sign a matching package.
   - Fix: choose a controlled production signing/distribution plan and an explicit migration path for existing installations. Keep this test APK update-compatible.
   - If skipped: a public release remains improperly signed. This does not prevent the authorized phone test build.

2. **Native round trips still need a phone** (`docs/PHONE_TEST_GUIDE.md`).
   - What this is: fixtures test the client/SQL contracts and UI state, while production Auth callbacks, Android keystore/SQLite and native sharing run on-device.
   - Problem: no Android device was connected, so these new native paths were not exercised against actual authenticated accounts.
   - Fix: run the supplied consenting-account phone sequence, including reconnect/restart, invitations, recovery/MFA, transfers and file opening.
   - If skipped: a platform-specific failure could be missed. No native acceptance claim is made.

3. **Task history is currently downloaded before UI filtering** (`lib/features/work/work_repository.dart`, `task_page.dart`, `work_overview.dart`).
   - What this is: RLS-scoped pagination obtains all readable task rows; UI filters Today/review/history afterward.
   - Problem: a mature agency with 100 Personnel and 10 daily occurrences can accumulate roughly 365,000 rows yearly. Repeated exact counts and downloaded snapshots become slow on a phone.
   - Fix: before that scale, query dashboard counts/queues server-side and add explicit date/page loading to history. Preserve complete records and authorization rather than silently truncating.
   - If skipped: large historical deployments can load slowly or use excessive phone memory. The current batch tests use small, explicit fixtures; no large-device benchmark is claimed.

## Verified

- Employee submission, Supervisor verification and final decisions are distinct. Wrong PIN returns a rejected receipt with committed counters; one request produces one submission. Reuse after revocation is denied.
- Tasks lock at the exact backend cutoff even before the job runs. Concurrent approve/reject produces exactly one final event. Reopening preserves the original deadline/history and requires another verification cycle.
- Agency transfers require both scopes and a live session, preserve old snapshots, retire old roles and stop future old work. Old-role reactivation and stale receipt access are denied.
- The workspace lifecycle/navigation regression suite remains passing. Confirmed backend session/role failures invalidate protected access; temporary device storage writes do not delay the online dashboard.
- Encrypted per-user SQLite rejects tampering/account relocation. Offline proof requires the same unexpired identity/token fingerprint and is removed on confirmed access loss. No raw credentials appear in drafts, reports or work events.
- Public RLS, invoker view and service-only transitions were checked live. Recent scheduled-job runs succeeded. Supabase advisors reported no ERROR; existing WARN/intentional private-table INFO items are documented in the transfer.

## Anti Slop review afterward

Reading this as: a workforce Android app for Supervisors and Personnel, using the supplied calm navy/light Material design, dial ENERGY 1 / RHYTHM 1 / MOTION 1.

- Hard checks PASS for source/UI states examined: real counts and authorized records; no fabricated testimonials/statistics; every added action has a real callback; loading, empty and error states are present. No marketing copy, invented roles or dead navigation placeholders were introduced.
- Purpose checks PASS: navy identifies JANITRA and primary actions; Roboto follows the handoff; 24px spacing separates work groups; Material controls preserve platform navigation/focus; status colors distinguish actual backend results; the Personnel primary action is task completion.
- Liveliness checks PASS for the retained calm direction: explicit 1/1/1 dials, one main task/review action, structural spacing, navy accent, recurring workforce task labels and PIN pattern, and native state transitions.
- Craft checks PASS for automated surfaces: Flutter analysis is clean, both APK variants build, 320px/200% text tests cover essential existing forms and the new keypad, and distinct verification/final-approval controls were exercised. White/navy contrast is 8.77:1; dark text/light surface is 13.11:1. PDF was rendered with readable dates, colored status and repeated headers; XLSX was reopened with valid styling/frozen panes.
- R-35 native acceptance remains pending: automated click-through covers the checked paths, not every Android control/integration on a physical device. This is a reviewable development test build; the complete public UI delivery gate is not claimed approved. Follow the phone guide before release.

Best next action: phone-test build 7. There are no known failing automated checks at this checkpoint. Production signing, native acceptance and high-volume history performance remain explicit limits; no broad refactor or new notification service was added.
