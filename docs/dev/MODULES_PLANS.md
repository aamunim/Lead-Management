# Modules, plans and limits (0B.05)

Plan: Ch 9 (9.1–9.5, 9.8, 9.9), Ch 7.8, Ch 5.7. Decisions D7, D22, D30, D31, D32. Migration
`supabase/migrations/20261114090000_modules_plans.sql`; tests `supabase/tests/0B05_modules_plans_test.sql`,
`supabase/tests/concurrency/usage_limit_concurrency.sh`, `scripts/ui/modules-plan.web.test.mjs`.

## Modules

- `public.modules` is the Ch 9.2 list as data (key, label key, dependencies, always on, default, industry scope, the
  milestone that builds it). Core leads and follow-ups are always on.
- A module **works** for an institution (`app.module_enabled(institution, key)`, or `app.module_enabled(key)` for the
  active institution) when it is always on, or when all of these hold:
  1. **allowed**: the plan includes it, or the platform allowed / took it away for this institution
     (`institution_modules.allowed`, Master Admin / Billing, logged);
  2. **switched on**: the institution's own choice (`institution_modules.enabled`, Settings → Modules,
     `settings.modules`), else its types' default (seeded at 0B.04), else the module default;
  3. its **industry** fits (merit list and board flow: education only);
  4. the modules it **depends on** work.
- Code checks `module_enabled`, never the institution's type. A module that is off is removed from menus, Home, filters,
  reports and settings, and its jobs skip the institution; its data is kept.
- The older on / off settings (fees, appointment, network …, 0B.01) stay as settings inside a module. Branches need the
  branches module and the `branches_enabled` setting.
- Module names come from the label system when the module has a label key (so words follow the institution), else
  from `admin:modules.names.*`.

## Plans

- `public.plans` (key, version): name, modules, limits (metric → number, null = unlimited), prices (currency, monthly,
  yearly, per type, D32), trial days, "for new institutions". **The numbers are placeholders accepted by the owner (D45)**, prices still blank (Ch 53.2 rows
  2–4); the Master Admin edits them in the panel (Institutions → Plans) without a release (D30, D31).
- Saving a plan makes a **new version**. An institution keeps its version until it changes plan (price protection,
  Ch 9.9 row 8, Proposed).
- `public.institution_plan`: plan + version, start, end date, billing cycle, price override, discount, limit overrides
  (one row per institution from day one; new institutions start on the trial). Changed by Billing / Master Admin in the
  institution's **Plan and billing** tab, with a reason, logged on both sides.
- `public.addons`: the add-on catalog as data (purchase flows come with billing, 0B.16).
- Downgrade fit check `app.plan_fit(institution, plan)`: what is above the new limits and which modules would stop.
  Proposed: the excess becomes read-only / archived, never deleted (the action comes with 0B.16).

## Limits

- `public.limit_metrics`: users, active leads, branches, storage, monthly SMS, monthly AI, automations, custom fields,
  custom record types, monthly API calls, daily campaign SMS. Monthly / daily periods use the institution's time zone.
- `app.limit_of(institution, metric)`: the override, else the plan; null = unlimited.
- `app.check_limit(institution, metric, delta, purpose)`: locks the counter row, so parallel requests queue; returns
  `ok` / `warning` (≥ 80 %) / `full` / `blocked` (> 100 %) and raises `limit_reached` when blocked. **OTP and urgent
  messages are never blocked** (`purpose` `otp` / `urgent` → `exempt`). Every milestone that uses a metric calls it
  on the server, never only in the app (Ch 9.9 row 3); import paths call it before writing.
- Counters (`public.usage_counters`): users and branches are kept by triggers that also enforce the limit for requests
  by people (seeds and platform scripts without a signed-in user are not limited); the other metrics are counted by the
  code that uses them (`app.usage_add`). `app.usage_reconcile()` recounts nightly (pg_cron `usage-reconcile`).
- The app: a banner on Home at 80 % and 100 % (numbers and "Upgrade" for people with `billing.view`, "tell your Admin"
  for others), the error `limit_reached` when the server blocks, and Settings → Plan and usage (`billing.view`).

## Permissions

| Key | Who (default) |
|---|---|
| `settings.modules` (sensitive) | Super Admin |
| `billing.view` (sensitive) | Super Admin |
| `platform.billing` | Master Admin, Billing: an institution's plan, overrides and allowed modules |
| `platform.plans` | Master Admin: the plans catalog |

## Test institutions

`supabase/seeds/0B05_plans.sql`: the older test institutions run on Standard; `plan-trial`, `plan-starter`,
`plan-standard`, `plan-pro`, `plan-enterprise` for CI.
