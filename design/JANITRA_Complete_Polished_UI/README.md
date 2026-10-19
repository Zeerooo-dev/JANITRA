# JANITRA — Remaining 10 Screen UI Polish

This ZIP contains **editable offline HTML/CSS/JS prototypes**, not Flutter or a live Supabase application.

## Screens
- Personnel Directory: `janitra_personnel_directory/code.html`
- Add Personnel: `janitra_add_personnel/code.html`
- Personnel Profile: `janitra_personnel_profile/code.html`
- Work Schedule: `janitra_work_schedule_overview/code.html`
- Edit Work Schedule: `janitra_edit_work_schedule/code.html`
- Assign Cleaning Task: `janitra_assign_cleaning_tasks/code.html`
- Approval Deadlines: `janitra_approval_deadline_settings/code.html`
- Override Locked Work: `janitra_override_locked_work/code.html`
- Reports Dashboard: `janitra_reports_dashboard/code.html`
- Report Preview & Export: `janitra_report_preview_export/code.html`

## Design refinements
- One task per screen; no repeated audit/security panels.
- Visible full employee/agency names instead of cut-off labels.
- Consistent system sans-serif typography, 16px body, 48-56px touch targets, strong contrast.
- Schedule overview focuses on shifts; editor permits weekdays, multiple shifts, and an effective date.
- Fixed Saturday deadline remains Monday 12:00 PM Philippine time; the weekday/Sunday selectors are separate.
- Override uses a required reason and new deadline; old deadline is displayed.
- Reporting summary has four essential metrics; detailed table is behind `View Full Report`.
- PDF and XLSX export remain future backend features; prototype buttons clearly explain they are not connected.
- Links connect the related prototypes and simple form interactions are demonstrable.

## Using the prototype
Run any local static server in this folder and open `index.html`. No Tailwind CDN or remote assets are required.

## Important
- Supervisor/Personnel are the only application roles. Employee and supervisor PINs are exactly four digits.
- Employee PIN validation creates `Pending Approval`; Supervisor PIN confirmation and final approval remain separate actions.
- These 10 screens do not implement PIN verification, real account invitations, scheduling writes, report exports, or RLS. Codex must implement them using Flutter + Supabase.
- The source ZIP screenshots are preserved as `reference-original.png` inside each screen folder for before/after comparison.
