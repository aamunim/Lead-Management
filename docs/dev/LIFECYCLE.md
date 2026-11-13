# Institution lifecycle (0B.07)

Plan: Ch 5.4, 5.15, 5.17 rows 5 / 10; Ch 6.4, 6.7, 6.9 rows 1 / 2 / 8; Ch 4.11; D25. Migration
`supabase/migrations/20261116090000_institution_lifecycle.sql`; tests `supabase/tests/0B07_lifecycle_test.sql`,
`scripts/ui/lifecycle.web.test.mjs`, `scripts/ui/panel.web.test.mjs`.

## States and transitions

| From | To |
|---|---|
| pending (waiting for approval) | trial (approval; the trial runs from now), active, suspended, closed |
| trial | active, read_only, suspended, closed |
| active | read_only, suspended, closed |
| read_only | active (paid), trial (extended), suspended, closed |
| suspended | active, trial, read_only, closed |
| closed | — (purged after the notice period) |

`platform_institution_set_status(institution, status, reason)`: platform only (`platform.institutions`; closing needs
`platform.institutions_close`), second step, reason required for read only / suspend / close; writes
`institution_status_history`, both audit logs and the event `institution.status_changed` (and `institution.closed`).

## What each state means (enforced on the server)

- **pending**: the Super Admin can sign in and keep setting up; the approval queue on the panel Dashboard shows it with
  duplicate warnings (same EIIN / institution code; same name with the same phone or address) and the trial-abuse flag
  (more open trials by one person or phone than `trial_limit_per_person`, Proposed 2).
- **read_only** and **closed**: a guard trigger (`zz_status_guard`, `app.status_guard`) on **every tenant table**
  refuses inserts, updates and deletes made by people (`institution_read_only`). Reads and the full export work; data is
  never deleted for non-payment. Tables an allowed action still writes are listed in `app.status_guard_exempt` with a
  reason (exports, audit, events, counters, idempotency keys, access rebuilds); the OTP / urgent-message tables join it
  in their milestones. Platform staff (second step) can still act. Lint rule **R15 `status_guard`**: a new tenant table
  must call `select app.attach_status_guard('<table>')` in its migration (extensions too) or be exempted with a reason.
- **suspended** and **closed**: the sign-in hook does not open that institution, and an older token for it is refused
  (`institution_suspended` / `institution_closed`); the person's other institutions work (D25).
- **closed**: needs a full export from the last 7 days; `purge_after` = now + `purge_notice_days` (Proposed 90, a product
  setting); the nightly job `institution-purge` deletes the institution and, by cascade, everything it owns. Nothing
  of any other institution is touched; the platform audit keeps a record. The integration hub (0B.11) listens to
  `institution.closed` to revoke connections, keys, webhooks and secrets.

The sign-in hook runs as `supabase_auth_admin`: every table it reads needs a grant and a policy for that role (lesson 16).

## Full export

`institution_export_create(institution?)` (the institution's Super Admin, or platform staff with
`platform.institutions`): every row of every tenant table of the institution, its people (names, emails) and a files
manifest (storage paths under the institution), stored in `institution_exports` and downloaded as a JSON file (web).
Works in every status. A large institution's export moves to an Edge Function writing to storage when sizes need it.

## Screens

- App: a banner on Home while waiting for approval, in the last 7 trial days, and when read only; Settings → Plan and
  usage → Full export (Super Admin).
- Panel: Dashboard → approval queue; Institutions list (status, plan, types, users, last sign-in; institutions with
  problems first); Institution → Overview (information, warnings, status actions with reason, history, exports).

## Open for the owner (Proposed, editable product settings)

- `purge_notice_days` (90) and `trial_limit_per_person` (2).
- Owner / legal task (0B.07-T11): check the current Bangladesh data-protection rules (minors' data, retention) before
  launch and write terms and a privacy policy naming every external provider.
