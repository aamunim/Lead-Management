# Schema lint and guardrails (0A.04)

The lint reads the **real catalog** of a migrated database (not the SQL text), so nothing slips through.
It runs in CI after every migration (`npm run lint:schema`) and fails the build with a readable message per finding.

## Rules

| Rule | What it checks | Why |
|---|---|---|
| `tenant_institution_id` | Every table in `public` / `app` / `ext_*` has `institution_id uuid not null`, unless allow-listed as a platform table. | Data of institutions must never mix (G1, Ch 4). |
| `rls_enabled` | Every `public` and `ext_*` table has RLS enabled **and** at least one policy. | Tables are exposed through the API (G2). |
| `index_leading_institution` | Every index on a tenant table starts with `institution_id`. | Speed and isolation with many institutions (Ch 4, 47). |
| `unique_includes_institution` | Unique constraints on tenant tables include `institution_id`. | Receipt numbers, stage keys, tags … are unique **per institution** (Ch 4.4). |
| `branch_id` | Core record tables (`institution_members`, `leads`, `clients`, `offerings`, `cohorts`, `payments`) have a nullable `branch_id`. | Branches from Phase 0 (D9). |
| `timestamptz` | No `timestamp without time zone` columns. | Institutions have their own time zones (Ch 13). |
| `neutral_names` | No education words (`student`, `course`, `batch`, `admission`, `guardian`, `alumni`, `college`, `school`, `papers`) in table, column or function names. | Neutral internal keys; labels change the shown word (G8, Ch 8). |
| `definer_registered` | Every `SECURITY DEFINER` function is in `app.definer_registry` with a reason and reviewer. | DEFINER bypasses RLS (G3; ~418 in the old app). |
| `definer_tenant_check` | A registered DEFINER function marked `filters_active_institution` uses `app.auth_institution_id()` or `app.require_active_session()`. | A DEFINER without an institution filter leaks data. |
| `search_path` | Every function pins `set search_path = ''`. | Prevents search-path hijacking; forces schema-qualified calls the sweep can see. |
| `invoker_sweep` | No INVOKER function the app can call (or trigger function) calls a function `authenticated` cannot execute. | Lesson 1: one revoked helper blanked every AI card for everyone. |
| `heavy_jit_off` | Functions marked `-- heavy` declare `set jit = off`. | Lesson 4: JIT turned 15 ms into 900 ms. |
| `rls_initplan` | Session helpers in policies are wrapped in `(select …)`. | Evaluated once per query, not once per row (Ch 47.9). |
| `institution_type` | Only allow-listed seeding code reads `institution_type` (SQL bodies and `src/`). | Behaviour comes from settings and modules (G9, Ch 2.7). |
| `definer_service_only` | DEFINER functions registered as `service_role_only` are not executable by `authenticated` or `anon`. | Edge-only readers such as `secret_read_for_service` (0A.07). |
| `phone_ascii` | Every `phone` / `*_phone` column has `CHECK (app.is_ascii_phone(col))` (plus the `app.normalize_phone_columns` trigger). | Mixed digits break duplicate checks and search (Ch 13.8 #3). See `LOCALE.md`. |
| `core_references_extension` (text) | No core migration references an `ext_*` schema. | The core must work without any extension (Ch 43.4). |
| `extension_changes_core` (text) | Extension migrations do not alter, drop, update or add triggers/policies/indexes on core objects; inserts only into the registries. | Extensions never change the core (Ch 43.4 #1, #4). See `EXTENSIONS.md`. |

## Exceptions

Add a row to `supabase/lint/allowlist.sql` with the rule, the object and a **real reason**. Reviewers check every change
to that file. Current exceptions: the platform tables (`institutions`, `profiles`, `platform_members`,
`app.definer_registry`) and `institution_members_user_idx` (looked up by user before an institution is active).

## Adding a SECURITY DEFINER function

Only when unavoidable (e.g. the all-leads phone duplicate check in 1.03). In the same migration:

```sql
insert into app.definer_registry (function_name, reason, added_in, reviewer, tenant_check) values
  ('public.find_leads_by_contact', 'Checks phones across all leads, returns only name, stage, owner.', '1.03',
   '<reviewer>', 'filters_active_institution');
```

The function must filter by the active institution and return only what is needed.

## Guard trigger for protected columns

Columns such as the pipeline stage, admission and fee fields change only through their RPC (Ch 3.3):

```sql
create trigger leads_guard before update on public.leads for each row
  execute function app.guard_columns('app.pipeline_action', 'stage_id', 'converted_at');
-- inside the owning RPC, before the update:
perform set_config('app.pipeline_action', 'on', true);
```

A direct edit raises `protected_column` (SQLSTATE P0405).

## RPC-as-real-role harness

Every RPC test signs in as a real user through Supabase Auth and calls PostgREST (`scripts/e2e/helpers.mjs`:
`signInAs`, `anonymousClient`, `claimsOf`). Never assert permissions as the database owner. `adminSql` is only for
test set-up and tear-down on the local database.

## Commands

```bash
npx supabase start && npx supabase db reset   # local database with migrations + seed
npm run lint:schema                           # the lint
npm run test:lint                             # each rule against deliberately bad fixtures (SQL fixtures + extension text-lint fixtures)
npm run test:db                               # SQL tests as real roles
npm run test:e2e                              # real sign-in + PostgREST tests
```
