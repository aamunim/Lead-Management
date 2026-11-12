# Setup checklist, branding and copy setup (0B.10)

Plan: Ch 6.5, 6.9 rows 4 and 7; Ch 5.3, 5.8, 5.16; Ch 10.2; decisions D12, D16, D17.

## Checklist

- `setup_checklist_items` (product-wide, **Proposed list**, Ch 6.5): key, owner (`super_admin`, `master_admin`, `both`),
  chapter, rule, `available` / `available_from` (the phase the feature arrives in), `optional`, `module` (an item tied to a
  module that is off is left out, e.g. branches), `video_url` (content task, 0B.10-T5), sort. Words in
  `admin:checklist.items.<key>` (education words come from labels).
- `institution_checklist`: items ticked by hand (status, note, who, when). Never read directly (RLS denies); the RPCs
  return the state.
- **Rules:** items with a rule are worked out from the data whenever the checklist is read (`app.checklist_rule_done`):
  `branding` (a colour or logo set), `branches` (an active branch), `staff` (two or more active people). So an item flips
  the moment its data changes, without a separate event. Later milestones add rules (e.g. `messaging` when an SMS
  connection is healthy, 0B.13) and set `available = true` for their items.
- **Progress:** done / available non-optional items.
- RPCs: `checklist_get()` and `checklist_mark(item, done, note)` for anyone with a settings permission (only manual,
  available items the institution does); `platform_checklist(institution)` (platform.view) and
  `platform_checklist_mark(...)` (platform.institutions; only items the platform does or shares). Marks are audited.
- Screens: Settings → Setup checklist (progress, "who does it" chips, "arrives in phase N", video link), a Home card
  until everything available is done, the panel Overview tab, and "Setup: N left" in the panel institutions list.
- The merchant-account item shows early with the note that manual payment works meanwhile (Ch 6.9 row 4).
- **Trial ending with setup incomplete (Proposed):** daily job `app.checklist_trial_alerts()` alerts every active
  Support and Master Admin user once per trial, `setup_alert_days_before_trial_end` (3) days before it ends.

## Branding (D12)

- Name and short name stay on `institutions`; colour `brand_color` and logo `brand_logo_path` are settings (area
  `settings.branding`, new permission; Admin template gets it by default).
- `branding_get()`, `branding_set(name, short_name, logo_path, clear_logo)`: the logo must be a file already in the
  institution's own folder of the private bucket `institution-files` (`<institution>/branding/...`). Audited; bumps the
  settings version so other devices reload (the header re-reads the name when the version goes up).
- Shown after sign-in: header logo (or a mark in the colour), web tab title, theme colour (a colour without enough contrast
  in light or dark is used for accents only, as the theme already does). **The sign-in page stays neutral** (settings
  are cleared on sign-out). Institution brand on its own domain or a branded app is Proposed for later (D16).
- **Logo upload is on the web app for now.** A native image picker is a new native module: adding it means a new app
  install instead of an over-the-air update, so it comes with the next app build (Proposed).

## Copy setup from another institution

- `copy_areas` registry (area, table, match columns, which rows are configuration): `labels`, `settings` (not branding or
  security), `custom_fields` (definitions, never values). Later milestones register theirs (SMS / email setup 0B.15,
  offerings Block 2).
- `platform_copy_setup(target, source, areas, confirm)`: platform.institutions + aal2; preview counts what would be added
  and what the target keeps (its own rows always win); copying never touches records; audited on both sides. Copying
  between institutions of one group is for when groups exist.
- Panel → Institution → Overview → Copy setup.

## Tests

- SQL `supabase/tests/0B10_setup_test.sql`.
- UI `scripts/ui/setup.web.test.mjs`: tick an item; branding with logo upload shown in the header and tab title; the
  sign-in page stays neutral; panel checklist; screenshots light / dark × bn / en with a long Bangla name.
