# Risk review — Phase 0A (0A.20-T7)

Plan Ch 50 rows that Block 0A must handle: T1–T5, T9 (technical), R1–R20 and R+ (roles and access), X7 (data model).
Status: **Handled** (built and tested in 0A), **Partly** (the 0A part is done; the rest has a named milestone) or
**Deferred** (named milestone). Evidence points to the tests that prove it. Reviewed at the end of 0A.20.

## Technical (Ch 50.3)

| Row | Risk | Status | What 0A did (evidence) | Still open → milestone |
|---|---|---|---|---|
| T1 | Tenant isolation beyond tables (storage, Realtime, Edge Functions, cron, push, client cache) | Partly | RLS on every tenant table with `institution_id` from the session (0A.03–0A.05); storage paths, private Realtime channels, Edge Function tenant context (0A.06); client cache keyed by user + institution and cleared on switch / sign-out (0A.14). Catalogue-driven leak test: 21 tenant tables, 56 RPCs, storage, Realtime, extension schemas, dual-membership user (`npm run test:leak`, self-test). | Per-institution job runner and its isolation → 1.16; push → 1.23 (both add their objects to the leak test). |
| T2 | Configuration explosion (type × module × setting × role) | Partly | Typed settings registry with JSON Schema per key (0A.08); role matrix generated from the registry and templates — 28 template roles × 11 permissions × scopes, 3,020 checks; a new permission without an expectation fails (`npm run test:role-matrix`, 0A.20); seed generator per template set (0A.20). | Type profiles as data and their seeds → 0B.03; per-institution settings keys → 0B.01. |
| T3 | Labels and two languages (hard-coded words, long Bangla text) | Handled | i18n lint and missing-key check (0A.10), neutral keys and label dictionary (0A.12), Bangla line height and design tokens (0A.13), terminology editor with preview (0A.19); screenshot matrix: every route × light/dark × bn/en with the weird-labels institution, committed baselines (0A.20). | — |
| T4 | Many institutions: a large one slows the others | Partly | `institution_id`-first indexes (schema lint, 0A.04); precomputed `user_access` and RLS that loads access once per query (0A.17); benchmark harness, large vs small institution side by side, noisy-neighbour check (`npm run bench`, 0A.20). The benchmark found `can()` re-planning on every call (SQL function with `SET`); fixed, 14× faster. | Real lead benchmarks → 1.01–1.04; CI slow-down gate built (0A.20-T5, D41) with the agreed threshold 25 % / 2 ms (D40). |
| T5 | One migration changes everyone; old app versions linger | Partly | Every PR applies all migrations to a fresh database (CI); minimum app version and "update required" screen (0A.14); app-update workflow; extension migrations with checksums (0A.09). | Staging rehearsal (migrate staging with seed data, full suite, promote) → **0A.20-T8, waiting for the staging accounts**; feature flags per institution → 1.18. |
| T9 | Per-institution secrets | Handled | Supabase Vault, write-only from the app, rotation with a valid-from date, revocation, values never in logs or audit (redaction tested), `integration.manage` is sensitive (0A.07, 0A.16). | — |

## Roles and access (Ch 50, rows from Ch 11.3)

| Row | Risk | Status | What 0A did (evidence) | Still open → milestone |
|---|---|---|---|---|
| R1 | New module → permission keys and roles changed by hand | Handled | Module manifests loaded into the registry on every deploy (`npm run db:permissions`), labels required in both languages (0A.16). | — |
| R2 | Branches and deep levels; only own / team / all | Handled | Org-unit tree with closure table (0A.15); scopes own / team / org_unit / branch / all, branch-limited assignments (0A.17); role matrix covers every scope (0A.20). | — |
| R3 | One person, several duties | Handled | Several role assignments, each with its own limits; limits never mix across assignments (0A.17 tests, role matrix). | — |
| R4 | Hidden behaviour of `acts_as` | Handled | Explicit behaviour flags per role (0A.16), editable in the role editor (0A.18). | — |
| R5 | `settings.manage` means too much | Handled | One permission per settings area (0A.16). | — |
| R6 | Wildcard `*` grows silently | Handled | `*` only on the Super Admin role, never platform permissions; sensitive permissions need two-step sign-in to grant (0A.16, 0A.18 tests). | Two-step sign-in screens → 0B.02 / 0B.18. |
| R7 | Two access systems ("who" rules and permission keys) | Handled | "Who" selector only for non-access settings; access is always a scoped permission (0A.16/0A.17). | — |
| R8 | Fragile ranks | Handled | No escalation (cannot give what you do not hold), outranking checks on assign / unassign / deactivate (0A.17, 0A.18). | — |
| R9 | Staff copy or export data before leaving | Deferred | Deactivation ends sessions at once (0A.18). | Export controls and watermarking → 1.25, import / export → 1.14. |
| R10 | Sensitive fields | Partly | Field registry and `sensitive_field.view` (0A.16). | Field-level masking → 1.25. |
| R11 | New kinds of approval | Deferred | — | Approval engine → 1.24. |
| R12 | Temporary access | Handled | Valid from / to on assignments, expiry job (pg_cron), shown on the person's roles (0A.17, 0A.18). | — |
| R13 | Sharing one record | Deferred | — | Collaborators → 1.26. |
| R14 | Complex rules slow lists | Handled | Precomputed `user_access`, init-plan RLS (+2.8 ms on 3,000 rows, 0A.17); benchmark (0A.20). | Lead list benchmarks → 1.04. |
| R15 | Stale permissions in the JWT | Handled | Access version in the token checked on every request; changed access stops the old session on its next request (0A.03, 0A.17); deactivation also ends sessions (0A.18). | — |
| R16 | "Why can't I see this lead?" | Handled (basic) | Access explainer per role: scope, branch / offering limit, dates (0A.18). | Field rules in the explainer → 1.25. |
| R17 | API keys, webhooks, custom records, extensions outside roles | Partly | Extensions switched per institution by the Master Admin, own schema, lint (0A.09). | Outgoing webhooks → 1.31; custom records and incoming API → 2.20. |
| R18 | Permission names tied to one industry | Handled | Neutral permission keys checked by the manifest lint; labels for words (0A.12, 0A.16). | — |
| R19 | Groups of institutions and portal users | Partly | One person in several institutions with an active one (D25, 0A.03), `user_kind` claim. | Groups and the group dashboard → 1.19 (group-owner leak test added there). |
| R20 | New permissions in future releases | Handled | Rollout rule (template defaults; inheriting own roles only when not sensitive) and the "new permissions in this release" screen (0A.16, 0A.18). | — |
| R+ | Locking yourself or everyone out | Handled | Last Super Admin and self-lockout guards on unassign and deactivate (0A.17, 0A.18 tests). | — |

## Data model (Ch 50.5)

| Row | Risk | Status | What 0A did (evidence) | Still open → milestone |
|---|---|---|---|---|
| X7 | Pressure on the data model | Partly | Neutral keys everywhere (0A.12), event catalogue with versioned payloads (0A.09), extension schemas (0A.09), org units instead of a single team field (0A.15). | Custom fields → 0B.06; custom records → 2.20. |

## Lessons (Ch 51.4 #1)

New in 0A.17–0A.20, added to `LESSONS.md`: a SQL-language function with a `SET` clause is planned again on every call —
helpers called many times per statement must be PL/pgSQL (found by the benchmark, 0A.20).
