# Typed settings and per-institution counters (0A.08)

## Settings are data

A setting is one row in `public.setting_definitions`:

| Column | Meaning |
|---|---|
| `key` | e.g. `followups.default_days` (neutral words only) |
| `scope` | `institution` (per institution) or `product` (one value for the whole product, e.g. `min_app_version`) |
| `schema` | JSON Schema; every write is validated with `pg_jsonschema`, and the default must match it |
| `default_value` | the value when nothing else is set |
| `version` + `migrate_fn` | when the shape changes, bump `version` and give a function `(value jsonb, from_version int) → jsonb`; `app.run_setting_migrations()` upgrades every stored value (and refuses a bump without a function) |
| `area` | permission area that guards writes (e.g. `settings.terminology`); checked with `can()` from 0A.17 |

Adding a setting = a migration that inserts a definition (and, later, type-profile defaults in 0B). **No code change** in
the settings data layer, the RPCs or the client store.

## Resolution layers

`definition default` → `type-profile default` (0B fills `app.type_profile_setting_default`) → `institution value`.
`public.settings_get_all()` returns `{settings_version, values, overridden}` for the active institution, plus the
product-level values.

## Writes

| RPC | Who (until `can()` in 0A.17) | Notes |
|---|---|---|
| `setting_set(key, value, institution_id?)` | platform Master Admin (fail-closed) | schema-validated (`setting_invalid` with a field-level message in `details`), keeps `previous_value` and `updated_by`, bumps `settings_version` |
| `setting_reset(key, institution_id?)` | same | removes the override; the next layer applies again |
| `product_setting_set(key, value)` | platform Master Admin | product-level keys only |

0A.09 connects every change to the audit log and `domain_events`.

## Keeping every device up to date

- PostgREST runs `app.pre_request()` before **every** API request. It returns the active institution's
  `x-settings-version` as a response header.
- The app's Supabase client (`src/lib/supabase.ts`) reads that header on every response; the settings store
  (`src/lib/settings.ts`) reloads when the version is newer. A change made on one device is therefore picked up by
  another device on its next request, without a restart. The store also refreshes on returning to the foreground,
  shows the cached copy first (per user + institution), and is cleared on sign-out or institution switch.
- Use `useSetting(key, fallback)` in screens and `getSetting(key)` elsewhere.

## Minimum app version

`min_app_version` (product setting). The app sends `x-app-version` on every request; `app.pre_request()` refuses an
older app with `upgrade_required` (SQLSTATE P0426, action `upgrade_app` in the error contract). Versions are compared
numerically (0.10.0 > 0.2.0). Requests without the header (web, tools) pass. The update banner arrives in 1.18.

## Counters

`app.counter_next(counter_key, branch_id?)` returns the next number of the active institution's counter (optionally per
branch). It is atomic and **gap-free**: the row lock lasts until the caller's transaction ends, so a rolled-back receipt
does not burn a number. It is not exposed through the API; the RPCs that issue numbers call it (receipts 2.06, refunds,
client numbers 2.04). Proven by a test where 50 parallel connections receive exactly 1..50.

## Tests

- `supabase/tests/0A08_settings_test.sql` — validation, layers, versions, reset, migrations, permissions, isolation,
  min version, counters.
- `supabase/tests/concurrency/counter_concurrency.sh` — 50 parallel `counter_next` calls (run by `npm run test:db`).
- `scripts/e2e/settings.e2e.mjs` — the header on real responses, a change seen by a second device, field-level
  validation message, `upgrade_required` for an old app.
