# JANITRA — Complete Polished Screen Handoff

**23 source screens: 13 previously polished + 10 newly polished.** Source is editable HTML/CSS/JavaScript for visual reference, NOT Flutter and NOT a connected Supabase system.

## What changed in the latest batch
- Personnel directory: full names and simpler list/search.
- Personnel invitation: clear form without onboarding marketing/security panels.
- Personnel profile: simple information and 3 management actions.
- Schedule overview: only active weekdays, morning/afternoon shift and main actions.
- Edit schedule: explicit weekdays, two shifts, add shift, effective date, no compliance claims.
- Assign task: activity, weekday buttons, two time fields, save.
- Deadline settings: weekday selector, fixed Saturday Monday 12 PM, optional Sunday rule.
- Lock override: work summary, required reason + extended deadline, no repeated warnings.
- Reports: weekly/monthly/custom, minimal filters, four summary counts.
- Report preview/export: a compact summary; full details behind View Full Report, with PDF / XLSX buttons.

## Opening
Start a local static server in this directory, then open `index.html` to access all 23 screens. The 10 new screens use local `assets/janitra-remaining.css` and `assets/janitra-remaining.js`, no internet dependency. Earlier 13 screens use the existing local Tailwind build.

## Critical requirements for Codex
- JANITRA is Flutter (Android) + Supabase, two roles only: Supervisor and Personnel.
- Both Employee and Supervisor PINs are **exactly 4 digits**.
- Employee PIN-confirmed task becomes Pending Approval; Supervisor PIN confirmation and final decision remain separate server-recorded operations.
- Saturday review closes Monday at 12:00 PM Asia/Manila; other workdays configurable; supervisor override requires reason and audit history.
- Reports are styled navy/white PDF and XLSX documents; HTML buttons currently show honest design-preview notices, and MUST be implemented securely in Flutter/Supabase.
- Long employee names wrap, controls at least 48px, high contrast, calm spacing and minimal badges.

## Limitations
- None of the HTML screens performs real account invites, scheduling writes, PIN checking, database updates, or report generation.
- Newer `preview-polished.png` images show the edited 10 HTML screens; `reference-original.png` files show their pre-edit Stitch screenshots.
- Some cross-screen navigation in earlier exported Stitch screens may need actual Flutter routing; this is a design library, not a fully wired web app.
