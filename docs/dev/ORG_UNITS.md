# Branches and the organisational unit tree (0A.15)

Roadmap 0A.15; plan Ch 12 (12.1–12.4, 12.6, 12.7), Ch 11.6, Ch 4.2. Decisions D9, D25.
Migration `20261110230000_org_units.sql`; tests `supabase/tests/0A15_org_units_test.sql`, `scripts/e2e/org-units.e2e.mjs`.

## Model

```
institution (implicit root)
├── branch (kind = branch, only directly under the institution)   + branches row: address, phone, head
│   ├── department
│   │   └── team …            any depth
├── department (institution-level, no branch)
```

| Table | What |
|---|---|
| `org_units` | `(institution_id, id, parent_id, kind: branch / department / team / other, name, branch_id, archived_at)`; `branch_id` = the branch the unit belongs to (kept by trigger, also after moves) |
| `org_unit_closure` | every (ancestor, descendant, depth) pair: **subtree = one index scan** (`app.org_subtree(institution, unit)`; 500 units < 5 ms, tested) |
| `branches` | details of branch units (address, phone normalised to ASCII, head) |
| `org_unit_members`, `org_unit_managers` | people in a unit / managing it (a manager's "team" scope in 0A.17 = the unit and everything under it) |

`institution_members.branch_id` (the person's home branch, from 0A.04) now points at `branches`.

## Rules

- Reading: every member of the institution reads its tree (RLS). `org_tree_get()` returns the whole tree in one call.
- Writing: only through the RPCs `branch_create / branch_update / branch_archive`, `org_unit_create / org_unit_update /
  org_unit_move / org_unit_archive`, `org_unit_add_member / org_unit_remove_member`, `set_manager`. Until permissions
  exist (0A.17) only the platform Master Admin may write (fail-closed). Every change is audited and emitted
  (`branch.*`, `org_unit.*`).
- **No cycles**; a branch stays directly under the institution; sibling names are unique among active units.
- **Never deleted, only archived — and only when empty** (no active sub-units, members, managers, or staff whose
  home branch it is; 1A/1B add their records — leads, clients, offerings, cohorts, payments — to that check).
  The database also refuses deleting a unit that still has anything attached (Ch 12.7 #7).
- **Branch gate:** `branches_enabled()` (placeholder setting `branches_enabled`, default off). Off: `branch_create`
  is refused and API answers leave branch fields out, so screens hide branch fields, filters and columns (Ch 12.2).
  0B replaces the placeholder with the module system and plan limits (Starter 1, Standard 2–3, Pro unlimited,
  extra branches as add-on). Turning branches on later needs no migration: every core table has a nullable
  `branch_id` from day one (Ch 12.1, 12.3; lint rule `branch_id`).

### Null branch (0A.15-T3, **Proposed**, implemented in `user_access` in 0A.17)

`branch_id = null` means institution-level / branch not set yet. Branch-limited staff do **not** see null-branch
records; Admins and the person who created the record do. Lists get a "Branch not set" filter (Ch 12.7 #1).

## Settings → Branches (0A.19)

`/admin/branches` (permission `settings.organisation`, shown only when branches are on): list, add, edit (name,
address, phone checked against the institution's phone rules, head) and archive. A branch still in use cannot be
archived: `branch_archive_check(id)` counts sub-units, unit members, managers, staff based there and roles limited to
it (1A / 1B add their records), and the screen offers **"move everything to another branch, then archive"**
(`branch_move_contents(from, to)`: moves sub-units with their subtrees, members, managers, home-branch staff and
branch-limited role assignments; access is rebuilt; audited as `branch.contents_moved` with the counts). With branches
off nothing about branches appears: no Settings entry, no branch field when giving a role, no branch in the
explainer or on a person's roles.

The roadmap calls the permission `settings.branches` ("key name to confirm" in 0A.16); the registry uses
`settings.organisation` (branches, departments and teams) — listed for the owner's review in `PERMISSIONS.md`.

**Proposed follow-ups (0A.19-T8, not built):** branch filter and column on the lead list and board (1A, Ch 15);
branch choice on the public application form (1B, Ch 27); a bulk "assign branch" tool with preview and undo (1A); a
"change branch" action on a lead (1A).

## Branch or a separate institution in a group? (0A.15-T6, Ch 12.6, Proposed guidance)

| Question | Branch (same institution) | Separate institution (in a group, D25) |
|---|---|---|
| Data | One place; visible across branches if allowed | Fully separate; only summaries on the group dashboard |
| Settings, pipeline, fee structure, templates | One set (with branch details) | Each its own |
| SMS sender ID, slug, domain, online-payment merchant | One (the institution's) | Each its own |
| Plan and billing | One plan, limited by number of branches | Each its own plan; optional group invoice |
| Fits | Several campuses of one institution | One owner's school, college and coaching centre |

## Open questions (owner, later — not needed before the milestones that use them)

1. Does any institution need a different online-payment merchant account or SMS sender ID **per branch**?
   (Today: one per institution; a fully separate account means a separate institution.) — needed by 0B.11 / 1B.
2. Are **per-branch receipt / ID number series** needed (e.g. `{BRANCH}` in the pattern)? — needed by Phase 2 fees.
