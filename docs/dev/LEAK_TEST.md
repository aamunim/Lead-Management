# Cross-tenant leak test (0A.05)

**Question it answers on every PR:** can anybody of institution B see anything of institution A?
It is catalog-driven: every tenant table (any table with `institution_id` in `public` or `ext_*`) and every function
`authenticated` can execute are found automatically, so new tables and RPCs are covered without writing new tests.
It complements the schema lint: the lint checks that a policy **exists**; the leak test checks that it **works**
(a table with a policy `using (true)` passes the lint but fails the leak test).

## What it does

1. **Fixtures:** inserts at least one row per tenant table for A and for B. A table-specific function
   `leak_fixtures.<schema>__<table>(institution uuid)` in `supabase/tests/leak/fixtures/all.sql` wins; otherwise a
   generic insert fills NOT NULL columns with typed values and reuses a row of the same institution for foreign keys.
   **A table that ends up without rows for A and B fails the run** (`no_fixture`), because the probe would prove nothing.
2. **Viewers** (real `authenticated` role, claims made by the real access-token hook):
   - a member of B only;
   - a person who belongs to A **and** B with B active (D25).
3. **Table probe:** each viewer counts A's rows in every tenant table, plus the platform tables (`institutions`,
   `profiles`, `institution_members`, `platform_members`). Any visible A row is a `table_leak`.
4. **RPC probe:** each viewer calls every executable function with A's ids as arguments. The call runs in a
   subtransaction that is always rolled back (side effects undone). An error is fine; a result that contains any of
   A's markers (A's id, A-only users, ids of A's rows) is an `rpc_leak`.
5. **Fail-safe placeholders:** if a Storage bucket exists or a table is published to Realtime before their probes
   exist (0A.06), the run fails (`storage_unprobed`, `realtime_unprobed`). External connections are covered by the
   table probe once their tables exist (0B).

## Intended visibility (allow-list)

`supabase/tests/leak/allowlist.sql` — narrow (rule + object + viewer) and each with a reason; listed in the output.
Today only the dual member's **own membership facts** are allowed (institution names they belong to, their own
membership rows, switching to A), which the switcher needs (D25). No tenant data of A is allowed for anyone.

## Self-test

`npm run test:leak-self` proves the leak test catches: a permissive / forgotten policy (both viewers), an RPC that
returns another institution's rows, a table it cannot fill, an unprobed Storage bucket and an unprobed Realtime
publication — and that a correct table with a foreign key passes. It found a real bug in the harness while being
written (a permission error from the harness itself was being read as "the viewer cannot see the table").

## Commands

```bash
npx supabase start && npx supabase db reset   # migrations + seed (institutions A and B, the viewers)
npm run test:leak                              # the leak test
npm run test:leak-self                         # the leak test catches deliberate leaks
```

In CI it is the job **"cross-tenant leak test"**; make it a required check on `main`.
