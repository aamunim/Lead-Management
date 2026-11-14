# Hub runtime (0B.12)

Plan: Ch 42 (42.2, 42.9 I4–I8, I12), Ch 25.5, Ch 9.5, 9.7, Ch 51 lesson 2; decisions D7, D15.

## How a message goes out

1. **Queue** — `app.outbox_enqueue(institution, channel, priority, recipient, payload, idempotency_key, category, send_after)`.
   - Server code only (service role): `notify()` in 1B, OTP sign-in in 0B.18, the panel's Test button. People cannot call it.
   - The institution is the one of the record being processed (I1).
   - The same key returns the first message, so nothing is sent twice.
   - Priority lanes: `otp` → `urgent` → `transactional` → `bulk`.
2. **Gates** — checked when queued and again before sending (`app.outbox_gate`):
   - closed or suspended institution: nothing;
   - before approval: OTP only (`institution_can_message`, 0B.09);
   - monthly limit (`sms_month`, `email_month`): bulk stops, OTP and urgent pass.
   - A gate that closes after queueing *holds* the message, and it is released hourly.
3. **Wake-up** — pg_cron calls `app.hub_kick_if_due()` every minute. The worker is woken only when something is due (lesson 2). An OTP or urgent message wakes it at once (trigger).
   - The worker URL and key are read from Vault (`hub_worker_url`, `hub_worker_key`).
   - Without them (local, CI) nothing is called.
4. **Claim** — `outbox_claim`:
   - Items stuck in `sending` for 10 minutes become `unknown`: never claimed again, never billed twice.
   - Then OTP of every institution goes first.
   - Then a fair share per institution (`hub_claim_per_institution`, Proposed 20), so one institution's 20,000-message bulk never delays another's OTP.
5. **Route** — `outbox_route` uses the 0B.11 resolver: the message's own institution, primary first, then backups.
   - Leaves out open circuits and connections over their `rate_per_minute`.
   - A Test message is pinned to one connection.
6. **Send** — the worker (`supabase/functions/hub-worker`, core in `_shared/hub/worker-core.ts`) tries each connection's adapter in order.
   - Every failure is recorded on that connection.
   - Success on a backup records `fallback_from` on the message and in the log (no silent fallback).
7. **Result** — `outbox_result`:
   - **Sent:** delivery log, ledger row, usage counter (parts).
   - **Failed:** back-off of 30 s, 1, 2, 4 … minutes, capped at an hour; never an immediate retry.
   - **After the last attempt:** `given_up`.
   - A late or repeated result changes nothing and is not billed.
8. **Circuit breaker** — `hub_circuit_failures` (Proposed 3) failures in a row pause a connection for 5 minutes.
   - The backup is used meanwhile.
   - Every Master Admin gets a `circuit_open` alert.
9. **Callbacks (I4)** — `POST /functions/v1/hub-webhook/<connection_id>`.
   - The connection named in the URL is loaded, and the request is trusted only with *that* connection's `webhook_secret` signature.
   - Each event is stored once in `webhook_events` (duplicates ignored), then applied to the message sent through that same connection (`delivered` / `undelivered`).
   - Forged callbacks are stored as rejected.
   - A status that arrives before the send result stays `pending` for reconciliation.
10. **Health** — the worker's health round calls each adapter's `health()` hourly. The result is stored as last success / last error.

## Ledger and costs

- `usage_ledger`: one row per institution, local day (its own time zone, I12), provider, channel, category and payer.
  - Holds count, parts, failed parts and cost (`price_per_part` from the connection's settings).
  - Only rows with payer `platform` are billable (D15).
  - Sandbox sends cost nothing and do not use the monthly limit.
- SMS parts: 160 / 153 for plain text, 70 / 67 for Bangla (`app.sms_parts`).
- Send times are computed in the institution's time zone (`app.institution_local_instant`). The quiet-hour rules themselves come with `notify()` in 1B.

## Adapters

- Versioned interfaces in `_shared/hub/adapters.ts`:
  - SMS and email: `send`, `health`, `verifyWebhook`, `parseStatus`.
  - Payment: declared for Block 2.
- Registry in `_shared/hub/registry.ts`. Real adapters register there as they ship: 0B.13 SMS, 0B.14 email.
- Mock adapters (`mock.ts`, providers `mock_sms` / `mock_email` from `supabase/seeds/0B12_mock_providers.sql`) are for tests only.
  - They are registered only when `HUB_ALLOW_MOCK=1`, and the seed is never applied to staging or production.

## Deploying (once per environment)

1. Deploy the functions: Actions → app-update, with "Edge Functions to deploy" = `hub-worker hub-webhook`.
2. In the Supabase SQL editor, store the worker address and key in Vault. Never in the repository:
   ```sql
   select vault.create_secret('https://<project>.supabase.co/functions/v1/hub-worker', 'hub_worker_url');
   select vault.create_secret('<service role key>', 'hub_worker_key');
   ```
3. Never set `HUB_ALLOW_MOCK` outside local development.

## Panel

- **Delivery log:** every result with connection, fallback, sandbox, parts, cost and the error with whose side it is on; filtered by channel. Also the usage ledger, with billable rows marked.
- **Institution → Integrations → a connection → Send test:** queued pinned to that connection, then visible in the delivery log.
- **Dashboard alerts:** circuit open, key rotation, setup incomplete.

## Tests

- SQL `supabase/tests/0B12_hub_runtime_test.sql` (22 checks), including 20,000 queued bulk messages with another institution's OTP in the first round.
- Unit `scripts/tests/hub-worker.test.mjs` (8).
- End-to-end `scripts/e2e/hub.e2e.mjs`: the real worker core through the API as the service role, two institutions, fallback, callbacks.
- UI `scripts/ui/delivery.web.test.mjs`.
- Leak fixtures for the four new tables.
