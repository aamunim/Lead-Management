# Lessons learned (Ch 51)

These mistakes and good patterns come from the earlier single-college app. Each one is now a rule, and each rule
is enforced by a milestone. In a multi-institution app every mistake is multiplied, so these rules are strict.
**This page is a living record:** after every serious incident, add a short write-up (template at the end).

| # | What happened | Rule now | Enforced by |
|---|---|---|---|
| 1 | A `SECURITY INVOKER` read function called a helper revoked from `authenticated` → "permission denied" → every AI card was **empty for every user**. | Test every RPC as a **real signed-in role**, never as the database owner; a sweep finds invoker functions / triggers that call functions the role cannot execute; show load errors in the UI instead of blanks; INVOKER + RLS by default, any DEFINER checks the institution. | 0A.04 (RPC-as-role harness, DEFINER audit), 0A.05 (leak test), G5, G17 |
| 2 | Queue bugs: wrong daily-limit counting; a manual check during work pushed to tomorrow; stuck items re-claimed forever (billed every 10 min); instant retries; kicks that woke the server with nothing to do. | Queues have **attempts, back-off, "given up"** and kicks that check feasibility; fair share per institution; idempotency keys. | 0B.12 (hub outbox), 1.16 (job scheduler), G13 |
| 3 | Edge Function time limit (150 s). | Each AI / outside call ≤ 75 s; start new work only in the first 45 s; no SDK retries; compare-mode providers run **in parallel**. | 0B.12, Phase 4 (4.04) |
| 4 | Postgres JIT turned a 15 ms report into 900 ms. | `set jit = off` on heavy plpgsql functions; benchmark with large institutions. | 0A.20 (benchmark), Phase 4 reports, G14 |
| 5 | AI provider model lists contained **retired models**; free tiers had small, unpublished quotas. | Filter retired models, self-heal on 404; record every provider problem where an admin sees it; never fall back silently. Same rule for every provider (integration hub). | 0B.11–0B.12, Phase 4 (4.04) |
| 6 | Cost shown with the wrong model, so budgets stopped work wrongly and admins were misled. | Compute cost with the **model actually used** ($0 for free providers); AI prices in `config/`, validated at build time. | `config/` (0A.01), Phase 4 (4.04) |
| 7 | Old app versions stay installed after every update. | Server decisions (institution, permissions) from the profile / session, not the client; backward-compatible RPCs or a new RPC; expand-then-contract migrations; minimum app version. | 0A.01 (these rules), 0A.02 (PR template), 1.18 (min version), G15 |
| 8 | Speed: every new list badge or chip can mean one extra request per row. | Batch into one RPC; denormalise counters with triggers; stale-while-revalidate caches ("never slower"). | Phase 1A lists, G14 |
| 9 | Phone duplicates also exist among leads the user cannot see. | Check across **all** leads (through one DEFINER function with an institution check), but reveal only name, stage and owner. | 1.03 |
| 10 | Soft delete + an append-only timeline made restore and audit easy (good pattern). | Keep it; notes are separate rows; base for per-institution undo. | 0A.09 (event / audit log), 1.09, G10 |
| 11 | Google Play: call-log permission declaration and an account-deletion web path are required; FCM needs `google-services.json` in the build; pre-launch test devices pollute push stats. | Confirm the Play policy first; native module in Phase 3; web account-deletion path; exclude test devices from push stats. | 0B.20, 1.23, 3.01 (gate) |
| 12 | Never commit secrets: Firebase JSON, `google-services.json`, `.env`, keystore, Apps Script secret, tokens. | Keys entered in the app, stored in the Vault; the app sees only a hint; never logged. | `.gitignore` (0A.01), 0A.02 (secret scanning, Proposed), 0A.07 (secrets), G11 |
| 13 | A per-row `can()` took ~0.45 ms: a SQL-language function with a `SET search_path` clause is never inlined and is planned again on every call (0A.20). | Helpers called many times per statement are PL/pgSQL (plan cached) or SQL without a `SET` clause; RLS loads a person's access once per query (init-plan), never per row. | Benchmark harness `npm run bench` (0A.20), `docs/dev/ACCESS.md` |
| 14 | A PR changed migrations without ticking "Database" under Deploy type; fixing the description did not clear the red check, because the check reads the description from the event of the last push (0B.03). | Fill in the PR template (Deploy type) before opening the PR; after editing the description, the next push re-runs the check (re-running the old job reuses the old description). | CI job "Migration changes declare a database deploy (D27)", `.github/pull_request_template.md` |
| 15 | The first preview APK had no `expo-updates` module: `eas update` published fine, but the phone never checked for updates, so the OTA never arrived (0B.03 staging test). | `expo-updates` is a dependency whenever app.json sets `updates.url`; adding it is a native change (new `runtimeVersion`, new store build). | `npm run check:config` (`scripts/validate-config.mjs`) |
| 16 | The sign-in hook was changed to read `institutions`; SQL tests passed (they call it as the owner) but every real sign-in failed, because the auth service runs it as `supabase_auth_admin`, which could not read that table (0B.07, found by a UI test). | Every table the hook reads needs a grant and a policy for `supabase_auth_admin`; tests call the hook under that role. | `supabase/tests/0B07_lifecycle_test.sql` (hook as `supabase_auth_admin`), UI sign-in tests |
| 17 | Purging an institution failed once it had role assignments: the cascade fired the access trigger, which queued a rebuild for the institution being deleted (FK error). Earlier purge tests used institutions without assignments (0B.09). | Triggers that write rows for an institution must skip an institution that no longer exists; purge tests use an institution with people and roles (`0B09_signup_test.sql`). |
| 18 | A brand-new login made in the Bangla wizard continued in English: the device choice was not stored on the account, so the server fell back to the institution default (0B.09, seen in a UI screenshot). | Values chosen before sign-up travel with the sign-up (user metadata → profile at creation); UI tests assert the language after sign-up. |
| 19 | Two checks in one SQL statement saw the same snapshot and `now()` (the alert job ran twice in one SELECT; a rotation date equal to `now()`). | In SQL tests, run each call in its own statement and store results; remember `now()` is fixed for the whole transaction. |

## How the lessons stay alive (Ch 51.3)

- **Automatic checks in CI:** RPC-as-role tests and the invoker / DEFINER sweep (lesson 1), cross-tenant leak test, secret scanning (lesson 12), AI price config validation (lesson 6).
- **Code-review checklist:** a new queue or job has attempts / back-off / "given up" (lesson 2); a new badge is batched (lesson 8); an RPC signature changed? (lesson 7).
- **Before release:** UX checklist (Ch 47) and the risk register (Ch 50).

## Incident write-up template

Copy this block to the end of the page after any serious incident.

```
### Incident <YYYY-MM-DD>: <short title>
- What happened (user-visible effect, which institutions, how long):
- Why it happened (root cause):
- How it was found:
- What was fixed:
- New rule or check added (and where it is enforced):
- Lesson number added to the table above:
```
