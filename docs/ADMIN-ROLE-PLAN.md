# Admin role integration

The Admin is one explicit global `role_assignments` row with no agency or site. Other roles retain their existing scoped rows. Shared database permission helpers give active Admins the Supervisor workflow permissions across agencies, with the same live-session checks. No existing account is promoted by the schema migration.

Only Admins invite Supervisors, replace their agency/site scopes, or suspend them. Personnel management remains scoped; global account deletion by a Supervisor requires authority over every assignment and rejects any target with Supervisor or Admin roles. Management endpoints repeat authorization inside PostgreSQL after password/MFA confirmation.

Deleting an account removes Auth access and credentials while keeping an inactive profile reference for historical task, approval and audit foreign keys. Existing history stays immutable. The old destructive erasure trigger is replaced. Deleted identities cannot be reactivated. A serialized database guard protects the last active Admin against role or profile changes.

The existing Supervisor dashboard is reused. Team hides Admins, and Admin-only Supervisor Management reuses the existing Team controls with scope editing. Multi-site Supervisor access is represented by one scoped role row per selected site.

First Admin nominated by the user: jeffirie12@gmail.com. Provisioning and production deployment require separate approval after local verification. Existing owner permission does not automatically become Admin permission.

Completed after explicit approval on October 19, 2026. See `ADMIN-ROLES-CHANGES-2026-10-19.md` for deployment verification, artifacts and device-testing limitations.
