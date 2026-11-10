# Users, roles, access explainer and change log (0A.18)

Roadmap 0A.18; plan Ch 11.14, 11.3 (R16, R20), 11.16 #1, Ch 8.6. Decisions D23, D26.
Migration `20261111110000_users_admin.sql`; seed `supabase/seeds/0A18_admins.sql`; tests
`supabase/tests/0A18_users_admin_test.sql`, `scripts/e2e/users-admin.e2e.mjs`, `scripts/ui/admin.web.test.mjs`,
`scripts/tests/admin.test.mjs`, `.maestro/users-roles.yaml`.

## Screens (Settings tab)

| Screen | Route | Shown when (`my_access`) | Server check |
|---|---|---|---|
| Users list (pending / active / deactivated, search) | `/admin/users` | `settings.users` | `users_list` → `can('settings.users')` |
| Person: contact, status, roles, units, access | `/admin/user/[id]` | `settings.users` | `user_detail`, `user_approve`, `user_deactivate`, `user_reactivate`, `user_update_contact`, `role_unassign` |
| Give a role (role + branch / unit + dates + preview) | `/admin/assign?user=` | `settings.users` | `role_assign`, `role_assignment_preview` |
| Roles list, new role from a template | `/admin/roles` | `settings.roles` | `roles_get`, `role_create` |
| Role editor (registry-driven), copy, delete | `/admin/role/[id]` | `settings.roles` | `role_update`, `role_set_grants`, `role_copy`, `role_delete` |
| Compare two roles | `/admin/role-compare` | `settings.roles` | read only |
| New permissions in this release (R20) | `/admin/new-permissions` | `settings.roles` | read only |
| Access explainer (R16) | `/admin/explain?user=` | `settings.users` | `access_explain`, `record_entities_get` |
| Change log | `/admin/audit` | `audit.view` | `audit_list` |

The app **hides** what a person cannot use (`src/lib/access.ts`, from `my_access`); the server is the real check
(Ch 4.7). Every call goes through `callWithSessionRetry` (`src/lib/admin.ts`), so a changed access version refreshes
the session once. Pure helpers (grouping, compare, scopes, release order) are in `src/lib/admin-core.ts`.

## Rules

- **Approve / deactivate / reactivate** need `settings.users`. Nobody deactivates themselves (`self_lockout`) or a
  person with more access (`permission_escalation`), and the last active Super Admin cannot be deactivated
  (`last_super_admin`). Deactivation bumps the access version (the next request is refused) and, when the person has
  no other active institution, deletes their `auth.sessions` so the refresh token stops working at once. The reason
  is stored on the audit row of the status change (`app.audit_reason`, read by the 0A.09 trigger).
- **Contact change**: name, phone (institution phone rules, `app.require_valid_phone`) and email. The email is
  changed in `auth.users` at once (Ch 11.14). The profile is shared by all of a person's institutions, so an admin may
  change it only for someone who belongs to this institution alone (`profile_shared`); anyone may change their own.
  On hosted Supabase this writes `auth.users` from a definer function; if the platform ever refuses it, move the email
  part to an Edge Function using the Auth admin API (same checks).
- **Role changes**: `settings.roles` (sensitive). Adding or removing a **sensitive** permission needs a two-step
  (`aal2`) session (0A.16-T5, `mfa_required`); other role changes work with a normal session. The two-step sign-in
  screens come in 0B, so until then sensitive permissions are given through roles that already have them.
- **Explainer**: evaluates every assignment of the person (also scheduled, ended and deleted-role ones) against the
  record: permission granted? dates? person active? branch limit, owner scope, offering limit, creator exception.
  It answers `allowed` + a summary (`allowed`, `membership_inactive`, `no_roles`, `no_role_grants`,
  `blocked_by_limits`) + one reason per assignment (`rule`). A record is either a described one
  (`{permission, owner_id, branch_id, offering_id, created_by}`) or a registered record type by id
  (`{entity, id}`). **Modules register their record tables** in `app.record_entities` (1A: leads):
  ```sql
  insert into app.record_entities (entity_key, table_name, view_permission, label_key, added_in)
  values ('lead', 'public.leads', 'lead.view', 'labels:lead.singular', '1A.xx');
  ```
- **Change log** areas: roles (`target_type = 'role'`), assignments (`role_assignment`), people (`membership`,
  `user`), settings (`setting`, `label`, `secret`, `extension`, `branch`, `org_unit`), field rules (`field_rule`,
  from 1B). Filter by person and dates (institution days); newest first, 50 per page (keyset on `at, id`).

## Test data

`owner.admin@example.test` is the Super Admin of institution A (college template), `pending.member@example.test` a
pending join request in A, and `weird.member@example.test` the Super Admin of the weird-labels institution C (for
screenshots). Password `password123` (local / CI only).

## Not built here

- **"Simple mode"** hiding units and approval policies for small institutions (0A.18-T9, Ch 11.16 #1) is *Proposed*
  and waits for the owner's decision.
- Password reset (0B, Ch 10.7), activity (phase 4), delegation / hand-over (1B), list layout editing, call-log sync
  requirement (phase 3) are shown as "coming in a later release".
- Access review report and monthly reminder (Ch 11.14) are not in this milestone.
