# Extensions (0A.09)

Plan: Ch 43.3, 43.4, 43.6. Code: `supabase/extensions/`, runner `scripts/apply-extensions.sh`, text lint
`scripts/extension-lint.sh`. Example: `supabase/extensions/example/`.

## First: does this request need an extension at all? (five layers, Ch 43.3)

Try each layer in order and stop at the first one that is enough:

1. **Setting**: a value the institution can change (0A.08). *"Follow-up after 5 days instead of 3."*
2. **Custom record or field**: data the institution defines itself (custom fields, 1.x). *"We also need the father's occupation."*
3. **Automation**: a rule on events (1.32). *"When a client is converted, send an SMS to the counsellor."*
4. **Webhook / API**: the institution's own system reacts to our events or calls our API (1.31). *"Push conversions to our ERP."*
5. **Extension**: new screens, tables and logic switched on only for chosen institutions.

## Triage rule (Ch 43.6)

- Wanted by **several institutions** → build it as a **core module** (with settings), for everyone.
- Wanted by **one institution** and not solvable by layers 1–4 → **extension**, built and **charged** separately.
- Never add a column, branch or `if institution = …` to the core for one institution (Ch 43.4 #1).

## Rules for an extension

| Rule | Enforced by |
|---|---|
| Own schema `ext_<key>`; own folder `supabase/extensions/<key>/migrations/0001_name.sql` | runner (file names), schema lint |
| Never alters, drops, updates or adds triggers, policies or indexes on core objects; may only *insert* into the registries `extensions`, `event_definitions`, `event_listeners` | `scripts/extension-lint.sh` (CI `lint:schema`) |
| The core never references `ext_*` | `scripts/extension-lint.sh` |
| Every table has `institution_id`, RLS and the `(select …)` policy template, and is visible only while the extension is on (`app.extension_enabled('<key>')`) | schema lint (also checks `ext_*`), leak test (covers `ext_*`) |
| Writes to core data only through versioned core RPCs; reacts to core changes by listening to events | review; events in `EVENTS.md` |
| App RPCs are `public.ext_<key>_<name>` and written as `BEGIN ATOMIC` SQL functions, so removing the schema removes them too | `uninstall.sql` test |
| Refuses with `extension_disabled` when switched off | tests |
| Registers its permissions (0A.16) and words as labels (0A.10) | later milestones |
| Has `README.md` (what it does, events, permissions) and `uninstall.sql` | review |
| Switching it off or removing it never breaks the core | `0A09_events_test.sql` sections 7–8, e2e |

## Applying and removing

- **Apply:** `npm run db:extensions` after `supabase db reset` (CI does this after every reset). Each file runs once in
  a transaction and is recorded in `app.extension_migrations` with its checksum; a changed applied file stops the run,
  so write a new file instead. The deploy workflow runs it after `supabase db push` with `APPLY_TEST_EXTENSIONS=0`
  and needs the `SUPABASE_DB_URL` GitHub secret once the first real extension exists.
- **Test-only extensions** have a `TEST_ONLY` file (the example). They are never applied to staging or production.
- **Switch on/off per institution:** `extension_set_enabled(institution, key, enabled)`, a platform action (Master
  Admin, 0B), audited and emitted as `extension.toggled`. Switching off hides the data; it does not delete it.
- **Remove:** run the extension's `uninstall.sql`. Its emitted events stay in the log as history (definitions are
  marked deprecated).

## New extension checklist

1. Copy `supabase/extensions/example/` to `supabase/extensions/<key>/`, delete `TEST_ONLY`, rename `ext_example`.
2. Write tables with the tenant template + `(select ext_<key>.enabled())` in every policy.
3. Add events with `extension_key`, listeners in `event_listeners`, RPCs as `public.ext_<key>_…`.
4. Add leak fixtures for its tables if the generic insert cannot fill them (`supabase/tests/leak/fixtures/all.sql`).
5. Run `npm run db:extensions`, `npm run lint:schema`, `npm run test:leak`, `npm run test:db`.
