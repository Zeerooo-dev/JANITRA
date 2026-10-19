# JANITRA Build 14: invitation rejection handling

## Confirmed cause

Live logs show the recent invite attempts on October 19 at approximately 02:10 and 02:12 Manila time were rejected by Supabase Auth with `email_address_invalid` and HTTP 400. These attempts used the address shown in the user's screenshot. It passed the application's basic email syntax check, had no whitespace and contained ASCII characters only. The exact upstream validation reason is not exposed by these logs; a syntactically valid address is not proof that the delivery service will accept it.

The previous invitation handler did not recognize that error code. It returned HTTP 502, which the client correctly treats as uncertain availability, displaying the global connection shield. Installing Build 13 did not resolve this missed server case.

## Fix

- Map `email_address_invalid` to HTTP 422 and `invitation_email_invalid` with an accurate message inside the invitation form.
- Do not invalidate verified workspace access for this request validation error.
- Continue treating real network failures, unknown server errors, expired sessions and revoked permissions through the existing fail-closed access checks.
- Leave all Admin roles, deletion/history rules, RLS, PIN protection and authentication settings unchanged.
- Version metadata is `1.0.0+14`. The server fix also works with the installed Build 13; a client update is not required for this error mapping.

## Verification

- 16 manage-users tests pass, including the actual upstream HTTP 400 error mapped to a request-level 422 without assigning access.
- Added a client regression proving the rejected invitation still throws a request error while emitting no AccessNotice and preserving the verified access policy.
- All 122 Flutter tests passed, including lifecycle, authorization, Admin roles, scheduling and offline/report regressions.
- Flutter analysis has no errors or warnings, with one unchanged informational lint in `personal_schedule_page.dart:139`.
- Release APK build completed successfully; Android package version is `1.0.0+14` and the signature verifies with the existing project certificate.

## Email-delivery blocker

The live project still has no custom SMTP provider and no send-email hook, with a two-email-per-hour limit. The user confirmed no provider is available yet. Supabase's default sender restricts recipients to project-team addresses. Configuring a provider is required for normal external invitations, independently of the incorrect connection popup.

Set up an email provider, then enter its host, port, username, password and verified sender directly in the project's Supabase Authentication / Email / SMTP settings. Keep credentials out of chat, Flutter source and source archives. Do not disable confirmation or create pre-confirmed Supervisor accounts to bypass invitation delivery.

Official guide: https://supabase.com/docs/guides/auth/auth-smtp

## Modified files

- `supabase/functions/manage-users/index.ts`
- `supabase/functions/manage-users/index_test.ts`
- `test/access_policy_test.dart`
- `pubspec.yaml`
- `docs/INVITATION-ERROR-FIX-2026-10-19.md`

## Production status

Deployed after explicit approval on October 19: manage-users ACTIVE version 9, JWT verification enabled. Verified unauthenticated requests are rejected with HTTP 401. No database migration, account modification or Auth configuration change was made. No live invitations were sent during diagnostics.

If the phone is still showing the connection shield left by the previous failed attempt, tap Retry connection once to revalidate access. Future email validation rejections remain inside the invitation form.

APK: `build/app/outputs/flutter-apk/janitra-build14-invitation-error-fix.apk`.

APK SHA-256: `9a17e1ad81fe8f2ccccc22e7be365071302ddddf55dbb57cbb9423f5c48f4e52`.
