# Event log and audit log (0A.09)

Plan: Ch 43.2–43.5, 43.7, Ch 3.3, Ch 11.14. Migration: `supabase/migrations/20261110180000_events_audit_extensions.sql`.
Tests: `supabase/tests/0A09_events_test.sql`, `scripts/e2e/extensions.e2e.mjs`.

There are two logs, and they answer different questions:

| | `domain_events` | `audit_log` |
|---|---|---|
| Question | "What happened?" (business fact) | "Who changed what, from what to what, and why?" (security) |
| Read by | Automation (1.32), webhooks (1.31), extensions, reports | Owners and auditors (Ch 11.14) |
| Written by | `app.emit_event(...)` only | `app.audit(...)` only |
| Changes | Marked `processed_at` by the dispatcher | **Never**: append-only (trigger), except when an institution is purged |
| Payload | Checked against the catalogue's JSON Schema | Free `before` / `after` JSON (never secret values) |

Product-level actions (no institution, e.g. `min_app_version`) go to `platform_audit_log` via `app.platform_audit(...)`.

## Writing from an RPC: one call each

```sql
perform app.audit(v_institution, 'setting.changed', 'setting', p_key,
                  jsonb_build_object('value', v_previous), jsonb_build_object('value', p_value));
perform app.emit_event(v_institution, 'setting.changed', 1, 'setting', p_key,
                       jsonb_build_object('key', p_key, 'value', p_value, 'previous_value', v_previous));
```

Both helpers refuse an institution that is not the caller's active one (`institution_mismatch`), unless the caller is
the platform Master Admin or a backend call without a user (service role, jobs). The app has no insert grant on
either table. Write them **in the same transaction** as the change, so a rolled-back change leaves no log entry.

Already hooked in: `setting_set`, `setting_reset`, `product_setting_set` (platform audit), `secret_set`,
`secret_revoke` (hint only, never the value), membership status changes (trigger, whatever path changed them),
`extension_set_enabled`.

## Event catalogue

`public.event_definitions` is the contract: `(event_key, version)` → `entity_type`, `payload_schema`, description.

- Keys are neutral and dotted: `<entity>.<past_tense_verb>` — `setting.changed`, `client.created`,
  `conversion.completed`. Never education words (Ch 8.3); the schema lint checks names.
- `emit_event` rejects an unknown key or version (`event_unknown`), a wrong entity type (`event_entity_mismatch`)
  and a payload that breaks the schema (`event_payload_invalid`, with field messages). This check on every write is
  the contract test: nothing that breaks the catalogue can reach the log.
- **Changing a payload = a new version row.** Keep the old version working until every listener and webhook has
  moved, then set `deprecated_at` (Ch 43.7 #6). Never edit a published schema in place.
- Extensions add their own events with `extension_key` set (e.g. `example.note_added`).

Current catalogue (v1): `setting.changed`, `setting.reset`, `secret.set`, `secret.revoked`,
`membership.status_changed`, `extension.toggled`, and from the example extension `example.note_added`.

## Listeners and the dispatcher

`public.event_listeners(listener_key, event_key, function_name, extension_key, enabled)` registers a function
`f(p_event jsonb)` for an event key. `app.dispatch_events(limit)` (service role only; the job scheduler of 1.16
calls it) takes pending events with `for update skip locked`, runs the matching listeners, and marks each event
processed. A listener that belongs to an extension runs only for institutions that have that extension on.
A failing listener never blocks the queue: its error is stored in `listener_errors` on the event.

## Who can read

Until permissions exist (0A.17), events and audit rows of the active institution are readable only by the platform
Master Admin (fail-closed); staff see nothing. 0A.17 replaces this with `can('audit.view')` and similar.
The catalogue (`event_definitions`) is readable by every signed-in user.

## Growth (watch-out, Ch 43.7 #5)

`domain_events` grows fast. Indexes start with `institution_id`; there is a partial index on pending events.
**Proposed (0A.09-T2, not built yet):** partition by time and expire processed events after a retention period once
volume requires it. The audit log is kept (it is the legal trail) and only removed with the institution.
