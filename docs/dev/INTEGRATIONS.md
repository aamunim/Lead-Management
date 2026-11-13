# Integration hub core (0B.11)

Plan: Ch 42 (42.1, 42.2, 42.8, 42.9 I1–I3, I9–I11, I14, 42.10 rows 1 and 9), Ch 5.3, 5.6, Ch 9.7; decisions D3, D4, D15, D22.

## Data

- `integration_providers` — product catalog: kind (sms, email, payment, ai, storage, push, pdf_image, domain, app), name,
  `settings_schema` (JSON Schema of the non-secret settings), `secret_fields` (values only ever go to Vault), capabilities,
  `adapter_version` (null until the adapter ships: 0B.13 SMS, 0B.14 email, Block 2 payments…), status. Seeded with generic
  entries (Custom HTTP SMS, SMTP, SSLCommerz, Google Drive, FCM, own AI key); the ready-made SMS adapters follow when the
  pilot gateways are known (Q3).
- `integration_connections` (per institution) and `platform_connections` (the platform's default gateways): mode
  sandbox / live, status, settings, priority (1 = primary, then backups), `live_test_passed_at`, `last_success_at`,
  `last_error` {code, responsibility, at, detail}. Never readable directly; RPCs only.
- `institution_service_payers` — who pays per institution and service (D15): `direct` (its own account) or `platform`.
- Secrets — the 0A.07 Vault store (`institution_secrets`) for institutions, `platform_secrets` for the platform; ref
  `conn.<connection>.<field>`. `integration_audit` — every change, values redacted, hints only.
- `integration_error_kinds` — whose side an error is on (I10): platform (adapter bug, config), institution (auth,
  balance, blocked account, merchant inactive, sender not approved), provider (down, timeout, rate limit).

## Rules

- **Master Admin only (D4):** every write needs `platform.integrations` + a two-step session. The institution's own
  Super Admin can neither write nor read keys; the institution sees status only (`integration.view_status`, Admin
  template by default): Settings → Connections.
- **Write-only keys:** `connection_secret_set` stores the value in Vault and returns only the hint (`abcd…wxyz`); the
  panel shows hint, age in days, and a scheduled rotation. Edge Functions read the key in force with
  `connection_secret_for_service` (service role only).
- **Rotation:** a key with a future effective-from date waits; the current key keeps working until then. Proposed: a
  reminder to rotate after `key_rotation_reminder_days` (365), daily job, panel alert.
- **Resolver (I1):** `app.resolve_connection(institution_of_the_record, kind, purpose)` — the institution comes from the
  record being processed (lead, payment, outbox row), never from client input. Order: the institution's active
  connections by priority; the platform's when the platform pays or the institution has none. A closed or suspended
  institution gets nothing.
- **Mode (I3):** sandbox / live shown everywhere; a live connection without a passed live test is left out for bulk
  sending (and later live payments). Switching mode clears the live test. Until the adapters run a real test, the
  Master Admin marks it after testing by hand.
- **Close hook (I14):** when an institution is closed, its connections are disabled and its secrets destroyed (values
  and metadata). Later milestones add API keys and webhooks to `app.integration_close`.
- **Secret scanning (T10):** `.gitleaks.toml` adds SSLCommerz store passwords, SMS gateway keys, Google refresh tokens
  and SMTP passwords to the default rules; `scripts/tests/gitleaks-rules.test.mjs` checks them.

## Screens

- Panel → Providers: catalog and the platform gateways (add, settings form from the schema, keys, live test, on / off).
- Panel → Institution → Integrations: the institution's connections, who pays per service, change log.
- App → Settings → Connections: status only (mode, last success, problem and whose side).

## Tests

- SQL `supabase/tests/0B11_integration_hub_test.sql` (24 checks), leak fixtures, UI `scripts/ui/integrations.web.test.mjs`.
