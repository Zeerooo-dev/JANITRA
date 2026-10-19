# JANITRA remaining work

Current next steps, October 18, 2026: build 9 source integration, original-directory analysis, tests and debug compilation succeeded; see [the integration report](INTEGRATION-2026-10-18.md). Backend migrations/functions are local only. Before production rollout, obtain explicit deployment approval, configure the separate identity secret, validate real Auth and ingress abuse controls in an approved environment, and complete physical-device acceptance for both roles. Preserve the original Supervisor and existing PIN pepper. Notes below are historical and must not be treated as the current deployment checklist.

Updated October 13, 2026. Build 7 implements and deploys the complete workflow test build. Current checkpoint: [transfer](JANITRA_TRANSFER_2026-10-13.md), [phone guide](PHONE_TEST_GUIDE.md), [build note](BUILD-7-2026-10-13.md).

1. Install the optimized build 7 APK over the existing app and follow the phone guide: consenting invitations, first password, transfers, suspension, both PIN systems, schedules, distinct verification/final decisions, deadlines, encrypted drafts and native report sharing.
2. Check lifecycle/navigation, TOTP/recovery links, secure-storage persistence, mobile data/Wi-Fi, process restart and large text. No Android device was connected to this development run.
3. Investigate reported failures using role/action/connection state/Manila time. Keep credentials out of chat and preserve the first Supervisor, applied migrations and PIN pepper. Backend corrections require a new additive migration.
4. Before public distribution, choose production signing/distribution while preserving installed-app compatibility. The test APK retains the development certificate. Review the existing password-protection advisory without assuming a paid-plan change is authorized.

Deployment is complete: six migrations, management functions v2 and workflow v1, all with JWT verification. The minute deadline job is active and succeeded. Public tables have RLS; client/anonymous workflow execution and direct task writes are denied. No production task fixtures or new real invitations were created. CLI database-login initialization still stalls; Management API HTTPS worked with the existing OS-keyring login.

Implementation/deployment and automated checks are complete for the requested test build. Phone acceptance and production release preparation remain separate. Notifications are in-app; offline access is personal and bounded by the verified session. Reports have explicit limits and never silently truncate.
