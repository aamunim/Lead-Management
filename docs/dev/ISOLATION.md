# Where institution data must stay separate (Ch 4.3) — status per area

Every row below is a review item in the PR template. "Proven by" names the automatic test that fails if it breaks.

| Area | Rule | Status | Built in | Proven by |
|---|---|---|---|---|
| Tables | `institution_id` + RLS on every tenant table, including custom fields / records and extension tables (Ch 43) | **Done** | 0A.03–0A.05 | schema lint, leak test (table probe) |
| RPC / server functions | Filter by the active institution; INVOKER by default; `can()` for permissions | **Done** (tenancy); `can()` in 0A.17 | 0A.03, 0A.04, 0A.17 | leak test (RPC probe), lint (DEFINER rules) |
| Storage | Bucket `institution-files` (private); path `<institution_id>/<area>/…`; policies allow only the active institution's folder | **Done** | 0A.06 | leak test (storage probe), e2e `isolation.e2e.mjs` |
| Google Drive folders | One folder tree per institution | Planned | 2.14 | — |
| Realtime | Private channels `inst:<institution_id>:<topic>`; only the active institution's channels; published tables must be tenant tables | **Done** | 0A.06 | leak test (Realtime probe), e2e |
| Edge Functions | User and institution from the session via `public.current_session()` (never the body); that institution's connections and secrets only | **Done** (middleware); connections in 0B.11 | 0A.06, 0B.11 | unit tests, `whoami` run with a real token |
| Background jobs | One loop over due institutions, each in its own time zone and settings | Planned | 1.16 | — |
| Push | Tokens tied to institution + user + app | Planned | 1.23 | — |
| Client cache | Keyed by user + institution; cleared on sign-out, user switch, institution switch (`src/lib/session.ts`) | **Hook in place**; caches in 1.34 | 0A.03, 1.34 | — |
| Export | Active institution only, with permission and log | Planned | 1.14, 1.25 | — |
| Logs and crashes | Tagged with institution and user ids, redacted (keys, tokens, phone numbers, national ids); an institution's admin never sees another's logs | **Done** (logger + redaction); dashboard in 1.18 | 0A.06, 1.18 | unit tests (`edge-shared.test.mjs`) |
| Public pages | Institution in the URL: `/apply/<slug>`, `/refer/<code>`; own domain (D16) | Planned | 1.29, 1.30, 5.02 | — |
| External connections | `institution_id` on connections; callback URL carries the connection id | Planned | 0B.11–0B.12 | table probe (once the table exists) |

## Conventions introduced in 0A.06

- **Storage path:** `<institution_id>/<area>/<...>`. `area` examples: `documents`, `voice-notes`, `receipts`, `photos`.
  Upload, read, list, sign, move and delete are allowed only under the active institution's folder.
  A public bucket is reported by the leak test unless allow-listed with a reason.
- **Realtime channel:** `inst:<institution_id>:<topic>` with `{ private: true }`. Broadcast and presence on any other
  name are refused for signed-in users.
- **Edge Function:** wrap the handler with `withTenant('<name>', handler)` from `supabase/functions/_shared/tenant.ts`.
  It resolves the session through `public.current_session()`, gives `ctx.log` (tagged, redacted) and `ctx.budget`
  (≤ 75 s per outside call, new work only in the first 45 s), and turns errors into the error contract.
- **Error contract:** `supabase/functions/_shared/errors.ts` — every error has a `code`, a translated `messageKey` and an
  `action` (`sign_in`, `choose_institution`, `refresh_session`, `retry`, `none`). The app uses `describeError` /
  `callWithSessionRetry` (`src/lib/errors.ts`) and shows an error state, never an empty list.
- **Logs:** `createLogger` (server) and `logger` (app) — one JSON line, always with `institution_id`, `user_id` and
  (server) `request_id`; values pass through `redact` (keys, tokens, JWTs, Bearer headers, BD phone numbers masked as
  `017•••••234`, national ids).

## Running Edge Functions locally

`npm run check:functions` typechecks them with Deno. To run one without the Supabase Edge runtime image:

```bash
SUPABASE_URL=http://127.0.0.1:54321 SUPABASE_ANON_KEY=<publishable key> \
  npx --yes deno@2 run --allow-net --allow-env --allow-read supabase/functions/whoami/index.ts
```
