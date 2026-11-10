# Access: role assignments, can(), user_access and the access version (0A.17)

Roadmap 0A.17; plan Ch 11.3, 11.6, 11.7, 11.13, 11.16; Ch 4.7; Ch 12.4. Decisions D9, D23, D25.
Migration `20261111100000_access.sql`; tests `supabase/tests/0A17_access_test.sql`, `scripts/e2e/access.e2e.mjs`.

## How access is decided

1. **Role assignment** = person + role + optional unit / branch + optional offering limit + valid from / to
   (`role_assignments`). A person may have several (D23).
2. **`user_access`** is precomputed: one row per (person, permission, assignment) with
   `branch_ids` (null = no branch limit), `user_ids` (null = any owner; own / team / org_unit scopes fill it) and
   `offering_ids`. **Limits stay bound to their assignment**: "Admin in branch X" plus "Caller in branch Y" gives
   everything in X and only own records in Y — never everything in Y (tested; Ch 11.16 #2).
3. **`app.can(action)`** — "at any scope" (settings, "may create"); **`app.can(action, record)`** — for one record
   `{owner_id, branch_id, offering_id, created_by}`. A record argument that is SQL NULL is refused (never read as
   "any scope"). `*` (Super Admin) covers every institution permission, never platform ones.
4. **RLS** on 1A tables: `select app.create_visibility_policy('public.leads', 'lead.view');` — the same rule,
   evaluated against the person's rows loaded once per query (3,000 rows: +2.8 ms). `app.row_visible(…)` checks one
   row outside RLS. `app.visible_branch_ids / visible_owner_ids / visible_offering_ids` are unions for filters and
   counts only, never for access decisions.

Rules applied: scope `own` / `team` (units the person manages, with sub-units) / `org_unit` / `branch` (the
assignment's branch, else the person's home branch) / `all`; **null branch** = visible only to people without a
branch limit and to the creator; **null offering** = the same with offering limits; temporary roles stop at
`valid_to` at once (the nightly job cleans up). Behaviour flags of a person = union of their roles (`app.user_flags`).

## Keeping it current

Changes to assignments, roles, grants, units, unit members / managers and memberships queue the affected people
(`access_rebuild_queue`); every RPC flushes its institution before returning, and a pg_cron job drains the rest every
minute, fairly per institution. When a person's access changes, their **access version** goes up: their current
token is refused on the next request with `session_refresh_required`, the app refreshes the session (0A.14 API
wrapper) and gets the new access — no waiting for token expiry (R15). Deactivation already ends sessions (0A.03).

## Safeguards (server-side, all tested)

- The last Super Admin cannot be removed (`last_super_admin`).
- Nobody removes their own last way to manage users (`self_lockout`).
- Nobody gives a role or a permission they do not hold themselves, and nobody changes a person with more access
  (`permission_escalation`; rank is for sorting only, R8). Enforced in the RPCs and by a trigger on every grant.
- A role with people cannot be deleted; `role_delete(role, move_to)` moves them first (`role_has_members`). System
  roles are never deleted.
- Sensitive permissions need a two-step session to change (0A.16); platform permissions can never be granted.

RPCs: `role_assign`, `role_unassign`, `role_assignment_preview` (current + resulting access before saving),
`role_copy`, `role_delete`, `my_access` (what the app may show), plus the 0A.16 role RPCs, all through `can()` and
audited / emitted (`role.assigned`, `role.unassigned`, `role.changed`).

## The earlier fail-closed checks

`settings_write_allowed(institution, area)` (settings, words, branches, roles) and `secret_write_allowed`
(`integration.manage`) now use `can()`; the platform Master Admin keeps access for the Master Admin panel (D4).
Reading events and the audit log needs `audit.view`.

## Every write RPC checks permission (T8)

Schema-lint rule `write_needs_can`: a public SECURITY DEFINER function that the app can call and that inserts,
updates or deletes must call `app.can()` or a helper built on it — or be allow-listed with a reason.

## "Who" selector

`app.who_matches(institution, rule, user)` evaluates `{mode: all | roles | users}` for non-access settings
(notification recipients in 0B).

## Speed of `can()` (0A.20)

`can()` is for one check per request (an RPC deciding whether a write is allowed): about 0.05–0.25 ms per call as
`authenticated`. Never call it per row of a list: lists use the RLS rule, which loads the person's access once per
query. The wrappers are PL/pgSQL on purpose — a SQL-language function with `SET search_path` is planned again on every
call (lesson 13). Measured by `npm run bench`.
