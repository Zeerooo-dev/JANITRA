# Privacy Policy content verification

Reviewed October 27, 2026 against the existing Flutter application, migrations and Edge Functions. The user supplied the policy draft and confirmed **Zeerooo-dev** as the public developer name and **jeffirie12@gmail.com** as the public privacy/account-deletion contact. The contact was not inferred from SMTP credentials. Retention periods are explicitly **not decided**.

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
| Supabase/storage | App source uses Auth, PostgreSQL and Edge Functions; no Supabase Storage bucket upload calls found. A read-only Management API check selected only this project's region and SMTP hostname: `ap-northeast-1` (Tokyo, Japan), `smtp.gmail.com`. No user records were queried or changed; no secret values were printed or saved. |
| Other providers | Gmail transactional delivery; GitHub Releases update checks/downloads and proposed GitHub Pages hosting; Android installation/secure storage/sharing and the user's authenticator application. Provider request data is distinguished from intentional workforce-record sharing. |
| Device collection | No advertising/analytics/crash-reporting SDK or camera/microphone/contact/GPS permission found in current app source/manifest. Entered workplace locations are not live GPS. Provider technical logs are disclosed separately. |
| Law/rights | Draft rights checked against the National Privacy Commission's Data Subject Rights and Data Privacy Act IRR. Rights remain subject to applicable law and limits; no blanket consent checkbox or certification/compliance claim was added. |

## Operator decisions and remaining gaps

1. **Retention schedule:** active/inactive accounts, tasks, reports, audit/security history and provider backups/logs have no confirmed operator-approved disposal schedule. No numeric period was invented. The policy discloses current behavior and request criteria; a policy document does not add automatic deletion jobs.
2. **Controller identity and responsibility:** Zeerooo-dev is the user-approved public developer name, not a verified registered company. Which legal person/employer/agency is the personal information controller for each deployment, and the appropriate contractual basis and processor agreements, need operator confirmation. The draft's broad contractual-safeguard assurances were not copied as verified facts.
3. **Rights/erasure operations:** the app has no self-service privacy-request or selective historical-data-erasure workflow. A verified public email starts a manual request. Ordinary account deletion is not sufficient to promise complete erasure under every applicable request. Do not label the app Play-compliant solely because this policy is present.
4. **Provider retention and transfers:** the primary region and SMTP provider are verified; exact backup/log retention, other processing countries and contractual safeguards are not established by source inspection. No fixed backup-expiry promise is made.
5. **Publication:** HTML is prepared locally, not hosted. The proposed Pages URL must be activated and checked after approval. Dates are October 27, 2026; review them at publication. No Terms of Service, consent gate, backend deployment or production data change is included.

## Official references

- [NPC data-subject rights](https://privacy.gov.ph/data-subject-rights/)
- [NPC Data Privacy Act implementing rules](https://privacy.gov.ph/implementing-rules-regulations-data-privacy-act-2012/)
- [NPC erasure/blocking guidance](https://privacy.gov.ph/right-to-erasure-or-blocking/)
- [Google Play User Data policy](https://support.google.com/googleplay/android-developer/answer/10144311?hl=en)
- [Google Play account-deletion requirements](https://support.google.com/googleplay/android-developer/answer/13327111)
- [Supabase regions](https://supabase.com/docs/guides/platform/regions)

This is a source-to-policy verification record, not a legal compliance certification.
