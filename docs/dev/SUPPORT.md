# Support entry (0B.08)

Plan: Ch 5.5, 5.3 (Audit tab), 5.17 row 3, Ch 11.15. Migration `supabase/migrations/20261117090000_support_entry.sql`;
tests `supabase/tests/0B08_support_entry_test.sql`, `scripts/ui/panel.web.test.mjs` (support entry).

## How it works

- **Who:** a platform user with `platform.support_access` (the Master Admin, or Support with the personal setup
  right) and the second step. Panel → Institution → Overview → **Enter institution**: a reason (shown to the
  institution) and a time limit (15 / 30 / 60 / 120 minutes; the server allows 5–240).
- **The token:** `support_session_start` creates a row in `support_sessions` and the app refreshes the token. The
  sign-in hook puts the session's institution and `support_session_id` into the token while the session is open and
  not expired. Every check reads the session from the table again (`app.support_mode()`): `auth_institution_id()`,
  `require_active_session()` and `can()` honour it; an ended or expired session is refused (`support_session_ended`).
- **Read only by default:** the lifecycle guard (0B.07) refuses every write in a read-only session
  (`support_read_only`). `can()` gives a support session every **non-sensitive** permission of the institution and
  never a sensitive one, so sensitive data stays masked (nothing sensitive is read, so nothing needs a read log).
- **Edit mode (Proposed four-eyes):** in the banner, "Ask for edit mode" with a reason; **another** Master Admin approves
  it on the panel Dashboard (`support_edit_approve`; nobody approves their own). Every write in edit mode is written
  to the platform audit as `support.write` with the table and the session id.
- **Scope:** one institution only; another institution's rows stay invisible and cannot be written by naming them.
- **Leaving:** Exit in the banner, or automatically at 00:00 (`support_session_end`, token refreshed).

## Visibility (Ch 5.17 row 3: mandatory)

- Both audit logs record start, end, edit request and approval, with `support_session_id`.
- The institution: Settings → **Support access** (`settings.security`, Super Admin by default) — who, when, why, read
  only or edit, how many changes, and each action.
- The panel: Institution → **Audit** tab — every platform change and support entry for the institution.

## Speed

`can()` checks the support session only when the token carries one; `can_check` is PL/pgSQL (plan cached, lesson 13).
Benchmark `can_per_call_us` ≈ 235 µs vs ≈ 205 µs before (within the agreed 25 % / 50 µs).
