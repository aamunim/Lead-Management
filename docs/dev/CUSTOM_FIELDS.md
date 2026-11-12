# Custom fields (0B.06)

Plan: Ch 14.2, 14.6, 14.12 rows 5 / 9 / 10, Ch 43 (values table), Ch 7.5 (presets). Migration
`supabase/migrations/20261115090000_custom_fields.sql`; tests `supabase/tests/0B06_custom_fields_test.sql`,
`scripts/ui/custom-fields.web.test.mjs`; benchmark case in `scripts/bench/run.mjs`.

## Data

- `custom_field_definitions` (per institution): entity `lead` / `client` / `network`, key, label (en / bn), type, options,
  flags (required, show on card, show in list, filterable, searchable, include in export, show on public form,
  sensitive), order, group (en / bn), `created_from_preset`, status `active` / `retired`.
- `custom_field_values`: one row per field and record, in typed columns (`value_text`, `value_num`, `value_date`,
  `value_bool`, `value_json`). **Never** jsonb or extra columns on the record tables.
- Types: short text, long text, number (min / max / decimals), date, one choice, several choices, phone (normalised with
  the institution's phone rules), email, web address, yes / no, GPA (0–5, at most two decimals), file (a document
  reference; the paper itself is stored by the files module).

## Rules

- **Validation on the server** (`app.custom_field_cast`): every value is checked against its field; errors come back
  as `custom_field_invalid` with the field key and the reason. Bangla digits are accepted.
- **Key and type** are fixed once a field has answers; everything else can change.
- **Retire** instead of delete: the field leaves forms and lists, its answers stay, and it can be brought back.
- **Plan limit** `custom_fields` counts active fields (80 % warning, 100 % block). Preset fields from the types need no
  room. Counted by a trigger, reconciled nightly.
- **Filterable** fields get their own partial index on `custom_field_values (institution_id, value_<column>) where
  field_id = …` (GIN on `value_json` for several choices); it is dropped when the field stops being filterable or is
  retired. Block 1A filters query `institution_id = $1 and field_id = $2 and value_<column> <op> $3` and hit it.
  Benchmark: a list filtered on two custom fields (3,000 records × 20 fields) takes about 8 ms (target 50 ms).
- **Sensitive** fields (for example a guardian's NID or a birth registration number, Ch 14.12 row 10): values are
  readable only with `custom_field.view_sensitive` (masked as `•••` otherwise); declared in the field registry
  (`custom_field.sensitive_value`); the AI layer (phase 4) never sends them.
- **Presets**: applying the types (0B.04) seeds the profile's custom-field presets, and a trigger installs them as
  lead fields (`created_from_preset`); the pack's sensitive fields are marked sensitive. Presets are never removed.
- **Idempotency**: `custom_field_values_set(entity, record, values, idempotency_key)` returns the first result for a
  repeated key (kept 7 days in `request_keys`).

## API

| RPC | Who |
|---|---|
| `custom_fields_list(entity)`, `custom_field_save(entity, id, field)`, `custom_fields_reorder(entity, order)`, `custom_field_retire(id, retired)`, `custom_fields_export(entity?)` | `settings.custom_fields` |
| `custom_field_values_set(entity, record, values, key?)` | `settings.custom_fields` until the record screens exist; then the record milestones call `app.custom_field_values_write` with their own permission check |
| `custom_field_values_get(entity, record)` | any member (sensitive values masked) |

Use of fields in message templates (Ch 24), filters (Ch 15), eligibility (Ch 29) and reports (Ch 38) is built in
those milestones; `custom_fields_export` is used by copy-from-institution (0B.10).

## Demo for the 0B.06 checkpoint (staging)

1. As the Super Admin of a demo institution: Settings → Custom fields → Leads → "Add a field".
2. Name it in English and Bangla, choose a type (for example "One choice" with a few choices, one per line
   `key | English | বাংলা`), tick "Show on the card" and watch the preview (form and card); save.
3. Move it up or down, put it in a group, retire it and bring it back.
4. After Settings → Institution type (for example School), the type's preset fields appear marked "From your type";
   guardian's NID and birth registration no. are marked sensitive.
