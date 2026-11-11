# Typed settings, the Appendix A catalog and per-institution counters (0A.08, 0B.01)

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

## Registered keys

| Key | Scope | Added in | Meaning |
|---|---|---|---|
| `min_app_version` | product | 0A.08 | Apps older than this must update. |
| `default_language` | institution | 0A.10 | UI language (`bn` / `en`) for members without their own choice; see `I18N.md`. |
| `time_zone`, `currency`, `phone`, `week_start`, `bangla_digits`, `payment_methods`, `address_placeholder` | institution | 0A.11 | Locale (area `settings.locale`); see `LOCALE.md`. |
| `working_days`, `working_hours`, `quiet_hours`, `scorecard_day` | institution | 0A.11 | Office calendar (area `settings.office`); behaviour later (1A, 1B). |
| `idle_signout_minutes` | institution | 0A.14 | Sign out after this many idle minutes (0 = never); area `settings.security`; see `SHELL.md`. |
| `branches_enabled` | institution | 0A.15 | Branches are used (placeholder until modules / plan limits in 0B); see `ORG_UNITS.md`. |
| Every Appendix A key (41 + `institution_name`) | institution | 0B.01 | Version-1 schemas; the owning milestone extends them. Neutral names (D42): `appointment` (campus visit), `network` (alumni), `clients` (students), `conversion` / `conversion_approval` (admission). List: `scripts/settings/gen_catalog_0B01.py`. |
| `app_name`, `app_domain`, `privacy_contact_email`, `developer_email` | product | 0B.01 | Platform config, Master Admin side (T9). |

**Areas (permission per area, Ch 11.5, R5):** `settings.team` (activity, reports, scorecard, credits, notifications,
web), `settings.conversion` (conversion, approval, clients, files, uploads, photos), `settings.fees`, `settings.leads`
(assignment, cards, filters, score, appointment, templates, reminder and escalation times), `settings.pipeline`
(board), `settings.calls`, `settings.ai`, `settings.forms` (network, public forms), `settings.office` (= the roadmap's
`settings.calendar`: working days / hours, quiet hours), `settings.locale`, `settings.general`, `settings.security`,
`settings.organisation`. A settings permission never widens which records someone sees.

**Proposed defaults (owner may review; each institution can change them):** first call within 5 minutes, early
reminder 15 minutes before, repeat every 30 minutes, team lead after 2 hours, admin after 24 hours, receipt prefix
`R-`. Feature keys default to off until their feature exists, except assignment, board, cards, filters, templates,
double-call warning and reports.

`institution_name` is registered for the catalog but lives in `institutions.name` (`stored_in`); `setting_set`
refuses it. The other per-institution configuration (branding, counters, login, plans, …) is listed in
`public.config_groups` with its owning tables and milestone (T3).

## History, rollback and reading (0B.01)

- Every change of `app_settings` writes `app_settings_history` (old / new value, schema version, who, when, reason;
  a reset has new value null). Readable by people who may change that area and by `audit.view`.
- `setting_rollback(history_id)` puts back the value from before that change (or the default), through
  `setting_set` / `setting_reset`, so it is validated, permission-checked, audited and recorded again.
- `get_setting(key)` / `get_settings(keys[])` (INVOKER; active institution from the session) return the value and
  its source: `institution` → `type_profile` (0B.03) → `default`. The app keeps using `useSetting` (cache per user and
  institution, cleared on switch).

## Adding a setting key

1. Add the key in a new migration: `insert into public.setting_definitions (key, scope, schema, default_value, area,
   description, label_key, owner_module, owner_milestone)`. The default must validate against the schema (a database
   check refuses it otherwise). Use a neutral key name (no industry words, Ch 8).
2. `area` is the settings permission that guards it; a new area is added to a module manifest
   (`config/modules/*.json`) with en / bn labels in `permissions.json`, then `npm run test:role-matrix -- --write`
   and review the matrix diff.
3. Add `keys.<key>.label` and `keys.<key>.help` to `src/i18n/locales/{en,bn}/settings.json`.
4. Changing the shape of an existing key: raise `version`, add a `migrate_fn` that upgrades stored values, never edit
   stored values by hand.
5. Never write a locale value (time zone, currency sign, country code) in code — `npm run check:i18n` fails
   (`scripts/check-locale-literals.mjs`). Read it with `useFormat()` / `useSetting()` / `app.setting_value()`.
6. CI: `npm run check:settings` (schema, owner, area, labels) and `supabase/tests/0B01_settings_catalog_test.sql`.

Besides the JSON Schema, `app.setting_extra_errors(key, value)` adds checks a schema cannot express (a time zone Postgres knows; start ≠ end of a time window). It runs in a trigger on `app_settings`.
