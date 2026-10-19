# JANITRA phone test guide

For current testing install `janitra-ui-build8.apk`. Supervisor navigation is Home, Tasks, Team, Reports. The header building button opens Workplaces; initials opens Profile. Employee navigation remains Home, My Tasks, Profile. Workflow checks below remain applicable. See [UI notes](BUILD-8-UI-2026-10-13.md).

This is the complete workflow test build, version 1.0.0+7. The app uses the connected JANITRA Supabase project. Automated checks are complete; the new workflows still need your physical-phone check. No real invitation was sent during development. Use consenting test accounts and workplace names you recognize.

## Install and resume

Install `janitra-all-workflows.apk` over the previous JANITRA build. It keeps the existing application ID and signing certificate. Do not uninstall to update: uninstalling removes local drafts. The optimized APK uses development signing for compatibility; it is not a Play Store release.

- Sign in with your existing Supervisor account. Do not reinvite it.
- Open Profile or a detail screen, switch to Messenger, and return several times. Your tab and navigation should remain. A background access check must not briefly replace verified access with Account connected.
- With airplane mode on, protected online access must close when revalidation cannot establish safety. Previously verified Personnel can open only their own encrypted saved work while the matching session remains unexpired. Supervisor organization data has no offline access path.

## Team and agency assignment

1. In Workplaces, create your client company and workplace if needed.
2. Open Manage People, invite a consenting Personnel account, select the workplace and confirm your own account password. The recipient opens the invitation and chooses their password before entering their workspace.
3. Check that Personnel sees Home, My Tasks and Profile, with their assigned workplaces. They can change their name, but cannot edit their agency or assign roles.
4. Set their Employee PIN from Manage People. A PIN must contain exactly four digits; leading zeros work. Confirm your own account password. Keep PINs and passwords out of chat and screenshots.
5. Manage Your Supervisor PIN in your Profile. This is separate from an Employee PIN.
6. Suspend a test Personnel assignment. It must lose authorization and future unsubmitted work there must be cancelled. Reactivate it and check that active future schedules return.
7. To test an agency change, first create or obtain agency-wide Supervisor authority in the destination agency, then create its client company and workplace. Select Change Agency for the active Personnel, choose the destination and workplace, give the reason, and confirm your password.
8. Old submitted/approved work must stay in the original agency. The old assignment is marked Transferred and cannot be reactivated with the old button. New access is only to the authorized destination. The employee can view their own old work and My Agency History. Transferring back requires the same authorized transfer flow.

Only an agency-wide Supervisor controlling both source and destination can transfer Personnel. A site-only Supervisor cannot transfer somebody to another employer. There is no Admin role or unrestricted employee agency editor.

## Schedules and cleaning

In Workplaces, open Schedules & Activities:

1. Add a cleaning activity with its workplace, location and instructions.
2. Add a Personnel work schedule, working days, dates, and shifts such as `07:00-12:00` and `16:00-20:00` on separate lines. Breaks fit inside a shift; overlapping work shifts are rejected. For overnight shifts, enter an end time earlier than the start; after-midnight breaks are recognized within that overnight shift.
3. Schedule Cleaning for the person and activity. Choose the matching work schedule to exclude breaks and gaps. Use the same first/last date for one-time work. Repeating work takes an interval in minutes, such as 30 or 60, with a last time.
4. Check Today/My Tasks on the Personnel account. Future occurrences are generated through 14 days ahead, with a daily extension. Cleanings linked to a work schedule must not fall in a break or outside a work segment.
5. Use Holiday, Substitute or Changed Time for a particular date. Substitutes must already be authorized Personnel at the same workplace. Submitted history must remain intact when future schedules change.
6. Edit enabled/paused settings to stop future work without deleting history. Check the visible exception and deadline settings.

All displayed times are Manila time; backend timestamps are UTC. Saturday review deadlines are always the following Monday at 12 noon Manila time. Other weekdays default to 24 hours after scheduled time and can be configured from 1 to 168 hours. Changing a deadline policy affects future unsubmitted occurrences, preserving submitted records' original deadlines.

## Submission, confirmation and final approval

1. Personnel opens a due task, optionally adds remarks, selects Mark as Done, and enters the Employee PIN on the keypad. A future task cannot be submitted early.
2. A successful server response shows Pending Approval, an official submission time, and an Employee confirmation event. Wrong PIN must not submit work. Five wrong attempts lock the PIN for 15 minutes across tasks; repeated network delivery of the same request must not count as another attempt.
3. Supervisor opens Review Work, chooses Needs Confirmation, opens the record, and uses Confirm Work with their Supervisor PIN.
4. The task must remain Pending Approval and show Supervisor Verified. PIN verification alone must not approve it.
5. Use the separate Final Work Approval button, or Reject Work with a reason. The final actor/time/outcome must appear in work history and the Personnel view.
6. On two devices, refresh the same task and try conflicting review actions. Only the operation matching the latest task version/state may succeed. Refresh shows the accepted result.
7. Check Notifications on both accounts and View Work History on the task. Notifications are stored in-app; they are not Android push messages or email alerts.

## Deadlines and reopening

At the exact review cutoff, pending work becomes Locked, not reviewed. The server enforces this even if the scheduled job has not yet updated its stored status. Unsubmitted work after its deadline is shown as Not submitted and cannot be submitted late.

For submitted locked work, use Reopen Locked Work, give a justification of at least 10 characters, choose a future deadline within seven days, and confirm your account password plus configured two-step verification. The original deadline and previous lock/verification history remain. The new review cycle needs another Supervisor PIN confirmation and a separate final decision. A past deadline, empty justification or stale version must fail.

Use a dedicated short-deadline test schedule or wait for its real deadline; changing the phone clock must not change authorization. Do not change production records from the dashboard just to simulate deadlines.

## Offline drafts and reconnection

- Personnel opens My Work Schedule to download their personal schedules, and My Tasks to download personal task records.
- Use Save Offline Draft for remarks. It must say Saved Offline, not Pending Approval. Offline work contains no PIN/password/raw session token.
- Disconnect, open Saved Offline Work, edit a personal draft, close and reopen the app while the previously verified session is still unexpired. Only the sealed, matching identity can read it. A different account, expired session, or confirmed suspension/revocation cannot open protected work.
- Reconnect, refresh the task, then Mark as Done and enter the PIN. No approval or PIN verification happens offline. Unchanged retries keep the same request ID; changed remarks or task versions get a new binding. Stale/cancelled/locked tasks must refuse submission and retain the local draft for review.
- Check wrong PIN, reconnect after a delayed response, and repeated taps. Success must produce one submission/history entry, not duplicates.
- Discard Draft removes only the local draft. Uninstalling or clearing Android app storage removes saved drafts; signing out retains encrypted per-account drafts but removes the authorization proof.

## Reports

In Workplaces, open Work Reports. Choose Weekly, Monthly or Custom, then PDF or XLSX. Set dates and optional workplace, Personnel, Supervisor and status filters. The source is an authorized server snapshot; no filter can widen your workplace scope.

- Check actual counts against known test tasks, including Approved, Rejected, Pending, Locked and Not submitted.
- Distinguish claimed completion, official submission/Employee confirmation, Supervisor verification and final decision times.
- PDF is landscape A4 with repeating headers, page numbers, status colors and full detailed notes for lengthy remarks/reasons.
- XLSX has Summary, Daily Work Records, Employee Confirmations, Supervisor Approvals, and Pending & Locked Tasks. Headers are frozen; text wraps and formula-like remarks remain text.
- Check empty reports, wrong date order, slow connections, share-sheet cancellation and opening the shared file in your chosen app. Large reports ask for a narrower period/filter rather than silently dropping rows (maximum one-year period, 10,000 records and 4 MB source snapshot).

## Account safety

Check two-step setup/login and password recovery using `janitra://auth-callback/`. Switching away clears typed task PINs/passwords in the new work forms. Do not send a code/password/PIN to the developer. For suspension/session expiry/revocation tests, use dedicated test accounts; never suspend or reset the first Supervisor.

Record each failure as: account role, screen/button, expected behavior, actual behavior, connection state, and approximate Manila time. Screenshots should hide credentials. Native invitation delivery, recovery links, SQLite/Android keystore persistence and share-sheet round trips require this phone check; the automated backend fixture does not certify them.
