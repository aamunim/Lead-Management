# Permission registry, roles, flags and templates (0A.16)

Roadmap 0A.16; plan Ch 11 (11.2–11.5, 11.7, 11.9–11.11, 11.15), Ch 43.5. Decisions D23 (several roles per person),
D26 (templates per type), D10. Migration `20261111090000_permissions_roles.sql`; manifests `config/modules/*.json`;
tests `supabase/tests/0A16_permissions_test.sql`, `scripts/tests/permissions.test.mjs`. Checking (`can()`) and
role assignments come in 0A.17; the role editor in 0A.18.

## Permissions are data

Each module declares its permissions in a manifest (`config/modules/<module>.json`):

```json
{ "module": "lead", "release": "1A.01",
  "permissions": [ { "key": "lead.view", "scopable": true, "sensitive": false,
                     "defaults": { "caller": "own", "team_lead": "team", "admin": "all" } } ],
  "fields": [ { "entity": "client", "field": "national_id", "sensitive": true, "permission": "sensitive_field.view" } ] }
```

- Keys are neutral `module.action` (`client`, `offering`, `conversion` — never education words; the database and
  `check:i18n` refuse them). Label and help text in `src/i18n/locales/{en,bn}/permissions.json` under the same key;
  CI fails without both languages.
- `npm run db:permissions` (`scripts/permissions/sync.mjs`) loads the manifests with `app.sync_permissions()`; it runs
  after migrations locally, in CI and in the deploy workflow (`SUPABASE_DB_URL` secret).
- **Scope** (scopable permissions): `own`, `team` (units managed, with sub-units), `org_unit`, `branch`, `all`.
- **Sensitive** (billing, integrations, deleting, exporting everything, sensitive fields, acting for others, roles):
  only reachable through the Super Admin `*`, never through inheritance; changing a role's sensitive permissions
  needs a two-step session (`aal2` claim; MFA enrolment screens are 0B).
- **Settings permissions are per area** (`settings.users`, `settings.roles`, `settings.terminology`,
  `settings.organisation`, `settings.locale`, `settings.office`, `settings.general`, `settings.security`, …) and say
  nothing about which data someone sees (R5). Every setting area is a registered permission (tested).

## Roles

| Table | What |
|---|---|
| `roles` | per institution: system (from a template) or custom; `name` or a default `name_key`; `rank_for_sorting` (sorting only, R8); `inherits_from_role_id`; behaviour `flags` |
| `role_permissions` | grants with scope; `*` only on the Super Admin role; a platform permission can never be granted (foreign key on `(key, kind)`) |
| `role_templates` | per type profile (college, school, coaching; D26), with flags; grants come from the manifests' `defaults` |
| `behaviour_flags` | `assignable`, `counts_on_leaderboard`, `receives_escalations`, `counts_as_manager`, `shown_in_team_activity`, `call_log_sync_required` (replace the old `acts_as`). With several roles, a flag is on if any role has it (applied in 0A.17). |
| `field_registry` | sensitive fields and the permission that shows them (masking in 1B; never sent to AI) |

**Templates (Proposed, owner review):**
- college: Principal (Super Admin), Vice-principal, Admin, Branch manager, Department head, Team Lead, Counsellor
  (`caller`), Conversion officer, Accountant, Viewer / Auditor, Governing body / Chair;
- school: the college list plus Head teacher, Assistant head teacher, Class teacher;
- coaching: Owner (Super Admin), Manager, Counsellor.

**New release (R20):** a new permission goes to system roles with its declared defaults, and to custom roles that
inherit from a role holding it — only if it is not sensitive. Super Admin gets everything through `*`.

RPCs now: `roles_get`, `role_create` (a copy starts with the parent's non-sensitive grants), `role_update`,
`role_set_grants` (Master Admin until `can()`; audited; event `role.changed`).

## "Who" selector (Ch 11.10)

`{mode: 'all' | 'roles' | 'users', roles: [], user_ids: []}` only for settings that are **not** access (notification
recipients, dashboard cards); the Super Admin role is never offered (`app.validate_who`). Access rules are scoped
permissions instead, e.g. `conversion.mark` (never `admission.mark`).

## Platform roles (T10)

Master Admin, Support, Billing, Developer and group owners stay in `platform_members` (and group tables, 0B). Their
permissions have `kind = 'platform'` and cannot be granted to an institution role.

## Extensions, custom records and API keys (T9, Ch 43.5, R17)

They use the **same registry**: an extension ships a manifest in its folder (`supabase/extensions/<key>/manifest.json`,
loaded by the same sync from phase 2), custom record types register `custom_<type>.view / edit …` (phase 2), and API
keys are given scoped permissions from this registry (phase 2) instead of a separate list.

## Owner review (0A.16 checkpoint)

1. The template role lists above.
2. The Proposed old → v2 permission map (plan Ch 11.5): `leads.view_own/_team/_all` → `lead.view` with scope,
   `payments.manage` → `payment.create / edit / void`, `refund.create`, `settings.manage` → per-area `settings.*`,
   `users.manage` → `settings.users` (+ `settings.roles`, sensitive), `*` → Super Admin only. Registered by the
   milestones that build those modules.
3. The key for branch settings: `settings.organisation` (covers branches, departments and teams).
