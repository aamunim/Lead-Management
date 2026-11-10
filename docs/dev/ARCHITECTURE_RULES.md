# Architecture rules

> Read this before writing any code. These rules come from the plan (`docs/PLAN_BN.md`, Ch 2, Ch 3, Ch 51) and the
> roadmap ground rules (`docs/DEVELOPMENT_ROADMAP.md`, G1–G20). Breaking a rule is a bug even if the feature works.
> When a rule blocks you, stop and ask the owner; do not work around it.

## 1. Design principles (Ch 2.3)

1. **Nothing is hard-coded.** Institution names, locale, stages, words, fees and rules are all settings or data (section 2).
2. **One product, many forms.** Every institution type is served by one codebase, through:
   - **type profiles** that seed good defaults at setup, all editable later (Ch 7);
   - **labels**: "Course" may be "Class", "Program", "Department" or "Technology" (Ch 8);
   - **modules** switched on or off per institution (Ch 9);
   - **custom fields** on leads and students, with presets per type (Ch 14);
   - **generic building blocks** instead of type-specific code (eligibility, admission tests, fee heads, guardians, forms, calendar, branches, language).
3. **Code reads settings and modules, never `institution_type`.** The type is used once, to seed defaults. This keeps one codebase and lets mixed institutions (e.g. school + college) work.
4. **The core never changes for one institution.** No per-institution columns or branches in core code or tables. Custom needs are met outside the core, from simple to special: settings → custom records → automation → webhooks / API → extensions (Ch 43).
5. **Institution data is always separate.** `institution_id` on every tenant table, `SECURITY INVOKER` + RLS by default, an automatic cross-tenant leak test from day one (Ch 4).
6. **The server trusts the profile / session, never the client.** Institution, permissions and money amounts are decided on the server from the user's session. Old app versions stay installed after every update, so RPC signatures stay backward compatible or a new RPC is added (Ch 3).
7. **Nothing is lost.** Soft delete and an append-only timeline make restore and audit easy (Ch 21). An institution's data is never deleted for non-payment (Ch 9).
8. **No secrets in code or chat.** Admins / the Master Admin enter API keys in the app; they are stored encrypted on the server; screens show only a hint (Ch 3, 42).
9. **Provider problems are never hidden.** Every error is recorded where an admin can see it; no silent fallback without a note; costs use the provider / model actually used (Ch 40, 42).
10. **Show errors, not blanks.** A failed load shows an error with Retry, never an empty screen. Every RPC is tested as a real signed-in role, not as the database owner (Ch 48).
11. **Ask before risky actions.** Confirmation dialog before costly AI re-runs and before deletes.
12. **When there are several ways, offer all as settings (D22)**, with good defaults (plans, recipients, Google sign-in, SMS providers, bulk SMS, OTP).
13. **Neutral internal names.** Tables, columns, RPCs, APIs and event keys are industry-neutral (`client`, `offering`, `cohort`, `conversion` …); words shown on screen come from labels (Ch 8).
14. **The app never gets slower.** Measure before and after every change (section 6).

## 2. Never hard-coded (Ch 2.4)

Everything below is a per-institution setting or data (full key list: plan Appendix A).

- **Branding:** institution name, short name, logo, colours — used on login, web shell, Home top bar, receipts, tab titles, permission texts, public forms and the native WhatsApp listener label.
- **External board flow:** step names, board-ID label, default admission fee, on / off (Ch 36).
- **Reset-password format:** generic, or based on the short name (Ch 10).
- **Locale** (Bangladesh defaults, but each a setting; Ch 13): time zone `Asia/Dhaka`; currency ৳; phone rules (`880`, `01XXXXXXXXX`); week Saturday–Friday, Friday off, scorecard day Sunday; Bangla templates and public forms; payment methods bKash / Nagad / Rocket; address placeholders.
- **Lead score:** rules refer to stage **kind** or id, never to hard-coded stage keys (Ch 22).
- **Everything else:** settings, roles, setup, counters (receipts, refunds, student IDs), Drive connection, PDF / photo service accounts, AI keys, labels, modules, branches, type profiles.

**Product-level (not per institution, Master Admin side):** app name, domain, privacy page contact, developer / feedback inbox owner (Ch 5). These live in `config/` (see `config/README.md`).

## 3. Database patterns (Ch 3.3)

- **Institution everywhere:** every tenant table has `institution_id`; RLS uses the active institution from the session (JWT) claim (Ch 4). Records that belong to a branch also carry `branch_id` (Ch 12).
- **Reads via RLS, writes via RPC:** tables are read through RLS; writes go through RPCs that check permissions with one function, `can(user, action, record)` (Ch 11).
- **`SECURITY INVOKER` by default.** `SECURITY DEFINER` only where unavoidable (e.g. phone-duplicate check across all leads), with an explicit institution and permission check, listed and reviewed, and covered by the leak test.
- **Guard triggers:** important columns cannot be edited directly. Pipeline, admission and fee fields change only through RPCs, which set a session flag such as `app.pipeline_action` that the guard trigger checks.
- **Append-only timeline:** every action writes a line to the activity timeline; this feeds a lead's Changes, the global change log and restore (Ch 21, 38). Notes are rows in a `notes` table (one row per note), never one text blob.
- **Event log:** every important action (lead created, stage changed, payment received …) is written to `domain_events`; automation, webhooks and extensions listen to it (Ch 43).
- **Denormalised columns maintained by triggers** keep lists fast (fee status, paid, due, paper counts, visit status, last contact, score, offering ids, AI chance).
- **Neutral names** for tables, columns and RPCs (Ch 8).
- **Everything sent outside goes through the outbox:** attempts, back-off, "given up", idempotency key (Ch 25, 42, 44).
- **Indexes start with `institution_id`.**
- **Heavy plpgsql report functions use `set jit = off`** (lesson 4).

## 4. App patterns (Ch 3.4)

- Settings are loaded once and cached; refreshed when they change.
- Lists use small RPCs and stale-while-revalidate caches (show last data at once, then refresh). **Caches are keyed by user and institution** and cleared on sign-out or institution switch (Ch 4, 47).
- All text comes from translation files (English + Bangla); renamable words come from labels (Ch 8, 13). A lint check rejects hard-coded UI strings.
- Ask before risky actions: a dialog before costly AI re-runs or deletes.
- Every screen passes the UX checklist (roadmap Section 9.4, plan Ch 47).
- Money is never computed on the client.

## 5. Database changes and old app versions (Ch 3.6)

One migration changes every institution at once, and old app versions stay on phones after every update. Therefore:

- **Backward-compatible RPCs.** Never change an RPC signature in place; add a new RPC (or a new optional parameter with a default) and keep the old one until no supported app version uses it.
- **Expand, then contract.** Add the new thing first; remove the old thing only after all clients have moved. Core schema changes are additive only (Ch 43).
- **Minimum app version** per release; apps below it are asked to update (Ch 46).
- **Staged rollout:** per-institution feature flags, beta institutions first, channel-based OTA, quick rollback (Ch 48; built in milestone 1.18).
- Server decisions (institution, permissions) always come from the profile / session, never from what the client sends.
- Expo SDK / React Native upgrades change `runtimeVersion` and need a new store build: do them at fixed times of the year, **never during admission season**.

## 6. Speed rule: "never slower" (Ch 2.5)

- Measure before and after every change that touches a list, a page or a report.
- Benchmark with about 3,000 leads per institution, plus one large institution, so a big institution never slows the others (Ch 4).
- Batch new badges / chips into the screen's single RPC; never one request per row (lesson 8).
- Speed techniques and caching: plan Ch 47; speed-check tool: Ch 46.

## 7. Observability (Ch 3.7)

- Every log line and crash report is tagged with institution id and user id.
- Never log secrets or full personal data.
- An error dashboard and spike alerts come in milestone 1.18.

## 8. App identity and secrets (Ch 3.8)

- Working name "Lead Management Platform" (D21, final name still open). **Android package `com.leadora.leads` (decided, D36)** and deep-link scheme `leadora`. None of them contains "admission", "college", "school" or "student" — `npm run check:config` enforces this. The package id cannot change after the first Play Store release; the Firebase Android app must be registered with exactly this package.
- `runtimeVersion` is pinned in `app.json`; changing it requires a new store build.
- Never commit: Expo token, Supabase access token, DB password, project ref, FTP credentials, `google-services.json`, keystore, `.env`, Apps Script secret, any API key. They live in the CI secret store and the Supabase Vault (`.gitignore` already blocks the common files).
