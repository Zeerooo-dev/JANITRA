# Privacy Policy content verification

Reviewed October 27, 2026 against the existing Flutter application, migrations and Edge Functions. The user supplied the policy draft and confirmed **Zeerooo-dev** as their independent developer/operator name. They subsequently withdrew their personal email from the policy and left a replacement public contact undecided. Their Supervisors already know how to contact them; section 10 describes existing workplace contact arrangements without inventing an address or form. Application-record disposal criteria remain **not decided**.

## Verified disclosures and corrections

| Topic | Evidence and resulting policy wording |
| --- | --- |
| Account/work data | `workspace_access.dart`, People/account forms, work repositories and migrations: identifiers, name, username/optional email, account status, role and assignment history; task/checklist, deadline, verification, approval/rejection, remarks, notifications and audit records. |
| Role access | `WorkspaceAccess`, Admin-role and Company-Wide Supervisor migrations: Admin is system-wide; Company-Wide Supervisors operate across agencies; Site-Specific Supervisors are limited to authorized sites. Personnel see personal assigned work. The draft's generic agency-only Supervisor sentence was corrected. |
| Auth and two-step verification | `main.dart`, `secure_auth_storage.dart`, MFA page and `personnel-auth`: Supabase sessions/password handling, username mapping, setup/recovery codes, secure session storage and authenticator enrollment/challenges. No promise that passwords/PINs never traverse verification services. |
| PINs | Protected credential tables and `manage-pins`/`workflow`: server verification credentials and guarded task transitions, not manager-readable permanent PINs/passwords. |
| Offline | `local_work_store.dart`, `offline_access.dart`, `work_repository.dart`: AES-GCM work snapshots/drafts; session-bound cache access limited to the earlier of session expiry or eight hours; online official submission/PIN/approval. The access limit is not an automatic erasure deadline. |
| Local retention | `LocalWorkStore.seal` preserves draft buckets and the secure-storage key. Confirmed loss of offline access attempts to remove non-draft snapshots. Sign-out ends access but is not complete erasure. The supplied draft did not disclose this distinction. |
| Reports | `reports_page.dart` saves PDF/XLSX files in application documents and invokes platform sharing. Exports are outside the encrypted draft store and not purged by work-cache cleanup. Recipient copies cannot be recalled. No separate client-representative application role exists. |
| Deletion | `20261018140000_admin_roles.sql`, later scope migrations and `manage-users`: Auth/session/identity/PIN/setup removal, disabled assignments, profile name replaced with `Deleted account`; work, approvals, audit/security history remain. Historical names may remain in snapshots. This is not full anonymization or an all-record erase. |
| Supabase/storage | App source uses Auth, PostgreSQL and Edge Functions; no Supabase Storage bucket upload calls found. Read-only Management API checks confirm `ap-northeast-1` (Tokyo, Japan), Gmail SMTP, Free plan, one-day diagnostic-log entitlement, disabled managed-backup retention entitlement, no listed backups, PITR disabled and zero log drains. See the precise evidence below. No user records were queried or changed; no secret values were printed or saved. |
| Other providers | Gmail transactional delivery; GitHub Releases update checks/downloads and proposed GitHub Pages hosting; Android installation/secure storage/sharing and the user's authenticator application. Provider request data is distinguished from intentional workforce-record sharing. |
| Device collection | No advertising/analytics/crash-reporting SDK or camera/microphone/contact/GPS permission found in current app source/manifest. Entered workplace locations are not live GPS. Provider technical logs are disclosed separately. |
| Law/rights | Draft rights checked against the National Privacy Commission's Data Subject Rights and Data Privacy Act IRR. Rights remain subject to applicable law and limits; no blanket consent checkbox or certification/compliance claim was added. |

## Operator decisions and remaining gaps

1. **Retention schedule:** active/inactive accounts, tasks, reports and application audit/security history have no confirmed operator-approved disposal schedule or criteria. These database records do not expire with Supabase diagnostic logs. No numeric period was invented and no automatic deletion job was added.
2. **Controller identity and responsibility:** the user confirms they operate independently as Zeerooo-dev; no separate company or team is claimed. This does not determine each participating employer/agency's legal responsibilities or establish processor agreements. Those arrangements remain outside this technical verification.
3. **Rights/erasure operations and public contact:** the personal email has been removed from the app policy, HTML and current policy reports at the user's request. A replacement public inquiry channel is undecided. Workplace contacts are described as the user supplied them; their accessibility and request handling have not been independently tested. The app has no self-service privacy-request or selective historical-data-erasure workflow. Ordinary account deletion cannot promise complete erasure under every applicable request. The user confirmed GitHub-only distribution, with no Google Play publication planned; Google Play contact requirements are not a gate for this GitHub release. This is not a claim that all applicable privacy obligations are satisfied.
4. **Provider retention and transfers:** current Supabase backup/log entitlements and availability are verified below. They do not establish complete provider-internal erasure deadlines, external copies, Gmail delivery-log retention, all processing countries or contractual safeguards. No fixed backup-expiry promise is made.
5. **Publication and phone acceptance:** on October 27, 2026, the owner confirmed physical-phone testing and approved GitHub publication of 1.0.2+29. This is user-reported acceptance; no device model or additional test steps are inferred. The policy's effective and updated dates are October 27, 2026. The HTML accompanies the GitHub release; the optional Pages site remains unactivated. No Terms of Service, consent gate, backend deployment or production data change is included.

## Official references

- [NPC data-subject rights](https://privacy.gov.ph/data-subject-rights/)
- [NPC Data Privacy Act implementing rules](https://privacy.gov.ph/implementing-rules-regulations-data-privacy-act-2012/)
- [NPC erasure/blocking guidance](https://privacy.gov.ph/right-to-erasure-or-blocking/)
- [Google Play User Data policy](https://support.google.com/googleplay/android-developer/answer/10144311?hl=en)
- [Google Play account-deletion requirements](https://support.google.com/googleplay/android-developer/answer/13327111)
- [Supabase regions](https://supabase.com/docs/guides/platform/regions)
- [Supabase backup availability and plan differences](https://supabase.com/docs/guides/platform/backups)
- [Supabase logs and plan-dependent retention](https://supabase.com/docs/guides/observability/logs)
- [Supabase pricing](https://supabase.com/pricing)
- [Management API organization entitlements](https://supabase.com/docs/reference/api/v1-get-organization-entitlements)
- [Management API backup listing](https://supabase.com/docs/reference/api/v1-list-all-backups)

## Read-only Supabase verification on October 27, 2026

Target: existing JANITRA project `pvjvgylzuhpskkrppyng`. The saved CLI login was used only in memory for authenticated HTTPS GET requests. No passwords, tokens, recipient addresses, user records, log messages or backup contents were printed or saved.

| Check | Observed value | Meaning and limit |
| --- | --- | --- |
| Project | `ACTIVE_HEALTHY`, `ap-northeast-1` | Primary database region Tokyo, Japan. Does not locate every provider operation. |
| Organization plan | `free` | Actual current plan, rather than an assumed pricing default. |
| `log.retention_days` entitlement | enabled, `value: 1`, `unit: days`, not unlimited | One-day diagnostic-log retention entitlement. Not an expiry for JANITRA task/audit tables or all provider-held copies. |
| `backup.retention_days` entitlement | no access, disabled, `value: 0` | No enabled managed-backup retention entitlement. Zero does not prove immediate deletion of every provider copy. |
| Backup listing | `backups: []`, `physical_backup_data: {}` | No customer-visible restore points were listed at verification. No backup was downloaded. |
| Backup flags | `walg_enabled: true`, `pitr_enabled: false` | WAL-G infrastructure flag is present, but PITR is disabled. The infrastructure flag alone does not establish accessible backups or a recovery guarantee. |
| `backup.schedule` entitlement | disabled | No enabled backup-scheduling entitlement. |
| Log drains | zero configured; entitlement disabled | No configured export through Supabase log drains. Does not rule out manual exports outside this review. |

Only project metadata, organization plan/entitlements, backup metadata and log-drain configuration were read. No database SQL, restore, export, paid upgrade, retention mutation, account change or deployment was performed. Supabase recommends off-site exports for Free projects; no new backup containing workforce data was created by this check. Record recovery remains an operational risk until an approved backup and restoration process exists.

This is a source-to-policy verification record, not a legal compliance certification.
