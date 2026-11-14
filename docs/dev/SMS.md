# SMS gateways (0B.13)

Plan: Ch 42.4, 42.9 I5, 42.10 rows 3–5 and 8; Ch 5.6; Ch 9.7; Ch 10.5; decisions D3, D4, D7, D15, D22, D33, D34, D35.

## Status

- **Built:** Custom HTTP adapter, platform gateway as backup, routes, masking status, parts and cost preview, balance
  and low-balance alerts, switching the primary, delivery reports by push and by polling, the daily contract-test
  plumbing.
- **Waiting for the owner (0B.13-T1, open question Q3):** which gateways the first institutions use. Candidates: SSL
  Wireless, BulkSMSBD, Alpha SMS, MiMSMS, Infobip, operator corporate SMS; Twilio for international.
  - The 3–4 ready-made adapters (T2) are built after that list is confirmed and each API, price and masking rule is
    checked.
  - Until then any gateway with an HTTP API works through Custom HTTP.
- **Launch gate (T11):** promotional SMS rules (sender ID, time, content; Ch 53.4 row 2) must be checked by the legal
  task before Campaigns (Block 1B) sends bulk SMS live.

## Custom HTTP (adapter `custom-http-1`)

Master Admin only. Settings (provider schema, checked on save):

- `send_url` (https), `method` GET or POST, `body_format` form or JSON.
- `params`: a JSON map. Values may use `{to}`, `{message}`, `{sender_id}`, `{api_key}` and `{unicode}` (1 for Bangla text).
- `success_match`: text or `/regex/` the response must contain. Without it, any 2xx counts as sent.
- `message_id_path`: e.g. `data.id`.
- `balance_url` + `balance_path`: the balance check.
- `status_url` (with `{message_id}`) + `status_path`: delivery reports by polling, for gateways without push.
- `sender_id`.
- `masking` {type `non_masked` / `masked`, status `applied` / `approved` / `rejected`, `non_masked_sender_id`}: a masked
  sender id is used only once approved (D35); until then the non-masked one.
- `route`: `transactional` / `promotional` / `all`.
- `price_per_part`, `rate_per_minute`, `low_balance_threshold`, `timeout_ms` (at most 20 s).

Keys: `api_key`, and `webhook_secret` for push reports (HMAC-SHA256 of the body in `X-Signature`), both write-only.

**Safety (Proposed):**

- Only https and public hosts are called.
- Refused: private, loopback, link-local (cloud metadata), carrier-grade NAT, multicast and internal names.
- Checked when saving (database, `app.url_is_public`) and again before every call, after DNS (adapter, `checkTarget`).
- No redirects are followed.
- Keys are scrubbed from every error detail.

Errors are mapped to whose side they are on (I10): auth, balance, sender, recipient → the institution; 5xx and timeouts → the provider; anything else → the platform.

## Routes, backup, switching

- OTP, urgent and transactional messages use connections whose route is `transactional` or `all`; bulk uses `promotional` or `all`. The OTP lane of 0B.12 still goes first.
- The platform gateway is used when the platform pays, when the institution has no connection, and — unless switched off for the institution (Integrations tab) — as the last backup. Proposed default: on. It is billed to the institution as platform-paid usage.
- **Switch gateway (D33, D34, D46 — Master Admin only):** add the new connection, check it with Send test, then "Make primary".
  - The old primary becomes the backup.
  - Queued messages use the new one at once, because routing happens at send time.
  - The log and the ledger keep the gateway that actually sent each message.
  - Every switch is audited.

## Parts, cost, balance

- Parts: plain text 160 (153 per part when split); Bangla / Unicode 70 (67). The same rule in the database
  (`app.sms_parts`), the hub (`_shared/hub/sms-parts.ts`) and the app (`src/lib/sms-parts.ts`); a unit test keeps them in step.
- The panel's Send test shows parts and cost before sending.
- The health round stores the balance:
  - below `low_balance_threshold`: every Master Admin is alerted, at most once a day;
  - at zero, or on a balance error: the institution sees "balance exhausted — recharge with the provider" when it pays directly.

## Delivery reports and contract tests

- Push: `hub-webhook/<connection_id>` (0B.12). Poll: sent messages without a report after 15 minutes (for up to 3 days) on connections with a `status_url`.
- Daily contract test (I5): adapters with a sandbox declare `contractTest`. A failure alerts the Master Admins (once a day). Custom HTTP has none; the ready-made adapters add theirs.

## Tests

- SQL `supabase/tests/0B13_sms_gateway_test.sql` (14 checks).
- Unit `scripts/tests/custom-http.test.mjs`: SSRF, masking, parameters, errors, balance, parts and their parity.
- Unit `scripts/tests/hub-worker.test.mjs`: health balance, polling, contract tests.
- UI `scripts/ui/delivery.web.test.mjs`: parts preview, make primary.
