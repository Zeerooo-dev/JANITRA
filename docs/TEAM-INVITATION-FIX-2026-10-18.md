# JANITRA Team and invitation debugging

## Findings

- Transferred rows are historical role assignments. They intentionally remain visible and do not grant active access.
- The owner list includes assignments across agencies. The old heading used the selected agency and hid Supervisor scope, making distinct assignments look duplicated.
- Live Auth configuration has no custom SMTP and no email hook; the email limit is two per hour. Supabase's default sender restricts recipients to project-team addresses. External email invitations require a configured SMTP provider: https://supabase.com/docs/guides/auth/auth-smtp
- The original failed request's exact Auth error was not recovered. Restrictions and rate limits were incorrectly collapsed into HTTP 502, which the client treats as uncertain authorization.

## Changes

- Team shows “All agency assignments” for owner results, includes agency and Supervisor scope, and labels the count as assignments. No records are removed or merged.
- manage-users returns specific 422/429 errors for email recipient restrictions and rate limits. Unknown upstream failures still fail closed. Safe diagnostic logs contain only error code/status, never email, passwords or tokens.
- No database, RLS, session checks, account permissions, or email confirmation settings changed.

## Modified files

- lib/features/workspace/people_page.dart
- supabase/functions/manage-users/index.ts
- supabase/functions/manage-users/index_test.ts
- test/access_policy_test.dart
- test/personnel_account_test.dart
- test/goldens/team-empty.png
- docs/TEAM-INVITATION-FIX-2026-10-18.md

## Verification

- 115 Flutter tests passed, including lifecycle, access policy, invitation, owner controls and narrow-screen checks.
- 13 manage-users tests passed, including email restrictions/rate limits without access assignment, password/MFA checks and existing-account invitations.
- Flutter analysis: no errors or warnings; one pre-existing informational use_null_aware_elements lint in personal_schedule_page.dart:139.
- Team empty-state snapshot updated and visually inspected; existing layout and branding retained.
- manage-users deployed with explicit user approval. No invitations sent or live records changed during debugging.

## Remaining limitation

Custom SMTP still needs provider credentials and sender configuration before external email invitations can work. No provider was configured, no credentials were invented, and email verification was not bypassed. Test delivery on a physical phone after SMTP setup. Release uses the existing signing configuration and remains version 1.0.0+12.
