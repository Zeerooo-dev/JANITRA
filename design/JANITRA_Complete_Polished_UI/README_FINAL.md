# JANITRA: Historical first-batch notes

This document describes the earlier 13-screen batch. The current archive contains 23 screens; use README_HANDOFF.md for the complete inventory.

This is a polished **HTML/Tailwind design prototype**, not a functioning Flutter app and not a connected Supabase backend. These are editable source screens.

## What was changed
- Preserved JANITRA branding, muted navy colors, and the original overall screen layouts.
- Added shared accessibility and color cleanup rules in `assets/janitra-polish.css`.
- Removed duplicate notices and secondary panels from the supervisor review queue, verification, employee PIN management, and locked task screens.
- Removed the extra photo-evidence block from the locked-work primary screen (it can be viewed in a separate details screen in production).
- Corrected payroll terminology to cleaning-work approval.
- Corrected supervisor PIN preview validation to **exactly four digits** and ensured the employee PIN field is initially empty.
- Employee completion workflow in prototype: Task Details → Confirm Completion → Employee PIN → Pending Approval.
- Supervisor workflow in prototype: Review Queue → Supervisor PIN → Separate Final Decision.
- Preserved large employee PIN keypad and simple personnel screens.
- Simplified locked-work content and added required reason + deadline controls to the override UI.
- Added a clickable `index.html` screen launcher and per-screen refreshed visual previews.
- Fixed misleading payroll and security language where present in the uploaded files.

## How to view
Open `index.html` from a local HTTP server for clickable access to the screens. Individual screens are in `<screen-name>/code.html`. The Tailwind styles are now bundled locally in `assets/tailwind-offline.css`, so layouts can render without a network connection. Google Fonts/Material Symbols links remain as optional external resources for exact icon typography. On a fully offline computer, icon glyphs may fall back to text.

## Important limitations
- Prototype buttons and modal effects are **not** Supabase-authenticated, and demo PIN entry does not verify real credentials. Never use real PINs in the preview.
- The original batch had 13 screen designs. Scheduling, Reports, Deadline Settings, and Override Form sources are now included in the complete 23-screen archive.
- Source `screen.png` images included in the original ZIP were renamed to `reference-original.png` for clarity. New `preview-polished.png` images are generated from the edited HTML using substitute icon glyphs in the local renderer; the actual HTML uses Material Symbols when available.
- Codex should implement proper routing, backend-backed actions, authorization, immutable audit history, and security in Flutter rather than treating the HTML scripts as a secure app.

## Critical business rules
Exactly two application roles: Supervisor and Personnel. Both employee and supervisor PINs are exactly 4 digits. Successful employee PIN confirmation creates a Pending Approval submission; supervisor PIN verification and final Approve/Reject decisions are separate server-recorded actions. Saturday work review deadline is the following Monday at 12:00 PM Asia/Manila, with authorized supervisor overrides requiring justification.
