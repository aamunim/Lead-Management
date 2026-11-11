# Leadora — Development Roadmap

> **Version 1 · based on the consolidated plan `PLAN_BN` (version 2, 53 chapters, decisions D1–D26).**
> Product name: **Leadora** (D37); Android package `com.leadora.leads` (D36).

## 1. About this roadmap

### 1.1 Purpose
This roadmap turns the product plan into an **ordered list of milestones and tasks**, from the first commit to the
last feature. It has two readers:

- **The owner:** to see what is built first, what comes next, what can be sold after each phase, and where the owner
  must decide or approve something.
- **The developer** (an AI coding agent or a human team): to build in the right order, without skipping a rule,
  setting, permission, test or edge case that the plan requires.

The plan (`docs/PLAN_BN.md`) says **what** to build and **why**. This roadmap says **in which order**, **what
"done" means**, and **what must not be missed**. When they disagree, stop and ask the owner; then update both.

### 1.2 How to read a milestone
Every milestone has the same shape:

| Part | Meaning |
|---|---|
| **ID and title** | e.g. `1.04 Pipeline stages, lost and reopen`. IDs are unique and never reused. |
| **Goal** | What the milestone delivers, in one or two sentences. |
| **Depends on** | Milestones that must be finished first. Never start a milestone before its dependencies are done. |
| **Plan chapters** | Where the full design is ("Ch 17" = chapter 17 of the plan). Read them before starting. |
| **Decisions** | Owner decisions (D1–D26) that apply. |
| **Build** | What is created: data (tables, RLS), server (RPCs, functions, jobs), app and web (screens), settings and permissions. |
| **Tasks** | A checklist (`☐`) in build order. Each task is small and verifiable. Task IDs: `<milestone>-T<n>`. |
| **Tests** | The tests that must exist and pass. |
| **Done when** | Acceptance criteria. The milestone is not finished until every line is true. |
| **Watch-outs** | Traps from the plan's critique tables, risks (Ch 50) and lessons (Ch 51). |
| **Owner checkpoint** | What the owner sees or approves at the end. |

Items marked **Proposed:** come from the plan's প্রস্তাবিত (not yet approved) items. Build them only after the
owner approves, or keep them behind a switch.

### 1.3 Milestone IDs and order

| Block | IDs | Contents |
|---|---|---|
| Stage S | S.01–S.06 | Before coding: decisions, accounts, external checks, pilot institutions, conventions |
| Phase 0A | 0A.xx | Core skeleton, multi-tenancy, labels and languages, roles and permissions, branches, event log, CI |
| Phase 0B | 0B.xx | Master Admin, onboarding, type profiles, modules / plans / billing, login methods, integration hub with SMS and email |
| Phase 1A | 1.01–1.15 | Core CRM: leads to follow-ups, calls, notes, visits, import / export |
| Phase 1B | 1.16–1.35 | Templates, notifications, campaigns, public forms, approvals, automation, groups, web, platform features |
| Phase 2 | 2.xx | Admission and students: offerings and seats, tests, papers, IDs, fees, payments, board flow |
| Phase 3 | 3.xx | Android native: call-log sync, WhatsApp auto-log, caller card, call lock |
| Phase 4 | 4.xx | AI, credits and leaderboard, team activity and reports |
| Phase 5 | 5.xx | Alumni and referrals, Photo Studio, feedback chat, applicant status page, branded apps |
| Later | L.xx | Other industries, portal, official WhatsApp API, more gateways, extensions |

Phases are built **in order**. Inside a phase, follow the "Depends on" lines; milestones without a dependency
between them may run in parallel.

### 1.4 Status words
- **Decided (D#):** approved by the owner. Build as written.
- **Proposed:** in the plan, waiting for the owner. Ask before building.
- **Gate:** a check that must pass before the next step starts (for example the Google Play permission check before Phase 3).

## 2. Ground rules (never break these)

These rules apply to **every** milestone. They come from the plan's principles (Ch 2), the lessons of the earlier
version (Ch 51) and the risk register (Ch 50). Breaking one of them is a bug, even if the feature works.

| # | Rule | Why | Plan |
|---|---|---|---|
| G1 | **Every tenant table has `institution_id`** (and `branch_id` where records belong to a branch), with an index that starts with `institution_id`. | Data of different institutions must never mix. | Ch 4, 12 |
| G2 | **RLS on every table**, using the active institution from the session claim; never trust an institution id sent by the client. | Old app versions and tampered clients exist. | Ch 4, 51 |
| G3 | **`SECURITY INVOKER` by default.** A `SECURITY DEFINER` function is allowed only with an explicit institution and permission check, and is listed in the leak test. | DEFINER bypasses RLS; the earlier version had hundreds. | Ch 3, 4 |
| G4 | **The cross-tenant leak test passes on every change.** New tables, RPCs, storage paths and Realtime channels are added to it automatically or the build fails. | One missed policy leaks another institution's data. | Ch 4, 48 |
| G5 | **Every RPC is tested as a real signed-in role**, never only as the database owner. | Permission errors were invisible in the earlier version. | Ch 51 |
| G6 | **Permissions come from the registry** (`module.action` + scope) and are checked with one function, `can(user, action, record)`. No role names in code. | New modules and custom roles must work without code changes. | Ch 11 |
| G7 | **No user-facing word is hard-coded.** Text comes from translation files (English + Bangla); renamable terms come from labels. A lint check enforces it. | Every institution can rename terms; the UI is bilingual. | Ch 8, 13 |
| G8 | **Neutral internal keys** (`client`, `offering`, `cohort`, `conversion` …) in tables, RPCs, APIs and events; education words only as labels. | The product will be sold outside education later. | Ch 8, 49 |
| G9 | **Code checks settings and modules, never the institution type.** The type is used once, to seed defaults. | All types must work from one codebase. | Ch 7 |
| G10 | **Append-only timeline and soft delete.** Every important action writes a timeline / `domain_events` row; deletes are soft and restorable. | Audit, restore and automation depend on it. | Ch 21, 43 |
| G11 | **No secrets in code, logs, chat or the repository.** Keys live encrypted on the server; screens show only a hint. | Leaked keys cost money and trust. | Ch 42, 51 |
| G12 | **Outside services only through the integration hub** (adapter, outbox, retries, signed callbacks, usage ledger). | Many providers × many institutions; failures must be visible and isolated. | Ch 42 |
| G13 | **Queues have attempts, back-off, "given up" and idempotency keys.** | The earlier version billed for endless retries. | Ch 44, 51 |
| G14 | **The app never gets slower.** Measure before and after; benchmark with about 3,000 leads per institution and several institutions. | Speed was the owner's rule in the earlier version. | Ch 2, 47 |
| G15 | **Backward-compatible RPCs.** Old app versions stay in the field; never break a signature in place; use a minimum app version when needed. | Users don't update at once. | Ch 48, 51 |
| G16 | **Core schema changes are additive** (expand, then contract later). No per-institution columns in core tables. | Custom needs must not break the core. | Ch 43 |
| G17 | **Show errors; never fail silently.** Every load and action shows a clear error with Retry. | Empty screens hid real failures before. | Ch 47, 51 |
| G18 | **Money is never computed on the client.** Amounts, fees, discounts and invoices come from the server; payments are verified server-to-server. | Tampering and double payments. | Ch 34, 35 |
| G19 | **Every user-visible change ships with a "What's new" entry** and states its deploy type (database / functions / app update / store build). | Owner and users must know what changed. | Ch 46, 48 |
| G20 | **Each new screen passes the UX checklist** (light / dark, Bangla / English, keyboard, large font, low-end phone, empty / error states). | Quality must be equal on every screen. | Ch 47 |

## 3. Definition of Done (every task and milestone)

A task or milestone is **done** only when all of these are true:

1. The behaviour matches the plan chapter(s) and the milestone's "Done when" list.
2. Data: migrations applied in a clean database and in a database with seed data; RLS on; indexes start with `institution_id`.
3. Permissions: new actions registered in the permission registry with defaults for system roles and role templates; sensitive ones flagged.
4. Labels and text: every new term registered as a label; all strings in English and Bangla translation files.
5. Tests: unit, RPC-as-role, cross-tenant leak and role-matrix tests added and green; UI and screenshot tests for new screens.
6. Performance: list and page timings measured against the benchmark; no regression.
7. Settings: new per-institution settings added to the settings registry with defaults per type profile (Appendix A of the plan).
8. Events: important actions write `domain_events` / timeline rows.
9. Docs: "What's new" entry; the plan or this roadmap updated if anything changed; deploy type noted.
10. Owner checkpoint shown (for milestones that have one).

## 4. Phase overview

| Phase | Goal | Exit criteria (gate to the next phase) | What can be sold / used after it |
|---|---|---|---|
| **Stage S** | Decisions, accounts and checks before coding | Blocking decisions taken (S.01); accounts ready; pilot institutions agreed | — |
| **0A** | Safe multi-tenant skeleton | Leak test and role-matrix test green in CI; two test institutions fully isolated; labels and two languages work; benchmark baseline recorded | Internal only |
| **0B** | Platform ready for real institutions | An institution can be created, approved, set up from its type profile, and sign in with password / Google / OTP; SMS and email go through the hub | Internal pilots (no CRM yet) |
| **1** | Core CRM | A pilot institution runs its daily lead work: leads, follow-ups, calls, notes, templates, notifications, campaigns, public form | **First paid customers** (lead-focused plans) |
| **2** | Admission and students | Admission, fees, payments (manual + SSLCommerz), receipts, IDs, board flow work end-to-end for school, college and coaching profiles | **Full education product** (Starter / Standard) |
| **3** | Android native | Play permission approved; call-log sync, WhatsApp auto-log, caller card and call lock stable on test phones | Calling-team institutions |
| **4** | AI and team | AI chance and credit within budget; leaderboard, scorecard, team activity and reports live | **Pro plan** |
| **5** | Everything else | Alumni and referrals, Photo Studio, feedback chat, applicant status page, branded app option | Enterprise / add-ons |
| **Later** | Growth | Other industries, portal, official WhatsApp API, more gateways, extensions | New markets |

**Dependency chain (simplified):**
`Stage S → 0A (tenancy → labels/i18n → roles → branches → event log) → 0B (Master Admin → setup/types → modules/plans → login → integration hub) → 1A (leads → list → pipeline → follow-ups → calls/notes) → 1B (templates → notifications → campaigns → forms → approvals/automation) → 2 (offerings → fees → payments → IDs → board flow) → 3 → 4 → 5 → Later`

**Proposed (Ch 52.11):** Phase 0 is split into 0A (structures that are expensive to change later) and 0B (the rest of the
platform), so that 0A can be finished and reviewed first. This roadmap uses that split.

## 5. Stage S — before writing code

### S.01 Owner decisions that block development

| Decision | Blocks | Plan |
|---|---|---|
| Final product name (or keep the working name for now) | 0A (app identifiers, package name, deep-link scheme), store listing | Ch 1, 53 |
| Prices, plan limits and trial length | 0B billing (structure can be built with placeholders) | Ch 9, 53 |
| Which modules belong to which plan | 0B modules and limits | Ch 9, 53 |
| SMS gateways used by the first institutions | 0B SMS adapters | Ch 42, 53 |
| Lead merge: keep or drop | 1A leads | Ch 14, 53 |
| The plan's **Proposed** items (WhatsApp manual in phase 1, salted phone hash, seat hold, cash close …) | The milestones that contain them | Ch 53 |

### S.02 Accounts and environments
- [ ] S.02-T1 Supabase organisation with three projects: **dev**, **staging**, **production**.
- [ ] S.02-T2 Expo / EAS account; app identifiers from the chosen (or working) name; channels `preview` and `production`.
- [ ] S.02-T3 Google Cloud project: OAuth client for "Sign in with Google" (start the verification early, Ch 10, 42).
- [ ] S.02-T4 Firebase project for push (shared app).
- [ ] S.02-T5 SSLCommerz sandbox account (platform merchant for subscriptions; test merchant for institutions).
- [ ] S.02-T6 Sandbox / test accounts at the chosen SMS gateways and an email provider; platform default sender.
- [ ] S.02-T7 Domain and DNS for the platform; wildcard SSL for `/<page>/<slug>` pages.
- [ ] S.02-T8 Google Play Console account; plan the call-log permission declaration early (Ch 41).
- [ ] S.02-T9 GitHub repository settings: protected main branch, required checks, secret scanning.
- [ ] S.02-T10 Secrets stored only in the CI secret store and the Supabase Vault — never in the repository (G11).

### S.03 External checks (do before the phase that needs them)

| Check | Needed before | Plan |
|---|---|---|
| Bangladesh data protection rules (children's data, retention) | Phase 1 launch | Ch 4, 50 |
| Promotional SMS rules (sender ID, timing, content) | Bulk SMS (Phase 1B) | Ch 26, 42 |
| SMS gateway APIs, prices and masking rules | 0B SMS adapters | Ch 42 |
| Google OAuth app verification | Production Google sign-in (0B) | Ch 10 |
| Google Play policy for call-log and notification access | Phase 3 (gate) | Ch 41 |
| SSLCommerz merchant onboarding steps for institutions | Phase 2 online payment | Ch 35 |
| VAT on subscription invoices | 0B billing | Ch 9 |
| Name availability (domain, Play Store, trademark) | Final name | Ch 1 |

### S.04 Pilot institutions
- [ ] S.04-T1 Agree at least one pilot each of: college, school, coaching centre (the first three type profiles to test for real).
- [ ] S.04-T2 Collect their current Excel files (for import mapping), SMS gateway, fee structure and roles.
- [ ] S.04-T3 Agree feedback rhythm (weekly) and a contact person per pilot.

### S.05 Working conventions
- [ ] S.05-T1 One pull request per task or small group of tasks; PR description lists milestone and task IDs.
- [ ] S.05-T2 Every PR passes the PR checklist (Section 9.1).
- [ ] S.05-T3 Branch per milestone; merge only with green CI.
- [ ] S.05-T4 Keep `docs/PLAN_BN.md` and this roadmap in the repository; update them in the same PR when a design changes.
- [ ] S.05-T5 A changelog / "What's new" file updated with every user-visible change (G19).

### S.06 Benchmarks and test data
- [ ] S.06-T1 Define the benchmark: two institutions with about 3,000 leads each, plus one large institution (about 30,000 leads), several branches and roles.
- [ ] S.06-T2 Define the seeded test institutions: one per education type profile (Ch 7), with unusual long labels in both languages (Ch 8).

## 6. Milestones

The milestones below are grouped by phase and listed **in build order**. Read Section 1.2 for the shape of a milestone.
Cross-block dependencies are written as "Phase 0", "Block 1A (…)" and similar when the exact ID is in another block;
the blocks follow one another, so everything in an earlier block is finished before the next block starts.

**Merge notes (read before starting):**
- **Settings:** 0A.08 builds the settings framework; 0B.01 only registers the Appendix A keys and profile defaults on top of it.
- **Release tooling:** 0A.02 builds environments, CI and the release workflow; 1.18 adds crash collection, the update banner, minimum app version enforcement in the app, and per-institution feature flags with beta rollout. Do not build feature flags twice.
- **Sign-in:** 0A.03 has a development-only sign-in; the real password, Google and OTP sign-in come in 0B.17–0B.20.
- **Notifications:** 1.11 runs reminders on a minimal runner and sends through the Phase 0 outbox; 1.16 moves all jobs onto the scheduler, and 1.22 adds inbox and push delivery.
- **Phone masking (D24):** 1.02 sends every phone number through one server function; 1.25 sets the real masking rule. **Phase 1A must not go to customers with counsellor roles before 1.25 is live.**
- **Change log and reports (Ch 38):** placed in Phase 4 (4.01, 4.02) as in the plan's roadmap; the plan also proposes the change log and core reports in Phase 1 (see Section 11, open item).

## Phase 0A: Core skeleton, tenancy and access

This block delivers the parts of the foundation that are very expensive to change later (Ch 52.11 #1, **Proposed** split of phase 0 into 0A/0B): the repository and CI, the multi-tenant database core (`institution_id`, nullable `branch_id`, RLS from a JWT claim, `institution_members` with user kind), the guardrails that keep tenants apart (schema lint, DEFINER audit, RPC-as-real-role tests, catalog-driven cross-tenant leak test), per-institution secrets, typed settings and counters, the `domain_events` log and extension rules, the bilingual (English + Bangla) UI framework, locale settings, neutral keys and the label dictionary, the design system and app shell, branches and org units, and roles and permissions v2 (registry, scoped roles, multiple roles, `can()`, `user_access`, access version, role templates, audit, basic access explainer).
**Exit criteria:** two seeded institutions plus a dual-membership user pass the leak test on every table, RPC, storage path and Realtime channel; the role-matrix test passes for every role template; every screen built so far passes the screenshot matrix (light/dark × bn/en × weird labels); CI blocks merges on any of these; Settings → Branches, Settings → Terminology, Users and the role editor work end to end for a Super Admin in both languages.
Production login methods, Master Admin panel, setup wizard, type profiles, modules/plans and the integration hub are Block 0B and build on top of this block.

### 0A.01 Repository skeleton, architecture rules and developer guide

**Goal:** Create the single codebase (Expo app for Android + web, Supabase backend) with the agreed stack and write down the non-negotiable design rules so every later milestone follows them.

**Depends on:** —

**Plan chapters:** Ch 2 (2.3, 2.4, 2.6, 2.7), Ch 3 (3.1–3.5, 3.8, 3.9), Ch 48 (48.2), Ch 51 (51.1–51.4).

**Decisions:** D8, D10, D13, D20, D21, D22, D25.

**Build**
- **Data:** Supabase project folder with `supabase/migrations/` (core) and a separate `supabase/extensions/<ext_name>/migrations/` convention (Ch 43.4); no tables yet.
- **Server:** Edge Functions folder (Deno) with a shared module skeleton; thin "platform adapter" layer for Supabase-specific parts (auth hook, Edge Functions) — **Proposed** (Ch 3.9 #4).
- **App & web:** Expo SDK 58, React Native 0.88, expo-router with file routes in `src/app`, React Compiler, typed routes; product name "Leadora" (D37; was the working name "Lead Management Platform"), own Android package and deep-link scheme with no "Admission", "College" or "School" in them; `runtimeVersion` pinned.
- **Settings & permissions:** none.

**Tasks**
- [ ] 0A.01-T1 Initialise the Expo app (SDK 58, RN 0.88, expo-router, `src/app`, React Compiler, typed routes) building for Android and web.
- [ ] 0A.01-T2 Set the app identity: product name "Leadora" (D37), neutral Android package id and deep-link scheme, pinned `runtimeVersion`; record that the final name/package is an open question (Ch 48.11, Ch 53).
- [ ] 0A.01-T3 Initialise the Supabase project structure: core migrations folder, Edge Functions folder, seed folder, and the extension layout (own schema `ext_<name>`, own migrations folder).
- [ ] 0A.01-T4 Add the library baseline listed in Ch 3.2 only as needed later (xlsx, expo-print, view-shot, MediaPipe, expo-audio are added by the milestones that use them; list them in the guide).
- [ ] 0A.01-T5 Write the developer guide "Architecture rules" covering the 14 principles of Ch 2.3: nothing hard-coded (Ch 2.4 list), one product many forms, code reads settings and modules and never `institution_type` (type used only in seeding), core never changes for one institution, data always separated, server trusts profile/session not client, nothing is lost (soft delete, append-only), no secrets in code or chat, provider errors never hidden, show errors not blanks, ask before risky actions, all options as settings (D22), neutral internal names, never slower.
- [ ] 0A.01-T6 Write the "scope boundary" page from Ch 2.6: in first release (all education types D8, branches D9, bn+en D13, Android + web), not in it (iOS, portal D10, non-education industries D20, branded apps D12 until phase 5, WhatsApp Business API, data migration from the old app), and legacy items that must not reappear: `call_results`, `document_types`, `feature_flags` table, settings keys `max_call_attempts`, `call_log_lock_hours`, `activity_retention_days`.
- [ ] 0A.01-T7 Write the database-pattern section of the guide (Ch 3.3): `institution_id` everywhere, read via RLS, write via RPC calling `can()`, default `SECURITY INVOKER`, guard triggers with session flags (e.g. `app.pipeline_action`), append-only timelines, `domain_events`, trigger-maintained denormalised columns, neutral names, outbox for everything sent outside.
- [ ] 0A.01-T8 Write the app-pattern section (Ch 3.4): settings loaded once and cached, refreshed on change; small RPCs + stale-while-revalidate caches keyed by user and institution; all text from translation files and labels; confirmation dialog before costly AI reruns or deletes.
- [ ] 0A.01-T9 Write the backward-compatibility rules (Ch 3.6): RPC signatures stay backward compatible or a new RPC is added; expand-then-contract migrations; core schema changes are additive only; minimum app version per release; server decisions from profile/session.
- [ ] 0A.01-T10 Add the "Lessons learned" page from Ch 51.2 (12 lessons, each linked to the rule and the milestone that enforces it) and an incident write-up template so the page stays a living record (Ch 51.4 #1).
- [ ] 0A.01-T11 Add a "product-level config" folder (`config/`) for values that change but are not per-institution (AI prices later, provider list and plan limits **Proposed**), with a JSON schema per file (Ch 3.5).
- [ ] 0A.01-T12 Record the scaling notes: Supabase limits to watch (connections, function calls, storage, Edge Function 150 s limit), and the planned path to move a very large institution to its own project (Ch 3.9 #3, Ch 4.8).

**Tests**
- unit: app boots to a placeholder route on Android emulator and web; `config/` files validate against their schemas.

**Done when (acceptance criteria)**
- `npx expo start` runs on Android and web from a clean clone; the package id and scheme contain no education words.
- The developer guide contains every rule listed in T5–T9 and the Ch 2.6 scope table; the lessons page lists all 12 lessons of Ch 51.2.

**Watch-outs (do not miss)**
- The old version hard-coded one college's name, locale and rules; nothing like that may enter this codebase (Ch 2.1, Ch 51.1).
- Changing `runtimeVersion` forces a new store build; plan SDK upgrades outside admission season (Ch 3.9 #8).
- Do not copy old-app tables or settings keys listed as dropped (Ch 2.6, Appendix A).

**Owner checkpoint:** Owner reviews the one-page "Architecture rules" and "Scope boundary" pages and confirms the working name and that the final name is still open.

### 0A.02 Environments, CI pipeline, secrets hygiene and release workflow

**Goal:** Make every change go through a PR with automated checks, separate dev/staging/production environments, and keep secrets out of code from day one.

**Depends on:** 0A.01

**Plan chapters:** Ch 48 (48.3–48.6, 48.10), Ch 3 (3.6, 3.8), Ch 47 (47.12 #1), Ch 51 (lessons 7, 12; 51.3).

**Decisions:** D13, D21.

**Build**
- **Data:** separate Supabase projects for development, staging and production.
- **Server:** GitHub Actions: `app-update.yml` (manual: Database + app / App only / Database only → `supabase db push`, optional `functions deploy <names>`, then `eas update --channel production`), `build-android.yml` (local EAS build on runner, `google-services.json` from a base64 secret, job verifies Firebase is inside the build), `deploy-web.yml` (web export + MediaPipe assets, FTPS upload), `ci.yml` (all PR checks).
- **App & web:** EAS profiles `development` (dev client APK), `preview` (APK, channel `preview`), `production` (AAB, channel `production`), `production-apk` (APK, channel `production`).
- **Settings & permissions:** none.

**Tasks**
- [ ] 0A.02-T1 Create the dev, staging and production Supabase projects and document which is used by which EAS channel.
- [ ] 0A.02-T2 Add the four EAS build profiles exactly as in Ch 48.3.
- [ ] 0A.02-T3 Write `app-update.yml` with the three deploy choices and function names input.
- [ ] 0A.02-T4 Write `build-android.yml` with the base64 `google-services.json` secret and a step that fails if Firebase config is missing from the build; parameterise app config so the same workflow can later build branded apps (D12, phase 5).
- [ ] 0A.02-T5 Write `deploy-web.yml` (web export, MediaPipe assets, FTPS) with a chunk-reload rule for half-uploaded deploys (Ch 48.10 #8); note **Proposed** move to atomic hosting in 1B (Ch 45).
- [ ] 0A.02-T6 Write `ci.yml` running on every PR: typecheck, unit tests, migration apply on a fresh database, and placeholders for the gates added by later 0A milestones (schema lint, leak test, RPC-as-role, DEFINER audit, role matrix, i18n lint, screenshot tests); merge blocked on failure.
- [ ] 0A.02-T7 Store all secrets only as GitHub secrets (Expo token, Supabase access token, DB password, project ref, FTP credentials, Firebase file, keystore, `.env`, Apps Script secret); add `.gitignore` entries for each.
- [ ] 0A.02-T8 **Proposed:** add secret scanning in a pre-commit hook and in CI (Ch 48.5, 48.10 #9) and a "rotate immediately" runbook for a leaked key.
- [ ] 0A.02-T9 Add the PR template: deploy type (database / Edge Functions / OTA / new store build), "What's new" entry in English and Bangla (Ch 48.6), RPC signature changed? (lesson 7), new queue/job has attempts/back-off/given up? (lesson 2), new badge batched? (lesson 8), Ch 4.3 isolation checklist, UX checklist link (Ch 47).
- [ ] 0A.02-T10 **Proposed:** CI check that a PR touching `supabase/migrations/` declares a database deploy (Ch 48.10 #3).
- [ ] 0A.02-T11 Document the release rules: staged rollout and per-institution flags come in 1B; no big release in admission peak weeks, hotfix channel for small flag-off fixes (Ch 48.6, 48.10 #7); run migrations on staging with seed data before production (Ch 48.10 #1).
- [ ] 0A.02-T12 Add the release calendar note: Expo SDK / RN upgrades at fixed times of year, never in admission season (Ch 3.9 #8).

**Tests**
- CI: a PR with a failing unit test cannot merge; a PR adding a fake secret string is blocked by the scanner (if Proposed T8 approved).
- build: `build-android.yml` fails when the Firebase secret is absent and succeeds when present.

**Done when (acceptance criteria)**
- A preview APK and a web build are produced from `main` by Actions with no secret in the repository.
- Every PR shows the template with deploy type and bilingual "What's new" fields.

**Watch-outs (do not miss)**
- Choosing "App only" when a DB change was needed breaks the app (Ch 48.10 #3).
- OTA cannot ship native changes; a wrong `runtimeVersion` makes old builds crash on new JS (Ch 48.10 #4).
- Never commit Firebase JSON, keystore, `.env`, tokens (lesson 12).

**Owner checkpoint:** Owner sees a green PR with a bilingual "What's new" entry and installs the preview APK from the build artifact.

### 0A.03 Tenancy core: institutions, memberships and the active-institution session

**Goal:** Create the minimum tenant data model and the session mechanism so that every request runs for exactly one active institution taken from the server-side session, never from the client.

**Depends on:** 0A.02

**Plan chapters:** Ch 4 (4.2, 4.5, 4.6), Ch 11 (11.7 user kind, 11.13, 11.15 platform/institution separation, R19), Ch 2.3 (principles 5, 6), Ch 3.6.

**Decisions:** D9, D10, D25.

**Build**
- **Data:** `institutions` (id, slug, name, short name, status column reserved for 0B lifecycle), `profiles` (user_id, display name, phone, email, `user_kind` = staff / portal / api, preferred UI language), `institution_members(user_id, institution_id, status pending/active/deactivated, joined_at, …)`, `platform_members(user_id, platform_role)` kept fully separate from institution membership (roles filled in 0B), `user_sessions` / access-version columns (`access_version` per user per institution). Every tenant table: `institution_id` NOT NULL first column of every index.
- **Server:** Supabase Auth custom access-token hook that writes `active_institution_id`, `user_kind` and `access_version` claims; RPC `set_active_institution(institution_id)` that checks membership and forces a fresh session; SQL helpers `auth_institution_id()` and `auth_user_id()` used by every RLS policy (wrapped in `select` for RLS init-plan caching, Ch 47.9).
- **App & web:** minimal development sign-in (email + password) used by tests and developers only; production login methods come in 0B (Ch 10).
- **Settings & permissions:** none yet.

**Tasks**
- [ ] 0A.03-T1 Migration: `institutions`, `profiles` (with `user_kind` staff/portal/api, default staff; portal users not enabled, D10), `institution_members`, `platform_members`.
- [ ] 0A.03-T2 Enable RLS on all four tables; members read only their own memberships; institution rows readable only by members of that institution.
- [ ] 0A.03-T3 Implement the custom access-token hook: if the user has one active membership, set it as active; if several, use the last selected (stored server-side); never accept an institution id from the client.
- [ ] 0A.03-T4 Implement `set_active_institution` (membership check, store selection, bump session) and the client call that refreshes the token afterwards (UI switcher is 1B).
- [ ] 0A.03-T5 Implement `auth_institution_id()` / `auth_user_id()` helpers reading JWT claims, and document the policy template `institution_id = (select auth_institution_id())`.
- [ ] 0A.03-T6 Add `access_version` per (user, institution) and a server check helper that rejects a request whose token carries an older version with a typed "session refresh required" error (used fully in 0A.17).
- [ ] 0A.03-T7 Implement immediate session revocation for a deactivated membership (sign-out of all that user's sessions for that institution) and an RPC "sign out all other devices" (Ch 47.10).
- [ ] 0A.03-T8 Add minimal dev sign-in screen behind a build flag; production builds hide it until 0B login ships.
- [ ] 0A.03-T9 Seed script: two institutions A and B, one user in each, one user who is a member of both (D25), one platform member.
- [ ] 0A.03-T10 Document the rule "a person in several institutions is checked only against the active one; switching creates a new session and clears client caches" (Ch 4.6).

**Tests**
- RPC-as-real-role: user of A cannot call `set_active_institution(B)`; dual-membership user can, and afterwards sees only B rows.
- RLS: forged `institution_id` sent by the client in an insert is rejected or overwritten by the session value.
- unit: token with old `access_version` is rejected; deactivated member's refresh fails.

**Done when (acceptance criteria)**
- A dual-membership user can switch active institution through the RPC and every query returns only the active institution's rows.
- Deactivating a member ends all of that member's sessions within one request.

**Watch-outs (do not miss)**
- Never assume "one user = one institution" (Ch 4.1, R19).
- Platform roles must never mix with institution roles (Ch 11.3 protections, Ch 11.15).
- Stale JWT permissions after role removal (Ch 4.13 #4, R15) — the access version check is the fix.

**Owner checkpoint:** Developer demo: same person switches between two test institutions and sees completely different data.

### 0A.04 Schema guardrails: migration lint, DEFINER audit and RPC-as-real-role harness

**Goal:** Make it impossible to merge a table, function or migration that breaks the tenancy and naming rules.

**Depends on:** 0A.03

**Plan chapters:** Ch 3 (3.3, 3.9 #1, #2, #6), Ch 4 (4.2, 4.4, 4.13 #1, #8), Ch 2.7 #5, Ch 8.10 #5, Ch 47.9, Ch 48.7, Ch 51 (lesson 1, 4, 7; 51.3).

**Decisions:** D9, D20.

**Build**
- **Data:** `security_definer_registry` (function name, reason, reviewer, tenant check confirmed) as a checked-in file plus CI table.
- **Server:** CI scripts: schema lint, function lint, invoker sweep; reusable guard-trigger helper that blocks direct edits of protected columns unless a session flag (e.g. `app.pipeline_action`) is set by the owning RPC.
- **App & web:** none.
- **Settings & permissions:** none.

**Tasks**
- [ ] 0A.04-T1 Schema lint: every table outside an allow-list of platform tables has `institution_id NOT NULL`, RLS enabled, at least one policy, and every index starts with `institution_id`; fail CI otherwise (**Proposed** migration check, Ch 4.13 #1).
- [ ] 0A.04-T2 Schema lint: core record tables (leads, clients, offerings, cohorts, users/memberships, payments when they arrive) must have a nullable `branch_id` (D9, Ch 12.3).
- [ ] 0A.04-T3 Schema lint: timestamps must be `timestamptz`; date-only fields use `date` (Ch 13.6).
- [ ] 0A.04-T4 Uniqueness lint: unique constraints on tenant tables must include `institution_id` (stage key, receipt no, refund no, network ref code, network field key, client-number series, phone duplicate check, tag name, offering name; Ch 4.4) except an explicit allow-list (public referral code may be globally unique).
- [ ] 0A.04-T5 **Proposed** naming lint: block new table, column, RPC and event names using education words (`student`, `course`, `batch`, `admission`, `guardian`, `alumni`, …) instead of neutral keys (Ch 8.3, 8.10 #5).
- [ ] 0A.04-T6 **Proposed** lint: `institution_type` may only be read in seeding code (Ch 2.7 #5).
- [ ] 0A.04-T7 Function lint: default `SECURITY INVOKER`; every `SECURITY DEFINER` function must be in the registry with a reason and must filter by the active institution; CI fails on an unregistered DEFINER (Ch 3.9 #1, Ch 48.7).
- [ ] 0A.04-T8 Invoker sweep: find any INVOKER function or trigger that calls a function the `authenticated` role cannot execute; fail CI (lesson 1).
- [ ] 0A.04-T9 RPC-as-real-role harness: a test helper that signs in as a real user with a real JWT and calls RPCs through PostgREST, never as the database owner; document that every RPC test must use it.
- [ ] 0A.04-T10 Lint for heavy functions: functions tagged `-- heavy` must contain `set jit = off` (Ch 3.9 #6, Ch 47.9).
- [ ] 0A.04-T11 Guard-trigger helper and its unit test (protected column edit blocked without the session flag, allowed inside the owning RPC).
- [ ] 0A.04-T12 Lint for RLS init-plan: policies must wrap `auth_*()` calls in `(select …)`.

**Tests**
- unit: each lint has a failing fixture migration and a passing one.
- RPC-as-real-role: sample RPC run as signed-in role succeeds; the same RPC calling a revoked helper fails in the sweep.

**Done when (acceptance criteria)**
- CI rejects a migration that adds a tenant table without `institution_id` or RLS, an unregistered DEFINER function, or an index not led by `institution_id`.
- The DEFINER registry exists and is empty or fully justified.

**Watch-outs (do not miss)**
- The old app had about 418 DEFINER functions; each one is a leak path in multi-tenant (Ch 3.3).
- An INVOKER read function calling a revoked helper made every AI card blank for everyone (lesson 1).
- DEFINER exceptions such as the all-leads phone duplicate check (1A) must filter by institution and return only name, stage, owner (Ch 4.13 #8, lesson 9).

**Owner checkpoint:** Developer shows a deliberately bad migration failing CI with a readable message.

### 0A.05 Cross-tenant leak test (catalog-driven)

**Goal:** Ship the automated leak test that runs on every PR and automatically covers every new table and RPC.

**Depends on:** 0A.04

**Plan chapters:** Ch 4 (4.12, 4.13 #1, #2), Ch 48 (48.7, 48.10 #6), Ch 43.4 #6, Ch 2.3 principle 5.

**Decisions:** D25.

**Build**
- **Data:** leak-test fixtures: institutions A and B with sample rows in every tenant table, dual-membership user.
- **Server:** test runner that reads the Postgres catalog (all tables in `public` and `ext_*` schemas, all RPCs exposed to `authenticated`, all storage buckets, Realtime channel patterns) and probes each as B.
- **App & web:** none.
- **Settings & permissions:** none.

**Tasks**
- [ ] 0A.05-T1 Fixture builder that inserts at least one row per tenant table for A and B through RPCs (or a test-only seeding role).
- [ ] 0A.05-T2 Table probe: as a B user, `select` every tenant table; assert zero A rows.
- [ ] 0A.05-T3 RPC probe: call every exposed RPC with A's ids as arguments; assert error or no A data.
- [ ] 0A.05-T4 Dual-membership probe: user in A and B with active institution B sees nothing of A in tables and RPCs (D25).
- [ ] 0A.05-T5 Catalog scan so new tables/functions/buckets are picked up without writing new tests; a table without fixtures fails the run (**Proposed**, Ch 4.12 last paragraph).
- [ ] 0A.05-T6 Include `ext_*` schemas and (when they exist) custom field/record tables (Ch 43.4 #6).
- [ ] 0A.05-T7 Placeholders for storage and Realtime probes (filled in 0A.06) and external-connection probe (filled in 0B, Ch 4.12 #5).
- [ ] 0A.05-T8 Wire into `ci.yml` as a required check; add it to the Ch 4.3 review checklist in the PR template.

**Tests**
- RLS + cross-tenant leak: the suite itself; a seeded fixture with a deliberately missing policy must make it fail.

**Done when (acceptance criteria)**
- The leak test runs on every PR, covers every table and RPC in the catalog, and fails when a policy is removed.

**Watch-outs (do not miss)**
- A leak test that only knows listed tables misses new ones (Ch 48.10 #6).
- Table RLS does not protect storage, Realtime, push or cache (Ch 4.13 #2).

**Owner checkpoint:** Owner sees the CI check named "cross-tenant leak test" green on a PR and red on a demo PR that removes a policy.

### 0A.06 Tenant isolation beyond tables: storage, Realtime, Edge Functions and tagged logs

**Goal:** Extend institution isolation to storage paths, Realtime channels and Edge Functions, and lay the foundation for logs tagged by institution and user.

**Depends on:** 0A.05

**Plan chapters:** Ch 4 (4.3), Ch 3 (3.7, 3.9 #3, #10), Ch 48.8, Ch 2.3 principle 9.

**Decisions:** —

**Build**
- **Data:** storage path convention `<institution_id>/<area>/…` with storage RLS policies; Realtime channel naming `inst:<institution_id>:<topic>` with authorization policies.
- **Server:** shared Edge Function middleware: resolves user and active institution from the session JWT (never from body), loads only that institution's context, enforces a timeout budget below the 150 s limit; structured logger adding `institution_id`, `user_id`, request id, with redaction of secrets and personal data.
- **App & web:** client logger that tags errors with institution and user ids (crash collection, error dashboard and alerts come in 1B).
- **Settings & permissions:** none.

**Tasks**
- [ ] 0A.06-T1 Create the storage bucket convention and policies; path must start with the active institution id.
- [ ] 0A.06-T2 Add Realtime authorization policies so a user can subscribe only to channels of the active institution.
- [ ] 0A.06-T3 Edge Function middleware (session → user, institution, access version check) and a sample function using it.
- [ ] 0A.06-T4 Structured logger (server and client) with institution/user tags and a redaction list (keys, tokens, full phone numbers, NID).
- [ ] 0A.06-T5 Error contract: every RPC/Edge Function error returns a typed code and a user-safe message key; UI must show an error state, never an empty list (principle 10).
- [ ] 0A.06-T6 Fill the leak-test storage probe (B cannot read/list/write A paths) and Realtime probe (B cannot join A channels).
- [ ] 0A.06-T7 Document the Ch 4.3 isolation table (tables, RPC, storage, Realtime, Edge Function, jobs, push, client cache, export, logs, public pages, external connections) in the review checklist with the milestone that implements each.

**Tests**
- RLS + cross-tenant leak: storage and Realtime probes for B against A, and for the dual-membership user.
- unit: logger redacts a fake API key and a full phone number.

**Done when (acceptance criteria)**
- Leak test covers storage and Realtime and is green; a log line from an Edge Function contains institution and user ids and no secret.

**Watch-outs (do not miss)**
- Errors without institution ids make support guess (Ch 3.9 #10).
- Never log secrets or full personal data (Ch 3.7).

**Owner checkpoint:** —

### 0A.07 Per-institution secrets foundation

**Goal:** Store per-institution keys encrypted, readable only by Edge Functions, shown only as a hint, with rotation and purge.

**Depends on:** 0A.06

**Plan chapters:** Ch 4 (4.10, 4.13 #9), Ch 3.8, Ch 48.5, Ch 2.3 principle 8, Ch 51 lesson 12.

**Decisions:** —

**Build**
- **Data:** `institution_secrets(institution_id, secret_ref, vault_id, hint, valid_from, rotated_at, revoked_at)`; values live in Supabase Vault.
- **Server:** RPCs `secret_set` (write-only, returns hint like `key…ab12`), `secret_rotate` (new value with "active from" date), `secret_revoke`; Edge-only reader `get_secret(institution_id, ref)` not granted to `authenticated`; `purge_institution_secrets(institution_id)` used by the 0B close flow.
- **App & web:** a reusable "secret field" component that shows only the hint and a replace button.
- **Settings & permissions:** writing secrets requires a sensitive permission (registered in 0A.16; `integration.manage` per Ch 43.5) — enforced once `can()` exists.

**Tasks**
- [ ] 0A.07-T1 Migration for `institution_secrets` with RLS (metadata only; never the value).
- [ ] 0A.07-T2 Vault wrapper RPCs: set, rotate with `valid_from`, revoke; return hint only.
- [ ] 0A.07-T3 Edge-only read path; confirm `authenticated` and `anon` cannot execute it.
- [ ] 0A.07-T4 Purge function for institution closure (connections, API keys and webhooks are disabled by 0B/1B flows; Ch 4.10, I14).
- [ ] 0A.07-T5 Secret field UI component (hint, replace, rotate date).
- [ ] 0A.07-T6 Logger and error paths redact secret values; test with a planted value.

**Tests**
- RPC-as-real-role: a staff user can set a secret but can never read it back; an Edge Function can.
- RLS + cross-tenant leak: B cannot see A's secret metadata.
- unit: error message from a failed provider call does not contain the key.

**Done when (acceptance criteria)**
- No API, screen, log or error ever returns a secret value; the UI shows only `key…xxxx`.

**Watch-outs (do not miss)**
- Leaks through logs, error messages and screenshots (Ch 4.13 #9, I2).
- Never put keys in code, commits or chat (Ch 3.8).

**Owner checkpoint:** —

### 0A.08 Typed settings framework and per-institution counters

**Goal:** Give every institution its own validated, versioned settings with defaults, cached on the client, and safe per-institution counters.

**Depends on:** 0A.05

**Plan chapters:** Ch 4 (4.4, 4.5), Ch 2 (2.4, 2.7 #1, #3), Ch 3.4, Ch 48.7 (settings validation), Ch 8.10 #7.

**Decisions:** D22.

**Build**
- **Data:** `setting_definitions` (key, JSON schema, default, version, area permission key, scope: institution/product); `app_settings(institution_id, key, value, schema_version, updated_by, updated_at)`; `settings_version` per institution (bumped on any change); `institution_counters(institution_id, counter_key, branch_id null, next_value)`.
- **Server:** RPCs `settings_get_all()` (resolved: product default → type-profile default (filled in 0B) → institution value), `setting_set(key, value)` validating against the schema and area permission; settings migration runner for schema version changes; `counter_next(counter_key, branch_id)` atomic, gap-free per institution.
- **App & web:** settings store loaded once after sign-in, cached per user + institution, refreshed when `settings_version` changes (checked on app foreground and on each RPC response header).
- **Settings & permissions:** area permission per key (e.g. `settings.terminology`, `settings.branches`) checked via `can()` once 0A.17 lands; product-level settings editable only by platform roles (0B).

**Tasks**
- [ ] 0A.08-T1 Migrations for `setting_definitions`, `app_settings`, settings version, `institution_counters`; RLS on institution tables.
- [ ] 0A.08-T2 JSON-schema validator in the database (or Edge Function) used by `setting_set`; reject invalid values with field-level messages.
- [ ] 0A.08-T3 Default resolution with layers (product, type profile hook for 0B, institution override) and "reset to default" per key.
- [ ] 0A.08-T4 Settings migration mechanism: each definition has a version; a migration function upgrades stored values; CI test runs all migrations on seed data.
- [ ] 0A.08-T5 Client settings cache keyed by user + institution, cleared on sign-out, user change or institution switch; refresh on version change.
- [ ] 0A.08-T6 Register `min_app_version` (product-level) and the server check: requests from an older app get a typed "upgrade required" error (banner UI in 1B, Ch 46).
- [ ] 0A.08-T7 Counter function with row lock, per institution and optional per branch (branch series is **Proposed**, Block 2); counters for receipt, refund, client number are created by their own milestones.
- [ ] 0A.08-T8 Record `updated_by`/`updated_at` and old value on every settings change; 0A.09-T8 connects this to the audit log and `domain_events`.

**Tests**
- unit: invalid value rejected; default returned when unset; migration upgrades an old value.
- RLS + cross-tenant leak: B cannot read or write A's settings or counters.
- concurrency: 50 parallel `counter_next` calls produce 50 distinct consecutive numbers.

**Done when (acceptance criteria)**
- Any key can be added by data (definition row) without code changes in the settings screens' data layer; every write is schema-validated and versioned.
- Changing a setting is visible on another signed-in device after its next request without restart.

**Watch-outs (do not miss)**
- Configuration explosion (type × module × setting × role): typed settings with schema and defaults are the guard (Ch 2.7 #1, T2).
- Stale cached settings or labels on some phones (Ch 8.10 #7).

**Owner checkpoint:** —

### 0A.09 Domain event log, audit log and extension framework

**Goal:** Record every important action as a domain event and every security-relevant change in an audit log from day one, and set the rules that let extensions plug in without touching the core.

**Depends on:** 0A.08

**Plan chapters:** Ch 43 (43.2–43.5, 43.7, 43.8), Ch 3.3, Ch 11.14 (audit log), Ch 2.3 principle 4.

**Decisions:** D8, D18, D20.

**Build**
- **Data:** `domain_events(institution_id, id, event_key, event_version, entity_type, entity_id, branch_id, actor_user_id, on_behalf_of_user_id, payload jsonb, occurred_at, processed_at)`; `audit_log(institution_id, actor, action, target_type, target_id, before, after, reason, at)`; extension registry `extensions(key, schema_name, version, status)` and `institution_extensions(institution_id, extension_key, enabled)`.
- **Server:** `emit_event(event_key, version, entity, payload)` helper called inside write RPCs; versioned event catalogue file (neutral keys such as `client`, `conversion`); extension rules: own schema `ext_<name>`, own migrations folder, writes to core only through versioned RPCs and events.
- **App & web:** none.
- **Settings & permissions:** extensions declare their permissions in the registry (0A.16); enabling an extension is a platform action (0B Master Admin).

**Tasks**
- [ ] 0A.09-T1 Migration for `domain_events` with indexes `(institution_id, occurred_at)` and `(institution_id, event_key, occurred_at)`; RLS read-only for permitted users; insert only via `emit_event`.
- [ ] 0A.09-T2 **Proposed:** partition `domain_events` by institution/time, expiry of old events and "processed" marker (Ch 43.7 #5).
- [ ] 0A.09-T3 Event catalogue document with versioned payload schemas and neutral names; contract test that emitted payloads match the schema (Ch 43.4 #7, #8).
- [ ] 0A.09-T4 Migration for `audit_log` (append-only: no update/delete grants) and helper `audit(…)`.
- [ ] 0A.09-T5 Extension scaffolding: template `ext_example` with own schema, own migrations folder, one RPC, one event listener; disabling or removing it leaves the core app working (Ch 43.4 #2).
- [ ] 0A.09-T6 Lint: core migrations may not reference `ext_*` objects; extension migrations may not alter core tables (only additive core changes, expand-then-contract, Ch 43.4 #4).
- [ ] 0A.09-T7 Leak test covers `ext_*` tables, `domain_events` and `audit_log`.
- [ ] 0A.09-T8 Hook `setting_set` (0A.08) into `audit(…)` and `emit_event('setting.changed', …)` with old/new values.
- [ ] 0A.09-T9 Document the five layers (setting → custom record → automation → webhook/API → extension) and the request triage rule (several institutions → core module; one → extension, charged) in the guide (Ch 43.3, 43.6).

**Tests**
- unit: `emit_event` rejects unknown event keys or wrong version payloads.
- RLS + cross-tenant leak: B sees no A events, audit rows or extension rows.
- integration: enabling and disabling `ext_example` for A does not change B and does not break core RPCs.

**Done when (acceptance criteria)**
- Every write RPC built from here on can emit a versioned event and an audit row with one call; the example extension can be enabled/disabled per institution without errors.

**Watch-outs (do not miss)**
- No per-institution columns in core tables, ever (Ch 43.4 #1).
- Event or API contract changes break institutions' ERPs and webhooks — version and keep old versions for a set time (Ch 43.7 #6).
- `domain_events` grows fast (Ch 43.7 #5).

**Owner checkpoint:** —

### 0A.10 Bilingual UI framework (English + Bangla)

**Goal:** Every UI string comes from translation files in English and Bangla, each user picks a language, and switching needs no restart.

**Depends on:** 0A.02

**Plan chapters:** Ch 13 (13.2, 13.8 #1, #8), Ch 8.9 (rules 1, 2), Ch 48.7 (labels and language), Ch 47.8.

**Decisions:** D13.

**Build**
- **Data:** `profiles.ui_language` (from 0A.03); institution default language setting `default_language` registered in 0A.08.
- **Server:** RPC `set_my_language`.
- **App & web:** i18n library setup with `en` and `bn` namespaces, `t()` helper, language switch at runtime, Bangla-capable font loaded.
- **Settings & permissions:** setting key `default_language` (institution).

**Tasks**
- [ ] 0A.10-T1 Set up the i18n library with English and Bangla resource files and namespaces per feature.
- [ ] 0A.10-T2 Language resolution: user choice → institution `default_language` → English; applies to the first screen after sign-in.
- [ ] 0A.10-T3 Runtime language switch without app restart on Android and web.
- [ ] 0A.10-T4 Lint: block hard-coded user-visible strings in UI code (JSX text, `title=` props, alerts); block literal "Student"/"শিক্ষার্থী" style words.
- [ ] 0A.10-T5 CI check: every key exists in both `en` and `bn` (no missing keys).
- [ ] 0A.10-T6 Glossary file (English ↔ Bangla core terms) and a per-release review step by the owner or a native reader (Ch 13.8 #8).
- [ ] 0A.10-T7 Document that message-template language follows the recipient, not the staff UI language (built in 1B, Ch 24).

**Tests**
- unit: missing-key check fails on a key present only in `en`.
- UI (Playwright web, Maestro Android): switch language on a sample screen; text changes without reload.

**Done when (acceptance criteria)**
- CI fails on any hard-coded UI string or missing translation; a user can switch bn/en instantly.

**Watch-outs (do not miss)**
- One English word on a Bangla screen (or the reverse) makes the app look half-translated (Ch 13.8 #1).
- Only two languages now; more later through the same structure (Ch 13.2, open question Ch 53).

**Owner checkpoint:** Owner switches a sample screen between Bangla and English on a phone.

### 0A.11 Locale settings, number/money/date formatting and Bangla digit input

**Goal:** Make time zone, currency, phone rules, week and holiday settings per institution, and format money in lakh style with correct Bangla handling everywhere.

**Depends on:** 0A.08, 0A.10

**Plan chapters:** Ch 13 (13.3, 13.4, 13.5 keys only, 13.6, 13.8 #3, #4, #7), Ch 2.4, Ch 47 (47.3, 47.4, 47.8).

**Decisions:** D13.

**Build**
- **Data:** setting definitions with Bangladesh defaults: time zone `Asia/Dhaka`, currency ৳, phone country code `880` and format `01XXXXXXXXX`, week start Saturday, `working_days` (Sat–Thu, Friday off), scorecard day Sunday, `default_language`, Bangla digits on receipts and public pages (optional), payment method list (bKash, Nagad, Rocket, cash, bank), address placeholder; `working_hours` and `quiet_hours` (default 22:00–08:00) registered with defaults (behaviour built later).
- **Server:** SQL helpers: `normalize_phone(text, institution)` (Bangla digits → ASCII, strips +880, spaces, dashes), `to_institution_time(timestamptz)`, `institution_today()`; all storage of digits in ASCII.
- **App & web:** formatting library: lakh grouping (১,০০,০০০ / 1,00,000), currency, dates in both languages, optional Bangla digits; input normaliser for phone/number fields; bn/en date and time pickers in the institution's time zone; times computed from server time, not the phone clock.
- **Settings & permissions:** locale keys; group key name (e.g. `locale`) to be confirmed with the Appendix A owner (0B).

**Tasks**
- [ ] 0A.11-T1 Register all locale setting definitions with schemas and Bangladesh defaults (Ch 13.3 table).
- [ ] 0A.11-T2 Server `normalize_phone` and digit conversion; applied in every RPC that accepts phone or numeric input (server and client both, Ch 13.8 #3).
- [ ] 0A.11-T3 Client input normaliser: typing or pasting "০১৭১১…" becomes "01711…"; `+880`, spaces and dashes fixed.
- [ ] 0A.11-T4 Money formatter with lakh grouping in both languages; lint/test forbids `toLocaleString` without the helper.
- [ ] 0A.11-T5 Date/time formatting and pickers in bn/en using the institution time zone; date-only fields never shifted by time zone.
- [ ] 0A.11-T6 Server-time offset in the client so calculations ignore a wrong phone clock (Ch 47.7).
- [ ] 0A.11-T7 **Proposed** spike: evaluate Postgres ICU collation for Bangla sorting and dual-script name matching; record the decision before name columns are created in 1A (Ch 13.8 #7).
- [ ] 0A.11-T8 Register `working_days`, `working_hours`, `quiet_hours` keys only; record that the holiday list, Settings → OFFICE screen and follow-up preset behaviour are built in 1A (Ch 18) and quiet-hours sending in 1B (Ch 25).

**Tests**
- unit: `normalize_phone('০১৭১১-২২৩৩৪৪')` = `01711223344`; `+8801711…` normalised; lakh formatting of 100000 → 1,00,000 and ১,০০,০০০.
- unit: times near midnight in `Asia/Dhaka` land on the correct local date (Ch 13.8 #4).
- screenshot: date picker and money field in bn/en × light/dark.

**Done when (acceptance criteria)**
- No locale value is hard-coded anywhere; changing time zone or currency for a test institution changes formatting without code changes.
- Database contains only ASCII digits for phones and amounts.

**Watch-outs (do not miss)**
- Storing local time instead of `timestamptz` gives wrong reminder/report days and DST bugs later (Ch 13.8 #4).
- Mixed digits break duplicate checks and search (Ch 13.8 #3).
- 100,000 style formatting is wrong for Bangladesh (Ch 47.8).

**Owner checkpoint:** Owner checks money and date samples in Bangla and English and confirms the defaults list.

### 0A.12 Neutral keys and the label dictionary

**Goal:** Fix the business-neutral internal keys and build the per-institution label dictionary (English singular/plural, Bangla forms) that every screen, message and print will use.

**Depends on:** 0A.08, 0A.10

**Plan chapters:** Ch 8 (8.1–8.7, 8.9, 8.10, 8.11), Ch 2.3 principle 13, Ch 43.4 #8.

**Decisions:** D13, D18, D20.

**Build**
- **Data:** `label_keys` (key, group, length limit, lockable), `label_defaults(scope: product/pack/profile, scope_key, key, en_singular, en_plural, bn_forms jsonb)`, `institution_labels(institution_id, key, en_singular, en_plural, bn_forms, locked_by_platform)`; seed every key of Ch 8.4: people (`lead`, `client`, `contact_person`, `network`, `referrer`), offering (`offering`, `cohort`, `slot_group`, `branch`, `external_board`, `board_id`), conversion path (`conversion`, `admitted`, `admission_cancelled`, `lost`, `appointment`, `assessment`, `merit_list`, `documents`, `client_number`), money (`fee`, `installment`, `receipt`, `discount`), staff roles (`caller`, `team_lead`, `admission_officer`), modules (`module.leads`, `module.students`, `module.alumni`, `module.admission_contribution`, `module.admission_flow`, `module.leaderboard`, `module.scorecard`, `module.referrals`), print titles (`doc.receipt_title`, `doc.admit_card_title`, `doc.application_form_title`, `doc.id_card_title`); education-pack defaults from Ch 8.4 and per-type examples from Ch 8.5 as profile defaults (wired to type profiles in 0B).
- **Server:** RPC `labels_get()` returning resolved labels (institution → profile → pack → product); server-side resolver for notifications and prints later; `labels_version` folded into settings version.
- **App & web:** `t('client.plural')`-style label lookup integrated with i18n; Bangla forms (base, plural, possessive, objective, e.g. শিক্ষার্থী / শিক্ষার্থীরা / শিক্ষার্থীদের / শিক্ষার্থীর); search helper that also matches default words (searching "student" finds a module renamed "Trainees").
- **Settings & permissions:** permission `settings.terminology` (registered in 0A.16); platform lock flag set by Master Admin (UI in 0B).

**Tasks**
- [ ] 0A.12-T1 Write the neutral-key reference table (Ch 8.3) into the developer guide, with old education name, default label and other-industry examples.
- [ ] 0A.12-T2 Migrations for label tables with RLS; seed all Ch 8.4 keys with English and Bangla defaults.
- [ ] 0A.12-T3 Resolution function with layers and fallback; cached with settings, refreshed instantly on change (Ch 8.10 #7).
- [ ] 0A.12-T4 Client label API integrated into `t()` (labels inside translated sentences use placeholders; text written so labels stand alone, e.g. "শিক্ষার্থী: ২৫", Ch 8.7).
- [ ] 0A.12-T5 Bangla form auto-generation for common forms with manual override (Ch 8.7).
- [ ] 0A.12-T6 Length limit per label key enforced server-side (Ch 8.8).
- [ ] 0A.12-T7 Search helper matching current label, default label and key in both languages (Ch 8.9 rule 5).
- [ ] 0A.12-T8 **Proposed:** final neutral status keys (`converted`, `conversion_cancelled`) and neutral module keys (`module.clients`, `module.network`); **Proposed** neutral names for Appendix A keys still in education words (`campus_visit` → `appointment`, `alumni` → `network`, `students`, `admission`) — decide before 0B registers Appendix A.
- [ ] 0A.12-T9 Rule in the guide: every later feature adds its new words to the label list before release (Ch 8.9 rule 6, Ch 52.9); template variables and export technical names stay fixed keys (Ch 8.9 rule 3, Ch 8.10 #6).
- [ ] 0A.12-T10 Seed the "weird labels" test institution with long, unusual labels in both languages (e.g. "Professional Development Participant") for screenshot tests (Ch 8.9 rule 4).

**Tests**
- unit: resolution order; length limit rejection; Bangla forms generated.
- RLS + cross-tenant leak: B cannot read/write A's labels.
- unit: search for "student" finds a module labelled "Trainees".

**Done when (acceptance criteria)**
- Every Ch 8.4 key exists with English (singular/plural) and Bangla forms; renaming `client` to "Trainee" in a test institution changes every place that uses the label API with no code change and no migration.

**Watch-outs (do not miss)**
- Renaming must never need a migration: tables, columns, RPCs, API fields, events and template variables keep fixed keys (Ch 8.9 rule 3).
- Bangla inflection breaks when labels are spliced into sentences (Ch 8.10 #3).
- Developers may create new keys with education names by habit (Ch 8.10 #5).

**Owner checkpoint:** Owner reviews the default English and Bangla labels table and the Proposed neutral key names (T8).

### 0A.13 Design system: tokens, theming and core components

**Goal:** Build the light/dark/brand token system and the shared components so every later screen is consistent, readable in Bangla and accessible.

**Depends on:** 0A.10, 0A.11

**Plan chapters:** Ch 47 (47.2–47.5, 47.8, 47.11, 47.12), Ch 13.4 (Bangla line height).

**Decisions:** D12, D13.

**Build**
- **Data:** institution brand colour comes from branding settings (0B Ch 6); default platform brand blue `#3557D4`.
- **Server:** none.
- **App & web:** tokens for colour (light, dark, brand; hot/warm/cold), typography (Bangla-capable font, Bangla-safe line height), spacing, radius; Material 3 tonal containers; components: buttons (≥48 dp targets, screen-reader labels), text fields (correct keyboard type, error under the field, Next/Done chaining), money and phone inputs (from 0A.11), date/time pickers, skeleton loader, empty state with action button (label-aware), error state with Retry, pull-to-refresh, undo snackbar, progress with cancel, confirmation dialog, bottom sheet that scrolls the focused field above the keyboard, Save bar that stays above the keyboard, hot/warm/cold chip with icon + text.
- **Settings & permissions:** none.

**Tasks**
- [ ] 0A.13-T1 Token files (light, dark, brand) and a theme provider; theme switch without restart (Ch 47.2).
- [ ] 0A.13-T2 Brand colour contrast checker: if the institution colour fails contrast in light or dark, use it as accent only and pick a safe text tone (Ch 47.12 #2).
- [ ] 0A.13-T3 Typography tokens with Bangla font and line height that does not clip vowel signs (ু, ৃ); large system font does not overlap or cut text (Ch 47.2).
- [ ] 0A.13-T4 Form components with keyboard handling: focused field scrolls above keyboard in screens, sheets and popups; Save visible above keyboard; Next/Done; tap outside or scroll dismisses keyboard; correct keyboard per type; OTP autofill support for later (Ch 47.3).
- [ ] 0A.13-T5 Form behaviours: unsaved-changes prompt on Back, draft autosave (survives incoming call/app kill), double-submit protection with client idempotency key to send to RPCs (Ch 47.4).
- [ ] 0A.13-T6 State components: skeleton, empty (with label-aware action), error with Retry (never silent), pull-to-refresh, undo, long-task progress with cancel (Ch 47.5).
- [ ] 0A.13-T7 Accessibility: 48 dp touch targets, screen-reader labels required by lint on icon buttons, contrast, no colour-only meaning (hot/warm/cold with icon/text) (Ch 47.8).
- [ ] 0A.13-T8 Component gallery screen (dev only) rendering every component in all states.
- [ ] 0A.13-T9 Screenshot harness: every gallery entry in light/dark × bn/en and with weird labels; automated contrast test.
- [ ] 0A.13-T10 Add the Ch 47 checklist (theme, keyboard, Bangla text, forms, states, navigation, network, accessibility, money, phone security) to the PR template as the per-screen release checklist.

**Tests**
- screenshot: gallery in light/dark × bn/en × weird labels; fails on clipped Bangla or overflow.
- unit: contrast checker rejects a light-yellow brand colour for text.
- UI (Maestro): long form on a small screen keeps the focused field and Save above the keyboard.

**Done when (acceptance criteria)**
- The gallery renders correctly in all four theme/language combinations and with system font at largest size; theme changes instantly.

**Watch-outs (do not miss)**
- Old app restarted on theme change (Ch 47.2).
- Long checklists get skipped under pressure: automate as much as possible (Ch 47.12 #1).
- Bangla fonts, line height and long translations break small phones (Ch 47.12 #7).

**Owner checkpoint:** Owner reviews the component gallery on a low-end phone in Bangla, light and dark, and approves the default palette.

### 0A.14 App shell, navigation, session plumbing and phone security

**Goal:** Provide the signed-in shell (branding area, tabs placeholder, profile) with correct navigation, per-user/per-institution caching rules, upgrade check and basic phone security.

**Depends on:** 0A.03, 0A.08, 0A.12, 0A.13

**Plan chapters:** Ch 47 (47.6, 47.7, 47.9 cache rules, 47.10), Ch 4.3 (client cache), Ch 4.5 (branding placement), Ch 3.4, Ch 13.2.

**Decisions:** D12, D13, D25.

**Build**
- **Data:** none new (uses profiles, settings, labels).
- **Server:** API client wrapper: sends app version and idempotency keys, handles "upgrade required", "session refresh required" (access version) and typed errors; slow-3G timeouts and retries.
- **App & web:** signed-in layout with top bar showing institution name/logo after sign-in and the neutral product name before sign-in; placeholder Home/More/Settings routes (real content in 1B, Ch 45); profile screen with language (bn/en) and appearance (System/Light/Dark; theme picker on web); offline "No internet" strip and "✓ Back online"; Android Back handling (close sheet/popup first, confirm before leaving Home); deep-link handler that switches institution first if needed (switch UI 1B); optional app lock (PIN/fingerprint); idle auto sign-out per institution setting; "sign out of all other devices"; responsive layout from 5-inch phones to tablets and web, safe areas, edge-to-edge.
- **Settings & permissions:** institution setting for idle sign-out minutes (name to confirm with Appendix A owner).

**Tasks**
- [ ] 0A.14-T1 Shell layout with branding slots (name/logo/colour from settings, defaults until 0B branding), neutral product name on pre-login screens.
- [ ] 0A.14-T2 Cache namespace helper `cacheKey(institution, user, …)`; settings/labels caches use it; all caches cleared on sign-out, user change and institution switch (SWR list caches added in 1B use the same helper).
- [ ] 0A.14-T3 API wrapper: version header, upgrade-required handling (blocking screen placeholder; banner in 1B), access-version refresh, typed error mapping, timeouts/retries tuned for slow 3G.
- [ ] 0A.14-T4 Profile screen: language and appearance switches applied without restart; saved to profile.
- [ ] 0A.14-T5 Navigation rules: Android Back closes sheets/popups first, Home exit confirmation; deep-link routing; remember list position API ("Keep in place") for lists in 1A.
- [ ] 0A.14-T6 Offline/online strip component wired to network status (offline queues in 1B).
- [ ] 0A.14-T7 App lock (PIN or biometrics, optional), idle sign-out (institution setting), sign out all other devices (RPC from 0A.03), cache wipe on sign-out.
- [ ] 0A.14-T8 Responsive and safe-area checks on 5-inch phone, tablet landscape and web widths.
- [ ] 0A.14-T9 Document the test phone list (one low-end 2–3 GB RAM, one mid-range, one small screen) and the manual pre-release pass with large font on (Ch 47.11, 47.12 #8).

**Tests**
- unit: cache is empty after sign-out and after institution switch.
- UI (Maestro Android, Playwright web): language/theme switch, Back behaviour, offline strip, idle sign-out.
- screenshot: shell and profile in light/dark × bn/en × weird labels.

**Done when (acceptance criteria)**
- After switching institution or signing out, no data of the previous institution or user remains on screen or in storage.
- An app older than `min_app_version` gets the upgrade-required response.

**Watch-outs (do not miss)**
- Old cache or old JWT showing the previous institution after a switch (Ch 4.13 #3).
- Cached names and numbers on a lost phone (Ch 47.12 #5).
- Phone clock may be wrong; use server time (Ch 47.7).

**Owner checkpoint:** Owner signs in on a phone, switches language and theme, turns on app lock, and signs out to see the cache cleared.

### 0A.15 Branches and the organisational unit tree

**Goal:** Model branches as one level of an unlimited org-unit tree (institution → branch → department → team) with managers, ready for branch scope in access checks.

**Depends on:** 0A.05, 0A.08, 0A.09

**Plan chapters:** Ch 12 (12.1–12.4, 12.6, 12.7), Ch 11 (11.6), Ch 4.2.

**Decisions:** D9, D25.

**Build**
- **Data:** `org_units(institution_id, id, parent_id, kind: branch/department/team/other, name, archived_at)`; `branches` details (org_unit_id, institution_id, name, address, phone, head_user_id, archived_at); `org_unit_members(institution_id, org_unit_id, user_id)`; `org_unit_managers(institution_id, org_unit_id, user_id)`; closure table or path column for fast subtree lookups; indexes `(institution_id, branch_id, …)`.
- **Server:** RPCs `branch_create/update/archive`, `org_unit_create/move/archive`, `org_unit_add_member/remove_member`, `set_manager`; rule: a branch or unit with records cannot be deleted, only archived after moving records (Ch 12.7 #7); events and audit rows emitted.
- **App & web:** none here (screen in 0A.19).
- **Settings & permissions:** branch feature gate read through a single helper `branches_enabled()` (placeholder setting now; replaced by the module system and plan limits in 0B: Starter 1, Standard 2–3, Pro unlimited, extra branches as add-on).

**Tasks**
- [ ] 0A.15-T1 Migrations for org units, branch details, members, managers with RLS and subtree index.
- [ ] 0A.15-T2 RPCs with validation (no cycles, branch kind only directly under the institution root, archive-only delete).
- [ ] 0A.15-T3 Null-branch rule: `branch_id` null means institution-level / not yet assigned; **Proposed:** branch-limited staff do not see null-branch records, Admin and the creator do (Ch 12.7 #1) — implemented in `user_access` (0A.17).
- [ ] 0A.15-T4 `branches_enabled()` helper; when off, APIs omit branch fields so screens hide branch fields, filters and columns (Ch 12.2).
- [ ] 0A.15-T5 Emit `org_unit.*` / `branch.*` domain events and audit rows.
- [ ] 0A.15-T6 Developer guide section "Branch or separate institution in a group?" (Ch 12.6, **Proposed** guidance) and the open questions (per-branch merchant/SMS sender, per-branch receipt/ID series; Ch 12.8).
- [ ] 0A.15-T7 Leak-test fixtures for org-unit tables.

**Tests**
- unit: cycle rejected; deleting a branch with members rejected; archive works.
- RLS + cross-tenant leak: B cannot read or change A's units.
- performance: subtree lookup for 500 units under 5 ms.

**Done when (acceptance criteria)**
- A test institution can have 3 branches each with departments and teams, managers assigned, and the tree can be read in one call.

**Watch-outs (do not miss)**
- Branch must be possible to turn on later without migrations — nullable `branch_id` on all core tables from day one (Ch 12.1, 12.3).
- Deleting a branch with records orphans data (Ch 12.7 #7).

**Owner checkpoint:** —

### 0A.16 Permission registry, roles, behaviour flags and role templates

**Goal:** Build the data-driven permission registry and the role model (system/custom roles, scoped grants, behaviour flags, sensitive permissions) with type-profile role templates.

**Depends on:** 0A.09, 0A.12, 0A.15

**Plan chapters:** Ch 11 (11.2–11.5, 11.7, 11.9, 11.10, 11.11 sensitive-field marking only, 11.15), Ch 43.5, Ch 8.6 (permission labels).

**Decisions:** D23, D26, D10.

**Build**
- **Data:** `permissions(key module.action, module, action, scopable bool, sensitive bool, label_key, help_key, introduced_in_release, default_for_templates jsonb)`; `field_registry(entity, field, sensitive bool, permission_key)`; `roles(institution_id, id, name, is_system, template_key, rank_for_sorting, inherits_from_role_id, flags)`; `role_permissions(role_id, permission_key, scope own/team/org_unit/branch/all)`; `role_templates(template_key, type_profile_key, name_label_key, grants, flags)`; behaviour flags: assignable, counts on leaderboard/scorecard, receives escalations, counts as manager, shown in team activity, call-log sync required.
- **Server:** registry loader from code-declared module manifests (each module declares permissions, defaults per system role/template); `*` only on the Super Admin system role and never expands to sensitive permissions for any other role; new-release permissions applied to system roles and templates by default; custom roles with "inherit from" receive only non-sensitive new permissions.
- **App & web:** none here (role editor in 0A.18).
- **Settings & permissions to register now:** `settings.users`, `settings.roles` (sensitive), `settings.terminology`, `settings.branches` (key name to confirm), `integration.manage` (sensitive, used by 0A.07 and 0B), plus area keys `settings.*` as later modules arrive; v2 key map for leads/reports/payments/discounts is **Proposed** (Ch 11.5 table) and registered by the milestones that build those modules.

**Tasks**
- [ ] 0A.16-T1 Migrations for permissions, field registry, roles, role permissions, role templates with RLS.
- [ ] 0A.16-T2 Module manifest format (permissions with key, scopable, sensitive, label key, help key, template defaults) and the loader that syncs it into `permissions` on deploy; CI fails if a permission has no label in both languages (Ch 11.16 #6).
- [ ] 0A.16-T3 Seed system roles: Super Admin (`*`), and education templates from Ch 11.7: College (Owner/Principal as Super Admin, Vice-principal, Admin, Branch manager, Department head, Team Lead, Counsellor/Caller, Admission Officer, Accountant, Viewer/Auditor, Governing body/Chair reports-only); School (same plus Head teacher, Assistant head teacher, Class teacher limited to own class); Coaching centre (Owner, Manager, Counsellor) (D26). Template names come from labels (`caller`, `team_lead`, `admission_officer`).
- [ ] 0A.16-T4 Behaviour flags table and defaults per template (replacing `acts_as`); multi-role rule: a flag is on if on in any assigned role (Ch 11.9).
- [ ] 0A.16-T5 Sensitive permission handling: excluded from wildcards except Super Admin `*`; changing a role that grants one requires an `aal2` (two-step) session — the check reads the JWT `aal` claim; MFA enrolment screens are 0B (Ch 10).
- [ ] 0A.16-T6 Field registry with sensitive flag (fee, discount, guardian NID, later health/KYC); sensitive fields never sent to AI (rule recorded for phase 4); masking enforcement is 1B.
- [ ] 0A.16-T7 New-release permission rollout: system roles and templates get declared defaults; custom roles inherit only non-sensitive ones; mark `introduced_in_release` for the "new permissions" view.
- [ ] 0A.16-T8 "Who" selector model `{mode: 'all'|'roles'|'users', roles: [], user_ids: []}` kept only for non-access settings (e.g. notification recipients, dashboard cards); roles list excludes Super Admin; access "who" rules become scoped permissions such as `conversion.mark` (Ch 11.10).
- [ ] 0A.16-T9 Extension and custom-record permission declaration path (same registry; custom records phase 2) and API key scopes from the same registry (phase 2) documented (Ch 43.5, R17).
- [ ] 0A.16-T10 Keep platform roles (Master Admin, Support, Billing, Developer, group owner) in `platform_members`/group tables only; DB constraint that no institution role can grant a platform permission.

**Tests**
- unit: `*` role gets non-sensitive and sensitive permissions; a custom role inheriting from Admin gets a new non-sensitive permission but not a new sensitive one.
- unit: CI fails when a manifest permission lacks a Bangla label.
- RLS + cross-tenant leak: roles of A invisible to B.

**Done when (acceptance criteria)**
- Seeding a college, a school and a coaching test institution creates their template roles with correct grants and flags; no permission key contains an education word.

**Watch-outs (do not miss)**
- Wildcard `*` silently growing to dangerous permissions (R6).
- `settings.manage` meaning "all settings and all courses" must not return: area settings permissions and data scope are separate (R5).
- Rank must not decide who can manage whom (R8); it is only for sorting.
- Ch 50 R7 writes `admission.mark`; use the neutral key `conversion.mark` (Ch 11.10).

**Owner checkpoint:** Owner reviews the role template list for college, school and coaching (D26) and the Proposed old-to-v2 permission map.

### 0A.17 Role assignments, `can()`, `user_access` and access version

**Goal:** Enforce access with one check function and a precomputed access table, supporting multiple scoped roles per user, temporary roles and immediate revocation.

**Depends on:** 0A.15, 0A.16

**Plan chapters:** Ch 11 (11.6, 11.7, 11.13, 11.3 protections, 11.16 #2, #3, #10), Ch 4 (4.7), Ch 12.4.

**Decisions:** D9, D23, D25.

**Build**
- **Data:** `role_assignments(institution_id, user_id, role_id, org_unit_id null, branch_id null, offering_limit uuid[] null, valid_from, valid_to, created_by)`; `user_access(institution_id, user_id, permission_key, scope, branch_ids, org_unit_ids, offering_ids, own_team_user_ids)` precomputed; access version bump on any change.
- **Server:** `can(user, action, record)` used by every write RPC (scope own/team incl. sub-teams/org_unit/branch/all, per-assignment branch and offering limits, union across roles with the larger scope winning but limits bound to each assignment); RLS helper functions using `user_access` with simple `IN` checks; incremental rebuild of `user_access` for changed users only, queued per institution; nightly expiry of temporary roles via pg_cron (moves to the 1B job scheduler later); safeguards: cannot remove the last Super Admin, cannot remove own admin access by mistake, cannot create or assign a role with permissions one does not have, cannot change a user with more power, role with members cannot be deleted without moving them to another role.
- **App & web:** none here (screens in 0A.18).
- **Settings & permissions:** assigning roles requires `settings.roles`/`settings.users`.

**Tasks**
- [ ] 0A.17-T1 Migration for role assignments and `user_access` with indexes led by `institution_id`.
- [ ] 0A.17-T2 `user_access` builder: full rebuild per institution and incremental per user; triggered by changes to roles, role permissions, assignments, org units, managers.
- [ ] 0A.17-T3 `can()` with scope evaluation, offering limit, null-offering rule (Admin and creator see records without an offering), null-branch rule (0A.15-T3), and temporary validity dates.
- [ ] 0A.17-T4 RLS policy helpers for tenant tables (`visible_branch_ids()`, `visible_owner_ids()`, `visible_offering_ids()`), to be used by 1A tables; `(select …)` wrapping for init-plan caching.
- [ ] 0A.17-T5 Access version bump on any access change and enforcement in the API wrapper/Edge middleware; deactivation revokes sessions immediately.
- [ ] 0A.17-T6 Safeguards (last Super Admin, self-lockout, no escalation, no deleting role with members, reassign step) enforced server-side.
- [ ] 0A.17-T7 RPCs `role_assign`, `role_unassign`, `role_create/update/copy/delete` using `can()`, emitting events and audit rows; "resulting access" preview function for an assignment before saving (Ch 11.16 #2).
- [ ] 0A.17-T8 CI check: every write RPC calls `can()` (static scan of function bodies) (Ch 11.16 #6).
- [ ] 0A.17-T9 Temporary role expiry job (pg_cron) and rebuild of affected `user_access` rows.
- [ ] 0A.17-T10 "Who" selector server evaluator `who_matches(rule, user)` for non-access settings (used by 0B notification recipients).

**Tests**
- RPC-as-real-role: user who is admin in branch A and caller in branch B can edit any record in A and only own records in B.
- unit: last Super Admin cannot be removed; Admin cannot grant `settings.roles` without having it.
- RLS + cross-tenant leak: `user_access` rows of A invisible to B.
- performance: rebuilding `user_access` for one user in an institution with 200 users and 50 units under 200 ms; RLS `IN` check on a 3,000-row synthetic table adds under 10 ms (Ch 11.16 #3, R14).

**Done when (acceptance criteria)**
- Removing a role takes effect on the user's next request (access version), without waiting for token expiry.
- All protections in Ch 11.3 ("protected against") are enforced and covered by tests.

**Watch-outs (do not miss)**
- Union of roles giving unintended power: an `all` scope from one role must not override another assignment's branch limit (Ch 11.16 #2).
- Mass reorganisation or import causing `user_access` rebuild storms — rebuild incrementally, fairly per institution (Ch 11.16 #3).
- A new RPC forgetting `can()` makes the system meaningless (Ch 11.16 #6).

**Owner checkpoint:** —

### 0A.18 Users screen, role editor, basic access explainer and audit view

**Goal:** Give the institution's Super Admin the screens to manage users, roles and assignments, compare roles, see new permissions and understand why someone can or cannot see a record.

**Depends on:** 0A.14, 0A.17

**Plan chapters:** Ch 11 (11.14, 11.3 R16, R20, 11.16 #1), Ch 8.6 (permission labels).

**Decisions:** D23, D26.

**Build**
- **Data:** none new.
- **Server:** RPCs `users_list(status, search)`, `user_detail`, `user_approve`, `user_deactivate`, `user_reactivate`, `user_update_contact` (email change applied immediately), `access_explain(user_id, record_ref)` returning which role/scope/rule allows or blocks, `audit_list(filters)`.
- **App & web:** Settings → Users: list of pending / active / deactivated users with search; detail with name, phone, email, role assignments (role + unit/branch + offering limit + dates), org units, list layout edit placeholder, call-log sync requirement shown read-only (phase 3); actions approve, deactivate/reactivate, password reset (button wired in 0B, Ch 10.7), activity (phase 4), delegation (1B). Settings → Roles: role editor generated from the registry grouped by module with labels and help, scope picker for scopable permissions, behaviour flags, compare two roles, copy role, "new permissions in this release". Access explainer (basic). Audit log viewer for role, assignment and settings changes.
- **Settings & permissions:** `settings.users` for Users, `settings.roles` (sensitive, `aal2`) for role changes.

**Tasks**
- [ ] 0A.18-T1 Users list and detail screens with all states (loading skeleton, empty, error with Retry) and search.
- [ ] 0A.18-T2 Approve / deactivate / reactivate flows with confirmation; deactivation ends sessions immediately.
- [ ] 0A.18-T3 Role assignment editor with branch/unit, offering limit and validity dates plus the "resulting access" preview.
- [ ] 0A.18-T4 Role editor generated from the registry: module groups, label + help per permission, scope picker, sensitive badge, behaviour flags; copy role; delete role with "move members to another role" step.
- [ ] 0A.18-T5 Compare two roles view and "new permissions in this release" view.
- [ ] 0A.18-T6 Basic access explainer: pick a user and a record (any registered entity; leads arrive in 1A) and show allowing/blocking role, scope, branch/offering limit and validity.
- [ ] 0A.18-T7 Audit log viewer for roles, assignments, field-rule and settings changes, filterable by actor and date.
- [ ] 0A.18-T8 All permission names shown via labels (e.g. "View trainees"); no hard-coded strings.
- [ ] 0A.18-T9 **Proposed:** "simple mode" hiding units and approval policies for small institutions until needed (Ch 11.16 #1) — build only if approved.

**Tests**
- role-matrix: Users and Roles screens hidden and RPCs refused for roles without `settings.users`/`settings.roles`.
- RPC-as-real-role: role change without `aal2` session refused.
- UI (Playwright web, Maestro Android): create custom role, assign with branch limit, explainer shows the reason.
- screenshot: Users list/detail, role editor, explainer, audit in light/dark × bn/en × weird labels.

**Done when (acceptance criteria)**
- A Super Admin can create a custom role from a template, assign it to a user for one branch with an end date, and see the change in the audit log.
- The explainer correctly tells why a test user can or cannot see a seeded record.

**Watch-outs (do not miss)**
- Small institutions find units, scopes and policies frightening (Ch 11.16 #1).
- The UI must hide what a user cannot do, but the server is the real check (Ch 4.7).

**Owner checkpoint:** Owner (as Super Admin of a test college) creates a role, assigns it, and asks the explainer "why can't this user see this record?".

### 0A.19 Settings → Branches and Settings → Terminology screens

**Goal:** Ship the two phase-0 settings screens owned by this block: branch management and the terminology (label) editor with live preview.

**Depends on:** 0A.11, 0A.12, 0A.18

**Plan chapters:** Ch 12 (12.2, 12.5), Ch 8 (8.8, 8.6, 8.10 #4), Ch 13.2.

**Decisions:** D9, D13.

**Build**
- **Data:** none new.
- **Server:** RPCs `labels_set(key, forms)`, `labels_reset(key | all)`; branch RPCs from 0A.15.
- **App & web:** Settings → Branches: list, create, edit (name, address, phone, branch head), archive; hidden entirely when branches are disabled. Settings → Terminology: table of term, key, default, English singular/plural, Bangla forms; live preview of a sample lead card, a receipt header and an SMS using the new words; reset one term or all to type-profile defaults; length limits shown; locked labels shown read-only; changes effective for everyone immediately and written to the change/audit log.
- **Settings & permissions:** `settings.branches`, `settings.terminology`; branch info template variables for receipts/templates/public forms are exposed later by 1B/2 (Ch 12.5, 24).

**Tasks**
- [ ] 0A.19-T1 Branches list/edit/archive screens with all states and validation.
- [ ] 0A.19-T2 Archive guard: if a branch has records or members, show the "move to another branch first" step.
- [ ] 0A.19-T3 Terminology table screen with search (matches default words too) and grouping as in Ch 8.4.
- [ ] 0A.19-T4 Live preview panel (sample lead card, receipt header, SMS text) in the current UI language with a toggle to the other language.
- [ ] 0A.19-T5 Reset to profile defaults per term and all, with confirmation.
- [ ] 0A.19-T6 Server-side length limits and locked-label enforcement; instant refresh on other devices through settings version.
- [ ] 0A.19-T7 Write every label change to the audit log with old/new values.
- [ ] 0A.19-T8 Record **Proposed** follow-ups: branch filter/column on lead list and board (1A, Ch 15), branch choice on public application form (1B, Ch 27), bulk "assign branch" tool with preview and undo (1A), branch change action on a lead (1A).

**Tests**
- role-matrix: screens and RPCs refused without `settings.branches` / `settings.terminology`.
- UI (Playwright, Maestro): rename `client` to "Trainee"/"প্রশিক্ষণার্থী", preview updates, shell menu and Users screen show the new word on a second device after refresh.
- screenshot: both screens light/dark × bn/en × weird labels.

**Done when (acceptance criteria)**
- Renaming a term changes it in every screen built so far in both languages without reinstalling or restarting.
- With branches disabled, no branch field, filter or column appears anywhere.

**Watch-outs (do not miss)**
- Wrong or improper labels reaching receipts and public pages: preview, change log, platform lock and one-click reset (Ch 8.10 #4).
- Half-renamed app (menu says Trainees, another screen says Student) (Ch 8.1).

**Owner checkpoint:** Owner renames two terms in Bangla and English for a test institution and sees the preview and the menus change, then resets them.

### 0A.20 Seeded test institutions, role-matrix and screenshot matrix, benchmark harness — Phase 0A exit gate

**Goal:** Close Phase 0A with the full automated safety net running on every PR and a demo to the owner.

**Depends on:** 0A.07, 0A.19

**Plan chapters:** Ch 48 (48.7, 48.10 #2), Ch 4 (4.8, 4.12 #6), Ch 11.13 (tests), Ch 2.5, Ch 47.9, 47.11, Ch 8.9 rule 4, Ch 50 (T1–T5, T9, R1–R20, R+), Ch 51.3.

**Decisions:** D8, D13, D25.

**Build**
- **Data:** seed generator for test institutions: one per role-template set (college, school, coaching; full type-profile seeds are added by 0B when profiles exist, D8), the weird-labels institution, a large institution and a small institution for benchmarks, the dual-membership user.
- **Server:** role-matrix test generator: for every role template × every registered permission × records inside and outside scope (own/team/unit/branch/all, offering limit, null branch).
- **App & web:** screenshot matrix job for every screen route: light/dark × bn/en × weird labels.
- **Settings & permissions:** none new.

**Tasks**
- [ ] 0A.20-T1 Seed generator CLI used by CI and staging; deterministic ids.
- [ ] 0A.20-T2 Role-matrix test generated from the registry and templates; fails when a new permission has no expectation entry.
- [ ] 0A.20-T3 Screenshot matrix over all routes; baseline images committed; nightly full run, PR run on changed screens.
- [ ] 0A.20-T4 Benchmark harness with large and small institutions side by side (~3,000-row synthetic lead-sized table now; real lead benchmarks in 1A), measuring RLS + `user_access` overhead and `can()` cost before/after a change.
- [ ] 0A.20-T5 **Proposed:** CI benchmark gate that fails a release when a measured path gets slower beyond a threshold (Ch 2.7 #4, Ch 47.12 #6).
- [ ] 0A.20-T6 Make all gates required on `main`: leak test, RPC-as-role, DEFINER audit, invoker sweep, schema lint, i18n lint and missing keys, role matrix, settings schema validation, screenshot diff.
- [ ] 0A.20-T7 Run the Ch 50 risk review for this block (T1–T5, T9, R1–R20, R+, X7) and record status per row; update the lessons page if anything new happened (Ch 51.4 #1).
- [ ] 0A.20-T8 Staging rehearsal: apply all migrations to staging with seed data, run the full suite, then promote.
- [ ] 0A.20-T9 Owner demo script: two institutions, dual-membership switch, branches, role assignment with branch limit, explainer, terminology rename in both languages, light/dark.

**Tests**
- role-matrix: full matrix green.
- RLS + cross-tenant leak: full catalog including storage, Realtime, ext schemas, dual-membership user.
- screenshot: every route × light/dark × bn/en × weird labels.
- performance: large institution does not slow the small institution's queries by more than the agreed threshold.

**Done when (acceptance criteria)**
- All gates listed in T6 are required checks and green on `main`.
- The demo script runs end to end on a phone and on web in both languages.
- Risk review rows for this block are marked handled or deferred with a named milestone.

**Watch-outs (do not miss)**
- Testing every combination is impossible; seed profiles, role matrix and typed settings target the risky ones (Ch 48.10 #2).
- "Never slower" measured by hand will be forgotten (Ch 2.7 #4).
- Group-owner leak test is added when groups ship in 1B (Ch 4.13 #10, Ch 11.16 #7).

**Owner checkpoint:** Owner watches the demo, confirms Phase 0A is done, and approves starting Block 0B (or parallel 0B work already allowed by dependencies).

## Phase 0B: Platform, onboarding and integrations

This block turns the Block 0A skeleton into a platform that can sign up, configure, bill and talk to real institutions. It delivers the per-institution settings registry (Appendix A), the Master Admin panel core (platform roles, two-step login, institution list, approval, lifecycle states, support entry, audit), industry packs and all nine education type profiles as versioned data, the setup wizard and checklist, modules, plans, limits and the subscription billing core, the custom field builder, the integration hub (catalog, connections, Vault secrets, adapters, outbox, webhook router, health, usage ledger) with SMS and transactional email adapters and the OTP route, the staff notification recipient matrix, and the remaining login paths (Google, OTP, staff sign-up and approval, profile, account deletion, sessions).
**Exit criteria:** a new education institution can self-sign-up (or be created by Master Admin), be approved, land in trial with its type-profile defaults seeded, configure branding and custom fields, have SMS and email set up by Master Admin, receive OTP and test messages through its own gateway, be billed (manual or platform SSLCommerz), expire into grace and read-only without data loss, and be suspended or closed safely; every new table, RPC and Edge Function is in the cross-tenant leak test; no code path branches on `institution_type`.

### 0B.01 Per-institution settings registry and Appendix A keys

**Goal:** One typed, versioned, per-institution settings store (`app_settings`) with JSON-schema validation, profile-sourced defaults and area-based settings permissions, so nothing is hard-coded again.

**Depends on:** Block 0A (tenancy schema + RLS + leak test, roles and permissions v2 core, labels/i18n, event log; **0A.08 typed settings framework**).

**Note (merge):** 0A.08 builds the settings framework (storage, validation, versioning, cache, counters). This milestone does **not** rebuild it: it registers every Appendix A key on top of 0A.08, adds type-profile defaults and the area-based settings permissions. Skip any 0B.01 task that 0A.08 already delivered.

**Plan chapters:** Appendix A (all), Ch 2 (no hard-coding, via Appendix A), Ch 11 (11.5 area settings permissions), Ch 13 (locale settings rows), Ch 51 (51.1 hard-coding lesson).

**Decisions:** D13, D22.

**Build**
- **Data:** `app_settings(institution_id, key, value jsonb, schema_version, updated_by, updated_at)` with unique `(institution_id, key)` and RLS; `setting_definitions(key, area, json_schema, default_source, owner_module, schema_version, label_key)` (product-level, read-only to tenants); `app_settings_history` (old/new value, actor, time) for rollback; seed definitions for every Appendix A key; do NOT create the dropped keys `max_call_attempts`, `call_log_lock_hours`, `activity_retention_days`, nor tables `feature_flags`, `call_results`, `document_types`.
- **Server:** `get_setting(key)` / `get_settings(keys[])` (INVOKER, active institution from session only), `set_setting(key, value)` validating JSON schema and area permission, writing history and a `domain_events` row; settings migration runner (per `schema_version`); default resolution order: institution value → type-profile default (from 0B.03) → product default.
- **App & web:** shared `useSetting(key)` hook with typed accessors and cache keyed by institution + user; developer docs page "Adding a setting key".
- **Settings & permissions:** area permissions `settings.team`, `settings.admission`, `settings.fees`, `settings.leads`, `settings.calls`, `settings.ai`, `settings.forms`, `settings.calendar`, `settings.general` (plus the 0A ones `settings.users`, `settings.roles`, `settings.terminology`, `settings.pipeline`); labels for every key and area.

**Tasks**
- [ ] 0B.01-T1 Create `setting_definitions`, `app_settings`, `app_settings_history` with `institution_id` on every tenant row, RLS and leak-test entries.
- [ ] 0B.01-T2 Write JSON schemas for all Appendix A keys, grouped by area: team and reports (`activity`, `reports`, `scorecard`, `credits`, `credit_extras`, `notifications`, `web`); admission and students (`admission`, `admission_approval`, `students`, `files`, `upload_rules`, `photo_presets`); fees (`fees`, `receipt_prefix`); leads (`assignment`, `board`, `lead_cards`, `lead_filters`, `lead_score`, `campus_visit`, `message_templates`); calls and contacts (`call_sync`, `call_lock`, `double_call`, `contacts_import`); AI (`ai_chance`, `ai_credit`, `ai_providers` — keys themselves only in Vault); alumni and forms (`alumni`, `public_forms`); office calendar (`working_days`, `working_hours`, `quiet_hours`); single values (`institution_name`, `developer_email`, `min_app_version`, `speed_to_lead_minutes`, `early_reminder_minutes`, `repeat_reminder_minutes`, `escalate_team_lead_hours`, `escalate_admin_hours`). Keys whose feature is built later get a minimal schema now; the owning milestone extends it via a schema-version migration.
- [ ] 0B.01-T3 Register the "other per-institution configuration" groups from Appendix A in the catalog with their owning tables (branding, board flow, reset-password format, locale, lead score, counters, external accounts, types and packs, plan and billing, login, roles and access, branches, notifications, campaigns, public pages, custom parts) so later milestones attach to them.
- [ ] 0B.01-T4 Locale defaults as settings, never constants: time zone `Asia/Dhaka`, currency ৳, phone rule (`880`, 01XXXXXXXXX), week Saturday–Friday with Friday off, scorecard day Sunday, payment methods bKash / Nagad / Rocket, address placeholder, default UI language (D13).
- [ ] 0B.01-T5 Implement `get_setting` / `set_setting` RPCs (INVOKER, institution from session, area permission check through the 0A `can()`), history rows and `domain_events`.
- [ ] 0B.01-T6 Implement the settings migration runner and a CI check that every key in `setting_definitions` has a schema, a label key and an owner module.
- [ ] 0B.01-T7 Add a lint rule that fails on hard-coded locale values (`Asia/Dhaka`, `৳`, `880`) outside the settings seed.
- [ ] 0B.01-T8 **Proposed:** neutral renaming of education-worded keys before any data exists (`campus_visit` → `appointment`, `alumni` → `network`, and review of `students`, `admission`); implement whichever names the owner approves at the checkpoint.
- [ ] 0B.01-T9 Mark product-level (not per-institution) values as platform config: app name, domain, privacy-page contact, owner of developer/feedback inbox.
- [ ] 0B.01-T10 Client hook `useSetting` with cache partitioned by institution and user; clear on institution change.

**Tests**
- RLS + cross-tenant leak: user of institution A cannot read or write B's `app_settings` or history; two-membership user sees only the active institution's rows.
- RPC-as-real-role: `set_setting` as a role with only `settings.fees` can change `fees` but not `assignment`.
- Unit: every Appendix A key validates its seed default against its schema; invalid values rejected with a clear error.
- CI: dropped keys/tables do not exist; lint catches a planted `Asia/Dhaka` literal.

**Done when (acceptance criteria)**
- Every Appendix A key exists in `setting_definitions` with schema, label (bn/en) and owner.
- Changing a setting is permission-checked per area, validated, audited and reversible from history.
- No locale value is hard-coded in app or server code (lint green).

**Watch-outs (do not miss)**
- Area permissions replace the old broad `settings.manage` (R5); settings permission never widens data visibility.
- Server decides from session data, never from client-sent institution or permissions (Ch 51 lesson 7).
- The old app's single-college hard-coding is the reason this exists (Ch 51); reviewers reject new constants.

**Owner checkpoint:** approve (or reject) the neutral renaming of `campus_visit`, `alumni`, `students`, `admission`; review the key catalog.

### 0B.02 Platform roles, Master Admin login and panel shell

**Goal:** A separate, hardened Master Admin panel with platform-level roles that never mix with institution roles.

**Depends on:** 0B.01; Block 0A (roles and permissions v2 core, event log, design system).

**Plan chapters:** Ch 5 (5.1–5.3, 5.14, 5.17 rows 1–2), Ch 11 (11.15), Ch 10 (10.2 Master Admin login), Ch 1 (1.5, 1.7 row 3, 1.8).

**Decisions:** D4, D21.

**Build**
- **Data:** `platform_users(user_id, platform_role, status, created_by)` with roles Master Admin, Support, Billing, Developer; `platform_audit_log(actor, action, institution_id nullable, target, before, after, ip, device, reason, at)` (append-only); `platform_login_devices(user_id, ip, device_fingerprint, first_seen)`.
- **Server:** `is_platform(role)` helper used only by platform RPCs; platform RPCs are separate from tenant RPCs; new IP/device alert job; every platform write goes through an audited wrapper that never logs secrets.
- **App & web:** separate web login page for the panel (not the staff login); mandatory second factor; panel shell with the menu from Ch 5.3 (Dashboard, Institutions, Groups, Profiles & packs, Providers, Announcements, Requests, Developer inbox, Platform users) where menus built later show "coming in phase N"; Platform users screen.
- **Settings & permissions:** platform permission keys `platform.institutions.*`, `platform.support.enter`, `platform.billing.*`, `platform.integrations.manage`, `platform.profiles.manage`, `platform.users.manage`, `platform.developer.view`; labels for roles and menus.

**Tasks**
- [ ] 0B.02-T1 Create `platform_users`, `platform_audit_log`, `platform_login_devices`; no tenant role can be granted a platform role and an institution Super Admin gets no platform role.
- [ ] 0B.02-T2 Implement the separate panel login page with mandatory second factor for every platform user (no opt-out), using Supabase Auth MFA.
- [ ] 0B.02-T3 New IP / new device alert to the account owner and to all Master Admins.
- [ ] 0B.02-T4 Audited wrapper for platform writes (actor, institution, before/after, reason); secrets redacted.
- [ ] 0B.02-T5 **Proposed:** least-privilege platform roles — Support read-only by default, Billing only billing, Developer only inbox/error views; Support setup rights (Ch 5.17 row 1) as an optional permission.
- [ ] 0B.02-T6 Panel shell with the Ch 5.3 menu (**Proposed** structure) and per-institution tabs Overview, Messaging, Notifications, Payments, Integrations, Domain, Plan & billing, Labels, Audit (tabs filled by later milestones).
- [ ] 0B.02-T7 Platform users screen: invite, deactivate, change role; no shared accounts (one person per account, enforced by invite-by-email).
- [ ] 0B.02-T8 Seed script for the first Master Admin (CLI only, never via public UI).
- [ ] 0B.02-T9 Product-level config: product name "Leadora" (D37) held in one config value used by panel, login, emails and privacy page, so the final neutral name is a config change; record the **Proposed** naming criteria (neutral, short, bn/en friendly, `.com`/`.com.bd` + Play name + trademark free) and the rule that name, Android package and deep-link scheme are fixed before the first store build (Ch 1.7 row 3).

**Tests**
- RLS: a tenant Super Admin JWT gets zero rows from every platform table and cannot call platform RPCs.
- Role-matrix: Support, Billing, Developer each can reach only their menus/RPCs.
- UI (Playwright): panel login without second factor is impossible; new-device login raises an alert.
- Leak test: platform audit rows of institution A not visible to institution B's Super Admin (the institution-facing view comes in 0B.09).

**Done when (acceptance criteria)**
- Platform login is on its own page and always needs two steps.
- Platform and institution roles are separate tables and permission spaces; tests prove no mixing.
- Every platform write appears in `platform_audit_log` without secrets.

**Watch-outs (do not miss)**
- One stolen Master Admin login exposes all institutions (M12, Ch 5.17 row 2): very few accounts, 2-step, alerts, full audit.
- Developer used to be a special in-tenant user identified by an email setting; now it is a platform role (Ch 5.2).
- Platform roles must not mix into institution roles (R+).

**Owner checkpoint:** log in to the panel with two steps; approve the menu structure and platform role rights.

### 0B.03 Industry packs and type profiles as versioned data

**Goal:** Store industry packs and all nine education type profiles as versioned, schema-validated data that Master Admin can edit without a release, with only the education pack open.

**Depends on:** 0B.02; Block 0A (labels and neutral keys, roles v2 core / role templates).

**Plan chapters:** Ch 7 (7.1–7.10), Ch 49 (49.2–49.5, 49.7, 49.9 phase 0), Ch 1 (1.6), Ch 5 (5.10).

**Decisions:** D8, D18, D19, D20, D26.

**Build**
- **Data:** `industry_packs(id, key, version, status, signup_open, labels, stages, modules, sensitive_fields, …)` and `type_profiles(id, pack_id, key, version, status, payload jsonb)`; JSON schema for the profile payload; seed the education pack (Lead → Student; Course / Class / Program; New → Contacted → Visit → Test → Admitted; education-only modules) and nine profiles: school, college, private university, polytechnic, madrasa, English-medium, coaching, training institute, nursing / medical / health.
- **Server:** profile validation function; `list_open_packs()` for the wizard (respects `signup_open`); pack/profile version publishing (draft → published).
- **App & web:** Master Admin → Profiles & packs: list, view, edit as structured form + JSON, validate, publish new version, set which industries are open for sign-up.
- **Settings & permissions:** `platform.profiles.manage`; labels for all profile/pack names in bn and en.

**Tasks**
- [ ] 0B.03-T1 Create `industry_packs` and `type_profiles` with version columns; published versions are immutable.
- [ ] 0B.03-T2 Write the profile JSON schema covering everything Ch 7.5 says a profile sets: labels, pipeline stages, required documents, fee structure, lead custom fields, board flow on/off, message templates, student-ID pattern, lead-score points, modules on/off, lost reasons / sources / tags, report presets, AI prompt words, role templates (D26), field-level rule defaults, notification recipient-matrix defaults, custom-field presets.
- [ ] 0B.03-T3 Seed the nine education profiles with the Ch 7.4/7.5 content (e.g. school: Class/Section/Session/Roll, stages New → Contacted → Visit → Admission test → Result → Ready → Admitted / Lost, birth certificate/TC/photo/guardian NID, admission + monthly + session fee, ID `{YYYY}{CLASS}{000}`; coaching: Course/Batch/Month/Student no., New → Called → Demo class → Enrolled / Lost, photo only, package or monthly fee, ID `{CODE}-{000}`). Content is **Proposed** (Ch 7.10) and reviewed with the owner.
- [ ] 0B.03-T4 Seed role templates per profile (D26): college — owner/principal (Super Admin), vice-principal, Admin, branch manager, head of department, team lead, counsellor (caller), admission officer, accountant, viewer/auditor, governing body/chair (reports only); school adds head teacher, assistant head teacher, class teacher (own class only); coaching — owner, manager, counsellor.
- [ ] 0B.03-T5 Seed custom-field presets (SSC/HSC GPA, board, roll, registration no., passing year, previous institution, date of birth, birth registration no., guardian NID, guardian occupation, group/department, shift, version) referenced by profiles.
- [ ] 0B.03-T6 Profile parts for blocks built in later phases (admission test, merit list, fee heads, board flow, hostel) are stored now but stay behind their modules until that phase (Ch 7.8).
- [ ] 0B.03-T7 Pack-level sensitive-field declaration (Ch 49.7): sensitive fields, never-to-AI flag, retention limit, view audit; for education mark guardian NID and birth registration no. sensitive.
- [ ] 0B.03-T8 Industry list data for the hidden wizard step (Ch 6.3 step 1 list, including "Other (general)") stored but not open; only education `signup_open = true` (D20).
- [ ] 0B.03-T9 Master Admin Profiles & packs screen with validate-before-publish and version history.
- [ ] 0B.03-T10 CI job validating every pack/profile row against the schema (Ch 7.9 row 1).
- [ ] 0B.03-T11 Lint/review rule: no code may read `institution_type` except the profile applier (Ch 7.2 developer rule).

**Tests**
- Unit: all nine seeded profiles pass the schema; a broken profile fails publish.
- RLS: tenants can read only published pack/profile data needed by the wizard, never edit.
- CI: lint fails on a planted `institution_type ==` branch outside the applier.

**Done when (acceptance criteria)**
- Nine education profiles and the education pack exist as published data, visible and editable (as new versions) in the panel.
- Only education is open for sign-up; other industries exist only as data rows marked closed (or are absent until their pack is built).

**Watch-outs (do not miss)**
- Code follows settings and modules, never type (Ch 7.2, Ch 9.2).
- Weak defaults give a bad first day (Ch 7.9 row 3): review profiles with the first institutions.
- Bangladesh admission systems change (Ch 7.9 row 7): profiles are data so updates need no release.

**Owner checkpoint:** walk through each of the nine profiles' defaults (labels, stages, documents, fees, role templates) and approve the **Proposed** contents.

### 0B.04 Profile applier, reset to defaults and Master Admin label control

**Goal:** Apply one or more type profiles to an institution, merge mixed institutions, track what the institution changed, and support "Reset to profile defaults" and later type/industry changes without losing data.

**Depends on:** 0B.03; 0B.01.

**Plan chapters:** Ch 7 (7.5, 7.6, 7.9 rows 4–5), Ch 6 (6.6, 6.9 rows 5–6), Ch 49 (49.4 rules, 49.8 rows 9–10), Ch 5 (5.3 Labels tab, 5.10).

**Decisions:** D8, D19, D20.

**Build**
- **Data:** `institution_profiles(institution_id, profile_id, profile_version, pack_id, pack_version, applied_at)`; `seeded_items(institution_id, area, item_key, source_profile, source_version, modified_by_institution bool)`; `label_locks(institution_id, label_key, locked_by, reason)`; `institutions.industry` always stored (education today).
- **Server:** `apply_profiles(institution_id, profile_ids[], exclude_areas[])` (the only code allowed to read type); merge rules for mixed types (stages and offerings partitioned by type; label conflicts returned for a choice); `preview_profile_change()`; `reset_to_profile_defaults(area)` with preview; `change_types()` / `change_industry()` that re-seed only unmodified items and never delete data.
- **App & web:** Settings → each area shows "Reset to profile defaults" with preview; Settings → Institution type (add/remove type) with warning and preview; Master Admin → Institutions → Labels tab: view the institution's labels and lock a label (e.g. legal receipt title); Profiles & packs → product-default labels editor.
- **Settings & permissions:** `settings.institution_type` (sensitive); `platform.labels.lock`.

**Tasks**
- [ ] 0B.04-T1 Create `institution_profiles`, `seeded_items`, `label_locks` with RLS and leak-test entries.
- [ ] 0B.04-T2 Implement `apply_profiles` for the parts that exist in phase 0 (labels, modules, settings defaults, role templates, custom-field presets, recipient-matrix defaults) and a registry so later blocks plug in their areas (stages, documents, fees, templates, ID pattern, lead score, reports, AI words).
- [ ] 0B.04-T3 Track "modified by institution" on every seeded item (trigger on update).
- [ ] 0B.04-T4 Mixed institutions: merge seeds, partition stages and offerings by type, return label conflicts for a choice in preview (**Proposed**, Ch 7.9 row 5).
- [ ] 0B.04-T5 "Reset to profile defaults" per area with a diff preview.
- [ ] 0B.04-T6 Change type / industry later with warning + preview; only unmodified items re-seed; data never deleted (Ch 6.6, Ch 49.4).
- [ ] 0B.04-T7 New profile/pack versions never auto-apply to existing institutions; Admin sees "new version available" with a preview and opts in (**Proposed**, Ch 7.6, Ch 49.8 row 9).
- [ ] 0B.04-T8 Existing institutions are stored with industry = education even though the step is hidden (**Proposed**, Ch 6.9 row 6).
- [ ] 0B.04-T9 Master Admin label view and lock; locked labels read-only in the institution's Terminology screen (0A).
- [ ] 0B.04-T10 Product-default label editor in Profiles & packs (changes product defaults, never an institution's own overrides).
- [ ] 0B.04-T11 Rule check: user-facing output (export headers, reports, PDFs) uses labels; neutral keys only in API/webhook (Ch 49.8 row 10) — add to review checklist.

**Tests**
- Unit: applying school + college merges without duplicate stages; label conflict surfaces in preview.
- Unit: after an institution edits a label, a type change does not overwrite it; reset restores it only after confirmation.
- RLS + leak: `seeded_items` and `label_locks` isolated per institution.
- Screenshot (light/dark × bn/en): Reset preview dialog and Labels tab.

**Done when (acceptance criteria)**
- A seeded test institution exists for each of the nine profiles (used in CI, Ch 7.3) and for one mixed (school + college).
- Reset and type change show a preview and never delete data or overwrite institution edits.

**Watch-outs (do not miss)**
- Forcing a new profile version on old institutions destroys their settings (Ch 7.9 row 4).
- Mixed-institution seed collisions ("Class" vs "Course") (Ch 7.9 row 5).

**Owner checkpoint:** demo a school + college mixed setup, a type change with preview, and a label lock.

### 0B.05 Modules, plans and limits

**Goal:** Data-driven modules (allowed by Master Admin, toggled by Super Admin), plans and limits enforced on the server with 80 % warnings and 100 % blocks, never blocking OTP or urgent messages.

**Depends on:** 0B.04; 0B.02.

**Plan chapters:** Ch 9 (9.1–9.5, 9.8, 9.9 rows 1–5, 9.10 phase 0), Ch 7 (7.8), Ch 5 (5.7, 5.10), Ch 14 (14.11 active-lead limit hook).

**Decisions:** D7, D22.

**Build**
- **Data:** `modules(key, label_key, depends_on[], always_on, industry_scope)` seeded with the Ch 9.2 list (core leads and follow-ups always on; calls and Android sync; WhatsApp log; campus visit; admission test and merit list; fees/payments/receipts; student ID; external board flow; hostel and transport; AI; credits and leaderboard; alumni and referral; Drive files and Photo Studio; public forms; bulk SMS / Campaigns; branches; automation / custom records / API / webhook / extensions); `institution_modules(institution_id, module_key, allowed, enabled)`; `plans(id, key, version, prices, modules[], limits jsonb)`; `institution_plan(institution_id, plan_id, plan_version, expires_at, billing fields, overrides jsonb)`; `usage_counters(institution_id, metric, value, period)` maintained by triggers.
- **Server:** `module_enabled(key)` used by RLS-adjacent checks, RPCs and job runners; `check_limit(metric, delta)` inside the same server `can()` path; nightly counter reconciliation job; downgrade fit check returning what must be reduced.
- **App & web:** Settings → Modules (Super Admin toggles allowed modules, shows dependency impact); Master Admin → Plan & billing tab (plan, expiry, per-institution overrides of price/discount/limits with log, allowed modules); limit banners (80 %) and blocking dialogs (100 %) with "Upgrade"; staff-facing message "Your institution's monthly SMS limit is reached, tell your Admin".
- **Settings & permissions:** `settings.modules`; `billing.view` (sensitive); `platform.plans.manage`; labels `module.*`.

**Tasks**
- [ ] 0B.05-T1 Create `modules`, `institution_modules` and seed the Ch 9.2 module list with labels (`module.students` → e.g. "Trainees").
- [ ] 0B.05-T2 Disabled module: removed from menus, Home cards, filters, reports and settings; background jobs skip that institution; data kept and returns on re-enable; core lead/follow-up module cannot be disabled.
- [ ] 0B.05-T3 **Proposed:** module dependency declarations and an impact list before enabling/disabling (Ch 9.9 row 2), e.g. Campaigns needs an SMS connection.
- [ ] 0B.05-T4 Modules default from type profile and (later) pack; industry-specific modules (merit list, board flow) only for education; blocks not yet built stay disabled while profiles still work for leads and follow-ups (Ch 7.8).
- [ ] 0B.05-T5 Create `plans` as data with **Proposed** five plans: free trial (14 or 30 days, fewer users, less SMS/AI; open question), Starter, Standard, Pro, Enterprise/custom with the Ch 9.3 module lists; plan versions so existing customers keep their price until expiry (**Proposed**, Ch 9.9 row 8).
- [ ] 0B.05-T6 Limits catalog: users, active leads, branches, storage, monthly SMS, monthly AI, automations, custom fields / records, API calls, daily campaign limit; plan values with per-institution Master Admin overrides (logged).
- [ ] 0B.05-T7 Trigger-maintained counters + nightly reconciliation (Ch 9.9 row 4); import paths call `check_limit` before writing with a preview.
- [ ] 0B.05-T8 Enforcement in server `can()`/`check_limit`, never UI-only (Ch 9.9 row 3); 80 % warning, 100 % block with message and Upgrade button; OTP and urgent messages exempt.
- [ ] 0B.05-T9 Add `institutions.plan`, `expires_at` and billing fields from day one if 0A did not.
- [ ] 0B.05-T10 Downgrade fit check: list of what to reduce; **Proposed:** excess is made read-only/archived, never deleted (Ch 9.9 row 5).
- [ ] 0B.05-T11 Add-on catalog as data (SMS packs, AI usage, extra users/branches/storage, custom domain, branded app, extensions, setup/import service) — **Proposed** (Ch 9.4); purchase flows come with billing (0B.16) and later phases.
- [ ] 0B.05-T12 Seed one test institution per plan for CI (Ch 9.9 row 1).
- [ ] 0B.05-T13 Plan prices, limits and trial length are **Master Admin settings**, editable at any time without a release (D30, D31); prices can differ per institution type (D32).

**Tests**
- RPC-as-real-role: creating the (N+1)th user beyond the limit fails server-side even when the client skips the check.
- Unit: counters equal reconciliation result after concurrent inserts (race test).
- Role-matrix: only `settings.modules` can toggle; only Master Admin can change `allowed`.
- UI (Maestro + Playwright): disabled module disappears from menu/settings; 80 % banner and 100 % dialog shown in bn and en.
- Leak test: `institution_modules`, `institution_plan`, `usage_counters` isolated.

**Done when (acceptance criteria)**
- Master Admin can change any institution's plan, modules and limits without a release; every change is logged.
- Limits are enforced server-side with 80 %/100 % behaviour; OTP and urgent messages are never blocked.

**Watch-outs (do not miss)**
- Configuration explosion (plan × module × type × role) — seeded test institutions per plan and profile in CI (Ch 9.9 row 1).
- Read-only status must still allow export, OTP and urgent messages (Ch 9.9 row 6).
- Open questions to resolve before the end of phase 0: real prices, exact limits, trial length, which modules per plan, price by type (Ch 53.2 rows 2–4).

**Owner checkpoint:** approve plan list, module per plan, limits and trial length (or accept placeholders, all editable as data).

### 0B.06 Custom field builder

**Goal:** One field builder for leads, students and alumni with typed fields, presets from the type profile, plan limits, sensitive flags and indexed values.

**Depends on:** 0B.05; 0B.04.

**Plan chapters:** Ch 14 (14.2 custom-field row and note, 14.6, 14.12 rows 5 and 10, 14.13 phase 0), Ch 43 (custom field values table, as referenced by Ch 14), Ch 7 (7.5 presets).

**Decisions:** D8, D20.

**Build**
- **Data:** `custom_field_definitions(institution_id, entity [lead | client | network], key, label (bn/en), type, options, required, show_on_card, show_in_list, filterable, searchable, include_in_export, show_on_public_form, order, group, sensitive, created_from_preset)`; `custom_field_values(institution_id, entity, record_id, field_id, value_text, value_num, value_date, value_bool, value_json)`; GIN / expression indexes only for `filterable` fields; no per-institution columns on core tables.
- **Server:** `upsert_custom_field_values(entity, record_id, values)` with type validation (GPA 0–5, two decimals; phone normalised; email/URL format; file = document reference), limit check (`custom_fields` limit), sensitive-field masking hook for the field-level rules built in Block 1B; definitions CRUD RPCs.
- **App & web:** Settings → Custom fields: per entity list, drag-to-order, groups, add/edit dialog with all options, preview of how the field appears on card/form.
- **Settings & permissions:** `settings.custom_fields`; sensitive-field view permission declared in the registry (`custom_field.view_sensitive`, sensitive); labels for field types and options.

**Tasks**
- [ ] 0B.06-T1 Create definitions and values tables with RLS, leak-test entries and indexes.
- [ ] 0B.06-T2 Field types: text, long text, number, date, select, multi-select, phone, email, URL, yes/no, GPA (0–5, two decimals), file (paper).
- [ ] 0B.06-T3 Options: required, show on card, show in list/table, filterable, searchable, include in export, show on public form, order, group.
- [ ] 0B.06-T4 Presets from the type profile installed by `apply_profiles` (Ch 7.5 / 14.6 preset list) and marked as preset-sourced.
- [ ] 0B.06-T5 Plan limit on field count (`custom_fields`) with 80 %/100 % behaviour.
- [ ] 0B.06-T6 Sensitive flag stored in the permission registry: only permitted roles see it; flagged "never send to AI" (enforced by the AI layer in phase 4).
- [ ] 0B.06-T7 Builder UI in Settings with group sections and ordering; one builder for `lead`, `client`, `network`.
- [ ] 0B.06-T8 Values RPC with type validation and idempotency key (Ch 14.12 row 9 pattern).
- [ ] 0B.06-T9 Indexes created/dropped when `filterable` toggles; document the expression-index pattern for Block 1A filters.
- [ ] 0B.06-T10 Export of field definitions for copy-from-institution (used by 0B.10).

**Tests**
- Unit: GPA rejects 5.01 and 3.456; select rejects unknown option.
- RLS + leak: values and definitions isolated; sensitive field hidden from a role without the permission.
- Performance: ≈3,000-lead benchmark with 20 custom fields, filtering on two `filterable` fields stays within the Ch 47 list target.
- Screenshot (light/dark × bn/en): builder and field dialog.

**Done when (acceptance criteria)**
- An institution created from the school profile has its preset fields; Admin can add, reorder, group and retire fields within the plan limit.
- Values are stored in `custom_field_values`, not jsonb on the lead row.

**Watch-outs (do not miss)**
- Slow filter/search as fields grow (Ch 14.12 row 5): index only filterable fields, field limit, benchmark.
- Minors' data (birth registration, guardian NID) is sensitive (Ch 14.12 row 10).
- Use of fields in templates (Ch 24), filters (Ch 15), eligibility (Ch 29) and reports (Ch 38) is built in those milestones; this milestone provides the definitions and values API.

**Owner checkpoint:** create a custom field on the web, see it in preview, confirm preset fields per profile.

### 0B.07 Institution lifecycle, list and approval

**Goal:** Master Admin institution list, approval with duplicate checks, and the full lifecycle (pending → trial → active → read-only → active; suspended; closed) enforced on the server.

**Depends on:** 0B.05; 0B.02.

**Plan chapters:** Ch 5 (5.4, 5.17 rows 5, 10), Ch 6 (6.4, 6.7, 6.9 rows 1, 2, 8), Ch 4 (4.11 full export before close), Ch 5.15 (data protection: export on leave, delete after notice).

**Decisions:** D25.

**Build**
- **Data:** `institutions.status` enum (`pending_approval`, `trial`, `active`, `read_only`, `suspended`, `closed`), `status_history`, `college_code`, `eiin`, `closed_at`, `purge_after`; `institution_exports(institution_id, kind full, file, created_at, requested_by)`.
- **Server:** `set_institution_status()` (platform only, audited); read-only enforcement guard used by every write RPC and RLS write policy (export, OTP, urgent messages still allowed); suspended blocks login for that institution's memberships; duplicate detection RPC; full institution export Edge Function (all tenant tables incl. custom records/extensions when they exist, to a private storage path under the institution); purge job after notice period.
- **App & web:** Master Admin → Institutions list (search; status, plan, type, users and leads count, last login, last problem; problem institutions first); Overview tab (info, type, status, usage, checklist progress placeholder, "Enter institution" entry point for 0B.08); approval queue on Dashboard; status-change dialogs with reason; institution-side banners for trial / read-only / suspended.
- **Settings & permissions:** `platform.institutions.approve`, `platform.institutions.status`, `platform.institutions.close` (sensitive, two-step).

**Tasks**
- [ ] 0B.07-T1 Add status columns, history and transitions table; valid transitions only (pending → trial on approval; trial/active → read_only after grace; read_only → active on payment; any → suspended; any → closed).
- [ ] 0B.07-T2 Server-side read-only guard on all writes; export, OTP and urgent messages exempt; data never deleted for non-payment.
- [ ] 0B.07-T3 Suspended: login to that institution refused with a clear message; other memberships of the same person unaffected (D25).
- [ ] 0B.07-T4 Status change notifies the institution's Super Admin(s) by in-app banner now and by email once 0B.14 lands and affects no other institution.
- [ ] 0B.07-T5 Duplicate checks before approval: same EIIN / College Code warns Master Admin; **Proposed:** name + phone + address similarity warning for institutions without codes (Ch 6.9 row 2).
- [ ] 0B.07-T6 **Proposed:** trial-abuse limit — cap on trial institutions opened by the same user or phone, flagged in the approval queue (Ch 6.9 row 8).
- [ ] 0B.07-T7 Full institution export (all data, files manifest) downloadable by Master Admin and the Super Admin; required before close.
- [ ] 0B.07-T8 Close flow: requires a completed full export, sets `closed`, schedules purge after the notice period, and emits `institution.closed` for the hub (0B.11 revokes connections, API keys, webhooks and secrets).
- [ ] 0B.07-T9 Institutions list and Overview tab; problem institutions sorted first.
- [ ] 0B.07-T10 Approval queue on the panel Dashboard (pending institutions).
- [ ] 0B.07-T11 Owner/legal task: verify current Bangladesh data-protection rules (minors' data, retention) before launch (Ch 5.15, Ch 53.4 row 1); write terms and privacy policy naming every external provider.

**Tests**
- RPC-as-real-role: in `read_only`, lead insert / setting change fail; export and OTP succeed.
- RLS + leak: full export contains only the institution's rows (assert across all tenant tables, two-membership user included).
- Unit: invalid transitions rejected; status history written.
- UI (Playwright): approve, suspend, reactivate, close from the panel.

**Done when (acceptance criteria)**
- Every lifecycle state behaves as Ch 5.4 describes and is enforced on the server.
- Closing an institution is impossible without a full export; after the notice period its data is purged and nothing else is affected.

**Watch-outs (do not miss)**
- Read-only during admission season is very damaging (Ch 9.9 row 6): Master Admin can extend expiry; export/OTP/urgent keep working.
- Closed institutions' connections, keys and webhooks must not keep running (Ch 5.17 row 10, I14).

**Owner checkpoint:** demo the lifecycle on a test institution and approve the notice period length before purge.

### 0B.08 Support entry ("Enter institution")

**Goal:** Let Support and Master Admin enter an institution with a reason, a time limit and read-only by default, fully audited and visible to the institution.

**Depends on:** 0B.07; 0B.02.

**Plan chapters:** Ch 5 (5.5, 5.3 Audit tab, 5.17 row 3), Ch 11 (11.15).

**Decisions:** —.

**Build**
- **Data:** `support_sessions(id, platform_user_id, institution_id, reason, mode read_only | edit, edit_reason, started_at, expires_at, ended_at)`; every action logged to `platform_audit_log` with `support_session_id`.
- **Server:** `start_support_session(institution_id, reason, minutes)` issuing a scoped session whose JWT carries the institution and read-only flag; `request_edit(reason)` (separate approval by a Master Admin, **Proposed**); automatic expiry; all tenant write RPCs refuse when read-only.
- **App & web:** "Enter institution" button on Overview with reason and duration; persistent banner "Support view — read-only — ends in mm:ss" with Exit; institution Settings → Security → Support access log (who, when, why, what) for Super Admin; panel Audit tab per institution.
- **Settings & permissions:** `platform.support.enter`, `platform.support.edit` (sensitive); institution-side `settings.security` to view the log.

**Tasks**
- [ ] 0B.08-T1 Create `support_sessions` and link audit rows.
- [ ] 0B.08-T2 Session issuing with reason required, time limit and auto-exit.
- [ ] 0B.08-T3 Read-only by default; edit mode requested separately with reason and audited.
- [ ] 0B.08-T4 Audit of every read of sensitive data and every write during support sessions.
- [ ] 0B.08-T5 Institution-facing support access log for Super Admin.
- [ ] 0B.08-T6 Panel Audit tab: all platform changes and support entries for the institution.
- [ ] 0B.08-T7 Leak test case: a support session for A cannot read B.

**Tests**
- RPC-as-real-role: writes fail in read-only support session; succeed only in approved edit mode.
- Unit: expired session token rejected.
- RLS + leak: support session scoped strictly to one institution.
- UI (Playwright): enter, banner countdown, auto-exit, Super Admin sees the entry.

**Done when (acceptance criteria)**
- No support entry without reason and time limit; default read-only; every action audited; the institution's Super Admin can see it.

**Watch-outs (do not miss)**
- Support entry can destroy trust (M4, Ch 5.17 row 3): visibility to the institution is mandatory, not optional.

**Owner checkpoint:** enter a test institution as Support and review the log shown to its Super Admin.

### 0B.09 Institution setup wizard and self sign-up

**Goal:** A short wizard (self sign-up by default, or run by Master Admin) that creates an institution with its type profiles applied and its first Super Admin, then waits for approval.

**Depends on:** 0B.07; 0B.04.

**Plan chapters:** Ch 6 (6.1–6.4, 6.8, 6.9 rows 1, 3, 6), Ch 1 (1.4), Ch 49 (49.4), Ch 10 (10.6 first Super Admin).

**Decisions:** D8, D19, D20, D25.

**Build**
- **Data:** `institution_signups(id, payload, status, ip, captcha_score, created_at)`; on confirm creates `institutions` (status `pending_approval`, `industry = education`), first `institution_members` row as Super Admin.
- **Server:** public `start_institution_signup` Edge Function with CAPTCHA and rate limit; `confirm_institution_signup` (creates institution, applies profiles via 0B.04, creates Super Admin, writes `domain_events`); `platform_create_institution` (same wizard, then invite Super Admin); SMS and bulk features disabled while `pending_approval`.
- **App & web:** public "Set up your institution" page (web + app entry); steps: (1) industry — hidden while only one industry is open; (2) types — one or more of the nine; (3) institution info — name, address, College Code and EIIN (both optional), short name / logo / colours here or later; (4) Super Admin — name, email, phone, password (Google / OTP options are added by 0B.17 / 0B.18; an existing member of another institution joins with the same login, D25); (5) preview of labels, stages, modules, custom fields, templates, document list, reports, role templates with the option to exclude parts; (6) confirm. After confirm: "Waiting for approval" with the option to continue setup.
- **Settings & permissions:** `platform.institutions.create`; labels for all wizard copy (bn/en).

**Tasks**
- [ ] 0B.09-T1 Public sign-up page with CAPTCHA and IP / email / phone rate limits (**Proposed**, Ch 6.9 row 1).
- [ ] 0B.09-T2 Wizard step 1 hidden while only one industry is `signup_open`; wizard starts at step 2 (D20).
- [ ] 0B.09-T3 Step 2 multi-select of types; mixed institutions allowed.
- [ ] 0B.09-T4 Step 3 info with optional College Code / EIIN and optional branding.
- [ ] 0B.09-T5 Step 4 Super Admin with password; if the email/phone already belongs to a verified user, attach a new membership instead of a new account (D25).
- [ ] 0B.09-T6 Step 5 preview with excludable parts (driven by `preview_profile_change`).
- [ ] 0B.09-T7 Confirm: create institution in `pending_approval`, apply profiles, create Super Admin membership; Super Admin can sign in and continue setup.
- [ ] 0B.09-T8 Gate: SMS and bulk features off before approval — expose `institution_can_message()` (false while `pending_approval`) that the hub outbox gate (0B.12) must call; after approval status `trial` with trial limits.
- [ ] 0B.09-T9 Master Admin "Create institution" runs the same wizard and sends a Super Admin invite (**Proposed**, Ch 6.2).
- [ ] 0B.09-T10 Wizard keeps only essentials; everything else goes to the checklist (Ch 6.9 row 3).

**Tests**
- UI (Playwright web + Maestro app): full self sign-up in bn and en, light and dark; Master Admin-created flow with invite.
- Unit: rate limit and CAPTCHA reject floods; duplicate EIIN flagged to Master Admin.
- RLS + leak: a pending institution's Super Admin sees only their institution.
- Screenshot (light/dark × bn/en): every wizard step.

**Done when (acceptance criteria)**
- A new education institution can sign up in under 5 minutes of form-filling, lands in `pending_approval` with profile defaults seeded, and appears in the Master Admin approval queue.
- No SMS or bulk sending is possible before approval.

**Watch-outs (do not miss)**
- Fake/duplicate institutions and SMS abuse (M2, Ch 6.9 row 1).
- No institution list is ever shown publicly (customer list leak, Ch 10.10 row 5).
- **Proposed** items (self sign-up + approval, Master Admin creation, CAPTCHA) need owner approval.

**Owner checkpoint:** sign up a test college end-to-end and approve it from the panel.

### 0B.10 Setup checklist, branding and copy-from-institution

**Goal:** A progress checklist that shows each institution (and Master Admin) what remains, shared-app branding after login, and helpers that cut onboarding work.

**Depends on:** 0B.09; 0B.06.

**Plan chapters:** Ch 6 (6.5, 6.9 rows 4, 7), Ch 5 (5.3 Overview checklist, 5.16 shared-app branding, 5.8 last bullet), Ch 1 (1.3 D12), Ch 10 (10.2 branding), Appendix A (branding row).

**Decisions:** D12, D16, D17.

**Build**
- **Data:** `setup_checklist_items(key, label_key, owner [super_admin | master_admin | both], chapter, completion_rule, video_url, order)` (**Proposed** list) and `institution_checklist(institution_id, item_key, status, completed_at, completed_by)`; branding fields (`name`, `short_name`, `logo_path`, `colors`) in an institution branding record; logos in a per-institution storage path.
- **Server:** completion rules evaluated by triggers/events (e.g. SMS connection healthy → SMS item done); `copy_setup_from_institution(source_id, areas[])` (platform or same-group only; copies configuration, never records); trial-end checker job notifying Support if setup is incomplete (**Proposed**).
- **App & web:** Settings → Setup checklist with progress %, "who does it" chips and short video links; same panel on Master Admin Overview and a "what is left" column in the institutions list; Settings → Branding (short name, logo, colours) applied post-login in app header, web shell, tab title and later receipts/forms; login screen keeps the neutral product brand (**Proposed**: institution brand on its own domain or branded app).
- **Settings & permissions:** `settings.branding`; checklist visible to `settings.*` holders; labels.

**Tasks**
- [ ] 0B.10-T1 Seed checklist items: branding; branches (if any); courses/classes, batches/sessions, sections; fee structure; pipeline stages and label review; invite staff and assign roles; SMS and email setup (Master Admin, D4); online payment — institution opens its own SSLCommerz merchant account (trade licence, bank account, verification) then Master Admin enters merchant details (D17); message templates (institution writes, D6); public application form; own domain (optional, D16); AI key and Google Drive (institution brings its own); old lead import. Items whose feature arrives later show "available in phase N".
- [ ] 0B.10-T2 Completion rules wired to events; manual "mark done" for items without a rule.
- [ ] 0B.10-T3 Progress % on Settings and a Home card placeholder (Home itself is built in Block 1B).
- [ ] 0B.10-T4 Master Admin view of checklist progress per institution and in the list.
- [ ] 0B.10-T5 Short video guide link per item (content task).
- [ ] 0B.10-T6 Branding settings and storage; brand shown after login in the shared app (D12); colours validated for contrast in light and dark.
- [ ] 0B.10-T7 "Copy from another institution" framework for configuration areas available now (custom fields, labels, settings); later milestones register SMS/email setup (0B.15), courses (Block 2) etc.
- [ ] 0B.10-T8 **Proposed:** notify Support when trial ends with setup incomplete.
- [ ] 0B.10-T9 Show the merchant-account step early with the note that manual payment works meanwhile (Ch 6.9 row 4).

**Tests**
- Unit: completion rules flip items on the right events.
- RLS + leak: checklist and branding isolated; copy-from refuses a source the caller may not use.
- Screenshot (light/dark × bn/en): checklist and branded header with a long Bangla name.

**Done when (acceptance criteria)**
- A newly approved institution sees its checklist with correct owners and progress; Master Admin sees the same status.
- Branding appears after login; login screen stays neutral.

**Watch-outs (do not miss)**
- Manual onboarding eats Support time (M1, Ch 6.9 row 7): import, copy, video guides, visible remaining tasks.
- Excel import of courses/staff/leads is Block 1A (Ch 23); paid setup/import service is an add-on (Ch 9.4).

**Owner checkpoint:** approve the checklist item list and see a branded institution after login.

### 0B.11 Integration hub core: provider catalog, connections and secrets

**Goal:** The shared hub data model: provider catalog, per-institution connections with sandbox/live modes and backups, Vault-held secrets that are write-only, rotation and audit.

**Depends on:** 0B.07; 0B.02.

**Plan chapters:** Ch 42 (42.1, 42.2 catalog/connections/secrets/audit rows, 42.8, 42.9 I1–I3, I9–I11, I14, 42.10 rows 1, 9), Ch 5 (5.6 secrets/audit, 5.3 Providers and Integrations tabs), Ch 9 (9.7 who pays).

**Decisions:** D3, D4, D15, D22.

**Build**
- **Data:** `integration_providers(key, kind [sms | email | payment | ai | storage | push | pdf_image | domain | app …], settings_schema, docs_url, capabilities, adapter_version, status)`; `integration_connections(id, institution_id nullable for platform, kind, provider, mode sandbox | live, status, settings, priority, payer direct | platform, live_test_passed_at, last_success_at, last_error, created_by)`; secret references only (`vault_secret_id`, `hint`, `effective_from`, `rotated_at`); `integration_audit`.
- **Server:** connection resolver `resolve_connection(institution_id_from_record, kind)` (never from client input, I1); Vault write-only RPC (Master Admin only), secrets readable only inside Edge Functions; rotation with effective-from date so the old key works until the new one tests OK; on `institution.closed`: disable connections, revoke API keys and webhooks, delete secrets (I14).
- **App & web:** Master Admin → Providers (catalog, platform default SMS gateway and mail); per-institution Integrations tab listing all connections with mode badge, status, hint `key…ab12`, last success/error; provider-specific settings form generated from `settings_schema`.
- **Settings & permissions:** `platform.integrations.manage` (sensitive); institution `integration.view_status` (status only, never keys).

**Tasks**
- [ ] 0B.11-T1 Create catalog, connections, audit tables; RLS so tenants see only status fields of their own connections.
- [ ] 0B.11-T2 Vault integration: write-only secret RPC, hint generation, never logged, never returned.
- [ ] 0B.11-T3 Key rotation with effective-from; **Proposed:** show key age and a yearly rotation reminder (Ch 42.10 row 9).
- [ ] 0B.11-T4 Connection resolver from record `institution_id`; primary + backup by priority.
- [ ] 0B.11-T5 Mode handling: sandbox/live shown everywhere; live bulk SMS (and later live payments) blocked until one live test succeeds; sandbox data marked (I3).
- [ ] 0B.11-T6 Payer per institution and per service: direct vs platform (D15).
- [ ] 0B.11-T7 Close hook: disable connections, revoke keys/webhooks, delete secrets.
- [ ] 0B.11-T8 Providers screen and per-institution Integrations tab (status only for other kinds that arrive later: AI, Drive, push, PDF/image).
- [ ] 0B.11-T9 Error messages state whose responsibility a failure is (adapter bug = platform; account/balance/merchant = institution) (I10).
- [ ] 0B.11-T10 Secret scanning in CI covers provider credential formats (Ch 51 lesson 12).

**Tests**
- RLS + leak: institution B cannot read A's connection settings; no tenant can read any secret or hint of another tenant.
- RPC-as-real-role: Super Admin cannot write or read secrets; Master Admin can write but never read back.
- Unit: rotation — old key used before `effective_from`, new after; close hook deletes secrets.
- Log scan test: a forced error path never prints the secret.

**Done when (acceptance criteria)**
- Master Admin can create, test-mark, rotate and disable connections per institution; secrets are only ever shown as hints.
- Closing an institution leaves no active connection or secret.

**Watch-outs (do not miss)**
- All keys in Master Admin hands (Ch 42.10 row 1): two-step login, write-only keys, full audit.
- Wrong institution's account (I1) is the top integration risk.
- Never commit secrets (Ch 51 lesson 12).

**Owner checkpoint:** see the Integrations tab with masked keys and the audit trail of a rotation.

### 0B.12 Hub runtime: outbox, worker, webhook router, health and usage ledger

**Goal:** The reliable runtime every external call uses: outbox queue with retries and priorities, fair per-institution and per-provider limits, webhook router with per-connection signatures, circuit breaker, health checks and the usage/cost ledger.

**Depends on:** 0B.11; 0B.05.

**Plan chapters:** Ch 42 (42.2 adapter/outbox/webhook/circuit breaker/status/ledger rows, 42.9 I4–I8, I12), Ch 25 (25.5 outbox and OTP priority queue, delivery log, ledger), Ch 9 (9.5 monthly limits, 9.7 ledger), Ch 51 (lesson 2 queue bugs).

**Decisions:** D7, D15.

**Build**
- **Data:** `outbox(id, institution_id, kind, channel, priority [otp | urgent | transactional | bulk], payload, idempotency_key unique, attempts, next_attempt_at, status [queued | sending | sent | failed | given_up | unknown], connection_id, provider_message_id, parts, cost, error)`; `delivery_log` (recipient, time, channel, template, result, provider message id, cost); `usage_ledger(institution_id, day, provider, channel, category [otp | notification | template | bulk], count, parts, failed_parts, cost, payer)`; `webhook_events(connection_id, signature_ok, payload, processed_at)`.
- **Server:** adapter interface (versioned) per kind (SMS: `send`, `balance`, `parse_status`; email: `send`, `parse_event`; payment interface declared for Block 2); outbox worker Edge Function woken by pg_cron only when work exists (pre-checked kick), running per institution in its time zone; back-off, `given_up`; separate high-priority OTP lane; per-institution and per-provider rate limits / fair share; monthly SMS/email limit gate (bulk stops, OTP and urgent pass); approval gate (no SMS/bulk before approval); webhook router `/hooks/<provider>/<connection_id>` verifying that connection's secret before trusting anything, idempotent; circuit breaker switching to backup with Master Admin alert; scheduled health checks and "Test" action; mock adapter (engineering, for tests only — the full sandbox/fake adapter set for CI is Block 1B).
- **App & web:** delivery log viewer (Master Admin; filtered by institution, channel, status); ledger daily view.
- **Settings & permissions:** `platform.integrations.manage`; institution `integration.view_status`.

**Tasks**
- [ ] 0B.12-T1 Create `outbox`, `delivery_log`, `usage_ledger`, `webhook_events` with RLS and leak-test entries.
- [ ] 0B.12-T2 Define the versioned adapter interfaces and an adapter registry.
- [ ] 0B.12-T3 Outbox worker: attempts, exponential back-off, `given_up`, idempotency key, no immediate retry, no re-claiming of stuck items forever, no wake-up without work (Ch 51 lesson 2, Ch 25.8 row 1).
- [ ] 0B.12-T4 Priority lanes: OTP lane never waits behind bulk; per-institution fair share and per-provider rate limits (I6).
- [ ] 0B.12-T5 Gates: institution status (no SMS/bulk before approval; closed = nothing), monthly limit (bulk blocked at limit; OTP/urgent never), plan module checks.
- [ ] 0B.12-T6 Send times and quiet hours computed in the institution's time zone (I12); quiet-hour rules themselves are applied by `notify()` in Block 1B.
- [ ] 0B.12-T7 Webhook router with per-connection signature verification, replay/duplicate protection, "pending" + reconciliation hooks (I4).
- [ ] 0B.12-T8 Circuit breaker + backup connection; alert Master Admin; no silent fallback — every fallback is noted on the message and in the panel (Ch 51 lesson 5).
- [ ] 0B.12-T9 Health checks on schedule and "Test" button results stored as last success / last error.
- [ ] 0B.12-T10 Usage ledger per institution, day, provider, channel and category with payer (direct/platform) so only platform-paid usage is billable (D15); cost = provider per-part price from the connection.
- [ ] 0B.12-T11 Delivery-log and ledger viewers in the panel.
- [ ] 0B.12-T12 Mock SMS/email adapters for unit and integration tests.

**Tests**
- Unit: given_up after N attempts; idempotent re-send returns the first result; stuck item not re-billed.
- Integration (I1): two institutions send at once; each message uses its own connection (assert on mock adapter).
- Load: one institution queues 20,000 bulk SMS while another requests OTP; OTP is sent within the target time.
- RLS + leak: outbox, delivery log, ledger isolated per institution.
- Webhook: bad signature rejected; duplicate callback processed once.

**Done when (acceptance criteria)**
- Every outbound SMS/email in the product goes through the outbox with a delivery-log row and a ledger entry.
- Bulk from one institution cannot delay another's OTP; monthly limit stops bulk only.

**Watch-outs (do not miss)**
- Queue bugs from the old app: wrong daily limit counting, endless re-claim (billed every 10 min), instant retry, idle wake-ups (Ch 51 lesson 2).
- Callbacks late, twice or forged (I4).
- No silent fallback (Ch 25.8 row 7).

**Owner checkpoint:** see the delivery log and ledger fill during a demo send from two test institutions.

### 0B.13 SMS adapters, Custom HTTP, platform gateway and OTP route

**Goal:** Per-institution SMS with the first 3–4 Bangladeshi gateway adapters, a safe Custom HTTP adapter, the platform default gateway, sender-ID handling and separate OTP/transactional routes.

**Depends on:** 0B.12.

**Plan chapters:** Ch 42 (42.4, 42.9 I5, 42.10 rows 3–5, 8), Ch 5 (5.6 SMS operations), Ch 9 (9.7 part counting), Ch 10 (10.5 sending row).

**Decisions:** D3, D4, D7, D15, D22.

**Build**
- **Data:** SMS connection settings schema: provider preset or Custom HTTP (URL, method, parameter map with `{to}`, `{message}`, `{sender_id}`, success rule), sender ID, masking type and approval status, route (otp/transactional vs promotional), per-part cost, low-balance threshold.
- **Server:** adapters (send one and many, Unicode, masked/non-masked, balance, delivery report by push or poll, error mapping, sandbox/test numbers); part counter (Bangla Unicode 70 per part, English 160); delivery status "unknown" after a timeout; low-balance job alerting institution and Master Admin; platform default gateway connection (used when institution has none, or as backup, D15 payer rules); daily sandbox contract test per adapter (I5).
- **App & web:** SMS setup form in Master Admin → Messaging (preset picker or Custom HTTP), "Test SMS", "Check balance", part and cost preview.
- **Settings & permissions:** `platform.integrations.manage`.

**Tasks**
- [ ] 0B.13-T1 Owner/research task first: ask the first institutions which gateways they use; verify API, price and masking rules for the shortlist (SSL Wireless, BulkSMSBD, Alpha SMS, MiMSMS, Infobip, operator corporate SMS; Twilio as international) before building (**Proposed**, Ch 42.4; open question Ch 53.2 row 5).
- [ ] 0B.13-T2 Build the 3–4 most-used adapters with the full capability list (send one/many, Unicode, masking, balance, delivery reports, error mapping, sandbox).
- [ ] 0B.13-T3 Custom HTTP adapter with **Proposed** safety limits: HTTPS and public hosts only, internal IPs blocked (SSRF), timeout, Master Admin only, validated by the Test button before saving.
- [ ] 0B.13-T4 Platform default gateway as a platform-owned connection; fallback per institution setting (platform gateway or nothing).
- [ ] 0B.13-T5 Part counting and cost preview (70/160); per-part cost recorded per connection for billing (D7).
- [ ] 0B.13-T6 Routes: OTP and transactional on the fast non-masked route; promotional separate; OTP priority lane from 0B.12.
- [ ] 0B.13-T7 Sender ID / masking approval status stored on the connection and shown; collect each gateway's sender-ID rules up front.
- [ ] 0B.13-T8 Delivery reports: push callbacks via the router, poll fallback, "unknown" after timeout.
- [ ] 0B.13-T9 Low-balance alerts to institution and Master Admin; status text "Balance exhausted — recharge with the provider" for direct-pay institutions (Ch 42.10 row 8).
- [ ] 0B.13-T10 Daily sandbox contract test per adapter; failure alerts the platform.
- [ ] 0B.13-T11 Legal check before bulk SMS goes live: promotional SMS rules (sender ID, time, content) (Ch 53.4 row 2) — recorded as a launch gate for Campaigns (Block 1B).
- [ ] 0B.13-T12 **Switch gateway at any time (D33, D34):** for an institution and for the platform default, add the new connection, verify it with Test SMS / sandbox, then make it "primary" in one action; the old one becomes backup or is disabled; queued messages go through the new primary; delivery logs and the ledger keep the gateway that actually sent each message; every switch is audited.
- [ ] 0B.13-T13 **Masking (D35):** masked sender ID per institution and gateway with approval status (applied / approved / rejected); until approved, send on the non-masked route; OTP may use a separate non-masked fast route.

**Tests**
- Unit: part counting for pure Bangla, pure English, mixed text; Custom HTTP rejects `http://`, `10.x`, `169.254.x` targets.
- Contract tests (sandbox) for each adapter.
- Integration: two institutions, two gateways — each sends via its own (I1).
- RLS + leak: SMS connection settings never visible to tenants.

**Done when (acceptance criteria)**
- Master Admin can set up SMS for an institution with a preset or Custom HTTP, send a test SMS, see balance and parts/cost, and see delivery results.
- OTP and transactional messages use the fast route and never queue behind bulk.

**Watch-outs (do not miss)**
- Gateway APIs change without notice, weak docs, unreliable delivery reports (Ch 42.10 row 4).
- Masked sender ID usually needs per-institution approval (Ch 5.6).
- Bangla SMS costs more parts — always show parts before sending.

**Owner checkpoint:** confirm the gateway shortlist and watch a test SMS (Bangla and English) go out through a real sandbox.

### 0B.14 Transactional email adapters and domain verification

**Goal:** Per-institution transactional email via SMTP or an API provider, with sender identity, SPF/DKIM/DMARC verification, a test button and a low-limit platform default mail.

**Depends on:** 0B.12.

**Plan chapters:** Ch 42 (42.5, 42.10 row 6), Ch 5 (5.6 email operations), Ch 25 (25.4 email channel).

**Decisions:** D1, D3, D4.

**Build**
- **Data:** email connection settings: type SMTP or API provider (Resend, Brevo, SendGrid, Mailgun, Amazon SES), sender name, sender address, reply-to, domain verification records and status; per-institution bounce/complaint counters.
- **Server:** SMTP adapter and API-provider adapters (start with SMTP plus the API provider(s) the owner picks; others follow the same interface); DNS checker for SPF / DKIM / DMARC; bounce/complaint webhook handling through the router; auto-pause of a bad sender; platform default mail with a low per-institution limit, sending from the institution's verified domain or a per-institution platform sub-domain.
- **App & web:** email setup form with step-by-step DNS instructions and "Verify", "Test email".
- **Settings & permissions:** `platform.integrations.manage`.

**Tasks**
- [ ] 0B.14-T1 SMTP adapter (Gmail app password, cPanel mail).
- [ ] 0B.14-T2 First API-provider adapter(s) from the Ch 42.5 list, chosen at the owner checkpoint.
- [ ] 0B.14-T3 Sender name/address/reply-to (institution's address so replies reach the right people).
- [ ] 0B.14-T4 Domain check with SPF/DKIM/DMARC instructions and Verify button.
- [ ] 0B.14-T5 Test email button.
- [ ] 0B.14-T6 Platform default mail with low limit; per-institution sub-domain option.
- [ ] 0B.14-T7 Bounce/complaint tracking per institution; pause bad senders and alert Master Admin.
- [ ] 0B.14-T8 Email templates for platform mails (status changes, invites, OTP) in bn and en via the label system.

**Tests**
- Unit: DNS checker parses correct/incorrect SPF and DKIM records.
- Integration: bounce webhook increments the right institution's counter only.
- RLS + leak: email connections and counters isolated.

**Done when (acceptance criteria)**
- Master Admin can configure, verify and test email for an institution; platform default mail works for institutions without their own setup.

**Watch-outs (do not miss)**
- Shared reputation: one institution's spam harms all (Ch 42.5, 42.10 row 6) — own verified domain or separate sub-domain, per-institution bounce watch.

**Owner checkpoint:** pick the first API email provider and see a verified test email from a test institution.

### 0B.15 Master Admin messaging screens and staff notification recipient matrix

**Goal:** The Master Admin Messaging and Notifications tabs: all-institution summary, monthly limits, fallback, copy setup, delivery log and errors, the institution's status-only view, and the staff notification kind × channel matrix (D5).

**Depends on:** 0B.13; 0B.14; 0B.10.

**Plan chapters:** Ch 42 (42.3), Ch 5 (5.6), Ch 25 (25.3 kinds registry, 25.4 channels and defaults; phase 0 part only), Ch 24 (24.5 staff row and matrix), Ch 9 (9.8 institution view).

**Decisions:** D1, D3, D4, D5, D15, D22.

**Build**
- **Data:** `notification_kinds(key, group, urgent, module_key, label_key)` seeded with Ch 25.3 kinds (`assigned`, `auto_assigned`, `follow_up`, `visit`, `speed_to_lead`, `outcome`, `missed_call`, `sync_nudge`, `signup`, `discount`, `payment`, `leaderboard`, `scorecard`, `alumni`, `feedback`, admission-flow steps, AI, board-flow "ready", `app_update`); `notification_matrix(institution_id, kind, recipient, channel [inbox | push | email | sms | whatsapp_link], enabled)` with phase-0 rows for recipient = staff; `messaging_limits(institution_id, monthly_sms, monthly_email, fallback platform | none)`.
- **Server:** matrix defaults from the type profile; monthly cost estimate (SMS parts per month) from historical volumes or plan assumptions; `copy_messaging_setup(source, target)` copies provider and settings but never secrets unless re-entered or explicitly copied by Master Admin.
- **App & web:** Master Admin → Messaging overview (one row per institution: SMS status, email status — on / not set / problem — low balance, sent this month, last problem; problems first); per-institution Messaging tab (SMS and email setup from 0B.13/0B.14, monthly limits, fallback, copy setup, delivery log, last error per channel, payer choice); Notifications tab (matrix grid with cost estimate and a "how many people, how many parts" preview before saving); institution Settings → Messaging status (e.g. "SMS: on ✓", this month's usage; gateway price hidden unless Master Admin shows it).
- **Settings & permissions:** `platform.integrations.manage`, `platform.notifications.manage`; institution `integration.view_status`; labels for every kind (in the institution's labels and the user's language).

**Tasks**
- [ ] 0B.15-T1 Seed `notification_kinds`; modules declare their kinds through the registry (Ch 25.3, Ch 43).
- [ ] 0B.15-T2 All-institution messaging summary, problems first.
- [ ] 0B.15-T3 Per-institution Messaging tab with monthly SMS/email limits (with plan limits), fallback, payer, last error per channel, delivery log.
- [ ] 0B.15-T4 "Copy setup from another institution" for the same provider.
- [ ] 0B.15-T5 Staff recipient matrix (kind × channel) per institution, defaults from profile; example defaults: assigned = inbox + push; speed_to_lead escalation = push then SMS; payment due/late = email + SMS; weekly scorecard = email.
- [ ] 0B.15-T6 Cost estimate in the matrix and a preview before saving; settings versioning with rollback (Ch 24 critique row 4).
- [ ] 0B.15-T7 Register the `notifications` setting ("who" selection, outside access rules) schema; the institution-side Settings → TEAM → Notifications screen and actual delivery (`notify()`) come in Block 1B.
- [ ] 0B.15-T8 Institution status-only view: no keys, no provider settings, no gateway buy price.
- [ ] 0B.15-T9 Alerts to Master Admin for low balance, repeated errors, bounces, sudden cost spikes.

**Tests**
- Role-matrix: Super Admin sees status and usage only; Master Admin sees and edits all.
- Unit: matrix defaults applied from school vs coaching profiles differ as defined.
- RLS + leak: matrix and limits isolated.
- Screenshot (light/dark × bn/en): Messaging overview, matrix grid, institution status card.

**Done when (acceptance criteria)**
- Master Admin can fully set up and monitor messaging for any institution from one place and decide channels per staff notification kind (D5).
- The institution sees only status and usage.

**Watch-outs (do not miss)**
- Master Admin as bottleneck (Ch 5.17 row 1): wizard-like forms, copy setup, checklist status, optional Support rights (**Proposed**).
- Wrong matrix inflates SMS bills (Ch 24 critique row 4, Ch 25.8 row 6): estimate and preview.
- Recipient rows for leads, students, guardians, referrers and consent/opt-out are Block 1B (Ch 24, phase 1).

**Owner checkpoint:** review the default staff matrix and the Messaging overview with two test institutions.

### 0B.16 Subscription billing core

**Goal:** Platform subscription billing: billing periods, special prices, upgrades/downgrades, expiry reminders, grace period then read-only, manual payments and the platform's own SSLCommerz account, invoices and receipts, and platform-paid usage on the same invoice.

**Depends on:** 0B.05; 0B.07; 0B.12; 0B.14.

**Plan chapters:** Ch 9 (9.6, 9.7 ledger use, 9.8, 9.9 rows 6–10, 9.10 phase 0), Ch 5 (5.7), Ch 42 (42.6 last bullet: platform merchant).

**Decisions:** D7, D14, D15, D17, D22, D29, D30, D31, D32.

**Build**
- **Data:** `promo_codes`, `offers`, `plan_price_versions` (D29) in addition to: `subscriptions(institution_id, plan_id, plan_version, period monthly | yearly, price, discount, starts_at, expires_at, grace_days)`; `billing_overrides` (special price/discount/limits, logged); `platform_invoices(number sequential platform-wide, institution_id, lines, vat, total, status)`; `platform_payments(method manual | sslcommerz, trx_id, verified_by, gateway_ref, status)`; `platform_receipts`.
- **Server:** prorated upgrade (immediate), downgrade at period end with fit check (0B.05); reminder job 15/7/3/1 days before expiry; expiry job → grace (e.g. 7 days) → `read_only` (0B.07), payment → `active`; manual payment entry and verification by Billing role; SSLCommerz adapter for the platform's own merchant account (create, server-to-server verify, IPN via router, idempotent, pending + reconciliation); invoice generation including platform-paid SMS/AI usage lines from the ledger (D15); VAT line when applicable.
- **App & web:** Master Admin → Plan & billing tab (plan, expiry, dues, overrides, extend expiry, record/verify manual payment, invoices); Billing role screens; institution Settings → Billing (plan, expiry, limit usage with 80 % warnings, this month's SMS/AI use, invoices/receipts download, pay online or submit manual payment).
- **Settings & permissions:** `billing.view`, `billing.pay` (sensitive, two-step); `platform.billing.*`.

**Tasks**
- [ ] 0B.16-T1 Create subscription, override, invoice, payment, receipt tables; platform-wide sequential invoice numbers.
- [ ] 0B.16-T2 **Proposed** billing rules: monthly/yearly (yearly discount), prices in ৳, VAT shown when applicable.
- [ ] 0B.16-T3 Special price / discount / extra limits per institution, every change logged.
- [ ] 0B.16-T4 Upgrade immediate with proration; downgrade at period end after fit check.
- [ ] 0B.16-T5 Reminder job 15, 7, 3, 1 days before expiry (email via 0B.14 + in-app banner).
- [ ] 0B.16-T6 Grace period then read-only; Master Admin can extend expiry; data never deleted for non-payment.
- [ ] 0B.16-T7 Manual subscription payments (bank / bKash / Nagad with transaction ID and verification, D14 pattern).
- [ ] 0B.16-T8 Platform SSLCommerz merchant integration (sandbox then live), server-side verification, idempotent IPN — completely separate from institutions' own merchant accounts (D17, Ch 9.9 row 10).
- [ ] 0B.16-T9 Invoices and receipts (PDF) downloadable from Settings → Billing; platform-paid usage on the same invoice.
- [ ] 0B.16-T10 **Proposed:** prepaid SMS balance (SMS packs) per institution as the preferred model.
- [ ] 0B.16-T11 Institution billing view per Ch 9.8 (no gateway buy price unless Master Admin enables it); other staff see only the limit message.
- [ ] 0B.16-T12 Owner/legal tasks: VAT and invoice rules in Bangladesh (Ch 53.4 row 6). Prices, limits and trial are entered by the Master Admin in settings (D30, D31).
- [ ] 0B.16-T13 **Price versions (D29):** changing a plan price creates a new version; new customers get it, running subscriptions keep their price until renewal unless the Master Admin applies it earlier; notice to the institution before a price rise (Ch 9.10).
- [ ] 0B.16-T14 **Promo codes / coupons (D29):** percent or fixed amount; valid from–to; max total uses and max per institution; plans / periods / add-ons it applies to; first purchase only (option); institution types (option); Master Admin can stop a code at once.
- [ ] 0B.16-T15 **Time-limited offers (D29):** automatic discount for everyone (or chosen institution types) between two dates, shown on the Billing page and as a banner; add-on discounts (e.g. SMS packs).
- [ ] 0B.16-T16 **Price calculation on the server, in this order:** plan price version → period discount (yearly) → institution special price → promo code or offer → VAT; stacking rule set by the Master Admin (default: one code or offer, whichever is better); never below zero; each discount on its own invoice line; everything audited.
- [ ] 0B.16-T17 Master Admin screens: Plans & prices (versions, per-type prices, trial), Offers & promo codes (create, pause, usage), offer report (uses, discount given, new institutions); institution Billing page shows running offers and accepts a promo code with the saving shown before payment.

**Tests**
- Unit: proration, reminder schedule, grace → read-only transitions with a fake clock.
- Integration (sandbox): SSLCommerz payment success, failure, duplicate IPN, missing IPN → reconciliation.
- RPC-as-real-role: amount and invoice come from the server; a tampered client amount is ignored.
- RLS + leak: invoices and payments visible only to the institution's billing users and platform Billing.

**Done when (acceptance criteria)**
- A test institution can be invoiced, pay manually or online, receive a receipt, get reminders, expire into grace and read-only, and return to active on payment — with no data lost.

**Watch-outs (do not miss)**
- Mixing subscription money with institutions' fee money is a legal and accounting risk (Ch 9.9 row 10).
- SMS bill disputes: statement must separate failed parts and direct vs platform cost (Ch 9.9 row 7); the Excel/PDF SMS statement itself is Block 2.
- Group invoices and group discounts (D25) come with groups in Block 1B; monthly cost view/budgets in Block 1B.

**Owner checkpoint:** approve billing rules and VAT handling; watch a sandbox subscription payment end to end.

### 0B.17 Google sign-in with institution modes

**Goal:** Sign in with Google via one platform OAuth client, with per-institution modes (invited only, open with approval, verified-domain auto-approval) and safe identity linking.

**Depends on:** 0B.09; 0B.01; Block 0A (password auth basics, `institution_members`, access version).

**Plan chapters:** Ch 10 (10.1, 10.2, 10.4, 10.10 rows 2, 5, 8, 10), Ch 42 (42.7 login row), Ch 53 (53.3 row 2, 53.4 row 4).

**Decisions:** D2, D22, D25.

**Build**
- **Data:** login settings (Appendix A "login" group): enabled methods per institution (**Proposed**), Google mode `invited_only` (default) | `open_with_approval`, domain auto-approve list (verified domains only) with default role; `user_identities` linking.
- **Server:** Supabase Auth Google provider; custom auth hook that matches a profile and memberships only by verified email/phone; open-mode institution lookup by exact code/EIIN (no list, rate-limited) creating a pending membership; domain auto-approval creating an active membership with the default role; deactivation ends all sessions incl. Google.
- **App & web:** "Sign in with Google" on app and web login; "Ask your Admin to add you" screen; code/EIIN lookup screen for open mode; Settings → Login (methods, Google mode, domains, default role); profile → linked login methods (last method cannot be removed).
- **Settings & permissions:** `settings.login` (sensitive); labels.

**Tasks**
- [ ] 0B.17-T1 Start Google OAuth consent-screen verification immediately (long lead time) — owner/ops task.
- [ ] 0B.17-T2 Configure the single platform Google OAuth client (branded-app clients are later, via hub "app" connections).
- [ ] 0B.17-T3 Custom auth hook: link only on verified email/phone; account merging only by Master Admin support with audit (**Proposed**).
- [ ] 0B.17-T4 Modes per institution: invited only (default), open with approval (pending membership, approver needs `settings.users`), domain auto-approve on verified domains with default role.
- [ ] 0B.17-T5 Open-mode institution lookup by exact code/EIIN only, rate-limited, never a list.
- [ ] 0B.17-T6 **Proposed:** each institution can enable/disable each login method.
- [ ] 0B.17-T7 One profile can hold Google + password (+ OTP); last method cannot be removed.
- [ ] 0B.17-T8 Deactivation immediately ends all sessions including Google.
- [ ] 0B.17-T9 Add Google option to the setup wizard Super Admin step (0B.09).
- [ ] 0B.17-T10 Login screen shows the neutral product brand; brand after login (D12).

**Tests**
- Unit: unverified email never links to an existing membership.
- UI (Playwright + Maestro): each mode — invited user enters; uninvited sees "Ask your Admin"; open mode creates pending; domain user auto-approved with default role.
- RLS + leak: a Google user with two memberships sees only the active institution.
- Security: lookup endpoint rate limit; no partial-match enumeration.

**Done when (acceptance criteria)**
- Staff can sign in with Google according to their institution's mode; signing in never grants access by itself.

**Watch-outs (do not miss)**
- Wrong identity match = wrong person's access (Ch 10.10 row 2).
- Customer list leak via pickers (Ch 10.10 row 5).
- Self sign-up spam (Ch 10.10 row 10): approval mandatory, domain auto-approve only on verified domains, rate limits, institution can stay invite-only.

**Owner checkpoint:** approve the default mode (invited only) and see all three modes demonstrated.

### 0B.18 OTP sign-in, forgot password and OTP second step

**Goal:** OTP by SMS and email for login, forgot password, account-deletion confirmation, phone/email change and optional risky actions, with strict limits, the OTP route and never blocked by quotas.

**Depends on:** 0B.13; 0B.14; 0B.17.

**Plan chapters:** Ch 10 (10.5, 10.7 forgot password, 10.9 second step, 10.10 rows 1, 3), Ch 42 (42.4 routes, 42.7 login row), Ch 9 (9.5, 9.7 OTP counted), Ch 25 (25.5 OTP queue).

**Decisions:** D2, D22.

**Build**
- **Data:** OTP settings per institution: channel SMS only | email only | both (default: SMS first, then email), where required (login, forgot password, delete account, phone/email change, optional risky actions such as payment void); `otp_requests(target_hash, institution_id resolved, channel, created_at, attempts, locked_until)`.
- **Server:** Supabase Auth OTP with custom send hook routing SMS through the resolved institution's OTP route (gateway found from the phone's membership), else the platform gateway if Master Admin allows; email through the institution's email setup else platform mail; 6 digits, 5 minutes, single use; limits per number/email/IP (e.g. 3 per 10 minutes, 10 per day; 5 wrong → 15-minute lock); neutral response for unknown numbers; CAPTCHA on public pages; ledger category `otp`, never blocked by monthly limits; anomaly alert to Master Admin.
- **App & web:** OTP login screen (phone or email), Android SMS auto-fill, web `one-time-code` autocomplete; "Forgot password" via OTP; OTP step-up dialog for sensitive permissions.
- **Settings & permissions:** `settings.login`; the OTP step-up applies to sensitive permissions from the 0A registry (billing, integrations, roles …).

**Tasks**
- [ ] 0B.18-T1 OTP settings schema and Settings → Login section (channel, where required).
- [ ] 0B.18-T2 Custom send hook resolving the institution's OTP route; platform gateway fallback only if Master Admin allowed it; email fallback.
- [ ] 0B.18-T3 **Proposed** numbers: 6 digits, 5-minute validity, single use; 3 per 10 minutes and 10 per day per target; 5 wrong attempts → 15-minute lock; per-IP limits; CAPTCHA on public pages.
- [ ] 0B.18-T4 Neutral message for unknown numbers/emails (no SMS sent, no enumeration).
- [ ] 0B.18-T5 OTP uses the high-priority lane; ledger counts it as `otp`; monthly limits never block it.
- [ ] 0B.18-T6 **Proposed:** "Forgot password" self-service via OTP.
- [ ] 0B.18-T7 **Proposed:** OTP as second step for sensitive permissions; roles with sensitive permissions cannot log in with OTP alone (password/Google + OTP) (Ch 10.10 row 3).
- [ ] 0B.18-T8 **Proposed:** alert Admin when a long-unused account logs in from a new device.
- [ ] 0B.18-T9 Android SMS auto-fill and web `one-time-code` autocomplete.
- [ ] 0B.18-T10 Anomaly alert to Master Admin on unusual OTP volume.
- [ ] 0B.18-T11 Add OTP option to the setup wizard Super Admin step (0B.09).
- [ ] 0B.18-T12 Hook point for the applicant status page (Block 3–5) and WhatsApp OTP (later, official API).

**Tests**
- Unit: expiry, single use, lock after 5 wrong, daily cap.
- Load: SMS bomb attempt across many numbers is throttled; costs stay bounded.
- Integration: OTP for a phone that belongs to institution A goes via A's gateway, B's via B's.
- UI (Maestro): auto-fill on Android; Playwright: web autocomplete attribute present.
- RLS + leak: `otp_requests` never readable by tenants.

**Done when (acceptance criteria)**
- Staff can sign in and reset passwords by OTP over SMS or email per institution setting; OTP is delivered even when the institution's bulk/monthly limit is reached.

**Watch-outs (do not miss)**
- OTP abuse and cost (Ch 10.10 row 1).
- SIM swap / recycled numbers in Bangladesh (Ch 10.10 row 3).
- One institution's bulk must never block another's OTP (I6).

**Owner checkpoint:** approve OTP numbers and channels; sign in by OTP on a phone.

### 0B.19 Staff sign-up, approval, app states and admin password reset

**Goal:** Staff self sign-up into pending memberships, admin invitations, approval, the full app state machine and the admin password-reset rules.

**Depends on:** 0B.17; 0B.18; Block 0A (roles v2 core, Users screen, access version).

**Plan chapters:** Ch 10 (10.3 identification, 10.6, 10.7, 10.10 rows 6, 9, 10), Ch 11 (11.14 approve/reset actions), Appendix A (reset-password format).

**Decisions:** D2, D25.

**Build**
- **Data:** `institution_members.status` pending | active | deactivated (from 0A) plus `requested_via`, `approved_by`; institution setting default new-user role; reset-password format setting (plain, or based on institution short name).
- **Server:** staff sign-up RPC (institution chosen by exact code/EIIN, never a list) creating a pending membership with the default role; `signup` event for users with `settings.users` (delivered in-app now; push/email delivery with `notify()` in Block 1B); invite by email/phone so the person enters on first login by password, Google or OTP; admin password reset Edge Function: sets password, ends all sessions, can force change on next login, only Super Admin may reset another Super Admin, nobody resets themselves, nobody resets someone with more power; **Proposed:** a person who is a member of another institution cannot be reset by one institution's Admin (self-reset via OTP or Master Admin support).
- **App & web:** sign-up screens; pending screen ("Check again", sign out, "Delete my account"; different text when deactivated); `must_change_password` screen; Home/Users "pending sign-ups" banner (Home card wired in Block 1B); reset dialog that generates a password and offers WhatsApp share; app states `loading`, `error`, `needs_setup`, `signed_out`, `pending_approval`, `must_change_password`, `active`.
- **Settings & permissions:** `settings.users` (approve, reset); labels.

**Tasks**
- [ ] 0B.19-T1 Staff self sign-up with exact code/EIIN lookup, rate-limited; pending membership with institution default role.
- [ ] 0B.19-T2 Server identifies memberships from the verified email/phone only, never from client input; one active membership opens directly (multi-membership chooser and switcher are Block 1B).
- [ ] 0B.19-T3 `signup` in-app notification and pending banner for approvers; approve from Users screen (0A).
- [ ] 0B.19-T4 Admin invitations by email/phone; first login by any enabled method.
- [ ] 0B.19-T5 App state machine with all seven states and their screens.
- [ ] 0B.19-T6 Admin password reset Edge Function with all rules; reset-password format setting; WhatsApp share of generated password.
- [ ] 0B.19-T7 **Proposed:** multi-membership users cannot be reset by a single institution's Admin.
- [ ] 0B.19-T8 Institution option to turn off self sign-up (invite only) and sign-up rate limits.
- [ ] 0B.19-T9 Leak test with a two-membership user (pending in A, active in B).

**Tests**
- RPC-as-real-role: Admin cannot reset a Super Admin; Super Admin cannot reset self; reset ends all sessions.
- UI (Maestro + Playwright): sign-up → pending → approved → active; deactivated text differs.
- RLS + leak: pending member sees no institution data.

**Done when (acceptance criteria)**
- Signing in never grants access until an Admin approves or invited the person; all app states render correctly in bn/en, light/dark.

**Watch-outs (do not miss)**
- Stale permissions in sessions (Ch 10.10 row 6): access version check (0A) on every request.
- Sign-up spam (Ch 10.10 row 10).

**Owner checkpoint:** sign up as staff, see the pending screen, approve from the Users screen, reset a password and share it.

### 0B.20 Profile, account deletion, privacy page and session security

**Goal:** Self-service profile, Google-Play-compliant account deletion with anonymisation, a static privacy page, and session/device security (sign-out hygiene, inactivity sign-out, sign out everywhere, optional app lock).

**Depends on:** 0B.19.

**Plan chapters:** Ch 10 (10.8, 10.9, 10.10 rows 4, 7, 9), Ch 5 (5.15 privacy policy), Ch 42 (42.9 I11 provider names), Ch 51 (lesson 11 web deletion path).

**Decisions:** D25.

**Build**
- **Data:** public bucket `avatars`; `account_deletion_requests(email_or_phone, institution_id, created_at, status)` rate-limited; inactivity sign-out setting per institution.
- **Server:** profile RPCs (name, phone edit; email change with confirmation link; phone change verified by OTP; password change; language; linked methods); `delete_my_account` (re-enter password and type `DELETE`, or OTP for password-less users) that anonymises across all memberships: leads unassigned, tokens/devices/chats deleted, profile "Deleted user", auth email scrambled, account banned; blocked if the person is the last Super Admin of any institution; leaving one institution = deactivate that membership; sign-out clears push registration, cache and device record; "sign out all other devices".
- **App & web:** Profile screen; Delete account flow (signed-in); public web page for deletion while signed out (sign in or send a rate-limited request to the Admins); static privacy page with product contact and the list of every external provider; Settings → Security: inactivity sign-out; optional app lock (PIN or fingerprint) on the phone.
- **Settings & permissions:** institution setting for inactivity sign-out (`settings.general`); labels.

**Tasks**
- [ ] 0B.20-T1 Profile screen and RPCs incl. email change confirmation and OTP-verified phone change; avatar upload to `avatars`.
- [ ] 0B.20-T2 Language choice per user (D13 framework from 0A).
- [ ] 0B.20-T3 Account deletion (signed in) with password or OTP confirmation and `DELETE`.
- [ ] 0B.20-T4 Anonymisation routine across all memberships; last-Super-Admin-of-any-institution guard with "make someone else Super Admin first" message.
- [ ] 0B.20-T5 Signed-out web deletion path (Google Play requirement) and rate-limited deletion request to Admins.
- [ ] 0B.20-T6 Static privacy page (and terms) naming all external providers (SMS gateways, email providers, SSLCommerz, Google, Supabase …).
- [ ] 0B.20-T7 Sign-out hygiene: unregister push, clear institution/user-partitioned caches, forget device; cache and Realtime keyed by institution (Ch 10.10 row 4).
- [ ] 0B.20-T8 Inactivity auto sign-out (institution setting) and "sign out all other devices".
- [ ] 0B.20-T9 Optional app lock (PIN / fingerprint) on Android.

**Tests**
- Unit: anonymisation leaves institution records intact and unassigned; last Super Admin deletion blocked.
- UI (Maestro + Playwright): deletion in app and on the signed-out web page; sign-out clears cache (no previous user's data visible after a different user signs in).
- RLS + leak: avatars bucket allows only own uploads; deletion requests isolated.
- Screenshot (light/dark × bn/en): profile, delete flow, privacy page.

**Done when (acceptance criteria)**
- A user can manage their profile and delete their account from the app or the web; no institution loses its last Super Admin; shared devices do not leak the previous user's data.

**Watch-outs (do not miss)**
- Account deletion vs multiple memberships (Ch 10.10 row 9).
- Shared office computers/phones (Ch 10.10 row 7).
- Google Play requires the web deletion path (Ch 51 lesson 11).

**Owner checkpoint:** delete a test account on the web and confirm the institution's records remain, unassigned and anonymised.

## Phase 1A: Core CRM — leads to follow-ups

This block turns the Phase 0 skeleton into a working lead CRM: the lead record (with guardians, offerings, tags and custom fields), who sees and edits which lead, the Add/Edit form with duplicate check, assignment and hand-over, the lead list and board, the lead page and peek sheet, pipeline stages with lost / reopen / basic "mark admitted", follow-ups with reminders and speed-to-lead escalation, manual call and WhatsApp logging, notes and voice notes on an append-only timeline with soft delete and restore, campus visits, the rule-based lead score, Recent and Starred, and Excel / phone-contact import and Excel export.
**Exit criteria:** a counsellor at a seeded test institution of each type profile can add, find, call (manual log), note, follow up, move, lose, reopen and mark admitted a lead on Android and web; every new table and RPC is in the cross-tenant leak test and the role matrix; the list, lead page and Today list meet the speed budget on the ≈3,000-lead benchmark; nothing from Ch 14–23 marked for phase 1 is missing, and everything marked for a later phase is listed as deferred in the milestone that touches it.
Notification delivery to the inbox and push, message templates, field-level masking, export controls, the approval engine, automation rules and the job scheduler arrive in Block 1B (IDs 1.16–1.35); this block writes to the hooks they will plug into and must not be released to customer institutions with counsellor roles before Block 1B's field-masking milestone (D24) is live.

### 1.01 Lead data model, master lists and phone rules

**Goal:** Create every table and column the lead CRM needs, seeded per type profile, with RLS, indexes and phone normalisation, so later milestones only add behaviour.

**Depends on:** Phase 0

**Plan chapters:** Ch 14 (14.1–14.6, 14.11), Ch 17 (17.2 fields only), Ch 18 (18.2 data), Ch 19 (19.2 data), Ch 21 (21.2 data), Ch 22 (22.2, 22.4 data), Ch 51 (lessons 1, 8, 9, 10).

**Decisions:** D8, D9, D20

**Build**
- **Data:**
  - `leads`: `institution_id`, `branch_id` (nullable), name (required), phone, alt_phone, email, area, whatsapp_number, whatsapp_username, lead_type_id, source_id, campaign_id, referred_by, stage_id, rating (`hot` / `warm` / `cold`), score, lost_reason_id, assigned_to, assignment_method, created_by, next_follow_up_at, last_contacted_at, admitted_at, lost_at, closed_at, call_attempts, unreachable_at, visit_status, visit_at, import_batch_id, deleted_at, created_at, updated_at; no `notes` text column and no `custom_fields` jsonb column.
  - Normalised phone columns for search and duplicate matching (phone, alt, WhatsApp; guardian phone on `contact_persons`) with trigram or suffix indexes.
  - `contact_persons` (name, phone, relation, `institution_id`, `branch_id`) and `lead_contact_persons` (many-to-many, so one guardian links siblings).
  - `lead_offerings` (lead ↔ `offering`, many) and `lead_tags` (lead ↔ tag, many). Use Phase 0's `offerings` table if present; otherwise create a minimal one (labels, active, order, `branch_id`) that Block 2 (Ch 28) extends with batches, sections and seats.
  - Master lists, each per institution: `lead_sources`, `campaigns`, `lost_reasons` (with an "Other…" flag), `tags`, `lead_types`. Do not create `call_results` or `document_types`.
  - `pipeline_stages` (key, label bn/en, kind `open` / `won` / `lost` / `cancelled`, colour, order, active, is_system, `course_ids`, `follow_up_days`, `note_required`, `ask_date`, `date_label`); behaviour comes in 1.07.
  - `follow_ups` (lead, assignee, due_at, status `pending` / `done` / `rescheduled` / `cancelled`, purpose `general` / `revive` / `call_back`, created_by, source) with a partial unique index "one pending per lead".
  - `call_logs` (lead, user, at, outcome, duration, note, direction, source `app` / `phone` / `whatsapp`, channel `phone` / `whatsapp` / `sms`, media `voice` / `video` / `message`, device_id, sim, template_id, deleted_at); outcome is a fixed enum: `connected`, `no_answer`, `busy`, `switched_off`, `wrong_number`, `call_back`, `missed`, `rejected`, `message`.
  - `notes` (one row per note: lead, author, at, body, deleted_at) and `voice_notes` (file list row: lead, call_log_id, storage path, duration, size, deleted_at).
  - `stage_history` (append-only), `lead_views` (user, lead, last_viewed_at; upsert), `lead_stars` (user, lead), `appointments` (neutral key `appointment`, formerly `campus_visit`).
  - Custom field values for entity `lead` go in Phase 0's `custom_field_values`; add GIN / expression indexes only for fields flagged "filterable".
  - Every table: `institution_id` first in every index, RLS through `user_access`, partial indexes that skip soft-deleted rows.
  - Seed data: master lists, stages and custom-field presets from each Phase 0 type profile (school, college, coaching, etc.) into each seeded test institution.
- **Server:** `normalise_phone(text, institution_locale)` (Bangla digits → Latin, +880 / spaces / dashes stripped, `01XXXXXXXXX` form by locale rule, default Bangladesh); WhatsApp username normaliser (lowercase, 3–35 chars); trigger that clears whatsapp_number when it equals phone; `domain_events` event type registration (`lead.*`, `follow_up.*`, `call.*`, `note.*`, `appointment.*`, `conversion.*`).
- **App & web:** Settings → LEADS → Lists screen (sources, campaigns, lost reasons, tags, lead types): add, rename (bn/en), reorder, deactivate.
- **Settings & permissions:** register module `lead` and its permission keys in the Phase 0 registry (`lead.view`, `lead.create`, `lead.edit`, `lead.delete` marked sensitive, `lead.assign`, `lead.import`, `lead.export`, with scopes `own` / `team` / `org_unit` / `branch` / `all`) plus template defaults per role template; register labels for `lead`, `contact_person`, `offering`, `conversion`, `appointment`, every list name and every call outcome (bn/en).

**Tasks**
- [ ] 1.01-T1 Write expand-only migrations for all tables above with `institution_id`, nullable `branch_id`, timestamps, soft-delete columns.
- [ ] 1.01-T2 Add RLS policies on every table using `user_access` (view/edit scopes are filled in by 1.02; start with institution isolation plus deny-by-default).
- [ ] 1.01-T3 Create indexes: `institution_id`-leading composites for list queries, normalised-phone trigram/suffix indexes, partial "not deleted" indexes, "one pending follow-up per lead" partial unique index.
- [ ] 1.01-T4 Implement `normalise_phone` and the WhatsApp normalisers with unit tests (Bangla digits "০১৭১১…", +880, spaces, dashes, intl `+` numbers for WhatsApp).
- [ ] 1.01-T5 Add the trigger that drops whatsapp_number when equal to phone and lower-cases the username.
- [ ] 1.01-T6 Wire `custom_field_values` for entity `lead`; create indexes only for filterable fields; enforce the plan's custom-field count limit from Phase 0.
- [ ] 1.01-T7 Add `contact_persons` and the link table; enforce same-institution links.
- [ ] 1.01-T8 Seed master lists, stages and custom-field presets from every type profile; re-run the Phase 0 seeded test institutions.
- [ ] 1.01-T9 Register permission keys, role-template defaults, labels and `domain_events` types.
- [ ] 1.01-T10 Build Settings → LEADS → Lists (bn/en labels, reorder, deactivate; deactivated items stay on old leads).
- [ ] 1.01-T11 Add all new tables to the cross-tenant leak test and the invoker/DEFINER sweep.
- [ ] 1.01-T12 Generate the ≈3,000-lead benchmark data set (with calls, notes, follow-ups, custom fields) for the seeded test institutions.

**Tests**
- Unit: phone normaliser (20+ cases incl. Bangla digits and pasted text), username normaliser.
- RLS + cross-tenant leak: every new table read/write from institution B returns nothing / is refused.
- RPC-as-real-role: list-screen CRUD as a signed-in counsellor, not as the DB owner (lesson 1).
- Seed check: each type profile's test institution has the profile's stages, lists and custom-field presets.

**Done when (acceptance criteria)**
- All tables exist with RLS on, and the leak test passes in CI with them included.
- Typing "০১৭১১-২২২ ৩৩৩" or "+880 1711 222333" stores `01711222333`.
- Each seeded type-profile institution shows its own lists and stages in Settings → LEADS.
- No `notes` text column, `custom_fields` jsonb, `call_results` or `document_types` table exists.

**Watch-outs (do not miss)**
- Keys stay neutral (`offering`, `contact_person`, `conversion`, `appointment`); screens show education labels only through the label system (D20).
- Custom-field filtering slows down with many fields: index only filterable fields and keep the per-plan limit (Ch 14.12 #5).
- Lesson 8: anything the list card will show must be a column or denormalised counter, not a per-row request.
- The appendix suggests renaming the `campus_visit` setting key to `appointment`; follow whatever Phase 0 decided and do not add a second name.

**Owner checkpoint:** Owner opens Settings → LEADS → Lists in a seeded school and a seeded coaching centre and sees the profile-specific lists and stages in Bangla and English.

### 1.02 Lead access rules and the phone presenter

**Goal:** Make "who sees and edits which lead" correct and fast everywhere, through one `can(user, action, record)` function and `user_access`, before any lead screen exists.

**Depends on:** 1.01

**Plan chapters:** Ch 14 (14.3 masking note, 14.10, 14.12 #3, #6), Ch 15 (15.11 #1), Ch 19 (19.4), Ch 51 (lesson 1, 7).

**Decisions:** D9, D23, D24

**Build**
- **Data:** extend `user_access` with the lead scopes (`own`, `team` incl. sub-teams, `org_unit`, `branch`, `all`), the offering limit per role / role grant, and the branch limit; access-version bump on change.
- **Server:**
  - `can(user, action, record)` for `lead.view`, `lead.edit`, `lead.delete`, `lead.assign` (permission union across multiple roles, D23).
  - RLS on `leads` and all child tables (notes, calls, follow-ups, appointments, stars, views, custom field values) uses simple `IN` checks against `user_access`; heavy plpgsql functions set `jit = off`.
  - Rules: creator always sees own leads; shared mode (assignment off or visibility `everyone`) lets everyone view and edit; offering limit hides leads of other offerings everywhere; leads with no offering are visible only to Admins and the creator; branch limit from the owner's unit and the lead's `branch_id`.
  - Phone presenter: every RPC that returns a phone, alt phone, guardian phone or WhatsApp number passes it through one server function `present_phone(user, value)`; in this block it returns the full number unless the Phase 0 role behaviour or a test flag says "mask", in which case it returns `017•••••234`. Block 1B's field-masking milestone replaces the policy behind it without touching callers.
  - `get_dial_target(lead_id, kind)` returns the real number only for an immediate dial / WhatsApp open, checks `can(view)`, and records the access in the Phase 0 audit log.
- **App & web:** a shared `<PhoneText>` component that never offers copy or long-press-select when the value is masked.
- **Settings & permissions:** read `assignment.enabled` and `assignment.visibility` (key registered in 1.03); `lead.delete` stays sensitive.

**Tasks**
- [ ] 1.02-T1 Implement scope resolution into `user_access` for leads (own / team with sub-teams / org_unit / branch / all).
- [ ] 1.02-T2 Implement the offering-limit and branch-limit columns and their refresh on role or grant change.
- [ ] 1.02-T3 Implement `can()` for lead actions and use it in RLS policies and RPC guards.
- [ ] 1.02-T4 Implement shared mode and "creator always sees own".
- [ ] 1.02-T5 Implement `present_phone` and route every phone-returning view/RPC through it.
- [ ] 1.02-T6 Implement `get_dial_target` with audit logging.
- [ ] 1.02-T7 Build `<PhoneText>` (masked: no copy, no select; Call / WhatsApp buttons still work).
- [ ] 1.02-T8 Extend the Phase 0 access explainer with the lead rules (assignment setting, scope, shared mode, offering limit, branch).
- [ ] 1.02-T9 Add role-matrix fixtures: counsellor, team lead, admission officer, admin, super admin, multi-role user, branch-limited user, offering-limited user.

**Tests**
- Role matrix: for each fixture user, the exact set of visible / editable leads on the seeded institution matches a checked-in expected list.
- RLS + leak: child tables (notes, calls) of an invisible lead are invisible too; institution B never sees A.
- RPC-as-real-role: `can()` and every guard run as the signed-in user role (lesson 1).
- Masking hook: with the mask flag on for counsellors, no RPC response contains a full phone number (scan all lead RPC outputs).
- Performance: list query with full RLS on the ≈3,000-lead set stays within the Phase 0 speed budget.

**Done when (acceptance criteria)**
- A team lead sees their team's and sub-teams' leads but not another team's; a branch-limited user sees only their branch.
- An offering-limited user ("BBA, MBA only") never sees a CSE lead in any list, search or count.
- In shared mode every member can view and edit every lead.
- The access explainer answers "why can't X see lead Y" for each rule above.

**Watch-outs (do not miss)**
- Three places decide ownership (assignment setting, scope permission, shared mode); the explainer is the fix (Ch 14.12 #6).
- Masking cannot stop the dialer or the phone's call log from showing the number; tell the owner the limit in writing (Ch 14.12 #3, Ch 19.11 #2).
- Server decisions come from the user's session and profile, never from what the client sends (lesson 7).
- Do not release to customers with counsellor roles until Block 1B's field-masking policy is live (D24).

**Owner checkpoint:** Owner logs in as a counsellor, a team lead and a branch-limited officer in a seeded institution and confirms each sees the right leads; the access explainer shows why.

### 1.03 Create and edit leads: form, duplicate check, assignment and hand-over

**Goal:** Let staff add and edit leads quickly and safely (no double saves, no hidden duplicates) and route each new lead to the right owner.

**Depends on:** 1.02

**Plan chapters:** Ch 14 (14.3–14.5, 14.7, 14.8, 14.9, 14.11, 14.12 #1, #2, #8, #9), Ch 47 references in 14.8.

**Decisions:** D9, D23, D24

**Build**
- **Data:** idempotency-key table for lead-writing RPCs; `assignment_method` values (manual, admin_auto, self, round_robin, import, hand_over); hand-over note stored as a note with kind `hand_over`.
- **Server:**
  - `create_lead(row, course_ids, tag_ids, contact_persons, custom_values, idempotency_key)` saves lead, offerings, tags, guardians and custom values in one transaction; second request with the same key returns the first result.
  - Validation: name required; at least one of phone, WhatsApp number or WhatsApp username; at least one offering if the institution has any; the last offering of a lead cannot be removed; source changes only with `lead.edit` scope `all`; required custom fields.
  - `update_lead(...)` with the same rules, idempotent.
  - `find_leads_by_contact(phone)`: SECURITY DEFINER, active institution checked explicitly, matches phone / alt / guardian / WhatsApp across all leads of the institution (including leads the user cannot see), returns at most 5 rows with name, stage and owner only, plus `can_open`, and "sibling of …" when the match is a guardian phone.
  - **Proposed:** per-user daily limit on duplicate checks and an admin alert on unusual use (Ch 14.12 #2).
  - Assignment trigger on insert implementing setting `assignment`: `enabled`, `visibility` (`assigned` / `everyone`), `admin_auto` (admins' new leads go to a chosen user), `caller_self`, `team_lead_self`, `team_lead_assign`, `handover` (anyone / team / managers / off); writes `assignment_method`.
  - `assign_lead(lead, user)`: Admin to anyone, Team Lead to self or own team; requires `lead.assign`; assignee list limited to users whose role has the behaviour switch "can be assigned leads".
  - `hand_over_lead(lead, user, note)`: respects `handover`, writes the note, emits `lead.handed_over`.
  - Emit `lead.created`, `lead.updated`, `lead.assigned` to `domain_events`; notification types `assigned` and `auto_assigned` raised through the Phase 0 recipient matrix (inbox/push delivery arrives in Block 1B).
  - Plan limit on active leads (Phase 0 limits): warning at 80%, block new leads at 100% with a clear message and an upgrade button.
  - **Proposed:** leads from public forms are never dropped at the limit; they are kept with an "over limit" mark and a notice goes to the Super Admin (wired when Block 1B builds public forms, Ch 27).
- **App & web:**
  - Add/Edit form: cards Who, Interested course, Quick details; folds Other contact, Guardian(s), Campaign / type / tags / notes, Custom fields (by group); branch picker when branches are on (default: user's branch).
  - Live duplicate panel under the phone field while typing ("Open" if allowed, "Save anyway"; "sibling of …").
  - Remembers last source and course; "Save & next" keeps source, course and assignee and opens an empty form.
  - Quality rules: number pad for phone, email keyboard for email, fields scroll above the keyboard, Save above the keyboard, Next moves to the next field, errors under the field, Back asks "Discard changes?", draft survives an incoming call, double-tap Save never creates two leads.
  - Assign and Hand over sheets (user picker filtered by the behaviour switch and the `handover` setting).
- **Settings & permissions:** register setting `assignment` (all options above) in Settings → LEADS; quiet-hours option "send `assigned` immediately" is read by 1.11.

**Tasks**
- [ ] 1.03-T1 Implement the idempotency-key store and helper.
- [ ] 1.03-T2 Implement `create_lead` and `update_lead` with all validation rules.
- [ ] 1.03-T3 Implement `find_leads_by_contact` (DEFINER, explicit institution check, max 5, name/stage/owner only, sibling detection).
- [ ] 1.03-T4 **Proposed:** add the duplicate-check daily limit and admin alert behind a setting (off until owner approves).
- [ ] 1.03-T5 Implement the assignment trigger for every `assignment` option and record `assignment_method`.
- [ ] 1.03-T6 Implement `assign_lead` and `hand_over_lead` with permission and behaviour-switch checks.
- [ ] 1.03-T7 Emit `domain_events` and raise `assigned` / `auto_assigned` notification requests.
- [ ] 1.03-T8 Enforce the active-lead plan limit (80% warning banner, 100% block with upgrade button).
- [ ] 1.03-T9 Build the Add/Edit form with cards, folds, guardian sub-form (link existing guardian by phone), custom fields by group, branch picker.
- [ ] 1.03-T10 Build the live duplicate panel with debounce.
- [ ] 1.03-T11 Implement remembered source/course and "Save & next".
- [ ] 1.03-T12 Apply the form quality rules (keyboards, scroll, Back confirm, draft persistence, Save disabled while in flight).
- [ ] 1.03-T13 Build Assign and Hand over sheets; show the hand-over note on the lead (shown by 1.05).
- [ ] 1.03-T14 Build Settings → LEADS → Assignment.

**Tests**
- RPC-as-real-role: `create_lead` with and without offerings, without phone but with username, with a same-key retry (returns same id).
- Leak: `find_leads_by_contact` called with institution B's phone from institution A returns nothing; response never contains phone, notes or ids of invisible leads beyond name/stage/owner.
- Role matrix: who can assign to whom; hand-over modes anyone / team / managers / off.
- UI (Maestro + Playwright): add lead, Save & next, duplicate panel shows sibling, double-tap Save → one lead.
- Screenshot: form light/dark × bn/en, large font.

**Done when (acceptance criteria)**
- Adding the same phone twice shows the existing lead (even if invisible to the user) with name, stage and owner only.
- A guardian phone that matches another lead shows "sibling of <name>".
- Double-tapping Save or retrying on a slow network creates exactly one lead.
- With `caller_self` on, a counsellor's new lead is assigned to them; with `admin_auto` on, an admin's new lead goes to the chosen user.
- At 100% of the plan's active-lead limit, Add shows the block message and an upgrade button.

**Watch-outs (do not miss)**
- The DEFINER duplicate function is a leak risk; it must check the active institution and be in the leak test (Ch 14.12 #1).
- Bulk probing by phone is possible; the Proposed daily limit is the mitigation (Ch 14.12 #2).
- Automation-rule assignment ("source Facebook → team B") comes from Block 1B (Ch 43); delegation and collaborators from Block 1B (Ch 11).
- The phone-contact and recent-call pickers on the Who card come in 1.14 and Phase 3 (Ch 41) respectively.

**Owner checkpoint:** Owner adds three leads with "Save & next", tries a duplicate and a sibling, and sees the right auto-assignment for two `assignment` settings.

### 1.04 Lead list, search and cards

**Goal:** Deliver the screen counsellors live in: a fast list with search, chips, sorting, "group by time", card designs and instant open from cache.

**Depends on:** 1.03

**Plan chapters:** Ch 15 (15.1–15.3, 15.5–15.7, 15.10, 15.11 #1, #2, #4, #8, #9), Ch 51 (lesson 4, 8).

**Decisions:** D9, D24

**Build**
- **Data:** denormalised counters on `leads` maintained by triggers (last call line, last note line, call count) so cards need no extra requests; `recent_searches` kept on device (last 8).
- **Server:**
  - `list_leads(filter_json, sort, page, page_size=30)`: one batched RPC returning everything a card needs (name, masked phone, stage, rating, score, next follow-up, last contact, star, card custom fields, latest call/note lines when enabled).
  - Search: name, guardian name, email, area, WhatsApp username, "searchable" custom fields, and later student ID and board ID (columns added by Block 2); 3+ digits (Latin or Bangla) also match all phone columns via the normalised index; fewer than 3 digits never search phones; Bangla text (Avro / Gboard) matches.
  - Search always includes closed leads; a hint counts matches hidden by the current chip or filter (only inside the user's own scope) with an "also matched in …" line.
  - `lead_chip_counts()` RPC for All, 🕘 Recent, ⭐ Starred, 🆕 Not called (🔮 AI Hot reserved for Phase 4); cached and invalidated after actions with an "updating" mark.
  - "Added by" user filter and "When" (Today / Yesterday / This week with week start from locale, default Saturday / This month / Custom).
  - Sorts: next call (default) with "group by time" (Overdue / Today / Tomorrow / This week / Later / No call), newest / oldest, name, longest without contact, recently contacted, score. Visit-date sort arrives in 1.13; papers pending, discount and fee sorts in Block 2; AI sorts in Phase 4.
  - Closed leads (Admitted, Lost, Cancelled) hidden per setting `admission.closed_in_list` unless a filter needs them (lost reason, fee).
- **App & web:**
  - List screen: virtualised, skeleton while loading, empty state "No leads yet" with Add / Import buttons, pull to refresh, error with reason and Retry, page size 30, "keep in place" after edits and when returning from a lead.
  - Per-user stale-while-revalidate cache that opens instantly and is wiped on sign-out or institution switch.
  - Card designs "New" (Material) and "Classic" chosen per user, admin can force one (More → APP → list design); "Show the latest on cards" toggle; card turns orange after `lead_cards.stale_days` without contact; rating with icon and colour (🔥🙂❄️); score chip; Call and WhatsApp buttons (SMS button wired by Block 1B templates); 👁 peek (1.05); card custom fields; masked number with working Call button.
- **Settings & permissions:** register `lead_cards` (stale_days, show latest, forced design) and `admission.closed_in_list`.

**Tasks**
- [ ] 1.04-T1 Add counter/denormalisation triggers for card fields.
- [ ] 1.04-T2 Implement `list_leads` with filter JSON input, scope-safe search and sorts.
- [ ] 1.04-T3 Implement phone search on the normalised columns (3-digit minimum, Bangla digits).
- [ ] 1.04-T4 Implement the hidden-match hint restricted to the user's scope.
- [ ] 1.04-T5 Implement `lead_chip_counts` with caching and invalidation.
- [ ] 1.04-T6 Implement "Added by" and "When" pickers with locale week start.
- [ ] 1.04-T7 Implement "group by time" sections.
- [ ] 1.04-T8 Implement `admission.closed_in_list`.
- [ ] 1.04-T9 Build the list screen states (skeleton, empty, error, refresh, keep in place).
- [ ] 1.04-T10 Build the per-user SWR cache and wipe on sign-out / switch.
- [ ] 1.04-T11 Build New and Classic cards with all elements above; register list-design and card settings.
- [ ] 1.04-T12 Save the last 8 searches on device.
- [ ] 1.04-T13 Run the ≈3,000-lead before/after benchmark and record the numbers.

**Tests**
- Unit: group-by-time bucket edges in the institution time zone.
- RLS: search for a phone owned by an invisible lead returns nothing and the hint does not count it.
- Performance: first page < Phase 0 budget on the ≈3,000-lead set with RLS on; one request per page (no per-row requests).
- UI: search by Bangla name, by 4 Bangla digits, closed lead appears in search; keep-in-place after editing a card.
- Screenshot: New and Classic cards light/dark × bn/en, large font, small phone.

**Done when (acceptance criteria)**
- The list opens from cache instantly and refreshes in the background; switching institution shows no previous institution's rows.
- Searching "১৭১১" finds leads whose phone contains 1711, masked for masked users.
- Chips show counts and refresh after an action.
- A card shows a "No call yet" lead under 🆕 Not called and turns orange after `stale_days`.

**Watch-outs (do not miss)**
- Every new badge or chip is a per-row request risk; batch into `list_leads` (lesson 8).
- `LIKE '%…%'` on phones is slow; use the normalised trigram/suffix index (Ch 15.11 #2).
- The hidden-match hint must never reveal leads outside the user's scope (Ch 15.11 #9).
- Bangla text must not clip; test large fonts (Ch 15.11 #8).

**Owner checkpoint:** Owner uses the list on a low-end Android phone with the ≈3,000-lead institution: search, chips, sort, both card designs.

### 1.05 Lead page, peek sheet, Recent and Starred

**Goal:** One page with everything about a lead, a peek sheet for quick decisions from the list, and personal Recent / Starred lists.

**Depends on:** 1.04

**Plan chapters:** Ch 16 (16.1–16.8), Ch 22 (22.4), Ch 15 (15.3 chips Recent / Starred).

**Decisions:** D24

**Build**
- **Data:** `lead_views` upsert per user-lead; `lead_stars`.
- **Server:**
  - **Proposed:** `get_lead_bundle(lead_id)` aggregate RPC returning header, actions allowed, next call, pipeline summary and summaries of every enabled card in one call; details (timeline, files) load on demand.
  - **Proposed:** card registry (module, order, permission) so cards come from data; institution can reorder or hide cards.
  - `record_lead_view` (upsert last viewed); cleanup of old views is a job (scheduled by 1.11's tick until Block 1B's scheduler takes over).
  - `star_lead` / `unstar_lead` (private to the user); `list_recent(user)` merges the user's calls, activity and opened leads, newest first; both drop leads the user can no longer view.
- **App & web:**
  - Phone layout: header (back, call, ⭐, edit); round buttons Call, WhatsApp, SMS (wired by Block 1B), Note, Next call; cards in order: next call (1.06), Pipeline (1.07–1.08), AI chance (Phase 4), External board / admission flow (Block 2), Admission credit (Phase 4), Visit (1.13), Fee (Block 2), Papers (Block 2), Files (Block 2), hand-over note; cards of disabled modules hidden; eligibility warning slot (Block 2, Ch 29).
  - Folds: Timeline (filled by 1.09/1.10, filter phone / WhatsApp), Admission, Info (incl. custom fields), Changes (per-lead change list from `domain_events` and audit rows; the institution-wide change log is Phase 4, Ch 38); bottom "+ Note" and "+ Log call".
  - URL parameters: `callNote` (open add-note view), `waCall` (WhatsApp call view, 1.10), `dial` (call on open, accepted only from the app's own notifications, with a confirm step until Phase 3's call lock exists); notification taps open the exact lead (deep link).
  - Delete with Undo toast (soft delete, rules in 1.09).
  - Wide / web layout with tabs Calls & notes, Interest, Details, Activity, Delete lead, built from the same components and action registry.
  - Peek sheet from the card 👁: last 5 calls, notes and voice notes with full text, "All" to expand, actions Open and Add note (AI card for open leads arrives in Phase 4).
  - Every button and card shows only with the matching permission; masked users see `017•••••234` in Info and cannot copy it; sensitive custom fields shown, masked or hidden by role (policy from Block 1B).
  - Load order: header, actions and next call first; the rest after.
  - Offline: "No internet" strip with cache time; stage and other changes validated by the server with a clear mismatch message.
  - Recent and Starred chips on the list; Recent card component ready for Home (placed by Block 1B, Ch 45).
- **Settings & permissions:** none new; uses `lead.*` keys and module switches.

**Tasks**
- [ ] 1.05-T1 Implement `get_lead_bundle` (Proposed) or, if not approved, a header RPC plus lazy card RPCs.
- [ ] 1.05-T2 Implement the card registry (Proposed) with module and permission gating.
- [ ] 1.05-T3 Build the phone layout: header, round actions, card slots, folds, bottom actions.
- [ ] 1.05-T4 Build the Info fold with custom fields by group and masked phones.
- [ ] 1.05-T5 Build the per-lead Changes fold.
- [ ] 1.05-T6 Implement URL params `callNote`, `waCall`, `dial` and deep-link routing; restrict `dial` to app notifications.
- [ ] 1.05-T7 Build the wide / web layout with the same components.
- [ ] 1.05-T8 Build the peek sheet.
- [ ] 1.05-T9 Implement `record_lead_view`, star / unstar, `list_recent`, and the Recent / Starred chips.
- [ ] 1.05-T10 Add the offline strip and server-validated action errors.
- [ ] 1.05-T11 Write the two-layout release checklist entry (phone and web show the same actions).

**Tests**
- RPC-as-real-role: bundle RPC as counsellor returns only permitted cards and masked phones when masking is on.
- Leak: stars and views of institution A invisible to B; a starred lead disappears from Starred after the user loses access.
- UI: open from card, peek → Add note, `callNote` link opens the note view, `dial` from an outside link does not auto-dial.
- Screenshot: lead page phone and web, light/dark × bn/en.
- Performance: lead page first paint on the benchmark set in one round trip for the header.

**Done when (acceptance criteria)**
- A disabled module's card never appears; a user without `lead.delete` sees no Delete.
- Peek shows the last 5 interactions in full and "All" expands.
- A lead opened appears at the top of Recent; starring is invisible to other users.
- Phone and web layouts offer the same actions.

**Watch-outs (do not miss)**
- Ten cards as ten requests is slow on bad networks; aggregate (Ch 16.7 #1).
- Writing a view row on every open bloats the table; upsert per user-lead (Ch 16.7 #4).
- Notes can contain phone numbers that masking cannot hide; **Proposed:** warn when a note contains a phone-like pattern (Ch 16.7 #6, built in 1.09).
- Stars and Recent never grant access (Ch 22.4).

**Owner checkpoint:** Owner walks through one lead on phone and web: header, actions, folds, peek, star, Recent.

### 1.06 Follow-ups and the Today list

**Goal:** Every lead has at most one pending "next call", set quickly with holiday-aware presets, and every counsellor starts the day from a correct Today list.

**Depends on:** 1.05

**Plan chapters:** Ch 18 (18.1–18.6, 18.8 #3, #5, #6, #7), Ch 13 references (working days, holidays, time zone).

**Decisions:** —

**Build**
- **Data:** `follow_ups` from 1.01; trigger keeps `leads.next_follow_up_at` equal to the pending row's due time.
- **Server:**
  - `schedule_follow_up(lead, preset | at, purpose)`: creating a new one marks the old pending one `rescheduled`; statuses pending / done / rescheduled / cancelled; purposes `general`, `revive`, `call_back`.
  - Presets computed on the server from the preset name: In 2 hours, Tomorrow 10:00, In 3 days, Next week; skip non-working days and holidays (Settings → OFFICE → Working days & holidays, Phase 0); always in the institution time zone with server time.
  - Manual pick on a holiday returns a warning, not an error.
  - `complete_follow_up`, `cancel_follow_up`; closed leads get no pending follow-up.
  - Default next call after a call outcome (used by the call popup in 1.10): wrong number → none; busy / no answer / call back → 2 hours; switched off → tomorrow; connected → 3 days.
  - Auto-done rule (applied by the call trigger in 1.10): any outgoing call or any connected call marks today's or overdue follow-up done. **Proposed:** an option "done only when connected" (Ch 18.8 #5).
  - `today_list(user)`: today's and overdue follow-ups excluding closed leads, ordered missed-call ("call back") first, then `revive`, then by time; plus the pending-call count for Home's "today stats".
- **App & web:** Next-call card on the lead page (preset chips + date-time picker with holiday warning); "Next call" round button; Today screen (Home card placement in Block 1B, Ch 45) with overdue / today sections.
- **Settings & permissions:** follow-up edits use `lead.edit` scope; register the Proposed "done only when connected" option under `call_sync` only if approved.

**Tasks**
- [ ] 1.06-T1 Implement the next_follow_up_at sync trigger and the one-pending rule.
- [ ] 1.06-T2 Implement `schedule_follow_up` with rescheduling semantics and purposes.
- [ ] 1.06-T3 Implement server-side presets with working days, holidays and time zone.
- [ ] 1.06-T4 Implement the holiday warning for manual picks.
- [ ] 1.06-T5 Implement the outcome → default next-call table as a server function.
- [ ] 1.06-T6 Implement `today_list` ordering and the pending count.
- [ ] 1.06-T7 Build the Next-call card, preset chips, picker and Today screen.
- [ ] 1.06-T8 Emit `follow_up.scheduled`, `follow_up.done`, `follow_up.rescheduled` events.
- [ ] 1.06-T9 **Proposed:** add the "done only when connected" option (off by default) if approved.

**Tests**
- Unit: presets across Friday holidays, a national holiday, month end, DST-free Asia/Dhaka and one non-Dhaka locale; phone clock set wrong does not change the result.
- RPC-as-real-role: reschedule creates exactly one pending row.
- Time-based tests on each type profile's test institution (Ch 18.8 #2).
- UI: set "Tomorrow 10:00" on Thursday in a Friday-off institution lands on Saturday 10:00.

**Done when (acceptance criteria)**
- A lead never has two pending follow-ups.
- Presets skip configured holidays and use institution time even if the phone clock is wrong.
- Today shows call-back items first, then revive, then by time, and hides closed leads.

**Watch-outs (do not miss)**
- One-pending rule cannot hold two tasks (call + paper submission); keep it, but the `purpose` field is there for future multiple tasks (Ch 18.8 #3, Proposed later).
- Holiday lists go stale (Eid dates); Phase 0's national default list and year-start reminder are the fix (Ch 18.8 #7).
- Stage rules (`follow_up_days`, `ask_date`) create follow-ups in 1.07; automation-rule follow-ups come from Block 1B (Ch 43).

**Owner checkpoint:** Owner sets follow-ups with each preset around a holiday and reviews the Today list order.

### 1.07 Pipeline stages: settings, rules and moves

**Goal:** Institutions control their own stages and stage rules; every stage move is validated, recorded and announced as an event, on the lead page and on the board.

**Depends on:** 1.06

**Plan chapters:** Ch 17 (17.1–17.4, 17.9, 17.10 #3, #8, 17.11), Ch 15 (15.9 drag rules).

**Decisions:** D8, D20

**Build**
- **Data:** `pipeline_stages` from 1.01; `stage_history` append-only (lead, from, to, by, at, note, date value); stages referenced by id everywhere, never by key.
- **Server:**
  - Stage CRUD with protection: system stages (Admitted `won`, Lost `lost`, Admission cancelled `cancelled`) cannot be deleted or change kind (labels can change); a stage with leads cannot be deleted (move leads or deactivate); new stages are inserted before the closed stages.
  - "Reset to profile defaults" with a preview of what changes.
  - `move_stage(lead, stage, note, date, idempotency_key)`: only between open stages; closed stages reachable only through the admit / lost / cancel flows (1.08); closed leads must be reopened first; `note_required` enforced; `ask_date` asks `date_label` and creates a follow-up for that date; `follow_up_days` creates a follow-up N days later; only stages applicable to the lead's offerings (`course_ids`) are offered; changing a lead's offerings checks the stage still fits.
  - Each move writes `stage_history` and emits `lead.stage_changed`.
- **App & web:** Settings → LEADS → Pipeline stages (labels bn/en, colour, order, active, kind shown, `course_ids`, rules); Pipeline card on the lead page with "Move" sheet (note / date prompts).
- **Settings & permissions:** `settings.pipeline` permission; register stage labels.

**Tasks**
- [ ] 1.07-T1 Implement stage CRUD RPCs with the protection rules.
- [ ] 1.07-T2 Implement "Reset to profile defaults" with preview.
- [ ] 1.07-T3 Implement `move_stage` with all rule checks and idempotency.
- [ ] 1.07-T4 Implement `ask_date` and `follow_up_days` follow-up creation via `schedule_follow_up`.
- [ ] 1.07-T5 Implement `course_ids` filtering of allowed stages and the offering-change check.
- [ ] 1.07-T6 Write `stage_history` and `domain_events` on every move.
- [ ] 1.07-T7 Build the Pipeline stages settings screen.
- [ ] 1.07-T8 Build the Pipeline card and Move sheet.
- [ ] 1.07-T9 Verify each type profile's seeded stages (school, coaching, generic) in the test institutions.

**Tests**
- RPC-as-real-role: user without `settings.pipeline` cannot edit stages; move with missing required note is refused.
- Unit: protection rules (delete system stage, delete used stage, kind change) all refused with clear messages.
- Role matrix: who may move stages (lead.edit scope).
- UI: move with `ask_date` creates the follow-up shown on the Next-call card.

**Done when (acceptance criteria)**
- Admitted, Lost and Cancelled always exist and can only be renamed.
- Moving to a stage with `note_required` without a note is refused; with `ask_date` the date becomes the next follow-up.
- Renaming a stage leaves history and reports intact (history stores ids).

**Watch-outs (do not miss)**
- Stage edits break old reports and scores if rules use keys; use ids and kinds (Ch 17.10 #3, Ch 22.3).
- `course_ids` plus offering limits can strand leads in stages the user cannot see; filter the move list and check on offering change (Ch 17.10 #8).
- Stage-based automation (SMS + follow-up on stage change) comes from Block 1B (Ch 43); funnel and lost-reason reports from Phase 4 (Ch 38).

**Owner checkpoint:** Owner renames a stage, adds a stage with "ask date", and moves a lead through it.

### 1.08 Lost, reopen and basic "mark admitted"

**Goal:** Close leads correctly (lost with reason, admitted, admission cancelled) and bring them back (reopen, revive, undo admission), with everything recorded.

**Depends on:** 1.07

**Plan chapters:** Ch 17 (17.5 basics, 17.6, 17.7 basics, 17.8, 17.9, 17.10 #1, #4, #5, #6, #7).

**Decisions:** D20

**Build**
- **Data:** **Proposed:** a separate `conversions` record per admission (lead, offering, date, note, status) so one client can have several conversions later (Ch 17.10 #5); `leads.admitted_at`, `lost_at`, `closed_at`.
- **Server:**
  - `mark_lost(lead, reason_id, note, revive_on, idempotency_key)`: reason required; "Other…" requires a note; optional "♻️ Revive on date" creates a `revive` follow-up; sets `lost_at` / `closed_at`; cancels other pending follow-ups; emits `lead.lost`.
  - `mark_admitted(lead, offering, admitted_on, note, idempotency_key)` (basic): permission `conversion.mark` with scope (formerly the `admission.mark` "who" setting); offering must be active; in one transaction: move to the `won` stage, set `admitted_at` / `closed_at`, finish pending follow-ups, write `stage_history`, emit `conversion.created`; officer notification request through the recipient matrix. A second request for an already-won lead returns the first result.
  - `cancel_admission(lead, reason)` (basic): permission `conversion.cancel`; reason required; moves to `cancelled`; keeps any student ID; emits `conversion.cancelled`.
  - `reopen_lead(lead, open_stage)`: works on lost or cancelled leads; target must be an open stage; emits `lead.reopened`.
  - "Undo admission" = cancel then reopen in one call, both written to history.
  - External side effects (SMS, push, AI) only via events / outbox, never inside the transaction.
- **App & web:** Admitted, Lost (reason picker, Other → note, revive date), Cancel admission, Reopen (open-stage picker) and Undo admission flows on the Pipeline card and from board drags (board in 1.12).
- **Settings & permissions:** permission keys `conversion.mark`, `conversion.cancel` with scopes; labels "Admitted", "Lost", "Admission cancelled".

**Tasks**
- [ ] 1.08-T1 Implement `mark_lost` with reason rules and revive follow-up.
- [ ] 1.08-T2 Implement basic `mark_admitted` (transactional, idempotent).
- [ ] 1.08-T3 **Proposed:** create `conversions` records if approved; otherwise store on the lead only.
- [ ] 1.08-T4 Implement basic `cancel_admission` and `reopen_lead`.
- [ ] 1.08-T5 Implement "Undo admission" as one call with two history rows.
- [ ] 1.08-T6 Emit events and raise officer-notification requests via the outbox.
- [ ] 1.08-T7 Build the four flows on the Pipeline card.
- [ ] 1.08-T8 Register permissions and labels; add to role templates.

**Tests**
- RPC-as-real-role: mark admitted twice with the same key → one admission.
- Unit: Lost with "Other…" without note refused; reopen to a closed stage refused.
- Role matrix: `conversion.mark` / `conversion.cancel` per scope.
- UI: lost with revive date shows a revive follow-up on that date in Today.

**Done when (acceptance criteria)**
- A lost lead has a reason (and a note for Other) and an optional revive follow-up.
- Mark admitted ends pending follow-ups and shows the lead as closed; retrying never duplicates.
- Undo admission leaves two history rows and the lead in the chosen open stage.

**Watch-outs (do not miss)**
- Full admission and cancel side effects (batch / section required by setting, seat lock, papers block/warn/allow, eligibility, "pay now" minimum, fee lock, student ID, board-flow reset, seat release, fee unlock, refund flow, welcome message, Students tab) are Block 2 (Ch 17.5, 17.7, Ch 28–36); AI credit is Phase 4 (Ch 40).
- Partial admissions: database work in one transaction, external work via outbox (Ch 17.10 #1).
- Undo admission with payments needs a warning and refund/approval step; add when payments exist in Block 2 (Ch 17.10 #6).
- Vague "Other" reasons make reports useless; note required (Ch 17.10 #7).
- "♻️ Lost lead called you" on a missed call is built in 1.10.

**Owner checkpoint:** Owner loses, revives, reopens, admits and undoes admission on one lead and reads its history.

### 1.09 Notes, voice notes, timeline, delete and restore

**Goal:** Every note is its own row, voice notes are recorded and played, the lead's timeline is append-only, and mistaken deletes can be undone.

**Depends on:** 1.05, 1.07

**Plan chapters:** Ch 21 (21.1–21.8), Ch 16 (16.3 delete), Ch 15 (15.8 bulk note), Ch 51 (lesson 10), Ch 50 (T6).

**Decisions:** —

**Build**
- **Data:** `notes`, `voice_notes` from 1.01; storage bucket with paths starting with `institution_id`; partial indexes excluding deleted rows.
- **Server:**
  - `add_note(lead, body, idempotency_key)` (new row each time); `add_note_bulk(lead_ids, body)` used by bulk actions (1.12), one row per lead.
  - Voice notes: upload AAC 64 kbps, max 1 hour (~28 MB); stored in platform storage (Supabase Storage) because Google Drive arrives in Block 2 (Ch 32). **Proposed:** keep platform storage as the fallback when Drive is missing or broken after Block 2. File list kept in the database and linked to the related call.
  - `get_timeline(lead, cursor, filter)`: paginated, merges notes, voice notes, calls (manual and later synced), WhatsApp logs, template messages (Block 1B), campaign messages (Block 1B), stage changes, visits, assign / hand-over, import "re-enquiry" lines (1.14) and public-form lines (Block 1B); filter phone / WhatsApp.
  - Timeline is append-only: no updates to old entries; deletion is a soft-delete mark.
  - Delete rules: holders of the module `delete` permission with scope delete any entry any time; the author may delete their own entry within 24 hours; only app-written entries (notes, manual calls, voice notes) can be deleted; synced calls never (Phase 3).
  - Restore: the deleter can Undo within 10 minutes; admins restore any time from the lead's Changes fold. Every delete and restore is written to the change log (who, when, what).
  - Lead soft delete via `lead.delete` with Undo toast. **Proposed:** a "Deleted" filter on the list and restore from the change log, showing who deleted and when (Ch 21.6).
  - **Proposed:** warn when a note contains a phone-number pattern (Ch 21.7 #5).
- **App & web:** note box on lead page, peek and call popup (1.10); mic button next to every note box; player with 1x / 1.5x / 2x; timeline fold with filter; Undo toast; Deleted filter (Proposed).
- **Settings & permissions:** `note.delete`, `call_log.delete` (scoped) in the registry; 24 h and 10 min are constants until the owner answers Ch 21.8's open question.

**Tasks**
- [ ] 1.09-T1 Implement `add_note` and `add_note_bulk`.
- [ ] 1.09-T2 Implement voice-note recording (AAC 64 kbps, 1 h cap), upload with retry and "upload pending" mark, and playback speeds.
- [ ] 1.09-T3 Set up the institution-prefixed storage bucket with RLS and add it to the leak test.
- [ ] 1.09-T4 Implement `get_timeline` with pagination and filters.
- [ ] 1.09-T5 Implement delete rules (admin any time, author 24 h, app entries only).
- [ ] 1.09-T6 Implement 10-minute Undo and admin restore; log every delete / restore.
- [ ] 1.09-T7 Implement lead soft delete with Undo toast.
- [ ] 1.09-T8 **Proposed:** implement the "Deleted" filter and lead restore.
- [ ] 1.09-T9 **Proposed:** implement the phone-pattern warning in note boxes.
- [ ] 1.09-T10 Build the timeline fold and note / voice UI on lead page and peek.

**Tests**
- RLS + leak: notes and voice-note files of institution A unreachable from B (table and storage path).
- RPC-as-real-role: author deletes own note at 23 h (ok) and 25 h (refused); admin deletes any.
- Unit: timeline merge order and cursor paging.
- UI: record a 30-second voice note offline, reconnect, it uploads; Undo restores within 10 minutes.
- Performance: timeline of a lead with 500 entries pages without slowdown.

**Done when (acceptance criteria)**
- Two users adding notes at the same time both keep their notes.
- A deleted note is restorable by an admin and its delete appears in Changes.
- A voice note plays at 1x / 1.5x / 2x and is linked to its call.

**Watch-outs (do not miss)**
- Soft delete plus append-only timeline is the first protection; whole-database backups cannot restore one institution (Ch 21.4, risk T6, lesson 10).
- Long voice uploads on weak networks: save locally first, queue and retry (the general offline queue is Block 1B, Ch 47).
- "Own delete within 24 h" can hide bad work; soft delete keeps it in the change log; frequent deletes shown in team activity in Phase 4 (Ch 21.7 #6).
- Permanent deletion after retention is a job in Block 1B (Ch 44) / Phase 0 data-protection rules (Ch 5).
- Never send note text to AI without de-identification (Phase 4, Ch 40).

**Owner checkpoint:** Owner adds text and voice notes, deletes and restores one, and reads the timeline with the phone / WhatsApp filter.

### 1.10 Calls and WhatsApp: manual logging, call popup and post-call rules

**Goal:** Counsellors call and open WhatsApp from the app (also with masked numbers), record every outcome in a few taps, and the lead's counters and follow-ups update automatically.

**Depends on:** 1.06, 1.08, 1.09

**Plan chapters:** Ch 19 (19.1–19.6, 19.9 talk time, 19.11 #1, #2, #5, #6, #7), Ch 20 (20.1–20.4, 20.6, 20.7 module, 20.8 #3, #4, #6), Ch 18 (18.3, 18.5).

**Decisions:** D24; WhatsApp in phase 1 is **Proposed** (Ch 20.9, Ch 52.10).

**Build**
- **Data:** `call_logs` from 1.01; index on (`institution_id`, user_id, at) and (`institution_id`, lead_id, at); **Proposed:** daily summary table for talk time (Ch 19.11 #7).
- **Server:**
  - `save_phone_call(lead, outcome, duration?, note, rating?, next_call, direction, at, idempotency_key)`: one RPC for popup and manual logs; source `app`; designed so the Phase 3 synced copy can be matched to it without duplicates.
  - Post-call trigger: set `last_contacted_at`; auto-done today's or overdue follow-up (any outgoing or any connected call, rule from 1.06); count unanswered attempts in `call_attempts`; after N attempts (default 5) set `unreachable_at` and create a retry follow-up after N days (both numbers in `call_sync`); a missed incoming call creates a "call back" follow-up and a `missed_call` notification request; a missed call from a lost lead raises "♻️ Lost lead called you"; closed leads' attempts are not counted.
  - Calls cannot be edited; one added note within 24 hours. **Proposed:** admin-approved outcome correction keeping the old value in the change log (Ch 19.11 #5).
  - WhatsApp manual log: `call_logs` with channel `whatsapp`, media `voice` / `video` / `message`, direction in / out, source `app`; own WhatsApp entries deletable within 24 hours.
  - `talk_time_report(day, user)`: per-person daily talk time from manual durations, flagged "manual / estimated".
- **App & web:**
  - Call from card, lead header, round button, peek and `dial` link; masked users dial through `get_dial_target` (no number shown or copyable).
  - Call popup on return to the app: outcome, note, rating, next call pre-filled from the outcome table, 🎙 voice note; offers to reopen a lost lead when connected; never hidden by the keyboard; draft kept if closed without saving.
  - "+ Log call" for calls made from other phones: outcome, time, note, next call.
  - WhatsApp button (card, lead page, peek): opens by WhatsApp number, else phone; username-only leads open the WhatsApp app; masked users open it from the app. Pre-filled template text arrives with Block 1B (Ch 24, D6); the do-not-contact warning on the WhatsApp button arrives with Block 1B consent (Ch 24).
  - "Log WhatsApp" (call or message, in / out, voice / video) and the `waCall` view.
  - "Ask after WhatsApp": on return from WhatsApp, ask what happened (call / message, outcome, note, next call); on/off via `call_sync`.
  - WhatsApp calls screen (More → TOOLS; More menu finalised in Block 1B): Today / 7 / 30 days, calls or messages, delete own entry within 24 h.
  - Talk-time line for the user's "today stats" (Home placement in Block 1B).
- **Settings & permissions:** `call_sync` subset used now (attempts before unreachable, retry days, ask after WhatsApp); module "WhatsApp log" (Ch 9, Proposed in Standard plan) gates WhatsApp features; obsolete keys `max_call_attempts` and `call_log_lock_hours` are not created.

**Tasks**
- [ ] 1.10-T1 Implement `save_phone_call` with idempotency and validation of the fixed outcome list.
- [ ] 1.10-T2 Implement the post-call trigger (last contact, auto-done, attempts, unreachable + retry follow-up, missed → call back + notification, lost-lead missed call, closed leads skipped).
- [ ] 1.10-T3 Implement the 24-hour add-note-once rule on calls.
- [ ] 1.10-T4 Build the dial path (normal and masked) from all call entry points.
- [ ] 1.10-T5 Build the call popup with outcome defaults, voice note, lost-lead reopen offer, draft keeping.
- [ ] 1.10-T6 Build "+ Log call".
- [ ] 1.10-T7 Build the WhatsApp open action (number / phone / username rules) gated by the module.
- [ ] 1.10-T8 Build "Log WhatsApp", the `waCall` view and "Ask after WhatsApp".
- [ ] 1.10-T9 Build the WhatsApp calls screen with 24-hour own delete.
- [ ] 1.10-T10 Implement `talk_time_report` (and the Proposed daily summary table if approved).
- [ ] 1.10-T11 Register `call_sync` keys used now and the WhatsApp module gate.
- [ ] 1.10-T12 Write the institution-facing note on masking limits (dialer / WhatsApp chat show the number).

**Tests**
- RPC-as-real-role: five `no_answer` logs → `unreachable_at` set and a retry follow-up exists; a connected call marks today's follow-up done.
- Unit: outcome → next-call defaults; closed lead not counted.
- Leak: call logs and WhatsApp logs of A invisible to B.
- UI (Maestro): call → return → popup → save; masked user dials without seeing the number; Ask after WhatsApp appears and logs.
- Screenshot: popup with keyboard open, light/dark × bn/en.
- Performance: talk-time report on the benchmark set with `jit = off`.

**Done when (acceptance criteria)**
- Every call from the app ends with a popup that saves outcome, note and next call in under 5 taps for the common case.
- A manual missed incoming call creates a call-back follow-up at the top of Today.
- The WhatsApp calls screen lists the user's WhatsApp entries for Today / 7 / 30 days.

**Watch-outs (do not miss)**
- Phase 1 runs entirely on manual logging; auto mode, call-log sync, ±10-minute sync matching, call lock ("📵 X is on a call"), incoming-call lock and caller card are Phase 3 (Ch 19.7, 19.10, Ch 41) because of Google Play's call-log policy (risk O5, T11).
- Double-call warning (`double_call`): Ch 19.12 lists it for phase 1 but Ch 52.5 and the block plan put it in Phase 3 with call lock; owner to confirm (open question in Ch 19.12 also asks whether call lock is needed in phase 1).
- WhatsApp auto-log (notification listener), WhatsApp lock and WhatsApp reports in Team activity are Phase 3 / 4; the official WhatsApp Business API is "later" (Ch 20.7).
- The outcome list is fixed; only labels change (Ch 19.11 #6).
- The weekday × hour heatmap belongs to the team reports in Phase 4 (Ch 19.9, Ch 38).
- Offline call saves are queued by the general offline queue in Block 1B (Ch 47); the idempotency key makes replay safe.

**Owner checkpoint:** Owner (or a pilot counsellor) makes ten calls and three WhatsApp contacts on a real Android phone and reviews the resulting timeline, Today list and talk time.

### 1.11 Reminders, speed-to-lead escalation and quiet hours

**Goal:** Remind the right person before a follow-up is due, escalate new leads nobody called, and never disturb people in quiet hours.

**Depends on:** 1.06, 1.10

**Plan chapters:** Ch 18 (18.7, 18.8 #1, #2, #4), Ch 14 (14.9 notification `assigned` quiet-hours option), Ch 16 (16.7 #4 view cleanup), Ch 51 (lesson 2).

**Decisions:** D1, D5

**Build**
- **Data:** `notification_requests` dedupe key (user, type, subject, window); job-run table with attempts, back-off and "given up".
- **Server:**
  - Job `notifications_tick` every minute: picks only institutions whose time has come, in small batches with a fair share per institution, attempts and back-off; evaluates each institution in its own time zone and settings.
  - It runs: follow-up reminders (`early_reminder_minutes` before due, then `repeat_reminder_minutes`), visit reminders (rules added by 1.13), speed-to-lead escalation, release of items held by quiet hours, and cleanup (60 days; also old `lead_views`).
  - Speed-to-lead: a new lead with no call after `speed_to_lead_minutes` → assignee; after `escalate_team_lead_hours` → team lead; after `escalate_admin_hours` → admins; recipients are users whose role has the behaviour switch "receives escalations"; once per lead per level.
  - Channels come from the Master Admin type × recipient × channel matrix (D5, Phase 0); example default for `speed_to_lead`: push, then SMS (D1). In this block SMS and email go through the Phase 0 outbox and adapters; inbox and push delivery are added by Block 1B (Ch 25, Ch 42) and pick up the same requests.
  - `quiet_hours` (default 22:00–08:00) delays push and also applies to SMS; option to send `assigned` immediately.
  - Notification types `follow_up`, `speed_to_lead`, `missed_call`, `visit`, `assigned`, `auto_assigned`, deduplicated per user and type.
  - Built on pg_cron as a minimal runner; Block 1B's per-institution job scheduler (Ch 44) takes it over without changing the job's contract.
- **App & web:** Settings → LEADS (or Notifications) for the minute/hour values; preview text in the matrix for the new types.
- **Settings & permissions:** register `speed_to_lead_minutes`, `early_reminder_minutes`, `repeat_reminder_minutes`, `escalate_team_lead_hours`, `escalate_admin_hours`; read `quiet_hours` and the working calendar (Phase 0); behaviour switch "receives escalations".

**Tasks**
- [ ] 1.11-T1 Implement the job-run table and runner with attempts, back-off, "given up" and per-institution fair batching (lesson 2).
- [ ] 1.11-T2 Implement follow-up reminders (early + repeat) with dedupe.
- [ ] 1.11-T3 Implement speed-to-lead escalation levels and the behaviour switch.
- [ ] 1.11-T4 Implement quiet-hours hold and release for push and SMS, with the "assigned immediately" option.
- [ ] 1.11-T5 Route requests through the recipient matrix to SMS / email (Phase 0 adapters) and leave inbox/push for Block 1B.
- [ ] 1.11-T6 Implement the 60-day cleanup and `lead_views` cleanup.
- [ ] 1.11-T7 Register the settings keys and build their settings fields.
- [ ] 1.11-T8 Add a job health view for Master Admin (last run, lag, given-up count) using Phase 0 observability.

**Tests**
- Unit: reminder windows across institution time zones; quiet hours crossing midnight.
- Integration (fake SMS adapter): a new lead uncalled for X minutes produces exactly one escalation per level; nothing is sent at 02:00 institution time.
- Load: 300 institutions × benchmark data; one large institution does not delay others' reminders beyond one tick.
- RPC-as-real-role: escalation recipients limited to the behaviour switch.

**Done when (acceptance criteria)**
- A follow-up due at 15:00 with `early_reminder_minutes = 15` creates a reminder at 14:45 institution time, once.
- Escalation goes assignee → team lead → admins at the configured times and stops once the lead is called.
- No SMS leaves during quiet hours; held items go out at the end of quiet hours.

**Watch-outs (do not miss)**
- One big institution must not delay everyone; fair share and small batches (Ch 18.8 #1, risk T7).
- Wrong time zone means 2 a.m. SMS; compute everything server-side in the institution zone (Ch 18.8 #2).
- Escalation SMS costs money and gets ignored if repeated; once per lead, SMS only if Master Admin turns it on (Ch 18.8 #4).
- Queue rules from lesson 2: attempts, back-off, given up, no re-claim loops, no empty kicks.

**Owner checkpoint:** Owner sees a test escalation chain arrive by SMS/email on the test institution and confirms quiet hours hold messages overnight.

### 1.12 Filters, saved filters, bulk actions and board view

**Goal:** Let admins and team leads slice the lead base, act on many leads safely, and see the pipeline as a board.

**Depends on:** 1.04, 1.06, 1.07, 1.08, 1.09

**Plan chapters:** Ch 15 (15.4, 15.6, 15.8, 15.9, 15.11 #3, #5, #6, #7), Ch 21 (21.2 bulk note).

**Decisions:** D9

**Build**
- **Data:** `saved_filters` (owner, shared flag, filter JSON with keys / ids); `bulk_jobs` (user, action, lead count, progress, skipped count, status).
- **Server:**
  - Filter JSON engine on the server. **Proposed:** the same engine is used by list, export, segments and campaigns (Block 1B reuses it for bulk SMS recipients, Ch 26).
  - Phase-1 filters: next call, rating, stage, tags, assignee (or unassigned), source, offering, campaign, lead type, date added, last contact, lost reason, campus visit (1.13 adds the visit fields), contact type, "filterable" custom fields. **Proposed:** branch filter when branches are on. Later filters: AI chance (Phase 4), admission window (Block 1B, Ch 27), papers, fee / payment, batch, "Not eligible" (Block 2).
  - Filters of disabled modules are hidden; admins choose which filters show and their order (setting `lead_filters`).
  - Saved filters personal or shared by admins; missing fields / stages in a saved filter are shown as dropped conditions with a clear mark, never silently ignored.
  - Bulk: select by long-press or "mark all matching" (max 2,000); confirm with the count; actions note, stage, tags, assign / hand over, next call, rating, lost, offering (admins only); runs in chunks of 200 with % progress and cancel; leads the user cannot edit are skipped and the skipped count shown; each lead gets its own timeline and change-log entry.
  - **Proposed:** undo of the last bulk action (Ch 15.11 #3). Large bulk deletes go through the approval engine (`lead.delete` policy) when Block 1B delivers it.
  - Quick menu (one or many leads): rating, stage, tags, assign, follow-up, note.
  - Board: one column per stage, same search / filter / sort as the list, lazy-loaded columns, paging per column, closed columns hidden on phones by default, columns with `course_ids` apply only to matching leads; dragging applies stage rules (note, date, admit / lost flows); setting `board` (on / off, show closed columns, who can use it).
- **App & web:** filter sheet, saved-filter picker, selection mode, bulk progress sheet, quick menu, board view (phone and web).
- **Settings & permissions:** register `lead_filters` and `board`; offering bulk change admin-only.

**Tasks**
- [ ] 1.12-T1 Implement the filter JSON schema and server engine used by `list_leads`.
- [ ] 1.12-T2 Implement each phase-1 filter and module-based hiding.
- [ ] 1.12-T3 **Proposed:** implement the branch filter.
- [ ] 1.12-T4 Implement `lead_filters` (visibility and order) and its settings screen.
- [ ] 1.12-T5 Implement saved filters (personal / shared) with dropped-condition marking.
- [ ] 1.12-T6 Implement selection and "mark all matching" (2,000 cap) with count confirmation.
- [ ] 1.12-T7 Implement bulk actions in 200-lead chunks with progress, cancel and skipped count, writing per-lead timeline / change entries.
- [ ] 1.12-T8 **Proposed:** implement undo of the last bulk action.
- [ ] 1.12-T9 Build the quick menu.
- [ ] 1.12-T10 Implement the board with lazy columns, per-column paging and drag rules.
- [ ] 1.12-T11 Implement setting `board` and phone default of hidden closed columns.
- [ ] 1.12-T12 Re-run the ≈3,000-lead benchmark with three filters combined.

**Tests**
- RPC-as-real-role: bulk stage change over 2,000 leads where 300 are not editable → 1,700 changed, 300 reported skipped.
- Leak: shared saved filters of A invisible in B; filter results respect scope.
- Unit: filter JSON validation; saved filter with a deleted custom field shows the dropped mark.
- UI: board drag into a `note_required` stage asks for the note; drag to Lost opens the lost flow.
- Performance: combined filters and board columns on the benchmark set within budget.

**Done when (acceptance criteria)**
- Admin can hide and reorder filters; disabled-module filters never show.
- Bulk actions show progress, can be cancelled, and every changed lead has its own timeline line.
- The board shows per-stage columns, loads lazily, and enforces stage rules on drag.

**Watch-outs (do not miss)**
- A wrong 2,000-lead bulk action does big damage: count confirmation, per-lead entries, Proposed undo (Ch 15.11 #3).
- Many filters plus RLS slow the list; keep `user_access` simple `IN` checks and `institution_id`-leading indexes (Ch 15.11 #1).
- Board with many stages and cards will not run on phones without lazy columns and paging (Ch 15.11 #7).
- Bulk fee, placement, board-flow "received" and AI check actions arrive with Block 2 and Phase 4.

**Owner checkpoint:** Owner builds and shares a saved filter, runs a bulk assign on 500 leads, and uses the board on phone and web.

### 1.13 Campus visits and the lead score

**Goal:** Plan and track visits with reminders and stage effects, and give every lead an explainable 0–100 score that works without AI.

**Depends on:** 1.07, 1.10, 1.11, 1.12

**Plan chapters:** Ch 22 (22.1–22.3, 22.5, 22.6), Ch 15 (15.5 visit / score sort), Ch 18 (18.7 visit reminders).

**Decisions:** —

**Build**
- **Data:** `appointments` (lead, status planned / visited / missed / cancelled, at, `branch_id`, created_by); partial unique index "max one planned per lead"; `lead_score_reasons` (lead, rule, points); settings version for `lead_score`.
- **Server:**
  - Visits: plan, mark visited / missed / cancelled; walk-in recorded directly as visited; optional stage effect "New or Contacted → Interested" (setting; stages identified by id / kind, not key); missed visit → follow-up after N days (default per type profile, open question Ch 22.6); reminders on the visit day from 09:00 and 1 hour before (type `visit`, through 1.11's tick, respecting quiet hours and holidays); visit branch recorded; warning when a visit is planned on a non-working day.
  - Lead-facing visit reminder SMS / email and template variables `{visit_time}` and branch map link come with Block 1B (Ch 24).
  - Lead score: base 30 plus points for visit done, visit planned, fee discussed (signal active once the Fee module exists, Block 2), answered call, stage, referral source, hot / cold rating; minus points for 7 days silent, 30 days silent, 3 misses in a row, wrong number; Admitted = 100, Lost = 0; every point stores its reason.
  - Recalculate on every lead change (trigger) and nightly per institution in its time zone, in batches with fair share (time-based signals only at night); recalculate all leads after a `lead_score` settings change, with settings versioning.
- **App & web:** Visit card on the lead page; quick "walk-in" button for reception (search by phone; create a lead if none); "Today's visits" card component and visit count for today stats (placed on Home by Block 1B); "Why this score" on the lead page; score chip 🔥 70+, 🙂 40–69, ❄️ < 40 on cards; score and visit-date sort and filter; help text explaining score vs. AI chance; Settings → LEADS → Campus visit; Settings → ADMISSIONS → Lead score.
- **Settings & permissions:** register `campus_visit` (or its neutral name decided in Phase 0) and `lead_score`; label `appointment` variants (Campus visit, Visit, Demo class, Counselling session, Office visit); module gate (visits in Standard plan, Ch 9).

**Tasks**
- [ ] 1.13-T1 Implement appointment RPCs, one-planned rule, walk-in, branch.
- [ ] 1.13-T2 Implement the stage effect setting and the missed-visit follow-up.
- [ ] 1.13-T3 Add visit reminders to `notifications_tick`.
- [ ] 1.13-T4 Build the Visit card, walk-in button and Today's visits component.
- [ ] 1.13-T5 Implement the score engine with stored reasons and the change trigger.
- [ ] 1.13-T6 Implement the nightly recalculation and settings-change recalculation with versioning.
- [ ] 1.13-T7 Build "Why this score", the score chip, score / visit sorts and filters.
- [ ] 1.13-T8 Build the two settings screens and register labels.
- [ ] 1.13-T9 Write help text distinguishing lead score from AI chance.

**Tests**
- Unit: score examples (base, each signal, each deduction, fixed values) match a table checked into the repo.
- RPC-as-real-role: second planned visit refused; walk-in creates a visited appointment.
- Time-based: reminders at 09:00 and visit − 1 h in the institution zone; none during quiet hours.
- Performance: nightly score job on 300 institutions × benchmark set finishes inside its window without blocking reminders.
- Screenshot: score chip and visit card light/dark × bn/en.

**Done when (acceptance criteria)**
- A lead can have only one planned visit; walk-ins are recorded in two taps.
- Missing a visit creates a follow-up N days later.
- The lead page explains every point of the score; Admitted shows 100 and Lost 0.
- Changing score points recalculates all leads.

**Watch-outs (do not miss)**
- Score rules and the visit stage effect reference stages by kind or id, never keys (Ch 22.3).
- Nightly job must batch per institution (Ch 22.5 #1); recalc after settings change (Ch 22.5 #2).
- One planned visit is not enough for other industries; the neutral key is ready, multiple appointments later via packs (Ch 22.5 #5).
- A wrong ❄️ makes counsellors drop good leads; always show reasons (Ch 22.5 #3).

**Owner checkpoint:** Owner plans, marks missed and walks-in visits, and checks three leads' scores and reasons.

### 1.14 Import, export and phone contacts

**Goal:** Bring leads in from Excel / CSV and phone contacts safely (mapping, dry run, duplicates, undo) and take filtered leads out to Excel.

**Depends on:** 1.03, 1.12, 1.13

**Plan chapters:** Ch 23 (23.1–23.4, 23.6, 23.7), Ch 14 (14.12 #4), Ch 50 (M1, T14, R9 partly).

**Decisions:** D24

**Build**
- **Data:** `import_batches` (user, file name, mapping, options, counts, status, created_at, undone_at); `import_rows` (row number, result, error reason, lead id, previous values for updates); `import_mappings` (saved per institution); contact-import batches reuse `import_batches` with kind `contacts`.
- **Server:**
  - Excel / CSV import (permission `lead.import`): automatic column detection with Bangla aliases ("নাম", "মোবাইল"), mapping to custom fields, saved mappings, preview and dry run (new / duplicate / error counts, nothing changed), phone normalisation with Bangla digits, duplicate handling by phone: skip / update (writes a "re-enquiry" timeline line) / create new; guardian matching by phone (reuse existing, else create; preview shows several guardian names on one phone); assignment none / one user / round robin over users with the "can be assigned leads" switch; default source and offering for the file; chunked processing with progress (driven chunk-by-chunk so no call exceeds Edge Function limits); error file (.xlsx with reasons); template file built from the institution's labels and custom fields; undo within 24 hours (new leads soft-deleted, updates restored to previous values). **Proposed:** before undo, warn "N new actions happened on these leads" and offer to exclude them (Ch 23.6 #8).
  - Duplicate checks during import look across all institution leads through the DEFINER function but show only name, stage and owner.
  - Phone contacts: pick one or several contacts or a whole contact group; set source "Phone contact", offering (required), tags, rating, assignee; existing numbers marked (all leads, name / stage / owner only); undo the whole batch within 24 hours; contacts permission asked only at that moment; who can use it is set by `contacts_import`.
  - Excel export (permission `lead.export` with scope): uses the list's current filter JSON; reads 1,000 rows per page; columns contact, offering, pipeline, visit, custom fields flagged "in export" (fee and board-flow columns added by Block 2); column names in the institution's labels; "Export my work" within the user's own scope.
  - The plan's active-lead limit applies to imports (1.03 rules).
- **App & web:** Import wizard (upload, mapping, preview, dry run, options, progress, result, error file, undo) on web and app; Settings → DATA → Import; Settings → DATA → Export; Settings → DATA → Phone contacts access; More → TOOLS → Phone contacts and "Export my work"; "Who" card on the Add form gains "pick from contacts"; lead import linked from the Phase 0 setup checklist.
- **Settings & permissions:** register `contacts_import`; `lead.import`, `lead.export` scopes ("export all" is sensitive).

**Tasks**
- [ ] 1.14-T1 Implement import batch / row / mapping tables with RLS and leak-test entries.
- [ ] 1.14-T2 Implement column auto-detection with Bangla aliases and custom-field mapping; saved mappings.
- [ ] 1.14-T3 Implement preview and dry run.
- [ ] 1.14-T4 Implement duplicate modes (skip / update + re-enquiry line / create) and guardian matching.
- [ ] 1.14-T5 Implement assignment modes incl. round robin over the behaviour switch.
- [ ] 1.14-T6 Implement chunked processing with progress and resumability.
- [ ] 1.14-T7 Implement the error file and the label-aware template file.
- [ ] 1.14-T8 Implement 24-hour undo (and the Proposed activity warning).
- [ ] 1.14-T9 Implement phone-contact import (single, multiple, group) with duplicate marks and batch undo.
- [ ] 1.14-T10 Add "pick from contacts" to the Add form's Who card.
- [ ] 1.14-T11 Implement Excel export from the current filter, 1,000-row paging, label column names, "Export my work".
- [ ] 1.14-T12 Build the Settings → DATA screens and More → TOOLS entries; link import from the setup checklist.
- [ ] 1.14-T13 Run a 10,000-row import and a 3,000-lead export on the benchmark institution and record times.

**Tests**
- RPC-as-real-role: import as a user without `lead.import` refused; export scope `own` returns only own leads.
- Leak: import batches and mappings of A invisible in B; duplicate marks never show B's leads.
- Unit: Bangla alias detection; phone formats (+880, 01…, spaces, Bangla digits) dedupe correctly.
- UI: full import wizard on web; contact-group import on Android; undo after 1 hour restores updated values.
- Performance: 10,000-row import completes in chunks without timeouts and without slowing another institution's list.

**Done when (acceptance criteria)**
- A messy institution Excel with Bangla headers imports after one mapping, and the mapping is reused next time.
- Dry run shows new / duplicate / error counts and changes nothing.
- Undo within 24 hours removes new leads and restores updated ones.
- Export opens in Excel with the institution's own column labels and respects the user's scope.

**Watch-outs (do not miss)**
- Export controls (approval above N rows `export.large`, export log, watermark, daily view / export limits with admin alert, masking in exports — Proposed) are Block 1B (Ch 23.5, Ch 11); do not release exports to counsellor roles before they land (risk R9).
- Large imports / exports as background jobs with a completion notification and short-lived signed download link use Block 1B's job scheduler and export pipeline (Ch 23.6 #3, #4).
- Promotional messages to contact-imported leads need the consent rules from Block 1B (Ch 24, Ch 23.6 #7).
- Alumni import is Phase 5 (Ch 37); course and staff Excel import belong to setup (Phase 0, Ch 6) and courses (Block 2, Ch 28); the whole-institution data export is Master Admin (Phase 0, Ch 5).

**Owner checkpoint:** Owner imports a real (anonymised) Excel from a pilot institution with dry run and undo, imports a phone-contact group, and exports a filtered list.

### 1.15 Lead merge (Proposed) and Phase 1A exit check

**Goal:** **Proposed:** merge two duplicate leads into one without losing history, then verify the whole block against its exit criteria.

**Depends on:** 1.14

**Plan chapters:** Ch 14 (14.7 merge, 14.12 #7, 14.13), Ch 53 (open question 6), Ch 52 (52.3 merge row, 52.9), Ch 50 (risks for this block), Ch 51 (lessons 1, 4, 8, 9, 10).

**Decisions:** — (merge is Proposed; open question Ch 53.2 #6 "keep; end of phase 1 or phase 2")

**Build**
- **Data:** **Proposed:** registry of lead-related tables (calls, notes, voice notes, follow-ups, stage history, appointments, tags, offerings, guardians, custom field values, stars, views, import rows; Block 2 registers fees, payments, papers, files); merge record (survivor, merged, by, at).
- **Server:** **Proposed:** `merge_leads(survivor, duplicate)` moves every registered related row to the survivor, keeps one pending follow-up, soft-deletes the duplicate, writes a timeline line on the survivor and a `lead.merged` event; **Proposed:** permission `lead.merge` (sensitive); merging an admitted lead or one with payments needs extra approval once the approval engine (Block 1B) and payments (Block 2) exist.
- **App & web:** **Proposed:** "Merge" from the duplicate panel and the lead page; side-by-side preview of both leads and the survivor's final values.
- **Settings & permissions:** **Proposed:** `lead.merge` in the registry and role templates (admin only by default).

**Tasks**
- [ ] 1.15-T1 Get the owner's answer on Ch 53.2 #6; if "Phase 2", move T2–T6 to Block 2 and keep only the exit check here.
- [ ] 1.15-T2 **Proposed:** build the related-table registry and a test that fails when a new lead-linked table is not registered.
- [ ] 1.15-T3 **Proposed:** implement `merge_leads` in one transaction with idempotency.
- [ ] 1.15-T4 **Proposed:** build the merge preview and confirm UI.
- [ ] 1.15-T5 **Proposed:** add `lead.merge` to the registry and templates.
- [ ] 1.15-T6 **Proposed:** add merge to the leak test and role matrix.
- [ ] 1.15-T7 Run the full block regression: role matrix, leak test, invoker/DEFINER sweep, RPC-as-real-role suite.
- [ ] 1.15-T8 Run the ≈3,000-lead benchmark for list, search, lead page, Today, board, timeline and compare with 1.04's baseline.
- [ ] 1.15-T9 Run the UX quality checklist (Ch 47) on every new screen, phone and web, light/dark × bn/en.
- [ ] 1.15-T10 Walk the risk list (Ch 50) rows for this block and record status.
- [ ] 1.15-T11 Confirm every label added in this block exists in bn and en with no hard-coded strings (lint).
- [ ] 1.15-T12 Write the "deferred from 1A" list for Blocks 1B, 2 and 3–5 and check each item is in their milestones.

**Tests**
- RPC-as-real-role: **Proposed:** merge two leads with calls, notes and follow-ups; survivor has all rows, duplicate soft-deleted, one pending follow-up.
- Leak: merge across institutions refused.
- Full regression suites and screenshots as listed in T7–T9.

**Done when (acceptance criteria)**
- Either merge works as described (if approved) or the owner's decision to move it is recorded and the item sits in Block 2.
- Every exit criterion in the block summary is checked and passed.
- The deferred list is complete and accepted by the coordinator.

**Watch-outs (do not miss)**
- Adding merge later means moving calls, fees, payments and papers; the registry design avoids rewrites (Ch 14.12 #7).
- Lessons 1, 4, 8, 9, 10 must be visibly enforced in CI and review checklists before exit.

**Owner checkpoint:** Owner decides on merge timing, sees a merge demo (if approved), and signs off the Phase 1A demo on a pilot institution.

## Phase 1B: Messaging, public pages and platform features

This block turns the phase-1 CRM into a product institutions can run on their own: message templates with consent and opt-out, notifications on every channel (inbox, push, email, SMS through the outbox), bulk SMS campaigns, the public application form at `/apply/<slug>` with admission windows and a custom domain, the remaining parts of roles v2 (field masking, export controls, approval engine, delegation, collaborators, access review), the institution switcher and groups, automation rules and outgoing webhooks, and the platform work around them (per-institution job scheduler, export snapshots, fake adapters, crash collection, update banner and minimum version, feature flags, offline queues and caching, Home / More / Settings and the website).
Exit criteria: every milestone below is done; the cross-tenant leak test covers every new table, RPC, public function, storage path, Realtime channel and the group dashboard; the role-matrix test covers every new permission; the ≈3,000-lead benchmark is not slower than at the end of Block 1A; one beta institution has run a full admission week (form → lead → template message → follow-up → campaign) on live SMS and email.

### 1.16 Per-institution job scheduler, run log and export snapshots

**Goal:** Run every scheduled job per institution, in that institution's own time zone and calendar, in fair batches with a run log; add per-institution export snapshots for disaster recovery.

**Depends on:** Phase 0; Block 1A (follow-up reminders, speed-to-lead, lead score jobs that move onto this scheduler).

**Plan chapters:** Ch 44 (44.1–44.6), Ch 4 (4.9, 4.11), Ch 13 (13.5 inputs: working days, holidays, quiet hours), Ch 50 (T6, T7, M8), Ch 51 (lessons 2, 3).

**Decisions:** D1, D5 (indirect). **Proposed:** the whole per-institution scheduler design, catch-up and delay alerts (Ch 44.6).

**Build**
- **Data:** job registry (job key, interval, owning module key, "runs in local time" flag, priority); per-institution job state (`institution_id`, job key, `next_due_at`, `last_success_at`) with an index on `next_due_at`; queue items with `institution_id`, attempts, `next_attempt_at`, status (pending / running / done / given_up), lease expiry and idempotency key; job run log (`institution_id`, job key, started, finished, item count, error); `export_snapshots` (`institution_id`, taken at, storage path, size, table list, status); snapshot storage bucket with `institution_id` as the first path segment and RLS.
- **Server:** one pg_cron tick that selects only due institutions with a cheap indexed query, checking time zone (IANA), working days, holidays, quiet hours, settings, module enabled and institution status; round-robin batches per institution; a kick only when work is waiting; Edge Function budget (150 s limit, every external call ≤ 75 s, new work only in the first 45 s); `x-cron-secret` kept in Vault, rotatable, plus internal-network or signature check; catch-up after a pause (jobs idempotent); suspended / read-only / closed institutions skip message-sending jobs while OTP and required maintenance still run; snapshot job (daily or weekly per institution) writing a full export including custom and extension tables.
- **App & web:** Master Admin panel: job run log per institution and "last successful run" age per job (feeds the health dashboard in 1.33).
- **Settings & permissions:** platform-side only (Master Admin, Developer read). Snapshot frequency (daily / weekly) as a platform setting per institution.

**Tasks**
- [ ] 1.16-T1 Write the job registry and seed it with every job from Ch 44.2–44.3, each tagged with its owning module and phase (jobs of later phases stay disabled).
- [ ] 1.16-T2 Migration: per-institution job state, queue table (attempts, back-off, given_up, lease, idempotency key) and run log, all with `institution_id` first in indexes, RLS on, Master Admin read policy.
- [ ] 1.16-T3 Implement the "who is due" query (time zone, working days, holidays, quiet hours, module on, institution status) and prove it uses the index (EXPLAIN in a test).
- [ ] 1.16-T4 Implement fair round-robin batching across institutions and per-provider limits hook (used by the outbox and campaigns).
- [ ] 1.16-T5 Implement claim with lease, back-off (no immediate retry), given_up after N attempts, and no endless re-claim of stuck items.
- [ ] 1.16-T6 Implement "kick only if work exists" for Edge Function workers; enforce the 150 s / 75 s / 45 s time budget in a shared worker helper.
- [ ] 1.16-T7 Move `x-cron-secret` into Vault, add rotation, and verify the caller in every worker.
- [ ] 1.16-T8 Move existing jobs onto the scheduler: `lead-notifications` (`notifications_tick`: held push after quiet hours, follow-up and visit reminders, speed-to-lead escalation, 60-day cleanup, every minute) and `lead-scores-nightly` (02:10 institution time) from Block 1A; integration health checks and any phase-0 subscription-expiry job from Phase 0.
- [ ] 1.16-T9 Status rules: skip message-sending jobs for suspended, read-only and closed institutions; always run OTP and maintenance.
- [ ] 1.16-T10 Catch-up: after a pause, process overdue work once (no duplicates) and record reminder delay per run.
- [ ] 1.16-T11 Run log writing (institution, start, end, items, error) and a "last successful run older than X" alert hook (surfaced in 1.33).
- [ ] 1.16-T12 Snapshot job: per-institution full export (all tenant tables incl. `custom_field_values`, custom and extension tables) to the snapshot bucket; retention rule; checksum.
- [ ] 1.16-T13 Write and rehearse the "restore one institution from a snapshot" runbook into a scratch project.
- [ ] 1.16-T14 Add the code-review checklist line: every new queue or job declares attempts / back-off / given_up / idempotency (Ch 51.3).

**Tests**
- Unit: due-selection for institutions in `Asia/Dhaka` and one DST zone, on a working day, a holiday and inside quiet hours.
- Queue: same item delivered twice runs once; lease expiry re-claims once; back-off delays grow; item reaches given_up after N failures; empty queue sends no kick.
- Fairness: an institution with 10,000 due items and one with 10 — the small one finishes in the first cycle.
- Status: suspended institution gets no reminder or SMS job but its OTP still sends.
- Module: disabling a module stops its job for that institution only.
- RLS + cross-tenant leak: run log, queue and snapshot bucket readable only by the owning institution / platform roles.
- RPC-as-real-role: workers and run-log RPCs tested as the real signed-in role, not the owner.
- Restore drill: one institution's snapshot restores into a scratch database with matching row counts.

**Done when (acceptance criteria)**
- Follow-up reminders fire at the right local time in two seeded institutions with different time zones.
- No job sends messages during quiet hours or on holidays unless the job is marked urgent.
- A large institution's backlog never delays a small institution's reminder by more than one scheduler cycle.
- Each job has a run log row per institution per run, visible to Master Admin.
- A snapshot exists for every active institution at the configured frequency and one restore drill has passed.

**Watch-outs (do not miss)**
- Lesson 2: wrong daily counts, endless re-claim (it billed every 10 minutes before), immediate retry and empty kicks all cost money.
- Lesson 3: Edge Function 150 s limit.
- pg_cron runs inside the database: jobs must be idempotent and catch up after maintenance (Ch 44.5 #7).
- Never schedule in "Dhaka time" globally (the old version did); always the institution's IANA zone.
- `x-cron-secret` leak lets anyone run jobs (Ch 44.5 #6).
- Snapshots must include custom and extension tables (Ch 43.7 #8).

**Owner checkpoint:** Demo of reminders firing in two institutions with different time zones, the run log in the Master Admin panel, and a one-institution restore from a snapshot.

### 1.17 Sandbox and fake adapters in CI, adapter contract tests

**Goal:** Every adapter kind (SMS, email, push, webhook delivery, domain/SSL) has a fake ("mock") version for development and CI and a sandbox path, so no test ever sends real SMS, email or money.

**Depends on:** Phase 0 (integration hub, SMS and email adapters, outbox); 1.16.

**Plan chapters:** Ch 42 (42.2, 42.9 I3, I5, I8), Ch 50 (I3, I5, I8), Ch 52.3 (platform work row).

**Decisions:** D3, D22 (adapters stay settings-driven).

**Build**
- **Data:** fake provider entries in the provider list (kind = sms / email / push / webhook / domain), visible only in dev, CI and test institutions; a captured-messages table for fakes (`institution_id`, connection id, payload, result); sandbox data flag on rows created through sandbox connections.
- **Server:** fake adapters implementing the same functions as real ones (SMS: `send`, `balance`, `parse_status`; email: send, bounce; push: send, receipt; webhook: receive and sign check; domain: DNS/cert check), with configurable failure modes (timeout, wrong key, zero balance, delayed / missing delivery report, bounce); daily contract tests that run every real adapter against its provider sandbox.
- **App & web:** connection mode (sandbox / live / fake) shown clearly on every connection screen in the Master Admin panel.
- **Settings & permissions:** fakes cannot be selected for a live production institution.

**Tasks**
- [ ] 1.17-T1 Define the fake-adapter interface per kind, matching the real adapter function list exactly.
- [ ] 1.17-T2 Build fake SMS (single and bulk send, Unicode, masked / non-masked sender, balance, delivery report push and poll, failure modes).
- [ ] 1.17-T3 Build fake email (send, bounce, complaint) and fake push (send, receipt with dead-token result).
- [ ] 1.17-T4 Build fake webhook receiver (records signed requests; can answer slow / 500 / timeout) for 1.31.
- [ ] 1.17-T5 Build fake DNS / certificate checker for 1.30.
- [ ] 1.17-T6 Captured-messages table and a test helper "assert institution X sent N messages through connection Y".
- [ ] 1.17-T7 Wire fakes into CI and seeded test institutions (one per type profile); block fakes on live institutions.
- [ ] 1.17-T8 Daily sandbox contract-test job per real adapter (I5); failures raise a Master Admin alert.
- [ ] 1.17-T9 Mark sandbox-created data with the sandbox flag and keep it out of usage billing.
- [ ] 1.17-T10 Two-institution routing test (I1): A and B each send; each uses only its own connection.

**Tests**
- Unit: each fake reproduces each failure mode and the real adapter's error mapping turns it into a clear message.
- I1 routing test: institution A's message never goes through B's connection, including when A has no connection and the fallback setting is "nothing".
- Contract: nightly sandbox tests for every real adapter (scheduled, not blocking PRs).
- CI: the full suite runs with zero outbound calls to real providers (network egress check).

**Done when (acceptance criteria)**
- CI runs every messaging, campaign, webhook and domain test against fakes with no real provider call.
- Every connection screen shows its mode; a fake cannot be attached to a live institution.
- A broken provider sandbox raises an alert within one day.

**Watch-outs (do not miss)**
- I3: sandbox and live mix-ups send real SMS or money; mode must be stored and shown on every connection.
- I8: testing without real money or SMS is a phase-1 requirement, not optional.
- Lesson 12: no provider keys in CI config or code; fakes need none.

**Owner checkpoint:** Owner sees a CI run where a whole campaign and notification flow passes without sending a real SMS, and the connection screens with their mode labels.

### 1.18 Crash collection, speed check, app versions, update banner, minimum version and feature flags

**Goal:** See every crash and slow request tagged with institution and user, show staff when an update is ready, block too-old apps, and roll features out per institution (beta first) with fast rollback.

**Depends on:** Phase 0 (min app version mechanism, design system, CI); 1.16.

**Plan chapters:** Ch 46 (46.1, 46.3–46.8; not 46.2 chat), Ch 48 (feature flags, beta institutions, channel OTA, rollback — phase-1 row in Ch 52.3), Ch 50 (T5, T12, T13, M11), Ch 51 (lesson 7).

**Decisions:** D12, D13. **Proposed:** moving crash collection to phase 1 and keeping chat in phase 5 (Ch 46.8); automatic speed sampling (Ch 46.7 #6).

**Build**
- **Data:** `crash_reports` (`institution_id`, `user_id`, signature, app version, OTA update id, channel, device, screen name, first / last seen, count, status open / resolved, resolved-in version); `speed_reports` (`institution_id`, `user_id`, per-request timings, device, network); `app_installs` (`institution_id`, `user_id`, build, OTA update id, channel, last opened); `whats_new_entries` (version, bn text, en text, date) and per-user seen marks; per-institution feature flags as part of the module system (not the old `feature_flags` table); beta-institution marker; crash storage path prefixed with `institution_id`.
- **Server:** crash ingest RPC with signature de-duplication and reopen when a resolved signature appears in a newer version; error-spike detector feeding alerts; `min_app_version` check (institution setting plus platform minimum per release); flag evaluation function used by app and RPCs.
- **App & web:** JS global handler and error boundary; offline crash queue (max 20) sent with current screen name only; Speed check screen (More → HELP and web avatar menu) that runs common requests and shows average and slowest per request with "send to developer"; App versions screen for admins (More → ADMIN): each person's build, OTA, channel, last opened, outdated flagged; OTA banner "A new version is ready · Restart / Later" checked on open and resume, at most every 30 minutes; What's new shown once per new entry, full list in More → APP, bn and en; blocking "update required" screen below the minimum version; Developer-role error dashboard (crash list, filters by institution, version, status).
- **Settings & permissions:** `min_app_version` (single-value institution setting, Appendix A); permission for App versions screen (admin area, e.g. under `settings.users`); platform Developer role reads crashes and speed reports; flags managed by Master Admin.

**Tasks**
- [ ] 1.18-T1 Migrations for crash, speed, install, What's new tables with RLS (institution users write own rows; platform Developer / Support read all).
- [ ] 1.18-T2 JS global handler + error boundary; capture screen name, never form values.
- [ ] 1.18-T3 Offline crash queue capped at 20, flushed on reconnect; signature hashing.
- [ ] 1.18-T4 Crash ingest RPC: dedupe by signature, count, reopen on regression in a newer version.
- [ ] 1.18-T5 Error dashboard for the Developer role with institution, version and status filters; spike detector.
- [ ] 1.18-T6 Request timing middleware in the API client; Speed check screen and "send results" (stored as a speed report the Developer role can read).
- [ ] 1.18-T7 Install check-in on app open (build, OTA id, channel); App versions admin screen with outdated marker. ("Ask to update" is wired to the `app_update` notification in 1.22.)
- [ ] 1.18-T8 OTA update banner with Restart / Later and the 30-minute throttle.
- [ ] 1.18-T9 What's new: bilingual entries, shown once, full list in More; release checklist line "one entry per change".
- [ ] 1.18-T10 Minimum version gate: compare against max(institution `min_app_version`, platform minimum); blocking screen with store link.
- [ ] 1.18-T11 Store-update card data for old store builds missing a required native part (Home card rendered in 1.35).
- [ ] 1.18-T12 Per-institution feature flags in the module system, beta-institution marker, channel-based OTA (beta channel first) and a documented one-step rollback.
- [ ] 1.18-T13 Native crash hook placeholder for `takeNativeCrashes` (filled in phase 3, Ch 41).

**Tests**
- Unit: signature dedupe; regression reopen; 30-minute banner throttle; version comparison.
- RLS + cross-tenant leak: crash rows and crash storage per institution; an institution user cannot read another institution's crashes.
- RPC-as-real-role: crash ingest and install check-in as a signed-in caller.
- UI (Maestro): force a crash offline, reconnect, see one report; banner Restart / Later; blocked below minimum version.
- Screenshot: banner, What's new, Speed check, App versions in light/dark × bn/en.
- Flags: a flag on for a beta institution is off for others; rollback restores the previous behaviour.

**Done when (acceptance criteria)**
- A crash shows up in the Developer dashboard with institution, user, version, OTA id, device and screen within minutes; repeats increase the count instead of adding rows.
- An app below the minimum version cannot be used until updated.
- Admins can see who is on an outdated version.
- A feature can be switched on for one beta institution only and rolled back.

**Watch-outs (do not miss)**
- Lesson 7: old app versions stay in use; server decisions never trust client-sent institution or permissions; RPCs stay backward compatible.
- Ch 46.7 #2: crash reports carry screen names only, never lead data or form values.
- Ch 46.7 #4: OTA reaches everyone at once — beta channel first, fast rollback.
- `runtimeVersion` must be fixed so new JS never runs on an old native build (Ch 48).
- Do not build the feedback chat or developer inbox here (phase 5).

**Owner checkpoint:** Owner sees a crash from a test phone in the error dashboard, the update banner and What's new on a phone, and a feature enabled only for the beta institution.

### 1.19 Institution switcher, groups and group dashboard (D25)

**Goal:** One login for people in several institutions with a one-tap switcher, and institution groups with a read-only group dashboard for the group owner, with no data ever mixed.

**Depends on:** Phase 0 (`institution_members`, active-institution session, Master Admin panel, billing core); Block 1A (leads, mark admitted basics); 1.18.

**Plan chapters:** Ch 10 (10.3, 10.6 `choose_institution`, 10.10 #4), Ch 5 (5.3 Groups menu, 5.11, 5.17 #9), Ch 11 (11.15, 11.16 #7), Ch 9 (9.6 group invoice and group discount), Ch 45 (45.6 #8), Ch 50 (R19, T1).

**Decisions:** D25, D12. **Proposed:** the `choose_institution` app state (Ch 10.6).

**Build**
- **Data:** `institution_groups`, `institution_group_members`; group-owner role as a group-level role on top of `institution_members` (no migration of members); per-institution daily summary table (leads, admissions; collection column filled when payments arrive in phase 2) used by the group dashboard; optional group billing flag (one invoice, group discount).
- **Server:** login resolves memberships only from the verified email / phone on the server; switch RPC issues a new session for the chosen institution; group dashboard RPC checks membership per member institution and reads only summaries; group invoice generation when group billing is on.
- **App & web:** institution chooser list (name, logo, role) after login when there are several active memberships; last-used institution opens next time; switcher in the Home top bar, More (bottom) and web top bar; Master Admin → Groups screen; group dashboard (read-only, per institution side by side).
- **Settings & permissions:** register group-owner role and its read-only group report permission; Master Admin-only group management.

**Tasks**
- [ ] 1.19-T1 Add the `choose_institution` state to the app state machine (after `active` check, before loading data).
- [ ] 1.19-T2 Chooser screen and "last used" memory per user (stored server-side, not trusted for access).
- [ ] 1.19-T3 Switch RPC: verify membership, write the active institution into a new session, bump nothing else.
- [ ] 1.19-T4 On switch: clear request memo and per-user cache, unsubscribe all Realtime channels, reset directory and labels, reload branding.
- [ ] 1.19-T5 Switcher button in Home top bar, More and web top bar (only when more than one membership).
- [ ] 1.19-T6 Group tables and Master Admin → Groups screen (create group, add/remove institutions, assign group owner); audit every change.
- [ ] 1.19-T7 Group-owner role on the member table; no write permission in any member institution through this role.
- [ ] 1.19-T8 Per-institution daily summary job (on 1.16) feeding leads and admissions numbers.
- [ ] 1.19-T9 Group dashboard RPC and screen: one column per institution, read-only, no raw records, no drill-down into data the person is not a member of.
- [ ] 1.19-T10 Group billing option: one combined invoice and group discount on top of each institution's own plan (Ch 9).
- [ ] 1.19-T11 Extend the cross-tenant leak test with a two-membership user and a group owner.

**Tests**
- RLS + cross-tenant leak: a two-membership user sees only the active institution's rows in every table, RPC, storage path and Realtime channel; after switching, nothing from the previous institution remains in cache.
- Group leak test: the group owner gets only summary numbers; raw-record RPCs called with another member institution's id fail.
- RPC-as-real-role: switch and group dashboard RPCs.
- UI (Maestro + Playwright): login with two memberships → chooser → switch → data changes; one membership → direct open.
- Screenshot: chooser and group dashboard light/dark × bn/en.

**Done when (acceptance criteria)**
- A person in two institutions logs in once, picks one, and switches with one tap; the last used one opens next time.
- Master Admin can create a group and a group owner sees each institution's leads and admissions side by side without opening each institution.
- Each institution keeps its own slug, domain, sender ID and templates whatever the memberships.

**Watch-outs (do not miss)**
- Ch 10.10 #4 / Ch 45.6 #8: stale cache, Realtime channel or push from the previous institution leaks data — full reset on switch, cache keys include institution and user.
- Ch 11.16 #7 / Ch 5.17 #9: the group dashboard must read only per-institution summaries with a membership check per institution.
- Never pick the institution from client-sent ids (lesson 7).
- Payments column of the group dashboard stays empty / hidden until Block 2 payments.

**Owner checkpoint:** Owner logs in as a two-institution test user and switches; then views the group dashboard for a seeded group (school + college + coaching).

### 1.20 Message templates and variables

**Goal:** Institutions write their own SMS, WhatsApp and email templates with variables, staff send them in one tap from the lead page, and a template report shows what happens after sending.

**Depends on:** Phase 0 (hub SMS / email adapters, outbox, labels, locale); Block 1A (lead page, peek sheet, call popup, manual call log, manual WhatsApp, timeline); 1.17.

**Plan chapters:** Ch 24 (24.1–24.4, 24.7 #1–#3, #7–#9), Ch 13 (money and date formatting), Ch 12 (branch address / phone / map link).

**Decisions:** D6, D13, D22.

**Build**
- **Data:** `message_templates` (`institution_id`, owner user for personal templates, shared / personal, name, channel SMS / WhatsApp / email, email subject, body, category, offering filter, usage count, channel-specific variants allowed); template send log (template id, lead, channel, edited before send flag, sent at); institution info fields (name, address, map link, office phone) with branch overrides; seed data: six Bangla templates, plus bn and en templates per type profile.
- **Server:** variable resolver for every variable in Ch 24.3 (`{name}`, `{first_name}`, `{course}`, `{batch}`, `{batch_start}`, `{section}`, `{student_id}`, `{fee}`, `{full_fee}`, `{discount}`, `{final_fee}`, `{paid}`, `{due}`, `{next_installment}`, `{next_due_date}`, `{visit_time}`, `{next_call}`, `{papers_missing}`, `{my_name}`, `{my_phone}`, `{institute}`, `{address}`, `{map_link}`, `{office_phone}`, `{today}`) returning "missing" for empty values; locale-aware money (lakh grouping) and dates in the message language; SMS part counter (Unicode 70, GSM 160) and cost estimate from the connection's per-part price; send RPC (gateway path through the outbox, or "open app" path that only logs); template report RPC.
- **App & web:** template editor with live part count and cost, variable picker showing institution labels, preview for 3 sample persons; send flow from lead page, peek sheet and call popup: pick → preview → send (open SMS / WhatsApp app, or via gateway; email via the institution's email setup); More → Templates tile and TOOLS → Templates; Settings → DATA → Message templates; template report screen.
- **Settings & permissions:** setting key `message_templates`; permission `settings.messaging_templates` for shared templates (personal templates for any user who can message leads); labels for template categories and the screen names.

**Tasks**
- [ ] 1.20-T1 Migration for templates and send log with RLS (shared visible to institution; personal only to owner); audit trigger on shared-template changes.
- [ ] 1.20-T2 Institution info fields plus branch overrides used by `{address}`, `{map_link}`, `{office_phone}`.
- [ ] 1.20-T3 Variable resolver with "missing" detection; variables whose module is not live yet (fees, batch, student ID — phase 2) resolve as missing and are hidden from the picker until the module is on.
- [ ] 1.20-T4 Locale formatting for money (lakh grouping) and dates in the message's language.
- [ ] 1.20-T5 SMS part counter (Bangla 70 / English 160 per part) and cost estimate; warning when parts exceed a threshold.
- [ ] 1.20-T6 Editor UI with label-aware variable picker and 3-person preview.
- [ ] 1.20-T7 Send flow from lead page, peek sheet and call popup; block sending when a variable is missing.
- [ ] 1.20-T8 Gateway path enqueues to the outbox (with idempotency key) and records the delivery log; "open app" path only logs.
- [ ] 1.20-T9 Every send writes a call-log entry of type message and a timeline line (Block 1A tables).
- [ ] 1.20-T10 Seed six Bangla templates and per-type-profile bn / en templates.
- [ ] 1.20-T11 Usage counter and "edited before send" flag.
- [ ] 1.20-T12 Template report: sent count, edited-before-send count, reply within 7 days, stage change after, admission after — labelled "happened after", with the same-period average for comparison.
- [ ] 1.20-T13 Register settings entry, More tiles, permission and all labels; Settings search terms.

**Tests**
- Unit: resolver for every variable, missing detection, part counter on Bangla / English / mixed text, lakh formatting.
- RLS + cross-tenant leak: templates and send log; personal templates not visible to other users.
- Role-matrix: only roles with `settings.messaging_templates` can create / edit / delete shared templates.
- RPC-as-real-role: send RPC as a counsellor.
- UI (Maestro): lead page → template → preview → send via gateway (fake adapter) → timeline line appears.
- Screenshot: editor and preview light/dark × bn/en with long labels.

**Done when (acceptance criteria)**
- A counsellor sends a template from the lead page in at most three taps with name and course filled in.
- A template with an empty variable cannot be sent and says which variable is empty.
- The editor shows parts and cost before saving; Bangla text counts 70 characters per part.
- Every send is in the timeline and call log; the template report shows the five numbers.

**Watch-outs (do not miss)**
- Ch 24.7 #1: wrong or offensive text sent in the institution's name — permission, audit and preview.
- Ch 24.7 #2: never send "{fee}" or "৳ " with an empty value.
- Ch 24.7 #3: Bangla Unicode silently triples cost.
- Ch 24.7 #7: keep channel-specific variants possible for a future WhatsApp API.
- Ch 24.7 #9: report says "happened after", not "caused by".
- **Proposed:** neutral variable aliases such as `{offering}` beside the old names (Ch 24.7 #8) — owner to confirm before adding.

**Owner checkpoint:** Owner edits a shared Bangla template, sees the part count and cost, sends it to a test lead and opens the template report.

### 1.21 Recipients matrix for leads, students and guardians; consent and opt-out

**Goal:** Extend the phase-0 staff recipient matrix to every recipient kind, and record per-person, per-channel consent and opt-out so no unwanted or wrong-person message goes out.

**Depends on:** Phase 0 (staff recipient matrix, Master Admin → Notifications, type profiles); Block 1A (leads with guardian / `contact_person`); 1.20.

**Plan chapters:** Ch 24 (24.5, 24.6, 24.7 #4–#6), Ch 25 (25.4), Ch 13 (quiet hours, time zone), Ch 50 (O4).

**Decisions:** D1, D5, D22. **Proposed:** all recipient kinds, the recipients matrix, consent / opt-out, transactional vs promotional split and the minors rule (Ch 24.8).

**Build**
- **Data:** recipients matrix rows (`institution_id`, notification / message kind, recipient kind staff / lead / `client` / `contact_person` / referrer / owner, channel inbox / push / email / SMS / WhatsApp link, on/off, student-guardian-both choice) with type-profile defaults and versioned history; `contact_consents` (`institution_id`, person ref, channel, sms_ok, email_ok, `do-not-contact`, opted out at, opt-out source); message class (transactional / promotional) on every kind and template category.
- **Server:** recipient resolver: applies matrix, consent, do-not-contact, class (opt-out blocks promotional only unless "all" chosen), minors rule (under 18 from date of birth → guardian for non-urgent; no date of birth → type-profile default, guardian in schools), presence of phone / email, quiet hours and institution time zone; monthly SMS parts estimate per matrix row; "how many people, how many parts" preview for a change.
- **App & web:** Master Admin → Institutions → \<institution\> → Notifications: kind × recipient × channel table with cost estimate, change preview, version history and revert; consent block on the lead page (and on student / guardian pages when they exist) with opt-out source and date; opt-out action for staff.
- **Settings & permissions:** matrix edited by Master Admin only (D5); consent editing under lead edit permission; referrer / alumni recipient only when the alumni module is on (phase 5).

**Tasks**
- [ ] 1.21-T1 Extend the matrix schema to all recipient kinds and the WhatsApp-link channel; seed type-profile defaults (school: guardian default).
- [ ] 1.21-T2 Matrix versioning with revert; audit every Master Admin change.
- [ ] 1.21-T3 Cost estimate column (SMS parts per month from recent volumes) and change preview.
- [ ] 1.21-T4 Consent table with channel flags, `do-not-contact`, opt-out date and source; RLS.
- [ ] 1.21-T5 Mark every kind and template category transactional or promotional.
- [ ] 1.21-T6 Recipient resolver used by every send path (templates, notifications, campaigns, automation, public form confirmation).
- [ ] 1.21-T7 Minors rule from date of birth with type-profile fallback.
- [ ] 1.21-T8 Consent UI on the lead page; opt-out with source; history visible.
- [ ] 1.21-T9 Quiet hours and time zone enforced in the resolver for SMS and email, not only push.
- [ ] 1.21-T10 Owner-message recipient (weekly summary, billing, usage alerts) sent from the platform side.

**Tests**
- Unit: resolver matrix — opted-out lead gets transactional but not promotional; `do-not-contact` gets nothing; a 16-year-old's non-urgent message goes to the guardian; no date of birth in a school → guardian.
- RLS + cross-tenant leak: consents and matrix rows.
- Role-matrix: only Master Admin edits the matrix; institution Super Admin can read status only.
- UI (Playwright): Master Admin changes a cell, sees the preview and cost, reverts.

**Done when (acceptance criteria)**
- Every send path goes through one resolver; a test proves an opted-out person receives no promotional message from any path.
- Master Admin sees the estimated monthly SMS parts before turning SMS on for a kind.
- Opt-out date and source are stored and visible as evidence.

**Watch-outs (do not miss)**
- Ch 24.7 #4: many combinations — good defaults, cost estimate, preview, versioned settings with revert.
- Ch 24.7 #5 / O4: promotional SMS law may change — keep class and route separate and opt-out evidence.
- Ch 24.7 #6: minors' data and fee reminders sent to a child cause complaints.
- Student and guardian message content (receipts, installments) arrives with Block 2; the matrix rows exist now.

**Owner checkpoint:** Owner reviews the default matrix for a school and a coaching centre and approves the defaults (Ch 53.3 #1).

### 1.22 Notification inbox and the notify() pipeline (inbox, email, SMS via outbox)

**Goal:** Every event becomes a typed notification delivered to the inbox and, per the Master Admin matrix, by email and SMS through the outbox, with de-duplication, quiet hours, muting and escalation rules.

**Depends on:** Phase 0 (outbox, delivery log, usage ledger, behaviour switches); Block 1A (assignment, follow-ups, speed-to-lead, visits); 1.16; 1.18; 1.21.

**Plan chapters:** Ch 25 (25.1–25.5, 25.8 #1–#4, #6, #7), Ch 9 (usage ledger by type, monthly limits, 80% warning), Ch 18 (escalation targets), Ch 50 (I6, I12, M6).

**Decisions:** D1, D3, D4, D5, D7. **Proposed:** users can mute only non-urgent kinds (Ch 25.9).

**Build**
- **Data:** notification kinds registry (key, group, urgent flag, label key, owning module) seeded with phase-1 kinds `assigned`, `auto_assigned`, `follow_up`, `visit`, `speed_to_lead`, `outcome`, `missed_call`, `signup`, `app_update` (others registered by their modules later: `sync_nudge`, `discount`, `payment`, `leaderboard`, `scorecard`, `alumni`, `feedback`, admission-flow steps, AI, board-flow "ready"); `notifications` inbox rows (`institution_id`, `user_id`, kind, title, body, deep link incl. institution id, read at, dedupe key) keeping the last 100 per user; per-institution kind on/off; per-user mutes.
- **Server:** `notify(user, kind, title, body, data, dedupe, urgent)` RPC; dedupe per user + kind across inbox, email and SMS; quiet hours 22:00–08:00 in institution time zone delaying push and SMS, with the "send assigned immediately" option; email / SMS through the outbox using the institution's own connection, fallback per institution setting (platform gateway / mail or nothing); OTP priority queue untouched by bulk; monthly limit stops bulk but never OTP or urgent; usage ledger counts each SMS part by type (OTP / notification / template / bulk); escalations only to users whose role has "receives escalations"; daily digest bundling low-priority kinds.
- **App & web:** inbox screen (Alerts) with read marks and deep links; unread badge on More, Alerts tile and web; Settings → TEAM → Notifications (key `notifications`: kinds on/off and "who" choice); user mute screen; "Ask to update" on App versions sends `app_update`.
- **Settings & permissions:** setting key `notifications`; area settings permission for notifications; "who" selection lists all roles except Super Admin (Ch 11.10).

**Tasks**
- [ ] 1.22-T1 Kinds registry with urgent flag and label keys (bn / en text from labels and user language).
- [ ] 1.22-T2 Inbox table, 100-row cap per user, RLS by user and institution.
- [ ] 1.22-T3 `notify()` with dedupe key covering all channels.
- [ ] 1.22-T4 Channel routing from the Master Admin matrix and recipient resolver (1.21).
- [ ] 1.22-T5 Quiet hours delay for push and SMS; "assigned immediately" option.
- [ ] 1.22-T6 Email and SMS via outbox with the institution's connection; fallback setting; never a silent fallback (note in delivery log).
- [ ] 1.22-T7 Monthly limit, 80% warning to Super Admin and Master Admin, stop bulk at 100%, OTP and urgent always pass.
- [ ] 1.22-T8 Usage ledger rows per SMS part with type tag (D7).
- [ ] 1.22-T9 Escalation routing by the "receives escalations" behaviour switch (Ch 11.9).
- [ ] 1.22-T10 Daily digest for non-urgent kinds.
- [ ] 1.22-T11 Inbox UI, badges, deep links (switch institution first when needed — uses 1.19).
- [ ] 1.22-T12 Admin kind on/off and "who" settings; user mute of non-urgent kinds only.
- [ ] 1.22-T13 Rewire Block 1A events (assignment, follow-up, visit, speed-to-lead, missed call, outcome, signup) to `notify()`; wire "Ask to update" (1.18).

**Tests**
- Unit: dedupe across channels; quiet-hour delay; urgent bypass; limit at 100% blocks bulk but passes OTP.
- Fairness (I6): a 20,000-message bulk in institution A does not delay institution B's OTP beyond its SLA.
- Routing (I1, Ch 25.8 #3): A's email goes through A's connection only.
- RLS + cross-tenant leak: inbox rows.
- Role-matrix: escalation reaches only roles with the switch on.
- UI (Maestro): assign a lead → inbox item → tap opens the lead.

**Done when (acceptance criteria)**
- Each phase-1 event creates exactly one inbox item per recipient and, if the matrix says so, exactly one email / SMS.
- No push or SMS is sent in quiet hours except urgent kinds and the "assigned immediately" option.
- The last error of each channel is visible to Master Admin; the institution sees only "SMS: on ✓" and usage.

**Watch-outs (do not miss)**
- Ch 25.8 #1 / lesson 2: outbox bugs (wrong daily count, endless re-claim, immediate retry, empty kicks).
- Ch 25.8 #2: bulk must never block OTP or urgent.
- Ch 25.8 #4: too many notifications make users mute everything — dedupe, quiet hours, digest, urgent cannot be muted.
- Ch 25.8 #7: no silent failures.

**Owner checkpoint:** Owner assigns a lead in the test institution and sees inbox, email and SMS (fake or sandbox) arrive per the matrix; Master Admin sees the delivery log.

### 1.23 Push per app, Push check and Push health

**Goal:** Reliable push notifications tied to institution, user and app, with a self-check screen for staff and a health table for admins.

**Depends on:** Phase 0 (hub push connection kind, design system); 1.19; 1.22.

**Plan chapters:** Ch 25 (25.5 push parts, 25.6, 25.7, 25.8 #5, #8, #9), Ch 42 (42.7 push row), Ch 50 (I13), Ch 51 (lesson 11).

**Decisions:** D1, D12, D25. **Proposed:** SMS fallback when push fails for an urgent kind (Ch 25.9).

**Build**
- **Data:** `push_tokens` (`institution_id`, `user_id`, `app_id`, token, platform, permission state, channel state, last check-in, pre-launch device flag); push receipts per app; push connection per app build in the hub (shared app now; branded apps in phase 5).
- **Server:** push send via pg_net to the Expo push API using the app's connection; receipt check every minute (`push-followup` job on 1.16) removing dead tokens; device check-in RPC; urgent-kind SMS fallback when push is not delivered.
- **App & web:** one-time permission request; Android channel `leads`; token registration with timeout; Push check screen (More → HELP → Notification check) showing permission, channel, token and a test push; Push health (More → ADMIN): one row per person, pre-launch test devices excluded; phone-specific battery-saver setup guide; notifications show the institution name; deep link carries institution id and switches institution after a server membership check; web sessions labelled "🌐 Website" and receive no push (inbox and badge only).
- **Settings & permissions:** Push health under an admin area permission; `google-services.json` supplied by build secrets, never committed.

**Tasks**
- [ ] 1.23-T1 Token table with `institution_id` and `app_id`; one person per install; sign-out deletes the token.
- [ ] 1.23-T2 Permission prompt, Android channel `leads`, registration with timeout, check-in RPC.
- [ ] 1.23-T3 Push sender through pg_net and the app's push connection; respects quiet hours from 1.22.
- [ ] 1.23-T4 Receipt job every minute; remove dead tokens; per-app receipts.
- [ ] 1.23-T5 Push check screen with test push.
- [ ] 1.23-T6 Push health admin screen; detect and exclude Google Play pre-launch devices.
- [ ] 1.23-T7 Institution name in notification text for multi-membership users; deep-link handler that verifies membership then switches.
- [ ] 1.23-T8 Urgent-kind SMS fallback (e.g. `speed_to_lead`) when push fails.
- [ ] 1.23-T9 Battery-saver guide per common phone brand (labels, bn / en).
- [ ] 1.23-T10 CI secret handling for `google-services.json` and a secret-scan rule.

**Tests**
- Unit: receipt handling removes dead tokens; fallback triggers only for urgent kinds.
- Leak: a push for institution A tapped while B is active switches to A only after the membership check; a non-member link is refused.
- UI (Maestro): Push check test push arrives; sign-out → no further pushes.
- Screenshot: Push check and Push health light/dark × bn/en.

**Done when (acceptance criteria)**
- A counsellor receives an `assigned` push within a minute outside quiet hours.
- Push health lists every staff member with token state, without pre-launch devices.
- A user can diagnose their own phone on the Push check screen.

**Watch-outs (do not miss)**
- Lesson 11: pre-launch test devices spoil push statistics; `google-services.json` must never be committed.
- Ch 25.8 #5: battery savers block push — check screens, guide and urgent SMS fallback.
- Ch 25.8 #8: tokens carry `app_id` so branded apps (phase 5) can use their own Firebase project.
- Branded-app push connections are deferred to phase 5 / later (Block 3–5).

**Owner checkpoint:** Owner runs Push check on a phone and views Push health for the test institution.

### 1.24 Approval engine

**Goal:** One general approval engine — action, role-based limits, approvers, expiry, audit — used by campaigns, large exports, lead deletion and later discounts, refunds and payment voids.

**Depends on:** Phase 0 (permission registry, `can()`, roles, audit log); Block 1A (lead delete); 1.22.

**Plan chapters:** Ch 11 (11.12, 11.16 #8, R11), Ch 26 (26.2 step 4), Ch 23 (large export), Ch 34 / 35 (discount and manual payment verification policies — defined now, used in phase 2), Ch 50 (R11).

**Decisions:** — (accepted v2 design, Ch 11.17).

**Build**
- **Data:** `approval_policies` (`institution_id`, action key such as `discount.give`, `payment.void`, `refund.create`, `lead.delete`, `campaign.send`, `export.large`, `fee.change`; per-role limits in money, percent or count; approvers by role / scope / named users; request expiry; escalation target); `approval_requests` (`institution_id`, policy, requester, payload, amount / count, status pending / approved / rejected / expired / escalated, decided by, reasons) with audit.
- **Server:** `request_or_execute(action, payload)` helper: within the caller's limit → run immediately; above → create a request, notify approvers, execute the stored action on approval; expiry and escalation job on 1.16; multiple approvers; delegation honoured (1.26).
- **App & web:** Settings → Approval policies (per action: limits per role, approvers, expiry); Approvals list (pending / decided) with approve / reject and reason; Home banner for pending requests (rendered in 1.35); notification kinds for approval requests registered in 1.22's registry.
- **Settings & permissions:** permission to manage approval policies (sensitive, 2-step, audited); approve permission per action with scope.

**Tasks**
- [ ] 1.24-T1 Policy and request tables with RLS and audit.
- [ ] 1.24-T2 Seed default policies per type profile for `campaign.send`, `export.large`, `lead.delete`; define (disabled until phase 2) `discount.give`, `payment.void`, `refund.create`, `fee.change`.
- [ ] 1.24-T3 Generic `request_or_execute` with server-side limit evaluation from the caller's role assignments (D23 union, scope per assignment).
- [ ] 1.24-T4 Execution on approval is idempotent (an approved request runs once).
- [ ] 1.24-T5 Expiry and escalation job; multiple approvers; requester and approvers notified.
- [ ] 1.24-T6 Policy editor and Approvals list UI; Home banner data RPC.
- [ ] 1.24-T7 Hook `lead.delete` (Block 1A soft delete) into the engine.
- [ ] 1.24-T8 Audit every request, approval and rejection.
- [ ] 1.24-T9 Register approval notification kinds and labels.
- [ ] 1.24-T10 **Proposed:** "simple mode" that hides org units and approval policies in small institutions until they are needed (Ch 11.16 #1); behind a setting until the owner confirms.

**Tests**
- Unit: within-limit runs immediately; above-limit creates a request; expired request cannot be approved; double approve runs once.
- Role-matrix: each role template × each policy, in-scope and out-of-scope records.
- RLS + cross-tenant leak: policies and requests.
- RPC-as-real-role: approve as an approver; approve as a non-approver fails.

**Done when (acceptance criteria)**
- A counsellor deleting a lead creates an approval request when policy requires it; the approver approves from the Approvals list and the delete happens once.
- Pending requests show on approvers' Home banner and in their inbox; expired requests escalate.
- Every decision is in the audit log.

**Watch-outs (do not miss)**
- Ch 11.16 #8: approvals stuck in admission season — several approvers, expiry, escalation, delegation, Home banner.
- Discounts move onto this engine in phase 2 (Block 2) — do not build discount screens here.
- Limits must be evaluated on the server, never from client-sent amounts.

**Owner checkpoint:** Owner sets the campaign approval threshold and the large-export row limit for the test institution and approves a request from the Approvals list.

### 1.25 Field-level masking (D24) and export controls

**Goal:** Fields can be visible, masked or hidden per role; counsellors see phone numbers masked by default but can still call and message from the app; exports are permissioned, logged, watermarked, limited and approved when large.

**Depends on:** Phase 0 (permission registry with sensitive flags, roles, `user_access`); Block 1A (leads, list, lead page, export); 1.24.

**Plan chapters:** Ch 11 (11.11, R9, R10, 11.16 #4), Ch 23 (export screen and file), Ch 45 (45.5 copy button), Ch 46 (46.7 #2), Ch 50 (R9, R10).

**Decisions:** D24.

**Build**
- **Data:** `field_rules` (`institution_id`, role, field key, mode visible / masked / hidden) with type-profile defaults (counsellor: phone masked, guardian NID masked, discount history hidden; accountant: fees visible, phone masked); sensitive-field flags in the registry; per-user daily view counter; `export_log` (`institution_id`, user, module, scope, row count, filters, file id, time); per-institution export limits (rows per export, daily rows) and alert thresholds.
- **Server:** masking applied inside read RPCs (format `017•••••234`), never in the client; dial / message action RPC that hands the full number only to the dialer or SMS intent, logs it and counts it against the daily view limit; sensitive fields excluded from any AI payload; export RPC checks module + scope export permission, routes above-N exports to `export.large` approval, stamps user name and time into the file, logs the export and raises an Admin alert over daily limits.
- **App & web:** Settings → Roles: field rules editor per role; masked numbers rendered with no copy option on phone and web (web copy button disabled for masked values); export screen shows the limit, approval need and watermark notice.
- **Settings & permissions:** per-module export permissions with scope (`lead.export` …), `export.large` policy, sensitive field-view permissions; field rules editing under `settings.roles` (sensitive, 2-step).

**Tasks**
- [ ] 1.25-T1 Field rules table and type-profile defaults; D24 default on for the counsellor (Caller) role template.
- [ ] 1.25-T2 Masking in every lead read RPC (list, board, search, lead page, peek, duplicate check result).
- [ ] 1.25-T3 Dial / message intent RPC with logging and daily view counter; call popup and template send use it.
- [ ] 1.25-T4 Disable copy, long-press copy and web copy button on masked values.
- [ ] 1.25-T5 Sensitive fields: hidden unless the field permission exists; excluded from AI payload builders (shared helper for phase 4).
- [ ] 1.25-T6 Export permission per module and scope; large export goes through `export.large` approval (1.24).
- [ ] 1.25-T7 Watermark (user name and time) in every exported file; export log.
- [ ] 1.25-T8 Daily view and export limits with Admin alert.
- [ ] 1.25-T9 Field rules editor in Settings → Roles; "results you will get" preview when assigning roles.
- [ ] 1.25-T10 Help text telling institutions what masking can and cannot prevent (Ch 11.16 #4).
- [ ] 1.25-T11 Performance check of masked list RPCs on the ≈3,000-lead benchmark.

**Tests**
- Unit: mask formats for BD numbers with and without +880.
- Role-matrix: every role template × every field mode; counsellor sees masked phone on list, lead page, search and export file.
- RLS + cross-tenant leak: field rules, export log.
- RPC-as-real-role: list RPC as a counsellor never returns the full number in the payload (assert on raw JSON).
- UI (Maestro + Playwright): counsellor taps call on a masked number → dialer opens; copy is not offered.
- Performance: list and search with masking on stay within the Block 1A benchmark.

**Done when (acceptance criteria)**
- In a new institution, counsellors see `017•••••234` everywhere yet can call and message from the app.
- An export above the row limit waits for approval; every export file carries the user's name and time; every export is in the log.
- Admin gets an alert when someone crosses the daily view or export limit.

**Watch-outs (do not miss)**
- Ch 11.16 #4: masking stops bulk copying, not single numbers (dialer, call log, WhatsApp, screenshots) — combine with limits and audit, and tell institutions.
- The full number must not appear in any API response the UI receives for a masked role.
- Crash reports and future screenshots must keep masked values masked (Ch 46.7 #2).

**Owner checkpoint:** Owner logs in as a counsellor and an admin side by side and sees the difference; tries a large export and approves it.

### 1.26 Delegation, collaborators and access review

**Goal:** Temporary acting-for-someone with audit, sharing a single record with a collaborator without changing owner, and a monthly access review for Super Admins.

**Depends on:** Phase 0 (role assignments with dates, `user_access`, audit, access explainer); Block 1A (leads, hand over); 1.16; 1.22; 1.24.

**Plan chapters:** Ch 11 (11.8, 11.14 access review, 11.16 #5, R12, R13), Ch 44 (access review job), Ch 50 (R12, R13, R16).

**Decisions:** D23 (indirect). **Proposed:** sensitive permissions cannot be delegated (Ch 11.16 #5).

**Build**
- **Data:** `delegations` (`institution_id`, from user, to user, start, end, reason, created by); `record_collaborators` (`institution_id`, record type, record id, user, view / edit, expires at, added by); actions log field "on behalf of".
- **Server:** `user_access` rebuild includes active delegations and collaborators (incremental, per changed user); `can()` honours them; "no more than your own power" check; expiry handled by a job; monthly access-review job sends the report reminder to Super Admins and ends expired temporary roles.
- **App & web:** Users → user → Delegate (by user or Admin); collaborator chip and "Add collaborator" on the lead page; Access review report (Settings → Roles): holders of sensitive permissions, unused accounts, temporary access ending soon.
- **Settings & permissions:** delegation permission; collaborator add permission (lead edit scope); access review report visible to Super Admin and `settings.roles`.

**Tasks**
- [ ] 1.26-T1 Delegation and collaborator tables with RLS and audit.
- [ ] 1.26-T2 Incremental `user_access` update for delegations and collaborators (queue on 1.16, fair share).
- [ ] 1.26-T3 `can()` support and "A acting for B" written into every audited action.
- [ ] 1.26-T4 Block delegating more than one's own power; block sensitive permissions (Proposed rule, behind a setting until owner confirms).
- [ ] 1.26-T5 Collaborator view / edit with expiry; assign and hand over remain unchanged.
- [ ] 1.26-T6 Expiry job for delegations, collaborators and temporary role assignments.
- [ ] 1.26-T7 Access review report and monthly reminder to Super Admins.
- [ ] 1.26-T8 Access explainer shows delegation and collaborator reasons.

**Tests**
- Role-matrix: delegated user can do exactly the delegator's in-scope actions, until the end date.
- RLS + cross-tenant leak: collaborator rows; a collaborator sees only the shared record.
- Performance: `user_access` rebuild for 500 users stays incremental; list benchmark unchanged.
- Unit: expiry ends access at the set time in the institution's time zone.

**Done when (acceptance criteria)**
- "Act for Rahim until Friday" works and stops on Saturday; every action shows "on behalf of".
- A specialist added as viewer can open one lead and nothing else.
- Super Admin gets the monthly access review and sees sensitive holders, unused accounts and ending temporary access.

**Watch-outs (do not miss)**
- Ch 11.16 #5: privilege escalation through delegation or collaborators.
- Ch 11.16 #3: `user_access` rebuild load — incremental and fair-queued.

**Owner checkpoint:** Owner reviews the access review report for the test institution.

### 1.27 Bulk SMS campaigns

**Goal:** The Campaigns module: send an SMS to a filtered or uploaded list with cost estimate, opt-out and duplicate removal, approval for large sends, speed limits, and a delivery report.

**Depends on:** Phase 0 (hub SMS, live-test state, usage ledger, plan limits, Master Admin panel); Block 1A (saved filters / segments, timeline); 1.16; 1.20; 1.21; 1.22; 1.24.

**Plan chapters:** Ch 26 (26.1–26.6), Ch 9 (campaign daily limits, monthly SMS limit, prepaid balance), Ch 42 (routes), Ch 50 (O4, I6, I7).

**Decisions:** D3, D7, D15, D22. **Proposed:** the whole Campaigns module design (Ch 26.2–26.4), auto-pause on complaint / failure rate (Ch 26.5 #1).

**Build**
- **Data:** `campaigns` (`institution_id`, name, audience source: saved lead filter / uploaded list (student, guardian and alumni segments added when those modules ship), template, language, scheduled at, speed limit per minute, status draft / pending approval / scheduled / sending / paused / stopped / done, approval request id, estimated parts and cost, created by); `campaign_recipients` (person ref, phone, parts, status queued / sent / delivered / failed / unknown / skipped with skip reason, provider message id, cost); per-institution campaign settings (daily limit, approval thresholds, sending speed, time window, opt-out text).
- **Server:** audience builder with exclusion counts (no phone, opt-out, `do-not-contact`, duplicate); per-recipient part count and total cost; balance check (prepaid platform balance when D15 = via platform); approval through `campaign.send` policy; send job on 1.16 respecting speed limit, quiet hours, institution and provider limits, promotional route / sender ID; "unknown" after a set time without delivery report; stop at 100% monthly limit (OTP and urgent continue); Master Admin stop button; bulk disabled until institution approved and until the SMS connection passed a live test.
- **App & web:** Campaigns screens: create (audience → message with 3-person preview and largest-part example → time → checks) → review → send / schedule; cancel before start; pause / stop during sending; report: sent, delivered, failed, unknown, cost, per-person status, resend to failed, export; Master Admin → institution → Messaging: campaigns list with stop button.
- **Settings & permissions:** module `campaigns` gated by plan (SMS packs are an add-on on any plan, Ch 26.4 / Ch 9); permission `campaign.send` with scope (e.g. own branch recipients); campaign settings under an area settings permission.

**Tasks**
- [ ] 1.27-T1 Migrations for campaigns, recipients and settings with RLS and audit (who, to whom, what text).
- [ ] 1.27-T2 Audience builder from Block 1A saved filters and uploaded lists; exclusion counts shown per reason.
- [ ] 1.27-T3 Per-recipient variable resolution and part count; missing-variable recipients listed separately and excluded.
- [ ] 1.27-T4 Cost estimate, balance check and 80% / 100% monthly limit handling.
- [ ] 1.27-T5 Approval through the `campaign.send` policy above count or cost thresholds.
- [ ] 1.27-T6 Scheduler send job with speed limit, quiet hours, time window, fair share and provider limits; promotional route and sender ID; opt-out text appended where required.
- [ ] 1.27-T7 Gates: institution not yet approved, no successful live test, module off, plan daily limit reached.
- [ ] 1.27-T8 Delivery report handling and "unknown" timeout; gateway capability shown (which gateways report delivery).
- [ ] 1.27-T9 Cancel scheduled, pause / stop sending; Master Admin stop button.
- [ ] 1.27-T10 Report screen, resend to failed, export (export rules from 1.25 apply).
- [ ] 1.27-T11 Timeline line for every campaign message; usage ledger rows typed "bulk"; statement line separate (D7).
- [ ] 1.27-T12 Auto-pause on high failure / complaint rate (Proposed; behind a setting).
- [ ] 1.27-T13 Legal check checklist item before enabling the module in production (sender ID rules, time window, content).

**Tests**
- Unit: exclusion counts; per-recipient parts with long names; cost totals.
- Fairness (I6): a 50,000-recipient campaign does not delay another institution's OTP.
- Gate tests: no live test → cannot send; not approved institution → cannot send; limit 100% → stops, OTP still sends.
- Role-matrix: `campaign.send` scope limits recipients to the sender's branch.
- RLS + cross-tenant leak: campaigns and recipients.
- UI (Playwright): create → approval → send on fake adapter → report with all statuses.

**Done when (acceptance criteria)**
- An admin sends a campaign to a saved filter and sees, before sending, how many are excluded and why, and the total parts and cost.
- A campaign above the threshold waits for approval; a scheduled campaign can be cancelled; a running one can be stopped.
- The report shows sent / delivered / failed / unknown and cost; failed numbers can be resent.

**Watch-outs (do not miss)**
- Ch 26.5 #2: a wrong filter to 50,000 people — big numbers on screen, approval, cancel and stop.
- Ch 26.5 #1 / O4: spam and law — promotional route, opt-out, Master Admin stop, legal check first (open question Ch 53.4 #2).
- Ch 26.5 #6: with platform-paid SMS (D15) no balance means no campaign.
- Ch 26.5 #7: per-person part count, not an average.
- Deferred: campaign effect report, email campaigns and more SMS adapters → Block 2; WhatsApp campaigns → later (official API).

**Owner checkpoint:** Owner runs a campaign in the beta institution on the live gateway after the legal check and reviews the report; owner confirms which plans include Campaigns and the daily limits (Ch 53.2 #3).

### 1.28 Academic calendar and admission periods

**Goal:** Each offering has sessions / intakes with admission start and end dates, so public forms know when admission is open and leads carry the season they belong to.

**Depends on:** Phase 0 (locale, time zone, offerings list used by leads); Block 1A (leads with offering of interest).

**Plan chapters:** Ch 13 (13.7), Ch 27 (27.4, 27.6 #8).

**Decisions:** D13.

**Build**
- **Data:** `offering_sessions` (`institution_id`, `offering` ref, session / intake name, admission opens at, admission closes at, session starts at, status); lead column for intended session / season ("next session" mark).
- **Server:** "is admission open for offering X now" function in the institution's time zone; current season derived from session dates (never the calendar year); season key on leads for later report and leaderboard filters.
- **App & web:** Settings → Academic calendar / admission periods: sessions per offering, dates, open / closed state.
- **Settings & permissions:** area settings permission for the calendar; labels for "session" / "intake" per type profile.

**Tasks**
- [ ] 1.28-T1 Sessions table with RLS; seed sample sessions in test institutions.
- [ ] 1.28-T2 Open / closed function using institution time zone; tests at boundaries.
- [ ] 1.28-T3 Season derivation from session dates; season key on leads (set on create from the form or manually).
- [ ] 1.28-T4 Settings screen for sessions per offering.
- [ ] 1.28-T5 Expose season as a filter dimension on lead list (reports and leaderboard filters arrive with Ch 38 / 39 in phase 4).
- [ ] 1.28-T6 Labels for session / intake terms.

**Tests**
- Unit: admission open / closed at 23:59 and 00:00 local time; January, July and semester session patterns.
- RLS + cross-tenant leak: sessions.
- Screenshot: settings screen light/dark × bn/en.

**Done when (acceptance criteria)**
- Admins set intake dates per offering; the system answers "open / closed" correctly in the institution's time zone.
- Leads carry a season derived from session dates.

**Watch-outs (do not miss)**
- Ch 27.6 #8: wrong time zone or session shows "Admission closed" by mistake and loses real applications.
- Seasons come from session dates, not calendar years (Ch 13.7).
- Deferred: "Roll over to next session" copies offerings, batches and fees → Block 2 (Ch 28); season filters in reports and leaderboard → phase 4 (Ch 38, 39).

**Owner checkpoint:** Owner sets the next intake for one offering in the test college.

### 1.29 Application form builder and the public `/apply/<slug>` page

**Goal:** A configurable, bilingual public application / enquiry form per institution that creates or matches a lead, gives an application number, sends a confirmation and starts assignment and speed-to-lead — protected against abuse.

**Depends on:** Phase 0 (custom fields, branding, labels incl. `doc.application_form_title`, storage, OTP / CAPTCHA infrastructure); Block 1A (lead creation, duplicate check, assignment rules, speed-to-lead); 1.20; 1.21; 1.22; 1.28.

**Plan chapters:** Ch 27 (27.1–27.3 except application fee, 27.5, 27.6, 27.7), Ch 12 (branch info), Ch 50 (T15).

**Decisions:** D13, D16 (platform path always available). **Proposed:** form builder, application number, suspicious-submission flag, form start vs submit rate (Ch 27.7).

**Build**
- **Data:** `public_forms` (`institution_id`, form key, enabled, sections, fields incl. custom fields, required flags, file-upload fields, bn / en texts, privacy link, guardian consent tick); `form_submissions` (`institution_id`, form, lead id, application number, ref code, source "Website form", IP / phone rate keys, suspicious flag, started / submitted marks); per-institution application-number counter.
- **Server:** public Edge Functions only (never direct table reads) that resolve the institution from slug and return only needed fields; submit function: rate limits (one phone ≤ 3 per hour; one institution ≤ 60 per 10 minutes), CAPTCHA, duplicate match against all the institution's leads by phone (timeline line on match), new lead otherwise, application number, `?ref=` stored for referral counting (referral inbox in phase 5), confirmation via recipients matrix and template with a daily cap, assignment and speed-to-lead start; "Admission closed" or "interest for next intake" from 1.28; uploads straight to storage with signed URLs.
- **App & web:** public page at `/apply/<slug>` (platform sub-path or sub-domain with a wildcard certificate), institution branding and branch info, bn / en with viewer switch, light and cached; Settings → Application form builder (sections, fields, required, uploads, texts, preview); type-profile default form (school: guardian data and consent required); short default form (name, phone, offering).
- **Settings & permissions:** setting key `public_forms` (each form on / off); permissions (with scope) to manage form settings and to view submissions; labels for form titles.

**Tasks**
- [ ] 1.29-T1 Form and submission tables with RLS; application-number counter (per-institution series, **Proposed**, open question Ch 27.7).
- [ ] 1.29-T2 Form builder screen with sections, custom fields, required flags, uploads, bn / en text and live preview.
- [ ] 1.29-T3 Type-profile default forms; short default form.
- [ ] 1.29-T4 Public read function by slug returning only form definition and branding.
- [ ] 1.29-T5 Public submit function: CAPTCHA, phone and institution rate limits, validation against the form definition.
- [ ] 1.29-T6 Duplicate match by phone across all the institution's leads (timeline line) or new lead with source "Website form"; store `?ref=`.
- [ ] 1.29-T7 Application number, confirmation SMS / email through the resolver and a template, daily confirmation cap.
- [ ] 1.29-T8 Assignment rules and speed-to-lead clock (Block 1A) on new leads.
- [ ] 1.29-T9 Admission closed / next-intake interest using 1.28.
- [ ] 1.29-T10 Signed-URL uploads with basic type and size checks (full upload rules arrive with Ch 31 in Block 2).
- [ ] 1.29-T11 Public page UI: branding, branch info, language switch, privacy link, guardian consent for schools; cached and light.
- [ ] 1.29-T12 Suspicious-submission flag and form start vs submit rate (Proposed; behind settings).
- [ ] 1.29-T13 Add public functions to the cross-tenant leak test.
- [ ] 1.29-T14 Load test of the public page and submit function before the first admission season.

**Tests**
- Unit: rate limits (4th submission per phone per hour refused; 61st per 10 minutes refused), duplicate match, closed-window behaviour.
- Cross-tenant leak: wrong slug never creates a lead in another institution; public functions return no other institution's data.
- UI (Playwright): submit in bn and en; closed window shows "Admission closed" with interest option.
- Screenshot: public page light/dark × bn/en on a 5-inch phone.
- Performance: load test with many institutions' forms at once.

**Done when (acceptance criteria)**
- A visitor submits `/apply/<slug>` on a phone, gets an application number and a confirmation SMS; the lead appears assigned with the speed-to-lead clock running.
- A repeat submission with the same phone adds a timeline line instead of a duplicate lead.
- The form builder changes appear on the public page without a release.
- Outside admission dates the page says "Admission closed" or records interest for the next intake.

**Watch-outs (do not miss)**
- Ch 27.6 #1: bots and spam cost SMS money — CAPTCHA, limits, confirmation cap.
- Ch 27.6 #2: institution always from slug on the server.
- Ch 27.6 #6: minors' data without guardian consent in schools.
- Ch 27.6 #7: long forms lose leads on mobile — small default.
- URL always includes the slug (`/apply/<slug>`, never `/apply`).
- Deferred: online application fee → Block 2 (with online payments, D11 / D17); `/refer/<code>` and applicant status page → Block 3–5 (phase 5).

**Owner checkpoint:** Owner submits the test college's form from a phone in Bangla and sees the lead, the application number and the confirmation.

### 1.30 Custom domain with automatic SSL (D16)

**Goal:** An institution can put its public pages on its own domain at any time, with DNS verification, automatic certificates and renewal, expiry alerts, and the platform URL always working as a fallback.

**Depends on:** Phase 0 (hub "domain" connection kind, Master Admin → Domain menu); 1.16; 1.17; 1.29.

**Plan chapters:** Ch 27 (27.2 address, 27.6 #4), Ch 42 (42.7 custom domain row, 42.10 #7), Ch 5 (5.3 Domain), Ch 45 (45.5 hosting, 45.6 #6), Ch 44 (domain / SSL check job).

**Decisions:** D16. **Proposed:** moving hosting to a provider with automatic SSL and atomic deploys (Ch 45.6 #6).

**Build**
- **Data:** domain connection per institution (`integration_connections` kind domain: hostname, verification token, DNS status, certificate status, issued / expires at, last check, last error).
- **Server:** DNS verification check; certificate issuance and renewal through hosting that does this automatically; host-header routing of custom domains to the institution's public pages (institution resolved from the verified domain on the server); daily domain / SSL check job with expiry alerts.
- **App & web:** Master Admin → Institutions → \<institution\> → Domain: add domain, DNS instructions, verify button, certificate status and expiry; institution side shows read-only status.
- **Settings & permissions:** Master Admin writes; institution Super Admin reads status.

**Tasks**
- [ ] 1.30-T1 Choose and set up hosting with automatic SSL and renewal (owner approval of the move).
- [ ] 1.30-T2 Domain connection model and Master Admin screen with DNS instructions.
- [ ] 1.30-T3 DNS verification and certificate status checks (fake checker in CI from 1.17).
- [ ] 1.30-T4 Host-header routing to the right institution; unknown hosts get a neutral 404.
- [ ] 1.30-T5 Daily check job; alerts before expiry to Master Admin and the institution; health dashboard feed (1.33).
- [ ] 1.30-T6 Keep the platform sub-path / sub-domain URL always live; show it as fallback.
- [ ] 1.30-T7 On institution closure: domain connection disabled (I14).

**Tests**
- Unit: verification state machine; expiry alert at 30 / 7 / 1 days (thresholds as settings).
- Cross-tenant leak: domain of institution A never serves B's form.
- Integration (fake checker): failed renewal raises an alert and the platform URL still serves the form.

**Done when (acceptance criteria)**
- Master Admin adds `admission.<college>.edu.bd`, the institution sets DNS, verification passes and the form loads on HTTPS within the provider's issuance time.
- Expiry alerts arrive before a certificate lapses; the platform URL keeps working.

**Watch-outs (do not miss)**
- Ch 27.6 #4 / Ch 42.10 #7: an expired certificate in admission season closes the form — auto-renewal, alerts, fallback URL.
- Ch 45.6 #6: FTP / cPanel cannot handle custom domains — hosting move is a prerequisite.

**Owner checkpoint:** Owner sees the test institution's form on its own domain and approves the hosting choice.

### 1.31 Outgoing webhooks

**Goal:** Institutions receive signed event notifications on their own servers, with retries, auto-disable on repeated failure, and a delivery log with "send again".

**Depends on:** Phase 0 (`domain_events`, hub, permission registry, 2-step login); 1.16; 1.17.

**Plan chapters:** Ch 42 (42.7 webhook row, 42.11 phase 1), Ch 43 (43.3 layer 4, 43.4 #7–#8, 43.5, 43.7 #6), Ch 5 (5.4 closure), Ch 50 (I14, R17), Ch 52.11 #3 (outgoing webhooks phase 1, incoming API phase 2).

**Decisions:** — (D18 / D20 indirect: neutral event keys).

**Build**
- **Data:** `webhooks` (`institution_id`, URL, event keys, secret in Vault, status active / auto-disabled / disabled, failure count); `webhook_deliveries` (`institution_id`, webhook, event id, attempt, status code, duration, result, next attempt).
- **Server:** dispatcher listening to `domain_events`, versioned event payloads with neutral keys (`client`, `conversion` …), HMAC signature per webhook secret, timeout, back-off, auto-disable after many failures with a notice, manual redeliver; HTTPS and public hosts only.
- **App & web:** Settings → API keys & webhooks (webhooks part): add / edit, choose events, show secret once, test delivery, delivery log with "send again".
- **Settings & permissions:** `integration.manage` (sensitive, 2-step, audited); plan gate (Pro per Ch 43.6).

**Tasks**
- [ ] 1.31-T1 Tables with RLS; secret stored in Vault, shown once as a hint afterwards.
- [ ] 1.31-T2 Written, versioned event payload contract (v1) for phase-1 events (lead created, stage changed, follow-up due, form submitted …).
- [ ] 1.31-T3 Dispatcher on the scheduler with timeout, back-off, attempts, given_up.
- [ ] 1.31-T4 Signature header and verification sample for receivers.
- [ ] 1.31-T5 Auto-disable after N consecutive failures; notify Super Admin.
- [ ] 1.31-T6 Settings UI with test delivery and delivery log, "send again".
- [ ] 1.31-T7 Block private IPs and non-HTTPS URLs.
- [ ] 1.31-T8 Revoke all webhooks and delete secrets when an institution is closed (I14).
- [ ] 1.31-T9 Plan gating and limits.

**Tests**
- Unit: signature generation; payload contract snapshot.
- Fake receiver (1.17): slow, 500, timeout → back-off, then auto-disable.
- RLS + cross-tenant leak: webhooks and deliveries; events of A never dispatched to B's webhook.
- Role-matrix: only `integration.manage` with 2-step can create webhooks.

**Done when (acceptance criteria)**
- An admin adds a webhook, triggers a lead creation and sees a signed delivery in the log; a failing endpoint is retried with back-off and then disabled with a notice.
- Closing an institution disables its webhooks.

**Watch-outs (do not miss)**
- Ch 42.7: retries must not flood the institution's server.
- Ch 43.7 #6: changing event contracts breaks ERPs — version and announce through What's new.
- Deferred: incoming API with scoped keys → Block 2.

**Owner checkpoint:** Owner sees a webhook delivery log for the test institution.

### 1.32 Automation rules

**Goal:** "When … if … then …" rules per institution so most custom requests are met without code.

**Depends on:** Phase 0 (`domain_events`, custom fields, plan limits); Block 1A (assignment, follow-ups, tags, stages); 1.16; 1.20; 1.21; 1.22; 1.24; 1.31.

**Plan chapters:** Ch 43 (43.1–43.3 layer 3, 43.4, 43.5, 43.6, 43.7 #1, #7), Ch 44 (date-based rules job), Ch 9 (automation limits, Standard plan), Ch 5 (5.13 rule: settings / custom records / automation first).

**Decisions:** D8, D18, D20 (indirect). **Proposed:** loop protection, dry run, rule log with one-click disable (Ch 43.8).

**Build**
- **Data:** `automation_rules` (`institution_id`, name, trigger: lead created / stage changed / field changed / specific date / payment received (available once payments exist in phase 2); conditions; actions: send SMS / email / push, assign, set field, create follow-up, add tag, call webhook; enabled; daily run cap); `automation_runs` (rule, event, record, depth, actions done, result).
- **Server:** rule engine consuming `domain_events`; depth counter per event chain with a hard limit; same rule on same record at most once per window; daily cap per institution (plan limit); SMS cost warning; large sends through the approval engine; date-based trigger job on 1.16; all sends through the recipients resolver.
- **App & web:** Settings → Automation: rule builder, dry run preview ("how many will receive what"), rule log, one-click disable.
- **Settings & permissions:** creating / changing rules needs `integration.manage`-class sensitive permission with 2-step and audit; plan gate (Standard).

**Tasks**
- [ ] 1.32-T1 Rule and run tables with RLS and audit.
- [ ] 1.32-T2 Trigger catalogue from `domain_events` with neutral keys; date trigger.
- [ ] 1.32-T3 Conditions on lead fields, custom fields, offering, stage, branch.
- [ ] 1.32-T4 Actions: send (via templates and resolver), assign, set field, create follow-up, add tag, call webhook (1.31).
- [ ] 1.32-T5 Loop protection: depth limit, once-per-window, daily cap, SMS cost alert.
- [ ] 1.32-T6 Dry-run preview and rule log; one-click disable.
- [ ] 1.32-T7 Large sends routed to approval (1.24).
- [ ] 1.32-T8 Date-based rule job on the scheduler.
- [ ] 1.32-T9 Plan gating and per-institution limits; Master Admin can disable an institution's automation.
- [ ] 1.32-T10 Seed example rules per type profile (disabled by default), e.g. "stage changed and offering BBA → SMS to guardian and a follow-up".

**Tests**
- Unit: a rule that sets a field which triggers itself stops at the depth limit; once-per-window holds.
- Fake adapter: a rule sending SMS to 5,000 leads asks for approval first.
- RLS + cross-tenant leak: rules and runs; events of A never trigger B's rules.
- Role-matrix: only permitted roles with 2-step can create rules.
- Performance: rule evaluation does not slow lead create / stage change beyond the benchmark (evaluation async).

**Done when (acceptance criteria)**
- An admin builds the example rule, sees the dry run, enables it, and the guardian gets an SMS and the lead a follow-up when the stage changes.
- A looping rule is stopped automatically and shown in the rule log.

**Watch-outs (do not miss)**
- Ch 43.7 #1: infinite loops sending thousands of SMS.
- Ch 43.7 #7: wrong rules message the wrong people — dry run, log, disable, approval.
- Never add institution-specific columns to core tables (Ch 43.4 #1).
- Deferred: custom records and incoming API → Block 2; extensions → later.

**Owner checkpoint:** Owner builds one rule with the dry run and sees it run on a test lead.

### 1.33 Master Admin health dashboard, alerts, monthly cost view and announcements

**Goal:** The platform team sees problems before institutions complain, sees what each institution costs per month, and can send targeted announcements.

**Depends on:** Phase 0 (Master Admin panel, usage ledger, setup checklist, platform mail); 1.16; 1.18; 1.22; 1.27; 1.30.

**Plan chapters:** Ch 5 (5.3 Dashboard and Announcements menus, 5.8, 5.9, 5.17 #4), Ch 9 (9.7 monthly cost view, budgets, alerts), Ch 10 (10.10 #1 OTP anomaly alert), Ch 42 (42.3 summary, alerts), Ch 46 (46.6 announcements), Ch 50 (M7, M11, T13, T16).

**Decisions:** D4, D7, D15. **Proposed:** targeted announcements by institution, type or plan (Ch 5.9); the panel menu structure (Ch 5.18).

**Build**
- **Data:** per-institution health snapshot (activity, errors, SMS / AI cost, call-log sync status, last login, inactive flag, setup items left); alert rules and alert events; monthly cost view per institution (SMS, AI, storage, function calls; who pays per D15), budgets; `announcements` (title / body bn and en, channels in-app / email, target: all / institutions / type / plan, schedule, maintenance notice flag) and per-user dismissals.
- **Server:** health aggregation job; alerts: SMS low balance or errors, email bounce, repeated connection failures, domain certificate expiring, sudden cost rise, sudden error rise, job "last success too old", OTP volume anomaly; branch breakdown; announcement delivery in-app and by platform email.
- **App & web:** Master Admin Dashboard: institutions with problems first, alerts, institutions awaiting approval, setup remaining; per-institution health page with branch breakdown; cost view per month with budgets; Announcements editor; in-app announcement banner and list for institution users.
- **Settings & permissions:** platform roles: Master Admin full; Support read; Billing reads cost view; Developer reads error metrics.

**Tasks**
- [ ] 1.33-T1 Health aggregation job (per institution, per branch) on 1.16.
- [ ] 1.33-T2 Alert rules and alert events with de-duplication and acknowledgement.
- [ ] 1.33-T3 Feed sources: hub connection errors and balances, email bounces, domain checks (1.30), job run log (1.16), crash / error spikes (1.18), OTP anomalies.
- [ ] 1.33-T4 Dashboard UI, problems first; per-institution health page; setup-remaining list.
- [ ] 1.33-T5 Monthly cost view (SMS, AI, storage, function calls) with D15 split, budgets and alerts.
- [ ] 1.33-T6 Announcements model, editor, targeting (Proposed), in-app banner and email delivery; maintenance notices.
- [ ] 1.33-T7 Call-log sync status and AI cost columns show "not active" until phases 3 / 4 fill them.

**Tests**
- Unit: each alert rule fires on seeded data and not on normal data.
- Role-matrix: Support cannot change anything; Billing sees cost but not institution data.
- Leak: announcements targeted to institution A never show in B.
- UI (Playwright): dashboard sorting, alert acknowledge, announcement send.

**Done when (acceptance criteria)**
- A seeded institution with an empty SMS balance and a failing email connection appears at the top of the dashboard with two alerts.
- Master Admin sees each institution's monthly cost, split by who pays.
- An announcement targeted at colleges reaches only college users, in the app and by email.

**Watch-outs (do not miss)**
- M7 / Ch 5.17 #4: problems unseen until complaints.
- T16: institutions running at a loss without a cost view.
- The dashboard must read summaries; never pull raw tenant data into platform views beyond what Support entry allows.

**Owner checkpoint:** Owner reviews the dashboard with seeded problem institutions, the cost view for one month and sends a test announcement.

### 1.34 Offline queues, caching and phone security

**Goal:** The app opens instantly from cache, works on bad networks with offline queues for additive actions, and protects cached data on lost or shared phones.

**Depends on:** Phase 0 (design system, session, sign-out cache clear); Block 1A (calls, notes, manual WhatsApp, activity); 1.18; 1.19.

**Plan chapters:** Ch 47 (47.7, 47.9, 47.10, 47.12 #3–#5), Ch 10 (10.9 phone security, 10.10 #7), Ch 45 (45.6 #7), Ch 52.10 (offline queue and cache in phase 1).

**Decisions:** D13 (indirect), D25 (cache per institution).

**Build**
- **Data:** client-side stores: in-memory request memo with TTL; AsyncStorage stale-while-revalidate caches for Home, Leads and Students keyed by institution + user; offline queues for activity, crash, calls and WhatsApp logs with idempotency keys; server-side idempotency key table for additive writes.
- **Server:** idempotent write RPCs for queued actions; server time endpoint used for all time calculations; "sign out all other devices" RPC; idle-timeout institution setting.
- **App & web:** "No internet" strip and "✓ Back online"; "updating" indicator on cached screens; fresh fetch before money or stage actions; timeouts and retries tuned for slow 3G; optional app lock (PIN / fingerprint); idle auto sign-out; sign out all other devices; cache cleared on sign-out, user switch and institution switch.
- **Settings & permissions:** institution setting for idle sign-out time; app lock is per user.

**Tasks**
- [ ] 1.34-T1 Request memo with TTL; SWR cache for Home, Leads (Students added in Block 2) keyed by institution + user.
- [ ] 1.34-T2 Offline queues for activity, crash, calls and WhatsApp logs; only additive actions; never money.
- [ ] 1.34-T3 Server idempotency for queued writes; replay after reconnect without duplicates.
- [ ] 1.34-T4 Network strip and back-online banner; slow-3G timeouts and retries.
- [ ] 1.34-T5 Fresh-fetch guard before stage change and (later) payment actions; "updating" indicator.
- [ ] 1.34-T6 Use server time for all time maths (phone clock may be wrong).
- [ ] 1.34-T7 App lock (PIN / fingerprint), idle auto sign-out (institution setting), sign out all other devices.
- [ ] 1.34-T8 Clear caches and queues on sign-out, user switch and institution switch (with 1.19).

**Tests**
- Unit: queue replay idempotency; cache key isolation per institution + user.
- UI (Maestro): airplane mode → log a call and a note → reconnect → exactly one of each on the server; app lock after background.
- Leak: after institution switch no cached rows of the old institution are readable.
- Performance: Home and Leads open from cache under 1 s on a low-end test phone; ≈3,000-lead list scroll stays smooth.

**Done when (acceptance criteria)**
- Calls and notes logged offline sync once when back online; nothing involving money can be done offline.
- Home and Leads open instantly from cache and refresh in the background.
- A user can lock the app and sign out all other devices; idle sign-out works per institution setting.

**Watch-outs (do not miss)**
- Ch 47.12 #3: stale cache leads to calling the wrong lead — "updating" mark and fresh fetch before critical actions.
- Ch 47.12 #4: offline conflicts — additive actions only.
- Ch 47.12 #5: cached data on lost phones — lock, idle sign-out, remote sign-out.

**Owner checkpoint:** Owner tries the app in airplane mode on a low-end phone and sees queued calls sync.

### 1.35 Home, More, Settings hub and website

**Goal:** Finish the phase-1 shell: the Home screen with today's work and numbers from one RPC, the grouped More menu, the Settings hub filtered by area permissions, and the website (WebShell, tables, global search).

**Depends on:** Phase 0 (shell, branding, Settings structure, labels); Block 1A (leads, follow-ups, visits, recent, starred, export); 1.18; 1.19; 1.20; 1.22; 1.24; 1.25; 1.34.

**Plan chapters:** Ch 45 (45.1–45.7), Ch 47 (47.9 single Home RPC, counts RPC), Ch 25 (25.7 web label), Ch 11 (11.5 area settings permissions).

**Decisions:** D12, D13, D25. **Proposed:** role-based Home cards, Settings search, new hosting (Ch 45.7).

**Build**
- **Data:** none new beyond per-user Home card preferences (Proposed) and setting key `web` (who may use the website; admins always).
- **Server:** one Home RPC returning every Home number for the user (pending calls, talk time, new leads, admissions, visits, team view for admins) and a counts RPC for chips; both permission- and module-aware.
- **App & web:** Home top bar (logo, switcher, streak chip hidden until phase 4, bell with unread badge, avatar); cards in order: store-update card (1.18), today's stats, rank card (phase 4, hidden), banners (pending sign-ups, pending approvals from 1.24; sync nudge in phase 3; discount requests in phase 2), Today's visits, Today's calls, Recent (Call these first in phase 4), Students summary / admission flow / report cards (later phases, hidden), quick actions, FAB "Add a lead" (label-aware); More groups (top tiles, ALUMNI, REPORTS, TOOLS, TEAM, ADMIN, APP, HELP, switcher and sign-out) showing only built, permitted and enabled entries; Settings hub by area permission with Super Admin seeing all, empty groups hidden, Settings search (Proposed), links from the setup checklist; website WebShell: collapsible left menu, top bar with page title, global search (Ctrl+K or `/`), `?` shortcuts, theme, language, switcher, avatar menu (Speed check, Sign out); Leads table: sortable columns, column chooser, density, board view, multi-select bulk actions, Excel export under 1.25 rules, right detail panel, hover card, copy button (not for masked values), row ⋯ menu (lead items now; student items in Block 2), KPI cards; web session label "🌐 Website"; chunk-error auto reload and 404 for missing assets.
- **Settings & permissions:** setting `web`; each Settings entry registered with its area permission (`settings.pipeline`, `settings.messaging_templates`, `settings.users`, `settings.roles`, `settings.terminology` …); menu names from labels.

**Tasks**
- [ ] 1.35-T1 Home RPC and counts RPC (one round trip each), measured before / after on the benchmark.
- [ ] 1.35-T2 Home top bar and cards with module and permission gating; FAB.
- [ ] 1.35-T3 Banners: pending sign-ups (Phase 0 data) and pending approvals (1.24).
- [ ] 1.35-T4 More menu groups with label-driven names; hide entries of later phases.
- [ ] 1.35-T5 Settings hub with area-permission filtering, Super Admin sees all, empty groups hidden; add phase-1 entries (Message templates, Notifications, Approval policies, Automation, API keys & webhooks, Academic calendar, Application form builder, Messaging status read-only).
- [ ] 1.35-T6 Settings search including default terms (Proposed).
- [ ] 1.35-T7 `web` access setting enforced server-side.
- [ ] 1.35-T8 WebShell: left menu, top bar, global search, shortcuts help, theme / language / switcher / avatar menu.
- [ ] 1.35-T9 Leads web table with sorting, column chooser, density, board view, bulk actions, export, right panel, hover card, copy rules, row menu, KPI cards.
- [ ] 1.35-T10 Chunk-error reload and 404 for missing assets after deploys.
- [ ] 1.35-T11 Web landing page: Leads until the Students tab exists (plan says web opens Students; interim until Block 2).
- [ ] 1.35-T12 Role-based Home card defaults and user hide / reorder (Proposed; behind a flag).

**Tests**
- Performance: Home opens from cache instantly and the Home RPC stays within budget on the ≈3,000-lead benchmark (big and small institution).
- Role-matrix: Home cards, More entries and Settings entries per role template.
- UI: Maestro (Home, More, Settings), Playwright (WebShell, Ctrl+K search, table bulk action, export).
- Screenshot: Home, More, Settings, WebShell in light/dark × bn/en, long labels.
- Leak: global search returns only the active institution's records.

**Done when (acceptance criteria)**
- A counsellor opens the app and sees pending calls, today's visits and recent leads in one screen without waiting.
- An accountant with only `settings.fees`-type rights sees only their Settings entries; Super Admin sees all.
- Admins work on the website with the Leads table, global search and bulk actions; masked numbers have no copy button.

**Watch-outs (do not miss)**
- Ch 45.6 #1: every new Home card is a new request — keep one RPC, measure before / after ("never slower").
- Ch 45.6 #3 / #4: Settings too big or entries invisible to everyone — search, Super Admin sees all, access explainer.
- Ch 45.6 #7 / #8: shared office computers and stale data after institution switch (1.34, 1.19).
- Deferred: live approval toast for "student ready" and student row menu items → Block 2; rank card, streak, Call these first → phase 4; sync nudge → phase 3.

**Owner checkpoint:** Owner uses Home on a phone and the website on a computer for one working day in the beta institution and signs off phase 1.

## Phase 2: Admission and students

Phase 2 turns the lead CRM from Phase 1 into a full admission system. It adds courses, batches, sections and seats; fees, discounts, payments, receipts, refunds and online payment (SSLCommerz into each institution's own merchant account); student IDs; the full admit / cancel transaction; the Students tab with placement and the external board flow; eligibility rules, required papers, file storage (Google Drive or platform storage) and PDF / photo services; the admission test, merit list and waiting list; student and guardian messages, email campaigns, campaign effect reports, more SMS adapters and SMS billing statements; and custom records with an incoming API. Fees and payments come first (Ch 52.11 item 2), so a coaching centre can collect fees as early as possible.
Exit criteria: every seeded type-profile test institution can admit a lead into a course / batch / section with seat, fee lock and student ID in one transaction; collect manual and SSLCommerz payments with correct receipts, invoices, reminders and daily reconciliation; run its Students tab, placement and board flow; collect papers and files; and (school / university profiles) run a test to a published merit list and waiting list. All new tables, RPCs, storage paths, custom-record tables and API keys pass the cross-tenant leak test. Every Phase 2 module can be turned off per institution without losing data.
Table names below are indicative; the neutral keys (`offering`, `cohort`, `slot_group`, `payment_plan`, `client`, `conversion`, `documents`, `client_number`, `assessment`, `after_steps`, `contact_person`) are fixed by the plan (Ch 8). The cross-cutting rules of Ch 52.9 apply to every milestone: register labels, permissions and template defaults before release, add every new table / RPC / storage path to the leak test, run the Ch 47 quality checklist on every new screen, and review the Ch 50 risk rows before the phase starts.

### 2.01 Courses, batches, sections and seats

**Goal:** Build the master data that every later admission feature uses: courses (`offering`), batches (`cohort`), sections (`slot_group`) and seat capacity, with branch scoping, labels and the yearly roll-over.

**Depends on:** Phase 0 (tenancy, branches, labels, permission registry, type profiles, custom field builder), Phase 1 (leads, pipeline stages with `course_ids`, admission windows and academic calendar, templates).

**Plan chapters:** Ch 28 (28.1–28.11), Ch 27 (27.4 roll-over), Ch 8 (labels), Ch 12, Ch 7.

**Decisions:** D8, D9, D20.

**Build**
- **Data:** `offerings` (`institution_id`, nullable `branch_id`, name, code, category, duration, active, sort order, optional admission fee threshold, institution-type group for mixed institutions); `cohorts` (`offering_id`, `branch_id`, name, start date, class time, seat capacity, status open / closed / full, denormalised `seats_filled`); `slot_groups` (`cohort_id`, name, on / off, **Proposed:** optional seat capacity). Unique (`institution_id`, code). RLS on all three. Trigger keeps `seats_filled` = admitted leads in the batch.
- **Server:** RPC `offering_catalog()` returning courses / batches / sections with all seat numbers in one call; RPC `rollover_session(from_session, to_session)` copying courses, batches and fee heads (fee heads once 2.02 exists); deactivate (never delete) for used courses and sections.
- **App & web:** Settings → ADMISSIONS → Courses & batches (list, edit, deactivate, section on / off); searchable course / batch / section picker grouped by institution type and branch, pre-filtered by the user's branch and offering limit; batch status chip (full).
- **Settings & permissions:** area permission for course and batch management (`settings.offerings`, not `settings.manage`); `offering.view` respects the offering limit from Ch 11; setting `admission.batch_required`; labels `course`, `batch`, `section` with defaults per type profile (Class / Program / Technology; Session / Intake; Group / Shift).

**Tasks**
- [ ] 2.01-T1 Migrations for `offerings`, `cohorts`, `slot_groups` with `institution_id`, nullable `branch_id`, indexes and RLS; add all three to the leak test.
- [ ] 2.01-T2 Trigger-maintained `seats_filled` counter on `cohorts`; status `full` derived when filled ≥ capacity.
- [ ] 2.01-T3 Register labels `course`, `batch`, `section` and their per-profile defaults (Ch 28.9 table); verify the neutral keys `offering`, `cohort`, `slot_group` in code.
- [ ] 2.01-T4 Register permission `settings.offerings` and data scope by offering limit; records without a course stay visible to Admin and creator.
- [ ] 2.01-T5 Settings screen ADMISSIONS → Courses & batches (phone and web), with deactivate instead of delete for courses and sections in use.
- [ ] 2.01-T6 `offering_catalog()` single RPC (all counts batched, lesson 8); `jit = off` if it is a heavy plpgsql function.
- [ ] 2.01-T7 Shared picker component: grouped by institution type (mixed institutions) and branch, searchable, pre-filtered by branch and offering limit.
- [ ] 2.01-T8 Link course to existing Phase 1 features: pipeline stage `course_ids`, template course filter, admission window per course / intake, lead "interested course" field.
- [ ] 2.01-T9 Seed courses / batches / sections per type profile in the seeded test institutions (coaching: many small batches; university: intakes Spring / Summer / Fall; school: shifts / versions; madrasa: boys / girls sections; polytechnic: group / shift).
- [ ] 2.01-T10 `rollover_session` RPC and "Roll over to next session" button with preview (what will be copied).
- [ ] 2.01-T11 Expose `{course}`, `{batch}`, `{batch_start}`, `{section}` template variables from this data.
- [ ] 2.01-T12 Confirm the master lists of Ch 28.8 (`lead_sources`, `campaigns`, `lost_reasons`, `tags`, `lead_types`) exist from Phase 1 and that `call_results` and `document_types` are not created.
- [ ] 2.01-T13 **Proposed:** optional seat capacity on sections; when set, both batch and section are checked (wired into 2.05).

**Tests**
- RLS + cross-tenant leak test on the three tables; branch-restricted staff see only their branch's courses.
- RPC-as-real-role: `offering_catalog()` as Caller with an offering limit returns only allowed courses.
- Unit: `seats_filled` trigger after admit, cancel and placement (placement wired in 2.08).
- UI (Maestro / Playwright): create course → batch → section, deactivate a used section, roll over to next session.
- Screenshot: Courses & batches screen light / dark × bn / en, with school and university labels.
- Performance: `offering_catalog()` on the ≈3,000-lead benchmark institution with 50 batches returns under the Ch 47 target.

**Done when (acceptance criteria)**
- An admin can create, edit and deactivate courses, batches and sections; a used course or section cannot be deleted.
- A school shows "Class / Session / Section", a university "Program / Intake / Section", with no code change.
- Batch shows filled / capacity and "full" status correctly after admissions.
- Roll-over copies courses and batches into the next session in one action.
- An accountant with only `settings.fees` cannot edit courses, and a user with `settings.offerings` does not automatically see all course data.

**Watch-outs (do not miss)**
- Never delete a used course / section; old records must keep the name (Ch 28.10 #6).
- Counters by trigger, not per-row queries (Ch 28.10 #4, lesson 8).
- Neutral keys from day one; never hard-code "batch" in code (Ch 28.10 #8, risk X7).
- Season filter for reports and leaderboards comes with Ch 38 / 39 in Phase 4; store the session on records now.

**Owner checkpoint:** Owner sees the Courses & batches screen in two type profiles (school and coaching) and approves the roll-over behaviour and whether section seat capacity (Proposed) is wanted.

### 2.02 Fee heads, schedules and fee settings

**Goal:** Replace the old "one total fee per course" with fee heads that each have a schedule, plus optional heads (including the Hostel & transport module), so every institution type can describe its fees.

**Depends on:** 2.01.

**Plan chapters:** Ch 34 (34.1, 34.2, 34.7), Ch 28 (28.2 fee lines, 28.6 fee sync), Ch 9 (9.2 modules), Ch 13 (money format).

**Decisions:** D8.

**Build**
- **Data:** `fee_heads` (`institution_id`, `offering_id`, name, amount in integer minor units, schedule one-time / monthly / per term-semester / per credit / annual-session / package, due day, late fee rule, optional flag); `optional_head_choices` per student; `transport_routes` (Hostel & transport module); institution default admission fee threshold plus per-course override (used by board flow, 2.16). RLS on all.
- **Server:** function `full_fee(offering)` = sum of one-time + package heads; recurring heads expose a rate; shared rounding function for percentages (single place); fee-sync job that recalculates open fee talks when a course's heads change (only open negotiations, never locked fees) with a preview of affected leads.
- **App & web:** Settings → ADMISSIONS → Fee & discount (fee heads per course, schedules, due day, late fee rule, optional heads); live total; money in lakh format (1,00,000) and optional Bangla digits.
- **Settings & permissions:** setting key `fees` (fee part); permission `settings.fees`; module "Fees, payments, receipts" (Starter) and module "Hostel & transport"; labels `fee`, `installment`, `discount`; neutral key `payment_plan`.

**Tasks**
- [ ] 2.02-T1 Migrations for `fee_heads`, `optional_head_choices`, `transport_routes`; leak test entries.
- [ ] 2.02-T2 Money stored as integers in minor units; one rounding helper used by all fee and discount code.
- [ ] 2.02-T3 Register module "Fees, payments, receipts" (Starter) and "Hostel & transport" (madrasa, school, nursing defaults); declare module dependencies (board flow needs fees, Ch 9.9 #2).
- [ ] 2.02-T4 Register `settings.fees`, labels `fee`, `installment`, `discount`, and the `fees` settings schema with defaults.
- [ ] 2.02-T5 Fee & discount settings screen: heads per course with schedule, due day, late fee rule, optional flag.
- [ ] 2.02-T6 Optional heads chosen per student (hostel, transport with route, books, uniform, lab); transport routes list under the Hostel & transport module.
- [ ] 2.02-T7 `full_fee()` and recurring-rate functions; **Proposed:** unified lock model (full fee = one-time + package; recurring heads lock the post-discount rate at admission).
- [ ] 2.02-T8 Fee-sync: recalculate open fee talks on head change, with "N leads affected" preview and audit entry.
- [ ] 2.02-T9 Seed fee heads per type profile (school: admission fee + monthly tuition + session fee; coaching: package or monthly fee; university: semester fee and per-credit rate).
- [ ] 2.02-T10 Include fee heads in the 2.01 roll-over.
- [ ] 2.02-T11 Mark fee and discount fields sensitive in the registry; type-profile defaults (counsellor cannot see discount history; accountant sees fees with phone masked) using Phase 1 field masking.
- [ ] 2.02-T12 Seed two test institutions: one with one-time / package fees and one with recurring heads (Ch 34.8 #3, Ch 48).

**Tests**
- Unit: `full_fee`, rounding of percentages, per-credit rate × credits.
- RLS + leak test on fee tables; role-matrix: counsellor cannot read discount history, accountant sees fees but masked phone.
- RPC-as-real-role: fee-sync preview as Admin.
- Screenshot: Fee & discount settings light / dark × bn / en, lakh format.

**Done when (acceptance criteria)**
- Each seeded type profile has a sensible fee structure out of the box.
- Changing a fee head shows how many open negotiations change, and locked fees do not change.
- Turning off "Hostel & transport" hides its heads and routes; data stays.

**Watch-outs (do not miss)**
- Rounding and decimals in one place; display in lakh format (Ch 34.8 #8).
- Fee rise mid-season must not change admitted students' locked rate (Ch 34.8 #6, Ch 28.10 #5).
- Per-credit fees need credit counts that the app does not register; keep the per-credit block behind its module until built and tested (Ch 9.2 rule, risk O1).
- Plan module list must match the phase (Ch 52.11 #2, Ch 53): Starter promises fees.

**Owner checkpoint:** Owner reviews the fee setup for a school and a coaching centre and confirms the Starter plan's module list now that fees arrive in Phase 2 (Ch 52.11 #2, Ch 53 Q3).

### 2.03 Fee talk, discounts, waivers and scholarships

**Goal:** Let counsellors negotiate fees with a lead, give discounts within role limits through the Phase 1 approval engine, and apply rule-based waivers and scholarships automatically.

**Depends on:** 2.02, Phase 1 (approval engine, notifications, timeline, Home / More).

**Plan chapters:** Ch 34 (34.3–34.5, 34.8, 34.9), Ch 11 (11.12 approval engine), Ch 44 (`fee-discounts`), Ch 24 (fee variables), Ch 14 (sibling link via guardian).

**Decisions:** D8, D23.

**Build**
- **Data:** `fee_talks` (lead, offering, status negotiating / discount waiting / discount given / final); `fee_talk_events` (quoted, lead asked, offer, note); `fee_discounts` (head or whole fee, amount or %, reason, status, expires_at, approval request id); `waiver_rules` (result-based, sibling, staff child, quota, merit rank; order and "stack with others" flag); trigger-maintained fee fields on the lead (status, full, discount, final).
- **Server:** approval-engine policies `discount.give` (role % limits: Caller 0, Team Lead 10, approvers 100; union across multiple roles) and `fee.change`; DB check: no discount > its head, total discounts ≤ full fee; waiver rule evaluator; job `fee-discounts` every 15 minutes expiring approved discounts after N days; notification kind `discount`.
- **App & web:** fee talk card on the lead page; "Give discount" sheet; Discounts queue (Approve / "Not now", shown only to approvers whose limit covers the request); Home "discount requests" banner; More → Discounts tile.
- **Settings & permissions:** `fees` keys: discount reason required, expiry days, waiver rules; policies `discount.give`, `fee.change`; old `discounts.approve*` mapped to the policy; `*` only for Super Admin.

**Tasks**
- [ ] 2.03-T1 Migrations for fee talk, events, discounts, waiver rules; RLS; leak test.
- [ ] 2.03-T2 Starting a fee talk moves the lead to Interested; every event goes to the timeline.
- [ ] 2.03-T3 Lead fee fields maintained by trigger; template variables `{fee}`, `{full_fee}`, `{discount}`, `{final_fee}`.
- [ ] 2.03-T4 Register policies `discount.give` and `fee.change` in the approval engine with default role limits; multiple roles = highest limit (D23).
- [ ] 2.03-T5 Manual discount on a head or the whole fee, amount or %, reason required (setting); within limit auto-approved, above limit → approval request.
- [ ] 2.03-T6 Database constraints: discount ≤ head, sum ≤ full fee, always checked server side.
- [ ] 2.03-T7 Waiver / scholarship rules engine (GPA, sibling from guardian link, staff child, quota, merit rank from 2.18), rule order and stacking setting; above-limit results go to approval.
- [ ] 2.03-T8 Discounts queue, Home banner, More tile, push to approvers, request age shown.
- [ ] 2.03-T9 Job `fee-discounts` (15 min, per-institution scheduler, idempotent) expiring approved discounts.
- [ ] 2.03-T10 Audit every request, approval and rejection.
- [ ] 2.03-T11 **Proposed:** escalation of an unanswered discount request to the next level after a set time.
- [ ] 2.03-T12 Collection-report hook: "discounts given" by person (report itself in 2.07).

**Tests**
- Unit: limit union for multi-role users; constraint rejects total discount > full fee; stacked waivers capped.
- RPC-as-real-role: Caller requests 15% → pending; Team Lead approves 10% only; Admin approves 100%.
- Role-matrix: queue shows only to approvers within limit; counsellor cannot see discount history (default).
- Job test: `fee-discounts` run twice expires once; runs in each institution's time zone.
- UI (Maestro): fee talk → discount request → approval → lead fields update.

**Done when (acceptance criteria)**
- A counsellor can quote, record lead asks and offers, and request a discount; the approver sees it within a minute (push + queue).
- A discount above the head or above the full fee is impossible, even through the API.
- Rule-based waivers apply automatically and respect order and stacking.
- Approved discounts expire after the configured days.

**Watch-outs (do not miss)**
- Collusion: role limits, mandatory reason, audit, discounts-by-person report (Ch 34.8 #1).
- New sensitive permissions are never in wildcards (Ch 11).
- Queue job must follow lesson 2 (attempts, back-off, given up, idempotency).

**Owner checkpoint:** Owner tries a discount request above the counsellor limit and approves it from the Discounts queue; confirms default role limits.

### 2.04 Student ID series and rules

**Goal:** Give every admitted student a unique, institution-defined ID through patterns or number ranges per course, batch or section.

**Depends on:** 2.01.

**Plan chapters:** Ch 33 (33.1–33.7), Ch 13 (session from academic calendar).

**Decisions:** D8.

**Build**
- **Data:** `client_number_rules` (scope offering / cohort / slot_group, pattern or range start–end, mode auto / manual / off, year source admission date / batch start); `client_number_series` (institution, year, course code, counter); `client_number_history` (old id, new id, reason, who); unique index (`institution_id`, student id).
- **Server:** pattern renderer for tokens `{YYYY}`, `{YY}`, `{SESSION}`, `{CODE}`, `{000…}`; `preview_next_client_number()` (no consumption); `take_client_number()` with row lock on the series in the caller's transaction, skipping IDs already used; range overlap check and 100,000 max; "Fill section ranges"; `renumber_all(preview)` (Admin only).
- **App & web:** Settings → ADMISSIONS → Student ID rules (rules list, summary of range usage, shared-series warning, gap display); search by student ID in lead list and global search.
- **Settings & permissions:** module "Student IDs" (Standard); label `student_id` (Roll, Registration no. …) and `doc.id_card_title`; neutral key `client_number`; permission for renumber (Admin, sensitive).

**Tasks**
- [ ] 2.04-T1 Migrations, unique index, RLS, leak test.
- [ ] 2.04-T2 Token renderer; `{SESSION}` taken from the academic calendar, not hard-coded (Ch 33.6 #6).
- [ ] 2.04-T3 Series per year (if pattern has a year) and per course code (if `{CODE}`).
- [ ] 2.04-T4 Rule precedence section > batch > course; range overlap validation; max 100,000 IDs per range.
- [ ] 2.04-T5 Range full → clear blocking error at admission.
- [ ] 2.04-T6 "Fill section ranges" for a batch.
- [ ] 2.04-T7 Summary: usage per range, gaps, warning when two batches share a series.
- [ ] 2.04-T8 Manual IDs must be unique and are logged; auto series skips existing IDs.
- [ ] 2.04-T9 Renumber everyone: Admin only, preview first, students already submitted to the board flagged (flag active once 2.16 exists), all old IDs logged.
- [ ] 2.04-T10 Seed patterns per type profile (coaching `{CODE}-{000}`, school `{YYYY}{CODE}{000}`).
- [ ] 2.04-T11 Register module, label, `{student_id}` template variable, ID search.
- [ ] 2.04-T12 **Proposed:** search by old ID; 90% range-full notification to Admin; branch as an extra rule scope.

**Tests**
- Unit: token rendering incl. year boundary in the institution time zone.
- Concurrency: 20 parallel `take_client_number()` calls give 20 distinct consecutive IDs.
- RLS + leak test; two institutions can have the same ID string.
- UI: create range rule, fill section ranges, preview next ID.

**Done when (acceptance criteria)**
- Preview shows the next ID without consuming it.
- Overlapping ranges are rejected; a full range blocks admission with a clear message.
- Renumber shows a full preview and logs every old ID.

**Watch-outs (do not miss)**
- Same next number in two parallel admissions (Ch 33.6 #1): lock + unique index.
- IDs are never reused; a cancelled admission keeps its ID (Ch 33.6 #5).

**Owner checkpoint:** Owner sets an ID pattern for a test college and sees the preview and the range summary.

### 2.05 Full admission transaction (admit, cancel, undo)

**Goal:** Complete `mark_admitted` and cancel admission with all Phase 2 side effects in one database transaction: seat lock, fee lock, student ID, follow-up closing, notifications, welcome message hook, and pluggable eligibility / papers checks.

**Depends on:** 2.01, 2.02, 2.03, 2.04, Phase 1 (pipeline stages, admitted basics, lost / reopen, notifications, `domain_events`, automation triggers, outbox).

**Plan chapters:** Ch 17 (17.5, 17.7, 17.8, 17.10), Ch 28 (28.5), Ch 34 (34.6), Ch 33 (33.4), Appendix A (`admission`, `admission_approval`).

**Decisions:** D8, D20.

**Build**
- **Data:** admission record (**Proposed:** separate `conversions` row so a student can later have more than one admission, Ch 17.10 #5); lead fields course, batch, section, admission date, student ID, fee locked flag; idempotency key on admit.
- **Server:** RPC `mark_admitted` (inputs: active course, batch per setting and within the course, section if the batch has sections, date, student ID, note); checks: seat with row lock on the batch (and section if Proposed capacity is set) unless overbooking allowed, eligibility check hook (activated in 2.11), papers check hook (activated in 2.12); side effects: close open follow-ups, lock fee, take student ID, reset board flow (hook for 2.16), notify officers, enqueue welcome message (2.16), write `domain_events` `conversion.created`. RPC `cancel_admission` (reason required; frees seat, unlocks fee, clears board flow, keeps student ID; warns if payments exist). "Undo admission" = cancel + reopen, both in history. RPC `change_final_fee` (policy `fee.change`; reason; 0 ≤ final ≤ full and ≥ already paid).
- **App & web:** full Admit sheet (course / batch / section pickers with seat counts, ID preview, eligibility / papers warnings, "pay now" slot filled in 2.06); Cancel admission sheet; Change final fee sheet.
- **Settings & permissions:** `conversion.mark`, `conversion.cancel` with scope (old `admission.mark` / `admission.cancel`); settings `admission` (batch required, overbooking allowed, eligibility mode, papers mode) and `admission_approval` (approval at admission).

**Tasks**
- [ ] 2.05-T1 Extend the Phase 1 admit RPC into the full transaction; all DB effects in one transaction, external effects through outbox / events.
- [ ] 2.05-T2 Seat check with row lock; second officer gets "Seat full — waiting list?"; overbooking only by setting and written to audit.
- [ ] 2.05-T3 Fee lock at admission (full fee and recurring rates); pending discounts cancelled, approved ones made permanent.
- [ ] 2.05-T4 Student ID taken in the same transaction (auto) or validated (manual); preview on the sheet.
- [ ] 2.05-T5 Idempotency: a repeated admit returns the earlier result (no second ID or payment).
- [ ] 2.05-T6 Pluggable pre-admission checks (eligibility, papers) returning block / warn / allow; default allow until 2.11 / 2.12.
- [ ] 2.05-T7 `admission_approval` setting: route admission through the approval engine when on.
- [ ] 2.05-T8 Cancel admission: reason, seat freed, fee unlocked, board flow cleared, ID kept, payment warning and pointer to refund (2.06).
- [ ] 2.05-T9 Undo admission = cancel + reopen in one action, both in timeline.
- [ ] 2.05-T10 Change final fee with policy `fee.change`, reason and bounds.
- [ ] 2.05-T11 Domain events and automation trigger "admitted" / "admission cancelled"; officer notifications.
- [ ] 2.05-T12 **Proposed:** admission as a separate record; before Undo with payments, require refund / approval step.
- [ ] 2.05-T13 AI credit at admission is deferred to Phase 4 (Ch 40); leave an event the Phase 4 credit job can consume.

**Tests**
- Concurrency: two officers admit into the last seat at the same time → exactly one succeeds.
- RPC-as-real-role: Admission Officer with branch scope cannot admit a lead in another branch.
- Unit: change final fee bounds; cancel keeps ID; re-admit gets the same ID.
- Idempotency: double tap on slow network creates one admission.
- UI (Maestro / Playwright): admit with section-required batch, cancel, undo.

**Done when (acceptance criteria)**
- Admission either fully happens or not at all; no half admissions on failure.
- Seat count, fee lock and ID are correct after admit, cancel and re-admit.
- Final fee can only change through the policy with a reason and within bounds.

**Watch-outs (do not miss)**
- Many side effects; outbox for SMS / push so their failure does not undo the admission (Ch 17.10 #1).
- Seat overbooking under load (Ch 28.10 #1, Ch 17.10 #2).
- Undo with payments leaves receipts inconsistent unless refund flow is followed (Ch 17.10 #6).

**Owner checkpoint:** Owner admits a test lead end to end on the phone and sees seat, fee lock and student ID update; then cancels and re-admits.

### 2.06 Manual payments, installments, void, verification and refunds

**Goal:** Let staff record cash, bank and send-money payments against admitted students, split fees into installments, void mistakes and issue refunds — never deleting a payment.

**Depends on:** 2.05, Phase 1 (approval engine).

**Plan chapters:** Ch 35 (35.1–35.4, 35.6, 35.10, 35.11), Ch 17 (17.5 pay now), Ch 11 (payment permissions).

**Decisions:** D14.

**Build**
- **Data:** `payments` (student or, for application / exam fee, lead / application; amount minor units; method; transaction ID; date; status recorded / to verify / verified / void; void reason; receipt number; optional institution receipt number; `branch_id`; sandbox flag for later); `installments` (≤ 24 lines, sum = final fee, due dates); `refunds` (amount ≤ net paid, reason, `RFD-YYYY-00001`); `receipt_series` and `refund_series` per institution per year; trigger-kept student totals (paid, net paid, due, next due).
- **Server:** RPCs `record_payment`, `verify_payment`, `void_payment` (policy `payment.void`), `create_refund` (policy `refund.create`; only for students whose admission is cancelled); receipt number `<prefix>-YYYY-00001` taken with lock, year from payment date in the institution time zone; payments fill the earliest installment first; domain event `payment.received` (automation trigger + outgoing webhook); notification kind `payment`.
- **App & web:** Take payment sheet (method list, transaction ID required for some methods, back-date up to N days, amount ≤ due), installment plan editor, payment history with VOID stamp, refund sheet, "pay now" on the Admit sheet with minimum amount.
- **Settings & permissions:** `fees` keys: methods (Cash, bKash, Nagad, Rocket, Bank, Card), transaction-ID-required methods, back-date days (default 7), institution receipt number off / optional / required (unique), pay-now minimum, verification mode; `receipt_prefix`; permissions `payment.create`, `payment.edit` with scope, policies `payment.void`, `refund.create`.

**Tasks**
- [ ] 2.06-T1 Migrations for payments, installments, refunds, series; RLS; leak test.
- [ ] 2.06-T2 Payment rules: only admitted students (except application / exam fees), amount ≤ due, back-date ≤ N days without Admin, no future date.
- [ ] 2.06-T3 Receipt series per year per institution with lock; voided numbers never reused; year boundary in institution time zone.
- [ ] 2.06-T4 Optional institution receipt number (off / optional / required, unique).
- [ ] 2.06-T5 Installment editor: up to 24 lines summing to final fee; earliest-first allocation; "Next due".
- [ ] 2.06-T6 Void through policy `payment.void` with reason; payment never deleted.
- [ ] 2.06-T7 Refund only for cancelled admissions; amount ≤ net paid (payments − refunds); `RFD-` series; policy `refund.create`.
- [ ] 2.06-T8 **Proposed:** "to verify" status for send-money payments, confirmed by a second person (or same officer by setting) through the approval pattern; unverified payments flagged in reports.
- [ ] 2.06-T9 **Proposed:** warning when the same method + transaction ID is entered twice in one institution.
- [ ] 2.06-T10 "Pay now" on the Admit sheet with configured minimum.
- [ ] 2.06-T11 Trigger-kept totals on the student (paid, due, next installment, next due date) and template variables `{paid}`, `{due}`, `{next_installment}`, `{next_due_date}`.
- [ ] 2.06-T12 Domain event `payment.received`, automation trigger, outgoing webhook, staff notification kind `payment`.
- [ ] 2.06-T13 Map old `payments.manage`, `payments.who`, `void_who` to new permissions / policies.
- [ ] 2.06-T14 **Proposed:** end-of-day cash close per person.

**Tests**
- Unit: allocation to earliest installment; net paid; refund cap; year-boundary receipt numbering (31 Dec 23:59 Dhaka).
- Concurrency: parallel payments get consecutive receipt numbers, no duplicates.
- RPC-as-real-role: Caller cannot record payment; Accountant with branch scope only in branch.
- Role-matrix: void and refund need policy approval above limits.
- UI (Maestro / Playwright): pay now on admit, installment plan, void, refund.

**Done when (acceptance criteria)**
- Staff can record a payment in under 30 seconds and the student's due and next due update immediately.
- No payment can be deleted; void keeps the record with reason and VOID state.
- Refunds are possible only for cancelled admissions and never exceed net paid.
- Receipt numbers are unique, yearly, per institution, with no reuse.

**Watch-outs (do not miss)**
- Fake send-money transaction IDs (Ch 35.11 #1, risk O3).
- Cash fraud via later void (Ch 35.11 #6): reason, policy, report of recent voids by person.
- Year boundary numbering (Ch 35.11 #7).

**Owner checkpoint:** Owner records a bKash payment, sees it verified by a second user, voids a test payment and issues a refund after cancellation.

### 2.07 Printable receipts and collection report

**Goal:** Produce branded printable receipts and give admins a collection report by method, person and branch.

**Depends on:** 2.06, Phase 1 (group dashboard, report scope, templates and outbox).

**Plan chapters:** Ch 35 (35.5, 35.8, 35.11 #9), Ch 13 (lakh format, Bangla digits), Ch 12 (branch details), Ch 5 (group dashboard).

**Decisions:** D1, D5, D25.

**Build**
- **Data:** receipt design in `fees` setting (template classic / modern / minimal, size A4 / A5 / A4 with two copies / POS 80 mm, accent colour, logo, title, header lines, 0–3 signatures, amount in words, PAID / VOID stamp, chosen fields, footer); daily summary table by day and method (trigger-maintained) for the report.
- **Server:** receipt render data RPC; collection report RPC (collected, refunded, net by method and person, branch split; current due and overdue; discounts given; recent voids; unverified payments; reconciliation mismatches added in 2.10); `jit = off` on heavy report functions.
- **App & web:** receipt designer with live preview in Settings → ADMISSIONS → Fee & discount; print via expo-print on phone and an iframe on web; share as text; send receipt to student / guardian by SMS / email (outbox, transactional); collection report screen; group owner sees each institution's collection read-only on the group dashboard.
- **Settings & permissions:** label `doc.receipt_title` (default "Money Receipt"); report scope permission (Ch 11, Ch 38); receipt message type in the recipient matrix.

**Tasks**
- [ ] 2.07-T1 Receipt designer settings and live preview.
- [ ] 2.07-T2 Render receipt with institution branding (name, logo, address, phone) and branch details when branches exist.
- [ ] 2.07-T3 Amounts in lakh format, optional Bangla digits, amount in words (bn / en).
- [ ] 2.07-T4 Print on phone (expo-print) and web (iframe); four paper sizes incl. POS 80 mm.
- [ ] 2.07-T5 Share as text; send receipt by SMS / email as a transactional message (not stopped by promotional opt-out).
- [ ] 2.07-T6 Register label `doc.receipt_title` and receipt message type in recipient matrix defaults.
- [ ] 2.07-T7 Trigger-maintained daily summary by day / method / person / branch.
- [ ] 2.07-T8 Collection report RPC and screen with all Ch 35.8 sections; scope by report permission.
- [ ] 2.07-T9 Group dashboard (Phase 1) extended with per-institution collection, read-only.
- [ ] 2.07-T10 Benchmark with a large and a small institution.

**Tests**
- Screenshot: all three templates × four sizes, light print, bn / en.
- Unit: amount in words in Bangla and English; VOID stamp on voided receipts.
- RPC-as-real-role: report scope (branch manager sees own branch only); group owner read-only.
- Performance: collection report on a busy-season dataset under target.

**Done when (acceptance criteria)**
- A receipt prints correctly on A4, A5, A4 two-copy and 80 mm POS from phone and web.
- The collection report totals match the payment table exactly.
- A group owner sees all member institutions' collections but cannot change anything.

**Watch-outs (do not miss)**
- Slow report in busy season (Ch 35.11 #9): summary tables, `jit = off`, benchmark.
- Receipts to minors' guardians by default in schools (Ch 24.6).

**Owner checkpoint:** Owner designs a receipt, prints it on a POS printer and reviews the collection report.

### 2.08 Students tab and placement

**Goal:** Give officers one place for admitted students (`client`) with summary, chips, filters, sorting, the web table, and single and bulk placement.

**Depends on:** 2.05, 2.06, 2.07, Phase 1 (lists and filter engine, export controls, Home / web shell, caching).

**Plan chapters:** Ch 36 (36.1–36.3, 36.6), Ch 45 (Home card, web Students table), Ch 47 (caching), Ch 23 (export rules).

**Decisions:** D8, D10.

**Build**
- **Data:** trigger-kept counters per student (paid, due, overdue, last paid, next installment); student custom fields via the same field builder.
- **Server:** `students_overview()` single RPC (summary: students, new this month, with due, due amount, overdue, collected this month, papers missing; chip counts; page of rows); placement RPC (course / batch / section change with seat check, fee re-lock, new student ID in auto mode, history); bulk placement RPC with preview (who moves, seats, new IDs, fee changes) and all-or-nothing commit.
- **App & web:** Students tab (chips All, Mine, Due, Overdue, Paid, Papers missing, New this month, board-flow chips; paid ranges ৳0, 1–999, 1,000+, 5,000+, 10,000+, custom, paid this week / month; sorts listed in Ch 36.2; search by student ID and board ID; list total paid); web Students table (sortable columns, column chooser, density, multi-select, Excel export, right panel, row ⋯ menu: payment, note, upload paper, flow step, section, board ID, student ID, change fee, papers popup, all notes); web opens Students instead of Home; phone Home "Students summary" card.
- **Settings & permissions:** `client.view` / `client.edit` / `client.export` with scope (old `students` "who" setting); label `student`, `module.students`; neutral key `client`.

**Tasks**
- [ ] 2.08-T1 Counters by trigger; `students_overview()` returns summary, chips and rows in one call (lesson 8).
- [ ] 2.08-T2 Students tab on phone with summary tiles that filter on tap.
- [ ] 2.08-T3 Chips, paid ranges, sorting, search by student ID (board ID search active from 2.16).
- [ ] 2.08-T4 Web Students table with all row actions; Home on web opens Students.
- [ ] 2.08-T5 Student custom fields in the field builder.
- [ ] 2.08-T6 Excel export through Phase 1 export controls (permission, scope, approval for large exports, user name stamp, log).
- [ ] 2.08-T7 Placement RPC with seat check, fee re-lock, new ID in auto mode (old ID logged), timeline / audit entry.
- [ ] 2.08-T8 Bulk placement: preview, then all-or-nothing; full failure list with reasons.
- [ ] 2.08-T9 Stale-while-revalidate cache for the tab (Ch 47).
- [ ] 2.08-T10 Register permissions, labels, module and Home card; "Papers missing" chip shows once 2.12 counters exist, board-flow chips once 2.16 exists.

**Tests**
- Performance: Students tab opens from cache instantly and refreshes under target on the ≈3,000-lead benchmark (with ≈1,000 students).
- RPC-as-real-role: "Mine" vs branch vs all scope; counsellor sees own students only.
- Unit: bulk placement rolls back fully if one seat check fails.
- UI (Playwright): web table column chooser, multi-select, export; Maestro: phone chips and placement.
- Screenshot: Students tab light / dark × bn / en with "Trainees" label.

**Done when (acceptance criteria)**
- Officer can answer "who owes, who is overdue, who has papers missing" from one screen.
- Bulk placement either moves everyone or nobody, after a preview.
- Export follows Phase 1 export rules and is logged.

**Watch-outs (do not miss)**
- Slow tab from per-row queries (Ch 36.6 #1).
- Half-done bulk placement (Ch 36.6 #2).
- Export as data theft route (Ch 36.6 #8, risk R9).
- No guardian / student portal (D10).

**Owner checkpoint:** Owner opens the Students tab on phone and web for a seeded college and moves three students to another section in one bulk action.

### 2.09 Recurring invoices, late fees, reminders and payment messages

**Goal:** Automatically create monthly / term / credit invoices, apply late fees, remind staff and message students or guardians about dues, late payments and receipts.

**Depends on:** 2.06, 2.07, 2.08, Phase 1 (job scheduler, recipient matrix, consent / quiet hours, outbox).

**Plan chapters:** Ch 34 (34.2 invoices, 34.8 #4, #7), Ch 35 (35.4, 35.7), Ch 44 (`fee-payments`, monthly / term invoices), Ch 24 (24.5, 24.6, 24.8), Ch 14 (guardian with several children).

**Decisions:** D1, D5.

**Build**
- **Data:** `invoices` (student, head, period, amount at locked rate, due date, late fee) with unique key (student, head, period); reminder log (one per reminder type per installment / invoice).
- **Server:** job "monthly / term invoices" (per institution, its time zone, small batches, round-robin, back-off); late fee by head rule; job `fee-payments` hourly from 09:00 institution time: staff reminders N days before and on due date, late after N days to owner + Team Lead + admins; student / guardian messages "payment due" and "payment late" (default channel email + SMS, Master Admin can change, D5), guardian default for schools and minors, one combined message for a guardian with several children; quiet hours respected; transactional not stopped by promotional opt-out.
- **App & web:** invoice list on the student; reminder settings in Fee & discount.
- **Settings & permissions:** `fees` reminder keys (days before, late days, channels); message types payment due / late in the recipient matrix with type-profile defaults.

**Tasks**
- [ ] 2.09-T1 `invoices` table with unique (student, head, period); RLS; leak test.
- [ ] 2.09-T2 Invoice job, idempotent, per institution time zone, batched, fair share; modules off → skipped.
- [ ] 2.09-T3 Invoices use the locked post-discount rate; new rates apply only to new students.
- [ ] 2.09-T4 Late fee rule per head applied by the job.
- [ ] 2.09-T5 **Proposed:** per-credit fee: credits per semester as an invoice input (manual or import); credit transfers via custom records (2.20).
- [ ] 2.09-T6 `fee-payments` job: staff reminders before / on due date and late escalation; each reminder sent once.
- [ ] 2.09-T7 Student / guardian due and late messages through outbox with recipient rules (guardian default in schools, under-18 rule, combined message for siblings).
- [ ] 2.09-T8 Quiet hours and time zone respected; transactional class not blocked by promotional opt-out.
- [ ] 2.09-T9 Job run log visible on Master Admin health dashboard.
- [ ] 2.09-T10 Seed message templates for due, late and receipt per type profile (bn / en).

**Tests**
- Job: run the invoice job twice for the same period → one invoice; catch-up after downtime.
- Multi-time-zone test institutions: reminders at local 09:00.
- Unit: combined guardian message for two children lists each child's due.
- Role-matrix: suspended / read-only institution sends no messages (OTP still works).

**Done when (acceptance criteria)**
- A school's monthly tuition invoices appear on the configured day with no duplicates.
- Staff and guardians receive exactly one reminder per due / late event, at the right local time.
- Promotional opt-out does not stop a due reminder; "stop all" does.

**Watch-outs (do not miss)**
- Double invoicing on job re-run (Ch 34.8 #4).
- Queue bugs and endless re-claim (lesson 2, Ch 44.5 #3).
- Wrong recipient for minors (Ch 24.7 #6).

**Owner checkpoint:** Owner sees a month of simulated invoices and reminders for a school test institution and approves default channels for due / late messages.

### 2.10 Online payment via SSLCommerz

**Goal:** Accept online payments for application fee, admission fee, monthly / term fees and installments through SSLCommerz, with money going straight to each institution's own merchant account.

**Depends on:** 2.06, 2.07, 2.09, Phase 0 (integration hub, Vault, webhook router, usage ledger, setup checklist), Phase 1 (public application form, sandbox / fake adapters in CI, custom domain).

**Plan chapters:** Ch 35 (35.9, 35.11 #2–#5, #8, #10), Ch 42 (42.2, 42.6, 42.8, 42.9 I1–I4, I8), Ch 27 (27.3 application fee), Ch 6 (merchant account step), Ch 9 (9.7 gateway fee).

**Decisions:** D11, D14, D15, D17.

**Build**
- **Data:** payment `integration_connections` (kind payment, provider SSLCommerz, mode sandbox / live, live-test-passed flag); `gateway_transactions` (invoice, amount from server, status initiated / pending / success / failed, provider ref, idempotency key, sandbox flag); usage ledger rows for gateway fees with payer (institution direct / platform, D15).
- **Server:** SSLCommerz adapter `create`, `verify`, `refund`, `parse_callback`; Edge Function to start a payment (amount and invoice from server only); callback at `/hooks/<provider>/<connection_id>` with signature check using that connection's secret; server-to-server verify before "paid"; idempotent callback; success creates payment + receipt automatically; live disabled until one live test succeeds; connection always looked up from the record's `institution_id` on the server.
- **App & web:** Master Admin panel → Institutions → \<institution\> → Payments (test mode, keys to Vault, "test payment" button, mode badge); "Pay online" on invoices / installments for staff to share; application fee step on `/apply/<slug>`; payment status (failed / pending) on the student.
- **Settings & permissions:** module "Online payment" (optional); `integration.manage` (Master Admin only for payment keys); setup checklist item "open your SSLCommerz merchant account" (Ch 6).

**Tasks**
- [ ] 2.10-T1 SSLCommerz adapter behind the hub's payment interface; versioned; fake adapter for CI.
- [ ] 2.10-T2 Master Admin Payments screen: sandbox first, keys in Vault (hint only), test payment button, live gate.
- [ ] 2.10-T3 Setup checklist step for the institution's own merchant account (trade licence, bank account, verification).
- [ ] 2.10-T4 Start-payment Edge Function: amount and invoice computed on server; client amount ignored.
- [ ] 2.10-T5 Webhook route with per-connection signature verification; idempotency key; duplicate callbacks processed once.
- [ ] 2.10-T6 Server-to-server verification; amount mismatch → not paid, goes to mismatch list (2.11).
- [ ] 2.10-T7 Success → payment + receipt (2.06 / 2.07) automatically; failed / pending shown with state.
- [ ] 2.10-T8 Application fee on the public form (Ch 27) and exam fee hook for 2.17.
- [ ] 2.10-T9 Gateway fee in the usage ledger with payer per D15; only platform-paid fees reach the institution bill.
- [ ] 2.10-T10 Sandbox payments marked and excluded from reports.
- [ ] 2.10-T11 Two-institution test proving each uses its own merchant account (I1).
- [ ] 2.10-T12 Privacy policy lists SSLCommerz (I11).

**Tests**
- Integration with sandbox: success, fail, cancel, duplicate callback, forged callback (bad signature rejected), tampered amount.
- Cross-tenant: institution A's invoice can never be paid into B's merchant (I1).
- RPC-as-real-role: only Master Admin can write payment keys; institution Super Admin sees status only.
- UI (Playwright): public form → application fee → receipt.

**Done when (acceptance criteria)**
- A test institution in sandbox can take an application fee and an installment online, and a receipt appears automatically.
- Live payments are blocked until a live test payment passes.
- A forged or duplicated callback never creates a second or fake payment.
- Money settles to the institution's own merchant account; the platform never holds it.

**Watch-outs (do not miss)**
- Amount tampering (Ch 35.11 #2); late / duplicate / fake callbacks (#3, I4); wrong institution's merchant (#4, I1); aggregator legal risk (#8, risk O2) — D17 only; sandbox vs live confusion (#10, I3).
- No portal (D10): students pay through the public form or staff-shared links.
- Other gateways (bKash, Nagad direct …) are later (Ch 52.8); open question which first (Ch 53).

**Owner checkpoint:** Owner (as Master Admin) sets up SSLCommerz sandbox for a test institution, runs a test payment and sees the "live blocked until test passes" state.

### 2.11 Reconciliation, pending payments, gateway refunds and payment link

**Goal:** Close the online-payment loop: time out pending payments, reconcile daily with the gateway, list mismatches, and refund through the gateway where supported.

**Depends on:** 2.10.

**Plan chapters:** Ch 35 (35.6 gateway refunds, 35.8 mismatch list, 35.9 reconciliation, 35.11 #5), Ch 42 (42.6, I4, I5), Ch 44 (online payment reconciliation job).

**Decisions:** D11, D14, D17.

**Build**
- **Data:** `reconciliation_items` (transaction, gateway status, app status, amount difference, resolved by / note).
- **Server:** daily reconciliation job per institution (gateway verify for each transaction of the day, pending timeout → verify → paid / failed / mismatch); gateway `refund` through adapter when supported, else manual refund record; circuit breaker and health status from the hub.
- **App & web:** mismatch list for officers (and in the collection report); refund via gateway option on the refund sheet; gateway status shown (refund, chargeback, settlement are between institution and SSLCommerz — app shows status only).
- **Settings & permissions:** pending timeout setting; who resolves mismatches (`payment.edit` scope).

**Tasks**
- [ ] 2.11-T1 Pending timeout and verify step in the job (idempotent, back-off, given up).
- [ ] 2.11-T2 Daily reconciliation job in institution time zone; results to `reconciliation_items`.
- [ ] 2.11-T3 Mismatch list screen and section in the collection report.
- [ ] 2.11-T4 Gateway refund via adapter; manual fallback.
- [ ] 2.11-T5 Health check and alerts to Master Admin on repeated failures (circuit breaker).
- [ ] 2.11-T6 **Proposed:** single-use payment link per invoice sent by SMS / email, no login, with expiry.
- [ ] 2.11-T7 Daily sandbox contract test for the SSLCommerz adapter (I5).

**Tests**
- Job: callback never arrives → pending resolved by reconciliation; job re-run makes no duplicate payment.
- Unit: mismatch when gateway amount ≠ invoice.
- Integration (sandbox): gateway refund status flows back.

**Done when (acceptance criteria)**
- Every online transaction is either paid, failed or on the mismatch list within one day.
- Officers can resolve a mismatch with a note; the report shows open mismatches.

**Watch-outs (do not miss)**
- Callbacks late / twice / never (Ch 35.11 #3).
- Payment link must not leak other students' data (no portal, D10).

**Owner checkpoint:** Owner reviews a reconciliation run with one forced mismatch and decides whether the payment link (Proposed) is wanted.

### 2.12 Eligibility rules

**Goal:** Flag or block ineligible leads per course using GPA, group, age on a date, gender and previous level, and tell public-form applicants early.

**Depends on:** 2.01, 2.05, Phase 0 (custom field builder and presets), Phase 1 (lead list filters, public form, approval engine).

**Plan chapters:** Ch 29 (29.1–29.6), Ch 15 (Not eligible filter), Ch 27 (public form), Ch 13 (dates in institution time zone).

**Decisions:** D8.

**Build**
- **Data:** `eligibility_rules` (offering, condition type min GPA overall / by subject, required group, age range on a date, gender, required previous level; version); stored result on lead per course: eligible / not eligible / **Proposed:** no data; failed-conditions text.
- **Server:** evaluator reading lead fields and custom fields (GPA 0–5 two decimals, SSC / HSC GPA, board, roll, registration no., passing year, previous institution, date of birth, group); result recomputed by trigger on lead save and by a background job on rule change; rule-change impact preview; public form check RPC; admission check plugged into 2.05 (warn or block).
- **App & web:** Settings → ADMISSIONS → Admission rules; warning on lead page listing failed conditions; "Not eligible" and "No data" filters; public form message.
- **Settings & permissions:** setting eligibility mode warn / block (under `admission`); `settings.admission_rules` area permission; **Proposed:** override with reason as an approval-engine policy (audited).

**Tasks**
- [ ] 2.12-T1 Rules table with versioning; RLS; leak test.
- [ ] 2.12-T2 Evaluator for all five condition types; age computed by date only in institution time zone.
- [ ] 2.12-T3 Stored result + trigger on lead save; job for recompute on rule change.
- [ ] 2.12-T4 Impact preview before saving a changed rule; audit entry.
- [ ] 2.12-T5 Lead page warning and list filters.
- [ ] 2.12-T6 Activate the 2.05 admission check (warn / block per setting).
- [ ] 2.12-T7 Public form uses the same rules; result is information only.
- [ ] 2.12-T8 Seed sample rules per type profile (school age by class, college SSC GPA + group, polytechnic SSC GPA, nursing strict subject / GPA).
- [ ] 2.12-T9 **Proposed:** "no data" state that never blocks; override with reason via approval policy; equivalence table for O / A level and foreign grades.
- [ ] 2.12-T10 Show gender / age conditions clearly on the public form; log every override.

**Tests**
- Unit: age boundary day (Class 1, 6+ on 1 January) in Asia/Dhaka and one other time zone; GPA by subject.
- Performance: "Not eligible" filter on ≈3,000 leads uses the stored field.
- RPC-as-real-role: block mode stops Admit for Admission Officer; override needs policy.
- UI: public form shows ineligible message.

**Done when (acceptance criteria)**
- Counsellors see "Not eligible" before calling; leads without data are not marked ineligible (if Proposed state approved).
- Block mode stops admission; warn mode shows the reasons.

**Watch-outs (do not miss)**
- Missing data marked ineligible (Ch 29.5 #1); slow per-row evaluation (#2); mid-season rule change (#3); applicants overstating GPA — papers verify (#5); discrimination complaints (#7); time zone boundary (#8).

**Owner checkpoint:** Owner approves the three Proposed items (no-data state, override, equivalence table) and sees a school age rule working.

### 2.13 Required papers, paper status and upload rules

**Goal:** Track which papers each lead must give, what has been received (original or copy, where kept, original returned), and define upload rules for files.

**Depends on:** 2.05, 2.08.

**Plan chapters:** Ch 31 (31.1–31.3, 31.6, 31.7 — not Photo Studio), Ch 28.8 (`document_types` dropped), Ch 15, Ch 24 (`{papers_missing}`), Ch 36 (Papers missing chip).

**Decisions:** D8, D22.

**Build**
- **Data:** `document_requirements` (name, description, required, course or all, order, accepted type any / image / pdf, image size, KB limit, passport photo options); `lead_documents` (received / not needed, original / copy, kept at, original returned, who / when); trigger-kept lead counters (required, received, originals held, missing).
- **Server:** papers check plugged into 2.05 (block / warn / allow); **Proposed:** nightly counter verification job that fixes and logs mismatches.
- **App & web:** Settings → ADMISSIONS → Required papers, Paper types; Settings → Web only → Upload rules (`upload_rules`); papers card on lead page and Students row popup; filters and sorts on counters; in-browser image resize and compression before upload; timeline entries for "kept at" and "original returned".
- **Settings & permissions:** `upload_rules` (web only edit); papers mode in `admission`; separate permission and scope to view paper files (Ch 11); label `papers`; neutral key `documents`.

**Tasks**
- [ ] 2.13-T1 Migrations; RLS; leak test.
- [ ] 2.13-T2 Paper types and required papers settings; seed per type profile (school: birth registration, TC, photo, guardian NID; coaching: photo only; nursing / medical: many).
- [ ] 2.13-T3 Per-lead status card with original / copy, kept at, original returned; every change in timeline with who and when.
- [ ] 2.13-T4 Trigger-kept counters; list filters / sorts; `{papers_missing}` variable; activate Students "Papers missing" chip.
- [ ] 2.13-T5 Activate 2.05 papers check (block / warn / allow).
- [ ] 2.13-T6 Upload rules editor (web only) and browser-side resize / compression.
- [ ] 2.13-T7 Paper file view permission with scope; view and download logged.
- [ ] 2.13-T8 Custom field type "file (paper)" linked to requirements; public form uploads mapped to requirements.
- [ ] 2.13-T9 **Proposed:** nightly counter verification job; printable original-returned receipt.

**Tests**
- Unit: counters after bulk changes; papers check modes.
- Role-matrix: user without paper-view permission cannot open files.
- Screenshot: papers card light / dark × bn / en.

**Done when (acceptance criteria)**
- Officers can see what is missing and where each original is kept for every student.
- Admit respects the papers mode.

**Watch-outs (do not miss)**
- Very sensitive papers incl. children's NID / birth records (Ch 31.6 #1): separate permission, logs, never to AI.
- Original lost disputes (Ch 31.6 #6); counter drift (#7).

**Owner checkpoint:** Owner configures required papers for a school and marks papers received for a test student.

### 2.14 File storage: Google Drive and platform storage

**Goal:** Store papers and voice-note files in each institution's own Google Drive (Apps Script, via the integration hub) or in platform storage, with all access through Edge Functions.

**Depends on:** 2.13, Phase 0 (integration hub, Vault), Phase 1 (voice notes, soft delete).

**Plan chapters:** Ch 32 (32.1–32.7), Ch 42 (42.7 Drive row, I1, I2, I14), Ch 4 (storage paths), Ch 5 (institution close).

**Decisions:** D4, D22.

**Build**
- **Data:** "storage" `integration_connections` (Apps Script URL, secret in Vault, hint only); `files` table (provider, file id, lead / student, paper, uploaded by, size, soft-delete); platform storage paths starting with `institution_id`.
- **Server:** Edge Functions `drive-connect` (ping, save, create root folder), `drive-upload` (≤ 35 MB, re-check upload rules, compress, auto-tick paper as "received, copy"), `drive-file` (stream; Drive link never exposed), `drive-delete` (move to Drive trash), `drive-zip` (≤ 60 files / 60 MB per lead); connection always resolved from the record's `institution_id`; queue and retry for quota errors; health check.
- **App & web:** Settings → DATA → Google Drive (step-by-step guide, Test button, status); Files card on the lead page (list, open, delete, ZIP; camera or file upload); folder naming `Lead Management/<Student ID Name | Name – Phone>/Papers | Voice notes` (renamed after admission).
- **Settings & permissions:** `files` (on / off; who sees all files → scoped permission own / team / branch / all); module "Google Drive files and Photo Studio" (Pro); hidden module keeps the file list.

**Tasks**
- [ ] 2.14-T1 Storage connection kind in hub; Apps Script setup guide; Test button; health status to Master Admin.
- [ ] 2.14-T2 `files` table, RLS, leak test including storage policies.
- [ ] 2.14-T3 Five Edge Functions with limits; server re-validation of upload rules.
- [ ] 2.14-T4 Platform storage alternative with institution-prefixed paths; **Proposed:** short-lived signed URLs only for platform storage.
- [ ] 2.14-T5 Folder naming before / after admission and rename on admission.
- [ ] 2.14-T6 Files card with camera / file upload, progress and retry; ZIP download.
- [ ] 2.14-T7 Scoped file view permission; logs of view / download.
- [ ] 2.14-T8 Soft delete in app + Drive trash; restore.
- [ ] 2.14-T9 Usage per institution in the ledger (bandwidth, function calls).
- [ ] 2.14-T10 Institution close: full export, connection disabled, secret deleted, platform files removed after notice.
- [ ] 2.14-T11 Setup checklist advice to use an institution-owned Google account (Proposed).
- [ ] 2.14-T12 Migration path between storages using the file list.

**Tests**
- Cross-tenant: A's file never goes to B's Drive; storage path / policy leak test.
- Integration: upload 35 MB OK, 36 MB rejected; ZIP of 60 files.
- RPC-as-real-role: own-only scope cannot stream others' files.
- Secret never in logs (log scan).

**Done when (acceptance criteria)**
- Staff upload and view files without any Google sign-in; Drive links are never shown.
- A lead's files download as one ZIP.
- Switching off the module hides the card; the file list stays.

**Watch-outs (do not miss)**
- Wrong deployment / URL (Ch 32.6 #1); Drive owner leaves (#2); Apps Script quotas (#3); streaming cost (#4); tenant leak (#5); secret leak (#6, lesson 12); institution leaving (#7); accidental delete (#8).

**Owner checkpoint:** Owner connects a test Google Drive using the guide and uploads a paper from the phone camera.

### 2.15 PDF / photo services and passport photo

**Goal:** Compress oversized PDFs with iLovePDF and cut out passport photos with remove.bg through hub connections, with in-browser crop and editor.

**Depends on:** 2.13, 2.14.

**Plan chapters:** Ch 31 (31.3, 31.4, 31.6 #2–#5, #8), Ch 42 (42.7 PDF / photo row, I11).

**Decisions:** D22.

**Build**
- **Data:** PDF / photo `integration_connections` (several accounts per institution with priority, monthly counter, quota state).
- **Server:** compression inside `drive-upload` for PDFs above the limit, trying accounts in priority order; `photo-cutout` Edge Function calling remove.bg accounts in order; quota warning and "keep without compression" fallback with message; institution may disable external services (browser-only processing).
- **App & web:** per-paper passport photo options (on / off, background colour, face %); browser steps: cutout, head detection, auto-crop, fixed size; editor (move, zoom, rotate, background, brightness); phone: camera upload with simple compression only.
- **Settings & permissions:** service on / off per institution; `integration.manage` for accounts (Master Admin).

**Tasks**
- [ ] 2.15-T1 iLovePDF and remove.bg adapters with priority and monthly counters.
- [ ] 2.15-T2 Quota-end fallback with clear message; early warning before quota ends.
- [ ] 2.15-T3 PDF compression path in `drive-upload`.
- [ ] 2.15-T4 `photo-cutout` function and browser passport-photo pipeline.
- [ ] 2.15-T5 Manual editor always available; fallback to simple crop when face detection fails.
- [ ] 2.15-T6 Switch to disable external services per institution; privacy policy names both services.
- [ ] 2.15-T7 **Proposed:** chunked upload for large files.
- [ ] 2.15-T8 Photo Studio (Ch 31.5, `photo_presets`) is deferred to Phase 5.

**Tests**
- Integration with fake adapters in CI: priority order, counter, quota fallback.
- UI (Playwright): passport photo with hijab / low light sample falls back to manual crop.

**Done when (acceptance criteria)**
- An oversized PDF is compressed under the KB limit or kept with a warning when all quotas are used.
- A passport photo of the configured size and background is produced in the browser.

**Watch-outs (do not miss)**
- Third-party data sharing (Ch 31.6 #2); quota exhaustion mid-season (#3); slow networks (#4); face detection failures (#5); heavy processing on cheap phones (#8).

**Owner checkpoint:** Owner sees a passport photo produced from a phone picture and a compressed PDF.

### 2.16 External board flow and post-admission messages

**Goal:** Track configurable after-admission steps such as university / board registration (`after_steps`), and send students or guardians welcome, batch-start and ID-issued messages.

**Depends on:** 2.04, 2.05, 2.06, 2.08, 2.13, Phase 1 (notifications, recipient matrix, templates).

**Plan chapters:** Ch 36 (36.4, 36.5, 36.6 #3–#7), Ch 17 (reset / clear), Ch 24 (student messages), Ch 25 (notification kinds), Ch 42 (boards row), Ch 28.2 (admission fee threshold).

**Decisions:** D8, D10.

**Build**
- **Data:** `after_step_definitions` (name, order, conditions: previous step, minimum net paid, required papers, required fields; board ID label); `client_after_steps` (student, step, done at, by, board ID, undo reason); board ID unique per institution + board + session (**Proposed** scope).
- **Server:** RPCs `mark_step`, `bulk_mark_received` (ready students only, others listed with reasons), `undo_step` (reason; later steps first); default steps Submitted Online (board ID required, unique) and Received by institution (Submitted + net paid ≥ course admission fee, error shows remaining amount); "ready" notification to officers with live toast and badge on web; admit resets and cancel clears the flow; warning on refund after Received; file import of board results where possible.
- **App & web:** Settings → ADMISSIONS → Admission flow (steps, names, board ID label, money and paper conditions, admission fee default, flow on / off); board-flow chips on Students; row actions; officer Home card (not submitted / ready); board ID search.
- **Settings & permissions:** module "External board flow" (Standard; off by default for school and coaching profiles); labels `external_board`, `board_id`, `module.admission_flow`; notification kinds admission-flow step and board "ready"; post-admission message types welcome, class / batch start, ID issued.

**Tasks**
- [ ] 2.16-T1 Migrations; RLS; leak test; steps as data (no board names in code).
- [ ] 2.16-T2 Seed default steps; per-type-profile module defaults.
- [ ] 2.16-T3 Conditions engine (previous step, min net paid with course override, required papers, required fields).
- [ ] 2.16-T4 Mark, bulk received, undo with order rule; admit reset / cancel clear hooks into 2.05.
- [ ] 2.16-T5 Board ID uniqueness check showing which student holds a duplicate.
- [ ] 2.16-T6 Ready notification, web live toast and badge, Home card counts.
- [ ] 2.16-T7 Students chips and board ID search; flag board-submitted students in renumber (2.04) and placement previews (2.08).
- [ ] 2.16-T8 Refund-after-Received warning (no automatic undo).
- [ ] 2.16-T9 Board result file import (where boards provide files).
- [ ] 2.16-T10 Welcome (at admit), class / batch start, ID issued messages through the recipient matrix, consent and quiet hours; templates seeded.
- [ ] 2.16-T11 **Proposed:** optional deadline per step with reminder and "time running out" Home card.

**Tests**
- Unit: Received blocked until net paid ≥ threshold; error states remaining amount.
- RPC-as-real-role: bulk received marks only ready students.
- UI: configure a custom step for a polytechnic profile; undo order enforced.

**Done when (acceptance criteria)**
- A college officer sees who is not submitted and who is ready, and can bulk-mark received.
- Each institution can rename steps, set conditions or turn the flow off.
- Students receive welcome / ID issued messages per the recipient matrix.

**Watch-outs (do not miss)**
- Board-specific code (Ch 36.6 #4); board ID repeats across years (#5); refund after Received (#6); ID change vs board data (#7); missed board deadlines (#3).
- No portal (D10).

**Owner checkpoint:** Owner runs a National University–style flow for a test college and approves the Proposed step deadline.

### 2.17 Admission test: sessions, registration, admit card and marks

**Goal:** Run admission tests: sessions, registration of leads, printable admit cards, attendance and marks entry or import.

**Depends on:** 2.01, 2.10, 2.13, Phase 1 (pipeline stages, templates, recipient matrix, import with preview).

**Plan chapters:** Ch 30 (30.1–30.3 attendance / marks, 30.6, 30.7 #1, #7, #8), Ch 22 (test as score signal), Ch 49 (neutral key `assessment`).

**Decisions:** D1, D5, D8.

**Build**
- **Data:** `assessment_sessions` (date, time, venue / room, capacity, courses, optional fee); `assessment_registrations` (lead, session, roll, attendance); `assessment_scores` (several mark parts incl. viva, total); draft state.
- **Server:** register RPC (capacity check); exam fee through 2.10 (online) or 2.06 (manual, lead-level); marks import with preview and dry run; admit card render data; SMS / email to applicant with details (outbox).
- **App & web:** test sessions screen, registration from lead page / bulk, printable admit card with photo and roll (staff print or applicant's own link only), attendance and marks entry, Excel import.
- **Settings & permissions:** module "Admission test and merit list" (Standard; school, university, some colleges; off → menus, cards, filters, reports and jobs hidden, data kept); labels `admission_test`, `doc.admit_card_title`; neutral key `assessment`; permissions `assessment.manage`, `assessment.marks`.

**Tasks**
- [ ] 2.17-T1 Migrations; RLS; leak test.
- [ ] 2.17-T2 Register module and labels; seed school pipeline stages Admission test → Result and templates "Admission test date", "result".
- [ ] 2.17-T3 Sessions with capacity and courses; registration single / bulk.
- [ ] 2.17-T4 Exam fee via online or manual payment.
- [ ] 2.17-T5 Admit card with title label, photo and roll; minimal personal data.
- [ ] 2.17-T6 Applicant message with session details (SMS / email per matrix, D1 / D5).
- [ ] 2.17-T7 Attendance and marks entry; multiple mark parts and total.
- [ ] 2.17-T8 Marks Excel import with preview and dry run; every change audited.
- [ ] 2.17-T9 Feed test registration / result as a lead score signal (school profile "Visit and test weigh most").
- [ ] 2.17-T10 Special merit formulas for one institution → extension or custom records (Ch 43), not core.

**Tests**
- Unit: capacity check; total of mark parts.
- Import: dry run shows errors, nothing saved.
- Role-matrix: only marks permission can edit marks.

**Done when (acceptance criteria)**
- A school can create a test session, register 200 leads, print admit cards and enter / import marks.
- Turning the module off hides every test screen; data remains.

**Watch-outs (do not miss)**
- Wrong marks import (Ch 30.7 #1); many exam formats (#7); children's photos and DOB (#8).

**Owner checkpoint:** Owner prints an admit card and imports a marks sheet in dry-run mode.

### 2.18 Merit list, quotas, lottery, results and waiting list

**Goal:** Produce per-course merit lists with tie-break rules, quota seats, auditable lottery, result publication (SMS / email and public result page), and an automatic waiting list.

**Depends on:** 2.17, 2.05, Phase 1 (public pages, custom domain, rate limit / CAPTCHA, job scheduler, notifications).

**Plan chapters:** Ch 30 (30.3 merit / quota / lottery, 30.4, 30.5, 30.7 #1–#6, 30.8), Ch 28.10 #2 (seat hold), Ch 44 (waiting list deadline job), Ch 34.4 (merit rank waivers).

**Decisions:** D1, D5, D8.

**Build**
- **Data:** `merit_lists` (course, status draft / published, locked after publish), entries (rank, selected / waiting / not selected, quota); `quotas` (name, seats within course / batch seats, **Proposed:** priority order, "unused quota seats go to general" setting); `lottery_draws` (seed, time, run by, full result, immutable); `waitlist_offers` (lead, offered at, deadline, status); **Proposed:** `seat_holds` with expiry.
- **Server:** merit computation with tie-break; publish (draft → published, then marks lock; change needs reason + approval); lottery with recorded seed (re-run gives same result); result messages through outbox with cost preview and per-institution limits, OTP priority unaffected; public result page `/result/<slug>` (roll + DOB, result only, no photo, rate limit + CAPTCHA, can be turned off, works on custom domain and with branding / labels); waiting-list job (institution time zone, idempotent): on deadline offer seat to next, notify officers each time; held seat on offer.
- **App & web:** merit list screen, quota settings, lottery screen, publish button with cost preview, waiting-list board.
- **Settings & permissions:** labels `merit_list`; publish as approval-engine action or sensitive permission; result page toggle; waiting-list deadline.

**Tasks**
- [ ] 2.18-T1 Migrations; RLS; leak test.
- [ ] 2.18-T2 Merit list per course with tie-break; selected / waiting / not selected.
- [ ] 2.18-T3 Quota seats inside batch seats; **Proposed:** quota priority and unused-seat setting.
- [ ] 2.18-T4 Lottery mode with seed, audit and reproducibility; result immutable.
- [ ] 2.18-T5 **Proposed:** draft → publish; marks locked after publish; change with reason and approval.
- [ ] 2.18-T6 Result SMS / email with cost preview, outbox queue and limits.
- [ ] 2.18-T7 Public result page with rate limit, CAPTCHA, result-only data, toggle, custom domain.
- [ ] 2.18-T8 Waiting-list deadline job and offers; officer notifications.
- [ ] 2.18-T9 **Proposed:** seat hold with expiry on offers (links to 2.05 seat check).
- [ ] 2.18-T10 Merit rank available to waiver rules (2.03).
- [ ] 2.18-T11 Applicant status page showing test date / result is deferred to Phase 5 (Ch 27).

**Tests**
- Unit: tie-break; lottery same seed → same result.
- Job: deadline passes while previous applicant pays → no double seat (hold / idempotent).
- Security: enumeration attempts on result page blocked by rate limit.
- Load: 5,000 result SMS queued without delaying another institution's OTP.

**Done when (acceptance criteria)**
- A school publishes a merit list or lottery result, applicants get SMS / email, and the result page answers roll + DOB.
- An unconfirmed selection after the deadline automatically moves the seat to the next waiting applicant.

**Watch-outs (do not miss)**
- Wrong published list (Ch 30.7 #1); enumeration (#2); SMS burst (#3); lottery transparency (#4); quota ambiguity (#5); same seat to two (#6); children's data (#8).

**Owner checkpoint:** Owner reviews a published merit list, a lottery audit record and the public result page; approves Proposed items (draft / publish lock, quota priority, seat hold).

### 2.19 Messaging additions and SMS billing statements

**Goal:** Add campaign effect reports, email campaigns, more SMS adapters and monthly SMS billing statements.

**Depends on:** Phase 0 (hub, SMS / email adapters, usage ledger), Phase 1 (campaigns, templates, recipient matrix, consent, Master Admin cost view); 2.08 (student segments).

**Plan chapters:** Ch 26 (26.3 effect, 26.4 email, 26.5 #8, 26.6), Ch 24 (24.4 template report, 24.7 #9), Ch 42 (42.4 adapter plan, 42.5 email), Ch 9 (9.7 statements, 9.9 #7), Ch 53 (gateway list, legal check).

**Decisions:** D3, D7, D15, D22.

**Build**
- **Data:** campaign channel email; effect snapshot per campaign recipient; `sms_statements` (institution, month, totals, split by type OTP / notification / template / bulk, failed parts separate, payer per D15).
- **Server:** effect computation (within N days: callback, stage change, visit, admission) worded "happened after"; **Proposed:** comparison with similar leads who did not get the campaign; email campaign sending via institution email connection (same checks: opt-out, do-not-contact, duplicates, approval `campaign.send`, rate limit, quiet hours, outbox); 2–3 more SMS adapters from the shortlist (SSL Wireless, BulkSMSBD, Alpha SMS, MiMSMS, Infobip, operator corporate SMS, Twilio) with send single / bulk, Unicode, masked / non-masked sender, balance, delivery reports, error mapping, sandbox numbers; monthly statement generator.
- **App & web:** campaign effect tab; email campaign editor (subject + body, preview of 3 people); Master Admin statement screen with Excel / PDF export.
- **Settings & permissions:** `campaign.send` scope reused; statement visible to Master Admin; institution sees its own SMS usage in Settings → Billing.

**Tasks**
- [ ] 2.19-T1 Campaign effect report (N days configurable) and template report alignment (same "happened after" wording, period average).
- [ ] 2.19-T2 **Proposed:** comparison group of similar non-recipients.
- [ ] 2.19-T3 Email campaigns reusing campaign pipeline; bounce / complaint tracking per institution.
- [ ] 2.19-T4 Confirm with first institutions which SMS gateways they use; verify API, price and masking rules before each adapter (Ch 53).
- [ ] 2.19-T5 Build the next SMS adapters to reach 3–4 ready adapters + Custom HTTP + platform default; contract tests in sandbox daily.
- [ ] 2.19-T6 Monthly SMS statement per institution: totals, split by type, failed parts separate, only platform-paid cost on the bill (D15).
- [ ] 2.19-T7 Statement export Excel / PDF; delivery-log evidence (provider message ID, parts, result).
- [ ] 2.19-T8 Campaigns for students / guardians use the Students segments (2.08).

**Tests**
- Unit: effect counting window; statement split totals equal ledger.
- Adapter contract tests with fake and sandbox; Unicode part counting (70 / 160).
- Cross-tenant: statements and email campaigns per institution only.

**Done when (acceptance criteria)**
- Admin sees what happened after a campaign within N days.
- An email campaign can be sent with the same safety checks as SMS.
- Master Admin downloads a monthly SMS statement per institution that matches the ledger.

**Watch-outs (do not miss)**
- Effect is not causation (Ch 26.5 #8, Ch 24.7 #9).
- SMS billing disputes (Ch 9.9 #7); shared email reputation (Ch 42.5); legal rules for promotional SMS (Ch 53).
- WhatsApp campaigns wait for the official API (later).

**Owner checkpoint:** Owner reviews a monthly SMS statement and a campaign effect report; confirms which extra SMS gateways to support.

### 2.20 Custom records and incoming API

**Goal:** Let institutions create their own record types (layer 2) and connect their own systems through a scoped incoming API (layer 4), without changing the core.

**Depends on:** 2.08, Phase 0 (`domain_events`, extension conventions, custom fields, permission registry), Phase 1 (automation rules, outgoing webhooks, export snapshots).

**Plan chapters:** Ch 43 (43.3 layers 2 and 4, 43.4, 43.5, 43.6, 43.7, 43.8), Ch 42 (42.7 incoming API row, I14), Ch 9 (limits, Pro plan), Ch 34.2 / 34.8 #7 (hostel room allocation, credit transfer examples).

**Decisions:** D8, D18, D20.

**Build**
- **Data:** `custom_record_types` (name, fields, link to lead / student); `custom_records` (`institution_id`, type, `jsonb` data, links) with GIN / expression indexes and schema validation from field definitions; `api_keys` (institution, scopes from the permission registry per area read / write, rate limit, rotation, last used, revoked).
- **Server:** auto-generated form, list, filter and export per type; per-type permissions (`view`, `create`, `edit`, `delete`, `export`) registered in the registry; versioned API (written contract, neutral field names) with key auth, per-key rate limit, audit; plan limits for custom record types / counts and API calls; keys and webhooks revoked on institution close.
- **App & web:** Settings → custom record types builder; records list / form on lead and student pages; Settings → API keys (create, scopes, rotate, revoke; key shown once).
- **Settings & permissions:** `integration.manage` (sensitive, 2-step login, audit) for API keys; module "Custom records" and "API / webhook" (Pro).

**Tasks**
- [ ] 2.20-T1 Migrations with `institution_id`, RLS and indexes; leak test scans these tables automatically.
- [ ] 2.20-T2 Type builder reusing the custom field builder; schema validation.
- [ ] 2.20-T3 Auto form, list, filter, export; included in full institution export and snapshots.
- [ ] 2.20-T4 Per-type permissions registered in the registry and role editor.
- [ ] 2.20-T5 Plan limits on types, records and API calls (server checked).
- [ ] 2.20-T6 Automation rules can use custom record events (via `domain_events`).
- [ ] 2.20-T7 API keys: scoped to one institution and chosen areas, read / write separate, rate limit, audit, rotation, revoke.
- [ ] 2.20-T8 Versioned API contract document with neutral names; deprecation notice via "What's new".
- [ ] 2.20-T9 Sample record types: hostel room allocation, scholarship application, library card.
- [ ] 2.20-T10 **Proposed:** migration path from a custom record type to a core module (stable field keys).
- [ ] 2.20-T11 Request intake rule documented for Master Admin: settings → custom records → automation first; extensions only when needed (later).

**Tests**
- Cross-tenant: API key of A can never read B; custom records of A invisible to B.
- Performance: filter on `jsonb` field over 50,000 records with GIN index on the benchmark institution.
- RPC-as-real-role: per-type permissions in role-matrix.
- API contract tests and rate limit test.

**Done when (acceptance criteria)**
- An admin creates a "Hostel room" record type linked to students without developer help, with list, filter and export.
- An institution's ERP reads students and posts payments through a scoped API key; every call is audited.
- Closing an institution revokes all its keys.

**Watch-outs (do not miss)**
- Slow `jsonb` queries (Ch 43.7 #2); custom-to-core migration (#3); breaking API contracts (#6); custom data missing from export / leak test (#8); risk R17.
- Never add institution-specific columns to core tables (Ch 43.4 rule 1).

**Owner checkpoint:** Owner builds a custom record type live and sees an API key's scope screen; confirms plan placement (Pro).

## Phases 3–5 and later: native, AI, team and the rest

This block takes the working product from Phase 2 (admission and students) to the full plan. Phase 3 adds the Android native module (call-log sync, held calls, sync health, caller card, incoming-call lock, WhatsApp auto-log) behind a Google Play policy gate, plus the server call lock and double-call warning that work on every platform. Phase 4 adds the change log, reports, team activity, the AI features (admission chance, AI admission credit, Admission Contribution) and credits / leaderboard / milestones / scorecard, after which the Pro plan can be sold in full. Phase 5 adds alumni and referrals, the applicant status page, Photo Studio, the feedback chat and developer inbox, and paid branded apps (D12). "Later" holds the items Ch 52.8 parks until the education release is stable or the owner decides.
Exit criteria: every milestone's "Done when" list is met; the cross-tenant leak test, RPC-as-real-role test, role-matrix and screenshot suites cover every new table, RPC, storage path and public page in this block; the product still works fully with every native permission refused (manual call log from Phase 1).

### Phase 3: Android native

#### 3.01 Google Play call-log policy gate and declarations

**Goal:** Confirm, before any native code ships, whether Google Play will allow this app (package) to hold `READ_CALL_LOG` and the other sensitive permissions, and file every declaration Play needs. The rest of Phase 3's native work is released to Play only after this gate passes.

**Depends on:** Phase 0 (app identity, package name and deep-link scheme, EAS profiles, account-deletion web path from login), Phase 1 (manual call log, call popup, manual WhatsApp log, crash collection, min app version, feature flags and beta institutions).

**Plan chapters:** Ch 41 (41.2, 41.7, 41.8 #1, #6, 41.9), Ch 52.11 item 4, Ch 48 (48.9, 48.11 Phase 3), Ch 19.11 #1, Ch 20.8 #1, Ch 50 (O5, T11), Ch 51 lesson 11, Ch 53.4 #5.

**Decisions:** D12, D21.

**Build**
- **Data:** none (policy work). A `docs/play-policy/` decision record in the repo.
- **Server:** none.
- **App & web:** permission-rationale screens drafted (one per permission: `READ_CALL_LOG`, `READ_PHONE_STATE`, `POST_NOTIFICATIONS`, `SYSTEM_ALERT_WINDOW`, Notification access), each optional and asked separately with the reason in plain words (bn/en). Web account-deletion path confirmed reachable from the Play listing.
- **Settings & permissions:** none.

**Tasks**
- [ ] 3.01-T1 Read the current Google Play "SMS and Call Log permissions" policy and the permitted-exception list; record the exact exception category the app would claim (for example a CRM/contact-management exception) and the evidence, in the decision record.
- [ ] 3.01-T2 Confirm the final product name / package / deep-link scheme is fixed (Ch 53.2 #1); a declaration is per package, so a later rename means a new declaration.
- [ ] 3.01-T3 Draft the Play permission declaration form for `READ_CALL_LOG` (and `READ_PHONE_STATE`), including the core-functionality description and a demo video script showing the call log being matched to leads.
- [ ] 3.01-T4 Draft the Data Safety form: hashed phone numbers (SHA-256 / HMAC) sent to server, call events, WhatsApp event metadata (never message text), crash reports, device id; retention (held calls 15 days default); deletion path.
- [ ] 3.01-T5 Write the justification texts for `SYSTEM_ALERT_WINDOW` (caller card overlay) and Notification access (WhatsApp listener); each feature is optional.
- [ ] 3.01-T6 Verify the web account-deletion path (Ch 10) works end to end and add its URL to the listing draft.
- [ ] 3.01-T7 Verify `google-services.json` is injected in `build-android.yml` and the Firebase check passes (Ch 48.4), so the declaration build is the real production build.
- [ ] 3.01-T8 Build a minimal internal-testing AAB with only the permissions and rationale screens (no sync yet) and submit the declarations early through the Play Console internal track.
- [ ] 3.01-T9 Record Play's answer: approved / rejected / more information. If rejected, record the reason and open the fallback decision for the owner (see Watch-outs and L.10).
- [ ] 3.01-T10 Update the privacy policy to name every native data flow (hash of number, WhatsApp event metadata, crash data).

**Tests**
- Manual: on a test phone, every permission can be refused and the app still works (manual call log, call popup, manual WhatsApp log from Phase 1).
- Manual: account deletion through the web path removes the account (or schedules it) and logs it.

**Done when (acceptance criteria)**
- The decision record states one of: "Play approved call-log use for package X on date D" or "Play refused; owner chose fallback F".
- Declaration, Data Safety form and privacy policy are submitted and saved in the repo as text.
- 3.03–3.08 may merge to main behind a feature flag at any time, but are not released to the Play production track until this gate shows "approved" (or the owner picks a fallback).

**Watch-outs (do not miss)**
- Play gives `READ_CALL_LOG` only to default dialers or approved exceptions, and each new package needs its own declaration (Ch 41.2, C8). Every branded app (5.08) repeats this whole milestone.
- Policy can change after approval (Ch 41.8 #1): the manual flow from Phase 1 must stay complete forever; never make any Phase 1 feature depend on the native module.
- **Proposed:** if Play refuses, evaluate distributing the APK outside Play or a default-dialer model, only after a legal/policy check (Ch 41.8 #1); open question in Ch 41.9. This is L.10, not part of Phase 3.

**Owner checkpoint:** The owner reads the decision record and either confirms "go" for Phase 3 native release or chooses the fallback (manual only, or start L.10).

#### 3.02 Server call lock and double-call warning

**Goal:** Stop two staff calling the same lead at the same time, and warn before calling a lead someone else contacted a few minutes ago. This is server-side and works on Android, iPhone and web without the native module.

**Depends on:** Phase 1 (lead list cards, lead page, peek, call buttons and `dial` links, manual call log and call popup, manual WhatsApp open/log, job scheduler, notifications), Phase 0 (settings framework, permission registry, labels).

**Plan chapters:** Ch 19 (19.4, 19.7, 19.8, 19.11 #3, #4, #8, #9, 19.12), Ch 20 (20.2, 20.6), Ch 44 (`call-lock-clean`), Ch 15 (card status).

**Decisions:** D24.

**Build**
- **Data:** `call_locks(institution_id, branch_id, lead_id, locked_by, channel phone|whatsapp, source app|device_incoming, expires_at, created_at)` with a unique index on `(institution_id, lead_id)`; RLS by `institution_id`. `call_lock_events` (or rows in `domain_events`) for take / release / override / "call anyway". 
- **Server:** RPC `take_call_lock(lead_id, channel)` — atomic insert-or-fail with expiry; returns `{ok}` or `{held_by, since}`; RPC `release_call_lock(lead_id)`; RPC `override_call_lock(lead_id)` checking the override rule; RPC `double_call_check(lead_id)` returning the last contact by another person within N minutes plus a "read notes" pointer; RPC `log_call_anyway(lead_id)`. Job `call-lock-clean` (scheduled, per institution) deletes expired locks. All `SECURITY INVOKER` + RLS.
- **App & web:** pre-call check on every call and WhatsApp entry point (list card, lead page header/round button, peek, `dial` link): block or warn dialog per mode; double-call dialog "Rahim called 12 min ago. Call again?" with "Read notes" and "Call anyway"; card badge "📵 X is on a call" (label-driven); masked-number users (D24) still go through the same check before the server hands the number to the dialer.
- **Settings & permissions:** setting `call_lock` (mode `block`/`warn`, duration 3–60 minutes, override `none`/`admin`/`admin_team_lead`, also lock WhatsApp yes/no); setting `double_call` (window N minutes, count attempts / notes / WhatsApp, include own contact, log "call anyway"). Permission `calls.lock.override` (scope team/branch/all) wired to the override option. Labels for every dialog string (bn/en).

**Tasks**
- [ ] 3.02-T1 Migration: `call_locks` table, unique index, RLS, expiry index; add to leak-test schema scan.
- [ ] 3.02-T2 Register `call_lock` and `double_call` settings (JSON schema, defaults) and their Settings screens (Settings → calls area).
- [ ] 3.02-T3 RPC `take_call_lock` as a single atomic statement (insert … on conflict do nothing / where expired), returning the holder on failure.
- [ ] 3.02-T4 RPCs `release_call_lock`, `override_call_lock` (checks override setting + permission, writes audit row).
- [ ] 3.02-T5 Release the lock automatically when the call popup is saved or dismissed, and when the manual WhatsApp log is saved.
- [ ] 3.02-T6 Job `call-lock-clean` on the per-institution scheduler; idempotent.
- [ ] 3.02-T7 RPC `double_call_check` honouring every `double_call` option; RPC to log "call anyway" into `domain_events`.
- [ ] 3.02-T8 Wire the pre-call check into every call and WhatsApp entry point on app and web; `block` vs `warn` behaviour.
- [ ] 3.02-T9 Card / lead page badge "📵 X is on a call" via a lightweight lock lookup in the list RPC (no extra round trip per card).
- [ ] 3.02-T10 Add "call anyway" counts to the call report (Phase 1 report) so Team Leads can see the habit.
- [ ] 3.02-T11 Register labels and permission keys; add role-template defaults (Admin and Team Lead may override when the setting allows).

**Tests**
- RPC-as-real-role: two callers in the same institution call `take_call_lock` concurrently (parallel connections) — exactly one succeeds.
- RLS + cross-tenant leak: a user of institution B cannot see or release a lock of institution A, including a user with two memberships (D25).
- Unit: expiry boundaries 3 and 60 minutes; `call-lock-clean` removes only expired rows.
- Role-matrix: override allowed/denied for each override option × role template.
- UI (Maestro): warn mode shows dialog and allows call; block mode prevents call; "call anyway" is logged.
- Screenshot: lock and double-call dialogs, light/dark × bn/en.

**Done when (acceptance criteria)**
- Two phones tapping Call on the same lead within one second: one dials, the other sees "X is on a call" (block) or a warning (warn).
- A lock left by a crashed app disappears by itself within the configured duration.
- The double-call warning appears exactly when the configured rules say it should, and "call anyway" shows in the report.

**Watch-outs (do not miss)**
- The lock must never live only on the client (race, Ch 19.11 #3).
- Hung locks after crash or lost network (Ch 19.11 #4): expiry + clean job + override.
- Warnings shown too often get ignored (Ch 19.11 #8): window per institution; log "call anyway".
- **Proposed (Ch 19.12):** the server lock does not need native code and could be pulled into Phase 1 for institutions with many callers; open question. Ch 19.12 also lists the double-call warning in Phase 1 while Ch 52.5 lists it in Phase 3 — if Phase 1 already shipped it, this milestone only verifies it and adds the WhatsApp-lock option.

**Owner checkpoint:** Demo with two phones on one lead in both modes; owner confirms default mode, duration and override rule.

#### 3.03 Native module scaffold, device registry, permissions, crashes and contact groups

**Goal:** Create the Kotlin Expo module `modules/call-log` with device identity, permission handling, native crash capture and phone contact groups, wired into a new store build — without call sync yet.

**Depends on:** 3.01 (permission texts; release gated), Phase 1 (crash collection and developer-side crash list, contacts import `contacts_import`, min app version and update banner), Phase 0 (deep-link scheme, institution branding).

**Plan chapters:** Ch 41 (41.3, 41.8 #6), Ch 46 (46.3 native crashes), Ch 23 (contact groups), Ch 48 (48.2 `runtimeVersion`, 48.3, 48.10 #4), Ch 6 (branding in native labels).

**Decisions:** D12, D21.

**Build**
- **Data:** `devices(id, institution_id, user_id, app_id, device_id, model, os_version, app_build, ota_update_id, permissions jsonb, last_seen_at)` with RLS (user sees own; managers via sync-health permission in 3.06).
- **Server:** RPC `register_device(device_id, info, permissions)` (institution from session, never from client).
- **App & web:** Expo module `modules/call-log` (Kotlin) exposing `getDeviceId`, `getPermissions`, `getContactGroups`, `takeNativeCrashes`; JS wrapper with no-op fallbacks on iOS/web; permission screen (each permission asked separately, with reason, optional); deep link `<scheme>://leads/<id>` handled; notification channel names and listener labels show the institution's name/branding, never hard-coded.
- **Settings & permissions:** none new.

**Tasks**
- [ ] 3.03-T1 Create `modules/call-log` Expo module skeleton (Kotlin), add to the dev client build profile.
- [ ] 3.03-T2 Bump `runtimeVersion`; plan a new store build and raise `min_app_version` only when the server starts depending on the module (Ch 48.10 #4).
- [ ] 3.03-T3 Implement `getDeviceId` (stable per install) and `getPermissions` (status of each permission and Notification access).
- [ ] 3.03-T4 Permission request flow: one screen per permission, explanation text from labels, "skip" always available; app works with every permission refused.
- [ ] 3.03-T5 `devices` table, RLS, `register_device` RPC called on app open and foreground.
- [ ] 3.03-T6 Implement `takeNativeCrashes` and feed native crashes into the Phase 1 crash pipeline (signature dedupe, tagged with institution, user, version, OTA id, device).
- [ ] 3.03-T7 Implement `getContactGroups` and add "import by contact group" to the Phase 1 contact import screen (setting `contacts_import`).
- [ ] 3.03-T8 Deep-link handler for `<scheme>://leads/<id>`, opening the lead in the active institution only (unknown or other-institution id → friendly "not found").
- [ ] 3.03-T9 Institution name/branding passed into native notification labels; update on institution switch.
- [ ] 3.03-T10 JS wrapper returns safe defaults on iOS and web; CI builds still pass for web.

**Tests**
- Unit (Kotlin): permission status mapping; device id stable across restarts.
- RLS + cross-tenant leak: `devices` rows; a two-membership user registers one device row per active institution.
- UI (Maestro, Android): refuse all permissions → manual call log still works.
- Manual: forced native crash appears in the crash list with device and version.

**Done when (acceptance criteria)**
- A preview APK installs, asks permissions one by one, and the developer sees the device in `devices` and native crashes in the crash list.
- Contact groups can be picked during contact import.
- Deep links open the right lead.

**Watch-outs (do not miss)**
- Overlay and Notification access frighten users and draw Play questions (Ch 41.8 #6): optional, separate, explained.
- Native changes cannot ship by OTA; wrong `runtimeVersion` crashes old builds (Ch 48.10 #4).
- Branding must never be hard-coded in native strings (Ch 41.3).

**Owner checkpoint:** Owner installs the preview build and walks the permission screens in both languages.

#### 3.04 Call-log capture and hashed sync

**Goal:** Automatically log calls with leads from the phone's call log: capture on the device, send only hashes, match on the server against leads the user can see in the active institution, and reconcile with manual entries.

**Depends on:** 3.03, 3.02, Phase 1 (`call_logs`, call triggers — `last_contacted_at`, `call_attempts`, unreachable, missed-call follow-up, "♻️ Lost lead called you" — `save_phone_call`, phone rules from locale settings), Phase 0 (`user_access`, active institution in session).

**Plan chapters:** Ch 41 (41.3 receiver/worker/queue, 41.4, 41.8 #2, #4, #5, #8, #9), Ch 19 (19.2 source `phone`, device id, SIM; 19.3; 19.6; 19.10), Ch 13 (phone rules), Ch 48.7 (leak test covers sync).

**Decisions:** D24, D25.

**Build**
- **Data:** `call_logs` already has source `phone`, device id, SIM, direction, duration (Phase 1); add unique key `(institution_id, device_id, call_started_at, number_hash)` for idempotent sync. `call_sync_runs(institution_id, user_id, device_id, sent, matched, held, errors, at)` for sync health. Per-institution secret salt in Vault (**Proposed**, see Watch-outs).
- **Server:** RPC `sync_phone_calls(device_id, items[])` — items carry hash, direction, start, duration, SIM slot; institution and user from session only; match hash against leads in `user_access` for the active institution; decide outcome (outgoing ≥ N s → `connected`, else `no_answer`; incoming answered → `connected`, else `missed`); reconcile within ±10 minutes with a manual or popup entry via `save_phone_call` (no duplicate); fire the Phase 1 call triggers; unmatched items go to held calls (3.05). RPC `get_number_hashes_salt()` if HMAC is approved.
- **App & web:** native call-end receiver + worker (capture about 6 s and 40 s after call end) + 15-minute safety job; local queue filtered by the institution's phone rules (default Bangladesh `880`, `01XXXXXXXXX`), SIM filter; JS API `setEnabled`, `getSims`, `setSimFilter`, `captureNow`, `getPending`, `removePending`, `recentCalls`; sync on app open and on return to foreground; Settings → Call sync screen (on/off, SIM choice, plain-language explanation of what is sent).
- **Settings & permissions:** setting `call_sync` (who syncs, incoming sync on/off, missed-call follow-up on/off, minimum seconds for connected, attempts before unreachable, retry days, ask after WhatsApp, hold calls on/off and days). Role behaviour switch "call log sync mandatory" is read here (enforced in 3.06).

**Tasks**
- [ ] 3.04-T1 Register `call_sync` setting schema and defaults; Settings screen. Confirm the old keys `max_call_attempts` and `call_log_lock_hours` do not exist.
- [ ] 3.04-T2 Native: call-end broadcast receiver + WorkManager jobs (≈6 s, ≈40 s) + 15-minute periodic safety job.
- [ ] 3.04-T3 Native: read new call-log rows since last cursor; filter by phone rule passed from JS (not hard-coded); apply SIM filter.
- [ ] 3.04-T4 Native: normalise number with the institution phone rule and hash (SHA-256, or HMAC with salt if approved); never store or send the raw number off the device.
- [ ] 3.04-T5 Native queue with `getPending` / `removePending`; small batches; survives reboot.
- [ ] 3.04-T6 Migration: idempotency unique key on `call_logs`; `call_sync_runs` table + RLS.
- [ ] 3.04-T7 RPC `sync_phone_calls`: matching only within the session's active institution and the user's visible leads; outcome rules from `call_sync`.
- [ ] 3.04-T8 Reconciliation ±10 minutes with manual/popup entries through `save_phone_call`; duplicates impossible.
- [ ] 3.04-T9 Call the existing Phase 1 triggers (last contact, attempts, unreachable, missed-call "call back" follow-up + `missed_call` notification, lost-lead missed call "♻️ Lost lead called you"; closed leads not counted).
- [ ] 3.04-T10 Institution switch: **Proposed** — items already queued are sent tagged with the institution that was active when captured; otherwise flush before switching. Implement whichever the owner approves.
- [ ] 3.04-T11 JS: trigger sync on app open/foreground; respect `setEnabled`; write `call_sync_runs`.
- [ ] 3.04-T12 Add `sync_phone_calls` to the leak-test RPC list and the RPC-as-real-role suite.

**Tests**
- Unit: outcome rules at N−1, N, N+1 seconds; incoming answered/unanswered.
- Unit: ±10 minute reconciliation — popup entry then sync → one row; sync then manual entry → one row.
- RPC-as-real-role: caller with scope `own` cannot match a lead outside scope (item goes to held calls instead).
- Cross-tenant leak: a two-membership user syncing while institution A is active never creates rows in B; hashes of B's leads never match.
- Queue: same batch sent twice → no duplicates (idempotency key).
- Performance: 500-item batch against the ≈3,000-lead benchmark institution finishes within the agreed budget.
- Manual: Xiaomi / Oppo / Vivo test phones — calls still arrive after the app is backgrounded for an hour.

**Done when (acceptance criteria)**
- A call to a lead's number appears on the lead's timeline within one minute of call end (or at next app open if the worker was killed), with outcome, duration and SIM.
- No raw phone number leaves the device (verified by inspecting the request payload).
- Manual entry + sync never produce two rows.

**Watch-outs (do not miss)**
- A plain SHA-256 of an 11-digit number is reversible by brute force (Ch 41.8 #2): treat hashes as personal data. **Proposed:** HMAC with a per-institution secret salt.
- Battery savers kill workers (Ch 41.8 #3): safety job + sync on app open.
- Personal calls fear (Ch 41.8 #5): only matched hashes create rows; SIM filter; plain explanation on screen.
- Number filter must come from the institution phone rule, not hard-coded Bangladesh (Ch 41.8 #8).
- One phone, several institutions (Ch 41.8 #9): match only in the session's active institution.

**Owner checkpoint:** Owner makes and receives real calls on a test phone and sees them on lead timelines; owner decides HMAC salt and institution-switch rule.

#### 3.05 Held calls, auto mode in the call popup and exact durations

**Goal:** Keep calls from numbers that are not yet leads for a limited time, fill the call popup automatically from the phone's call log, and make talk-time reports exact when sync is on.

**Depends on:** 3.04, Phase 1 (call popup, talk-time report and call heatmap, job scheduler).

**Plan chapters:** Ch 41.4 (held calls), Ch 19 (19.5 auto mode, 19.9 durations), Ch 44 (`held-calls-cleanup`), Ch 41.8 #5.

**Decisions:** D24.

**Build**
- **Data:** `held_calls(institution_id, user_id, device_id, number_hash, direction, started_at, duration, sim, expires_at)` with RLS (owner user only; never readable by others); index on `(institution_id, number_hash)`.
- **Server:** unmatched sync items go to `held_calls` when `call_sync.hold_calls` is on (default 15 days); trigger on lead insert / phone update: if a held call matches the new lead's hash, move it into `call_logs` silently (no notification, no follow-up); job `held-calls-cleanup` (daily, per institution) deletes expired rows.
- **App & web:** call popup auto mode — when the call exists in the phone call log, outcome, duration and SIM are pre-filled; user can still change outcome and add note/rating/next call/voice note. Talk-time report and heatmap mark rows as "exact (synced)" vs "estimated (manual)".
- **Settings & permissions:** `call_sync` hold on/off and days (already registered).

**Tasks**
- [ ] 3.05-T1 Migration `held_calls` + RLS + leak-test registration.
- [ ] 3.05-T2 `sync_phone_calls`: route unmatched items to `held_calls` with `expires_at`.
- [ ] 3.05-T3 Trigger on lead create and phone/WhatsApp number change to attach matching held calls without alerts or follow-ups.
- [ ] 3.05-T4 Job `held-calls-cleanup` on the per-institution scheduler; logs counts to the job run log.
- [ ] 3.05-T5 Call popup auto mode: after returning from the dialer, read `recentCalls` for that number and pre-fill.
- [ ] 3.05-T6 Report: duration source flag on talk-time and heatmap; legend label in both languages.
- [ ] 3.05-T7 Missed-call "call back" follow-up from synced incoming missed calls respects `call_sync.missed_followup`.

**Tests**
- Unit: held call attaches when lead is created with that number; does not alert; expired rows removed by job.
- RLS: another user (even Admin) cannot read someone's held calls.
- UI (Maestro): call from lead page → return → popup shows prefilled outcome and duration.

**Done when (acceptance criteria)**
- Calling an unknown number, then adding it as a lead within 15 days, shows the earlier call on the new lead's timeline.
- After 15 days (default) the held row is gone.
- The popup is pre-filled on Android with permission and still works manually without it.

**Watch-outs (do not miss)**
- Held calls are personal-call data: keep them invisible and short-lived (Ch 41.8 #5).
- Never create follow-ups or notifications when attaching held calls.

**Owner checkpoint:** Owner sees a pre-filled popup and an "exact" talk-time figure.

#### 3.06 Sync health, nudges and "Sync required"

**Goal:** Let managers see whose phone sync is off or broken, nudge them, and optionally require sync before the Android app can be used.

**Depends on:** 3.04, 3.05, Phase 1 (notifications incl. type registry, Home banners, Master Admin health dashboard), Phase 0 (role behaviour switches, permission registry).

**Plan chapters:** Ch 41.4 (sync health, nudge, mandatory sync), Ch 11.9, Ch 45 (Home banner, More → TEAM, Settings → TEAM), Ch 25 (`sync_nudge`), Ch 5 / Ch 50 M7 (sync status on Master Admin dashboard), Ch 41.8 #3, #7.

**Decisions:** D23.

**Build**
- **Data:** `devices` and `call_sync_runs` feed a view `sync_health_v` (per user/phone: permissions, sync on, SIM, pending count, last sync, last error, directory size from 3.07). `user_access_overrides` or a per-user field for "Sync required" (Super Admin only).
- **Server:** RPC `get_sync_health()` (scoped by permission, worst first); RPC `send_sync_nudge(user_ids[])` creating `sync_nudge` notifications; auto-stop nudges when sync turns on; Master Admin per-institution sync status aggregate.
- **App & web:** Sync health screen (More → TEAM and Settings → TEAM), sorted worst first; Home banner "turn on call sync"; blocking screen on Android when sync is required and not set up; **Proposed:** phone-brand battery-optimisation guide (Xiaomi/Oppo/Vivo).
- **Settings & permissions:** permission `calls.sync_health.view` (scope team/branch/all); permission `calls.sync_required.manage` (sensitive, Super Admin only); behaviour switch "call log sync mandatory" read from roles (any role on → on, D23); **Proposed:** per-user override of the role switch (Ch 11.9). Notification type `sync_nudge` in the recipient matrix.

**Tasks**
- [ ] 3.06-T1 View/RPC for sync health with scope filtering; worst-first ordering rule (no permission > sync off > errors > oldest last sync).
- [ ] 3.06-T2 Sync health screens on app (More → TEAM, Settings → TEAM) and web.
- [ ] 3.06-T3 `send_sync_nudge` RPC + notification type `sync_nudge`; auto-dismiss when the target's sync is on.
- [ ] 3.06-T4 Home banner for users whose sync is off (Ch 45).
- [ ] 3.06-T5 "Sync required": per-person flag (Super Admin only) + role behaviour switch; Android app shows a blocking setup screen until sync is set up; iOS/web unaffected.
- [ ] 3.06-T6 Show directory size and limit on the sync health row (from 3.07).
- [ ] 3.06-T7 Master Admin health dashboard: per-institution sync status (phones syncing / not syncing).
- [ ] 3.06-T8 **Proposed:** battery-optimisation guide screen per phone brand, linked from sync health and the setup screen.
- [ ] 3.06-T9 Register labels, permissions and role-template defaults.

**Tests**
- Role-matrix: Team Lead sees own team only; Caller sees nobody; Admin sees all.
- RLS + leak: sync health never shows another institution's devices.
- UI (Maestro): user with "Sync required" cannot pass the setup screen until permissions are granted and sync runs once.
- Screenshot: sync health list, light/dark × bn/en.

**Done when (acceptance criteria)**
- A manager can see, for every phone in scope, permission state, last sync time and errors, worst first.
- A nudge reaches the user and stops once they turn sync on.
- "Sync required" blocks only Android and only until set up.

**Watch-outs (do not miss)**
- Silent sync death is the main failure (Ch 41.8 #3); last-sync time is the key column.
- Sync required must not block iPhone or web users (Ch 19.11 #9).

**Owner checkpoint:** Owner sees the sync health list for a test team and sends a nudge.

#### 3.07 On-device lead directory, caller card and incoming-call lock

**Goal:** Keep an offline directory of the user's leads on the phone so an incoming lead call shows a caller card (name, stage, last note) before answering, sets the call lock, and offers "add a note".

**Depends on:** 3.02, 3.04, 3.06, Phase 1 (field masking D24, institution switcher D25, notifications).

**Plan chapters:** Ch 41 (41.3 directory, overlay, call lock, notifications; 41.5; 41.8 #2, #4, #6, #7, #9), Ch 19.7 (incoming lock), Ch 19.11 #9.

**Decisions:** D24, D25.

**Build**
- **Data:** none on server beyond a directory RPC; on device: directory in app-private storage (hash → name, stage, course/offering label, last note snippet, next call).
- **Server:** RPC `get_lead_directory(since)` returning up to the limit (default 10,000) of visible leads in the active institution, prioritised (own leads, active stages, recent); **Proposed:** delta updates (`since` cursor). No phone numbers in the payload, only hashes.
- **App & web:** JS API `setLeadDirectory`, `getCallerCard`, `setCallerCard`, `previewCallerCard`, `setCallLock`; caller-card overlay (`SYSTEM_ALERT_WINDOW`, optional); "incoming lead" and "add a note" notifications; caller-card settings screen with live preview; directory wiped and rebuilt on institution switch and on sign-out.
- **Settings & permissions:** caller-card field choice (stored in `call_sync` or per-user preference); **Proposed:** directory size limit setting.

**Tasks**
- [ ] 3.07-T1 RPC `get_lead_directory` with priority ordering and limit; INVOKER + RLS; leak-tested.
- [ ] 3.07-T2 Native directory store (private storage, encrypted if available); `setLeadDirectory` with full and **Proposed** delta modes.
- [ ] 3.07-T3 Refresh directory on app open, after sync, and on institution switch; wipe on sign-out.
- [ ] 3.07-T4 Incoming-call detection (`READ_PHONE_STATE`) → look up hash → show overlay caller card (if permission) or a heads-up notification.
- [ ] 3.07-T5 Caller card fields configurable with `previewCallerCard`; card never shows the phone number (D24).
- [ ] 3.07-T6 Incoming lead call: native `setCallLock` takes the server lock (channel phone, source device_incoming) and releases it at call end.
- [ ] 3.07-T7 After a lead call ends: "add a note" notification opening the lead via deep link.
- [ ] 3.07-T8 Show directory size and truncated flag in sync health (3.06).
- [ ] 3.07-T9 Offline: caller card works with no network.

**Tests**
- Unit (Kotlin): lookup by hash; wipe on switch.
- Cross-tenant: after switching from A to B, no A lead can appear on a caller card.
- Performance: building a 10,000-entry directory on the low-cost test phone within the memory budget agreed in 3.09.
- Manual: incoming call from a lead's number in airplane-mode-data-off state shows the card.

**Done when (acceptance criteria)**
- An incoming call from a lead shows name, stage and last note before answering, offline.
- During that call, other staff see "X is on a call" for the lead; the lock clears at call end.
- The phone number is never shown on the card.

**Watch-outs (do not miss)**
- Directory is incomplete above 10,000 leads (Ch 41.8 #7): priority order, size shown in sync health.
- Overlay is sensitive (Ch 41.8 #6): optional; notification fallback.
- Directory must only contain leads the user can see, and only the active institution (D25).

**Owner checkpoint:** Owner receives a call from a test lead and sees the caller card; chooses default card fields.

#### 3.08 WhatsApp auto-log (notification listener)

**Goal:** Log WhatsApp and WhatsApp Business calls and messages from lead numbers automatically, from notifications only, never reading message text.

**Depends on:** 3.03, 3.04, 3.07, Phase 1 (manual WhatsApp log, "Ask after WhatsApp", WhatsApp calls screen, `call_logs` channel `whatsapp`).

**Plan chapters:** Ch 41.6, Ch 20 (20.5, 20.6, 20.8 #1, #2, #6), Ch 41.3 (WhatsApp listener API).

**Decisions:** D6, D24.

**Build**
- **Data:** `call_logs` rows with channel `whatsapp`, media `voice`/`video`/`message`, source `whatsapp` (auto) — unique key `(institution_id, device_id, event_at, number_hash, media)`.
- **Server:** RPC `sync_whatsapp_events(device_id, items[])` — match hash in active institution; skip if a manual entry for that lead exists within 15 minutes; idempotent.
- **App & web:** Notification listener service for WhatsApp and WhatsApp Business that extracts only who / when / call-or-message (never text); JS API `getWhatsAppStatus`, `setWhatsAppEnabled`, `openNotificationAccess`, `getWhatsAppPending`; listener label with institution branding; WhatsApp report and screens show source (auto / manual).
- **Settings & permissions:** WhatsApp auto-log on/off per user; module "WhatsApp log" must be on.

**Tasks**
- [ ] 3.08-T1 Native `NotificationListenerService` filtered to WhatsApp package ids; parse sender and type only; discard text in memory immediately.
- [ ] 3.08-T2 Resolve sender to number where possible and hash it; drop events that are not phone numbers.
- [ ] 3.08-T3 Queue + `getWhatsAppPending`; sync with `sync_whatsapp_events`.
- [ ] 3.08-T4 Server de-duplication (unique key) and 15-minute manual-entry rule.
- [ ] 3.08-T5 Settings screen: status, `openNotificationAccess`, enable/disable.
- [ ] 3.08-T6 Reports and WhatsApp calls screen: show source auto/manual and a note that auto-log is not complete.
- [ ] 3.08-T7 Leak test and RPC-as-real-role for `sync_whatsapp_events`.

**Tests**
- Unit: parser never returns message text (assert on fixture notifications containing text).
- Unit: manual entry at t, auto event at t+10 min → skipped; at t+20 min → kept.
- Cross-tenant: two-membership user; events only in active institution.

**Done when (acceptance criteria)**
- A WhatsApp message or call from a lead appears in the lead timeline with media type, without any message text stored anywhere.
- Turning Notification access off stops auto-log; manual log and "Ask after WhatsApp" still work.

**Watch-outs (do not miss)**
- Listener is Play-sensitive (Ch 20.8 #1): optional; declared in 3.01.
- Notifications are missed when WhatsApp notifications are off or the chat is open (Ch 20.8 #2): label auto-log as incomplete.
- Duplicate or missing entries between manual and auto (Ch 20.8 #6): 15-minute rule + unique key; own entries deletable within 24 hours (Phase 1).

**Owner checkpoint:** Owner sends a WhatsApp message from a test lead's phone and sees the event (no text) on the timeline.

#### 3.09 Native hardening: battery, data, low-end phones and security sweep

**Goal:** Make the native features dependable on cheap Android phones and prove they leak nothing across institutions before release.

**Depends on:** 3.03–3.08.

**Plan chapters:** Ch 41.8 (#3, #4, #7, #9), Ch 47 (low-cost phone testing, offline), Ch 48.7 (leak test incl. sync, RPC-as-real-role, manual test phones), Ch 50 (T11), Ch 51 lessons 1, 11.

**Decisions:** D25.

**Build**
- **Data:** none.
- **Server:** load-test fixture for sync RPCs.
- **App & web:** tuning only (batch sizes, worker intervals, directory delta updates if approved).
- **Settings & permissions:** none.

**Tasks**
- [ ] 3.09-T1 Measure battery and mobile data use over a working day on the low-cost, mid-range and small-screen test phones; record budgets.
- [ ] 3.09-T2 Tune batch sizes and worker timing; confirm only hashes are sent.
- [ ] 3.09-T3 Memory budget for a 10,000-lead directory on the low-cost phone; adjust priority/limit.
- [ ] 3.09-T4 Kill-the-app and reboot tests on Xiaomi / Oppo / Vivo; confirm safety job and sync-on-open recover all calls.
- [ ] 3.09-T5 Leak-test sweep: every new table (`call_locks`, `devices`, `call_sync_runs`, `held_calls`) and RPC (`sync_phone_calls`, `sync_whatsapp_events`, `get_lead_directory`, `get_sync_health`, lock RPCs) with two institutions and a two-membership user.
- [ ] 3.09-T6 RPC-as-real-role sweep and DEFINER audit for all Phase 3 functions.
- [ ] 3.09-T7 Maestro flows: sync on/off, caller card, lock, WhatsApp auto-log, all-permissions-refused path.
- [ ] 3.09-T8 Update UX checklist (Ch 47) results for every new screen.

**Tests**
- All listed above; plus the ≈3,000-lead benchmark with sync traffic from 20 simulated devices.

**Done when (acceptance criteria)**
- Measured battery/data use is within the budgets the owner accepted.
- Leak, RPC-as-real-role and DEFINER suites pass with the new objects included automatically by the schema scan.

**Watch-outs (do not miss)**
- Silent stop on battery-saver phones (Ch 41.8 #3); data/battery cost (Ch 41.8 #4).
- Invoker function calling a locked helper made every card empty in the old app (Ch 51 lesson 1): test as real role, show load errors, never blank.

**Owner checkpoint:** Owner reviews the battery/data numbers and the test-phone results.

#### 3.10 Phase 3 release: Play review, staged rollout and minimum version

**Goal:** Release the native build to Play with approved declarations, roll it out to beta institutions first, and then to everyone.

**Depends on:** 3.01 (gate passed), 3.09.

**Plan chapters:** Ch 48 (48.6 safe release, 48.9 Play), Ch 46.5 (`min_app_version`), Ch 46.6 (store-update card), Ch 52.9 (risk check, no big release in busy weeks), Ch 50 (O5, T11, T12).

**Decisions:** D12.

**Build**
- **Data:** module/feature flag "Android call sync" per institution (module system, Ch 9); plan mapping (Android call sync on Pro).
- **Server:** none new.
- **App & web:** "What's new" entries (bn/en); Home store-update card for users on builds without the native module.
- **Settings & permissions:** module "Calls and Android call sync" switchable per institution and plan.

**Tasks**
- [ ] 3.10-T1 Production AAB via `build-android.yml`; upload with the approved declarations and Data Safety form.
- [ ] 3.10-T2 Enable the feature flag for beta institutions; watch crash and sync-health dashboards for a week.
- [ ] 3.10-T3 Raise `min_app_version` only for features that require the native build; older builds keep manual logging.
- [ ] 3.10-T4 Store-update card on Home for older store builds (Ch 46.6).
- [ ] 3.10-T5 What's new entries in both languages; Master Admin announcement.
- [ ] 3.10-T6 Map module to plan (Pro) in the plan table; check Starter/Standard institutions still have manual logging.
- [ ] 3.10-T7 Review the risk register (Ch 50) rows O5, T11, T12 and record status; check release date is not in an admission busy week.

**Tests**
- E2E (Maestro) on the production build; rollback drill on the OTA channel.

**Done when (acceptance criteria)**
- The build is live on Play; beta institutions have sync on for one week without a sync-related crash spike; then rolled out to all Pro institutions.

**Watch-outs (do not miss)**
- No big release in an admission busy week (Ch 48.6).
- If Play pulls the permission later, turn the module off by flag; manual logging continues (Ch 52.11 #4).

**Owner checkpoint:** Owner approves the go-live date and the beta institutions.

### Phase 4: AI and team

#### 4.01 Global change log and restore

**Goal:** Give Admins one page-based timeline of everything that changed in the institution, with counts by type, Excel export and restore of soft-deleted items, on app and web.

**Depends on:** Phase 1 (append-only `lead_activity` timeline, soft delete and 10-minute undo, notes as separate rows, lead "Changes" tab, export controls and approvals), Phase 0 (audit log for label and role/permission changes).

**Plan chapters:** Ch 38 (38.1, 38.3, 38.5 #6, #8, #9, 38.6), Ch 21 (restore rules), Ch 51 lesson 10.

**Decisions:** D9, D13.

**Build**
- **Data:** view or RPC union over `lead_activity` and other audit rows (stage change, notes, payments, settings changes, label changes, role/permission changes); indexes on `(institution_id, created_at)` and `(institution_id, type, created_at)`.
- **Server:** RPC `get_change_log(type?, actor?, branch?, from, to, page)` with per-type counts; RPC `restore_item(kind, id)` with dependency check (e.g. deleted course) and clear message; export through the Phase 1 export pipeline (permission, approval for large exports, name/time stamp, log).
- **App & web:** Change log screen (app) and web version with Excel export; restore button for Admins at any time; type filter chips with counts.
- **Settings & permissions:** permission `changelog.view` (scope branch/all), `changelog.restore` (sensitive), `changelog.export` (export permission).

**Tasks**
- [ ] 4.01-T1 Build the change-log source (view/RPC) over existing timeline and audit tables; no new event table.
- [ ] 4.01-T2 Paging and per-type counts; indexes; `jit = off` on the heavy function.
- [ ] 4.01-T3 Restore RPC: dependency check, conflict message, writes its own timeline row.
- [ ] 4.01-T4 App screen and web page; filters by type, person, branch, date.
- [ ] 4.01-T5 Excel export using Phase 1 export controls.
- [ ] 4.01-T6 Confirm label changes (Settings → Terminology) and role/permission changes appear.
- [ ] 4.01-T7 **Proposed:** retention period of the change log by plan (Ch 38.5 #8) — store the setting, do not delete until the owner approves.

**Tests**
- RLS + cross-tenant leak (incl. two-membership user) on the change-log RPC.
- Role-matrix: Caller cannot open; Admin can restore; branch-scoped manager sees only own branch.
- Unit: restore of a note whose lead is deleted → clear error, nothing half-restored.
- Performance: change log on the ≈3,000-lead benchmark returns page 1 under the agreed budget.

**Done when (acceptance criteria)**
- An Admin can find any deleted note/lead/follow-up from the change log and restore it from app or web.
- The export file carries name/time stamp and is logged.

**Watch-outs (do not miss)**
- One wrong join mixes institutions (Ch 38.5 #9): INVOKER + RLS, leak test.
- Restore conflicts with current data (Ch 38.5 #8).
- **Proposed (Ch 38.6):** the change log and core reports were proposed for Phase 1; Ch 52.6 puts "team" work in Phase 4. If Phase 1 already built them, 4.01/4.02 only add what is missing.

**Owner checkpoint:** Owner deletes a test lead, finds it in the change log and restores it.

#### 4.02 Reports

**Goal:** Ship the full reports area — summary, funnel, visits, source, team, WhatsApp, template, collection, lost, call heatmap — scoped to what the viewer can see, splittable by branch and admission season, bilingual, with a Home card.

**Depends on:** 4.01, Phase 1 (leads, stages, follow-ups, visits, templates, call log and talk time, WhatsApp log), Phase 2 (payments for the collection section), Phase 0 (`user_access`, branches, access explainer, labels), 3.05 (exact durations).

**Plan chapters:** Ch 38 (38.4, 38.5 #3, #4, #7, #9), Ch 19.9 (heatmap, talk time), Ch 20.6 (WhatsApp report), Ch 13 (admission season), Ch 45 (Home card, web dashboard grid), Ch 47 (charts, `jit = off`), Ch 51 lesson 4.

**Decisions:** D9, D13, D23, D25.

**Build**
- **Data:** **Proposed:** daily summary tables (calls per user/day, leads per source/day) maintained by job or trigger (Ch 19.11 #7, Ch 38.5 #4); indexes starting with `institution_id`.
- **Server:** one report RPC per section, all `SECURITY INVOKER` + RLS, `set jit = off`; filters: period, person, course (offering), branch, admission season; Home numbers in one RPC; chip counts in one counts RPC.
- **App & web:** Reports screen with sections; funnel bar tap → lead list; scope banner ("Based on the leads you can see: Branch X"); small in-house chart component built on design tokens (no chart library), colour plus text/icon; web dashboard grid; Home card "this month"; sections of disabled modules hidden.
- **Settings & permissions:** setting `reports` (who sees, Home card on/off, which sections on); permission `reports.view` (scope own/team/branch/all); titles and legends from labels.

**Tasks**
- [ ] 4.02-T1 Register `reports` setting and permission; role-template defaults.
- [ ] 4.02-T2 Section RPCs: summary, funnel, visits, source, team, WhatsApp (source auto/manual shown), template usage and effect, collection, lost by reason, call heatmap (weekday × hour) and daily talk time per person.
- [ ] 4.02-T3 Filters: period, person, course, branch (D9), admission season (Ch 13).
- [ ] 4.02-T4 Chart component (bar, funnel, heatmap) on tokens; dark mode and large font safe.
- [ ] 4.02-T5 App Reports screen and web dashboard grid; funnel tap-through.
- [ ] 4.02-T6 Scope banner + link to the access explainer.
- [ ] 4.02-T7 Home card with this month's numbers (single Home RPC).
- [ ] 4.02-T8 Hide sections whose module is off.
- [ ] 4.02-T9 **Proposed:** daily summary tables and a job to fill them; switch heavy sections to them.
- [ ] 4.02-T10 Confirm no report ever mixes institutions; cross-institution totals only on the Phase 1 group dashboard.

**Tests**
- RLS + cross-tenant leak on every report RPC, including a two-membership user.
- Role-matrix: same data, Caller vs Team Lead vs Admin see different totals matching their scope.
- Performance: each section on the ≈3,000-lead benchmark and with a big + small institution together, before/after `jit = off`.
- Screenshot: every section light/dark × bn/en, plus long-label test institution.

**Done when (acceptance criteria)**
- Every section listed in Ch 38.4 is present, respects module on/off and viewer scope, and can be split by branch and admission season.
- Each section loads within the agreed budget on the benchmark.

**Watch-outs (do not miss)**
- JIT turned a 15 ms report into 900 ms (Ch 51 lesson 4).
- "Why is my number different?" (Ch 38.5 #3): scope banner.
- Colour-only meaning and dark-mode breakage in hand-made charts (Ch 38.5 #7).
- Open question (Ch 38.6): which report sections belong to which plan.

**Owner checkpoint:** Owner reviews every section with demo data and chooses Home card defaults.

#### 4.03 Team activity

**Goal:** Show managers what each person actually did — app time, calls, talk time, WhatsApp, leads added/imported, follow-ups on time or late, speed to first call, gaps and Lost decisions — within their team scope.

**Depends on:** 4.02, 3.04 (synced incoming/outgoing/missed), 3.08 (WhatsApp auto), Phase 1 (follow-ups, Lost/reopen, offline queue pattern, working hours), Phase 0 (behaviour switches, org units).

**Plan chapters:** Ch 38 (38.2, 38.5 #1, #2, #5, #6), Ch 19.12 (Phase 4 team activity report), Ch 20.9 (WhatsApp in team activity), Ch 11.9, Ch 13 (working hours), Ch 47 (offline queue, clock).

**Decisions:** D9, D23.

**Build**
- **Data:** `app_sessions(institution_id, user_id, device_id, started_at, ended_at, active_seconds)` with RLS; server receive time stored.
- **Server:** RPC `push_app_sessions(items[])` (clips impossible times, uses server time); RPCs `get_team_activity(period)` and `get_person_activity(user_id, period)` — rows: incoming / outgoing / missed calls, talk time, short calls, WhatsApp, leads added, leads imported, follow-ups on time/late, speed to first call, Lost reasons, hourly chart, gaps (60+ minutes inactive in app inside working hours); Lost section with "still Lost?" flag.
- **App & web:** session tracker (foreground + idle N minutes) with offline queue; Team list (Today / Yesterday / This week / This month); person detail; Lost section; export Excel or text.
- **Settings & permissions:** setting `activity` (on/off per institution, idle minutes N, Team Leads see own team on/off; **Proposed:** gap threshold setting); permission `activity.view` with scope `team` / `branch` / `all` (team = org units the manager manages, incl. sub-units); behaviour switches "show in team activity" and "count as manager"; export permission.

**Tasks**
- [ ] 4.03-T1 Register `activity` setting, `activity.view` permission, template defaults (Admins all, Team Leads team, Callers none).
- [ ] 4.03-T2 `app_sessions` table + RLS + leak test; client tracker with idle timeout and offline queue.
- [ ] 4.03-T3 Server-time correction and clipping of abnormal session times.
- [ ] 4.03-T4 Team list RPC and screen; only users whose roles have "show in team activity" on.
- [ ] 4.03-T5 Person detail RPC and screen incl. hourly chart, gaps labelled "inactive in app", speed to first call.
- [ ] 4.03-T6 Lost section with move, reason, note and current status.
- [ ] 4.03-T7 WhatsApp shown separately (auto/manual).
- [ ] 4.03-T8 Export Excel/text through export controls.
- [ ] 4.03-T9 **Proposed:** staff can see their own activity data; **Proposed:** exclude times with visit or payment entries from gaps.
- [ ] 4.03-T10 Privacy policy text about activity tracking.

**Tests**
- Role-matrix with org units and sub-units; Caller sees nobody.
- RLS + leak on `app_sessions` and activity RPCs.
- Unit: phone clock 2 days wrong → session lands on server day.
- UI (Maestro): offline session queue flushes after reconnect.

**Done when (acceptance criteria)**
- A Team Lead sees exactly their team; numbers match the call log and follow-up tables for a test day.
- Turning `activity` off stops tracking and hides the screens.

**Watch-outs (do not miss)**
- Feels like surveillance (Ch 38.5 #1): per-institution switch, working-hours-only gaps, clear policy text.
- "60+ minutes idle" misleads (Ch 38.5 #2): label "inactive in app".
- Exports carry personal data (Ch 38.5 #6).

**Owner checkpoint:** Owner views a demo team's day and approves the gap wording and defaults.

#### 4.04 AI foundation: connections, privacy, cost ledger and queue

**Goal:** Build the shared AI plumbing — provider connections in the integration hub, safe input building, cost ledger and budgets, and a correct queue — before any AI feature.

**Depends on:** Phase 0 (integration hub, Vault, sensitive-field registry, labels, job scheduler with attempts/back-off/given-up), Phase 1 (Master Admin monthly cost view, health dashboard), Phase 0 (plans/limits and add-on billing).

**Plan chapters:** Ch 40 (40.2, 40.6 providers/cost/ledger/problems, 40.7, 40.8, 40.9 #2, #3, #4, #6, #7, #9), Ch 42 (AI connection kind), Ch 44 (`ai-*` kicks, daily run check), Ch 9 (AI add-on, monthly AI limit), Ch 5 (per-institution AI cost), Ch 50 (O6, T16, I11, R10), Ch 51 lessons 2, 3, 5, 6, Ch 53.3 #6.

**Decisions:** D13, D15, D20.

**Build**
- **Data:** hub connection kind `ai` (providers Claude, Gemini) in `integration_connections`, key in Vault, hint only on screen; `ai_usage_daily(institution_id, day, feature, provider, model, input_tokens, output_tokens, cost_usd)` (features `chance`, `credit`, `haiku:<f>`, `gemini:<f>`); `ai_price_config` (model → prices, last-updated date) validated at build; `ai_provider_status(institution_id, provider, last_error, key_state refused|credit_out, at)`.
- **Server:** shared Edge Function helpers: provider adapters (Claude with prompt caching on the system prompt, structured JSON-schema output, Sonnet server-side refusal fallback, Haiku direct; Gemini Flash only, retired models filtered, 404 self-heal to best available model with a note, 429 → 15-minute pause); time rules (each call ≤ 75 s, no SDK retries, new work only in the first 45 s of a 150 s run, parallel providers in compare mode); kick jobs every 2 minutes that wake the function only if work is waiting (`x-cron-secret`); fair share per institution; budget check (monthly $ budget, plan AI limit: warn at 80 %, auto off at 100 %); usage written to the hub usage ledger.
- **App & web:** Settings → AI: provider on/off switches (off = never used, key never sent), mode per feature (`claude` | `gemini` | `gemini_then_claude` | `compare`), model per feature (Haiku 5.5 / Sonnet 5.5), monthly budget, last problem per provider, key state, free-tier data-use warning for Gemini, "about our institution" text for AI; Master Admin: per-institution AI cost + alert.
- **Settings & permissions:** setting `ai_providers`; permission `ai.settings.manage` (sensitive, 2-step login, audit); `integration.manage` for keys. Default mode `claude` (Haiku); Gemini optional.

**Tasks**
- [ ] 4.04-T1 Add `ai` kind to the hub provider list with setting forms, test button, last error.
- [ ] 4.04-T2 `ai_price_config` + build-time validation; show "price last updated" date (**Proposed**, Ch 51).
- [ ] 4.04-T3 `ai_usage_daily` ledger + feed into hub usage ledger + Master Admin cost view and alerts.
- [ ] 4.04-T4 Budget and plan-limit enforcement (80 % warning, 100 % auto off; manual checks still allowed).
- [ ] 4.04-T5 Claude adapter: prompt caching, JSON schema, Sonnet refusal fallback, 75 s timeout, no SDK retry.
- [ ] 4.04-T6 Gemini adapter: Flash only, retired-model filter, 404 self-heal with note, 429 pause 15 minutes.
- [ ] 4.04-T7 Privacy layer: people as P1, P2…; never names or phones; sensitive fields (registry) stripped; notes passed as a separate "data only" block (prompt-injection guard); labels used in prompts; answer language Bangla by default (D13).
- [ ] 4.04-T8 Generic AI queue pattern: states, attempts, back-off, "given up" after 3, credit-error wait 5 minutes, idempotency key, no endless re-claim, kick only if work waits, fair share.
- [ ] 4.04-T9 Settings → AI screen and provider problem display; never silent fallback.
- [ ] 4.04-T10 Key ownership: **Proposed** — each institution brings its own key by default; Master Admin can switch an institution to the platform key billed on its invoice (D15 pattern). Owner decision (Ch 53.3 #6).
- [ ] 4.04-T11 Privacy policy names each AI provider; check Bangladesh data-protection rules before enabling (Ch 40.9 #4).

**Tests**
- Queue tests: same item twice, back-off, given up, daily count only `auto`, manual check during a running job is not pushed to next day.
- Unit: input builder never contains a name, phone or sensitive field (fixture with all of them).
- Contract tests (sandbox) for Claude and Gemini adapters; mock adapters in CI.
- RPC-as-real-role for every AI read function (lesson 1).
- Cost: free provider counts $0; Claude cost uses the actually selected model.

**Done when (acceptance criteria)**
- An institution can add a Claude key, press Test, and see only the hint afterwards.
- A forced provider failure shows in Settings → AI and never silently switches without a note.
- Budget reaching 100 % stops auto runs; Master Admin sees AI cost per institution.

**Watch-outs (do not miss)**
- Queue bugs billed every 10 minutes in the old app (Ch 51 lesson 2).
- Edge Function 150 s limit (lesson 3); retired models and hidden free quotas (lesson 5); wrong-model cost (lesson 6).
- One big institution blocking the queue (Ch 40.9 #7).
- **Proposed (Ch 40.6):** Batch API for daily runs (50 % cheaper) — planned, not done before; build in 4.05 only if approved.

**Owner checkpoint:** Owner decides key ownership default and AI add-on pricing (Ch 40.10, Ch 53).

#### 4.05 Admission chance engine

**Goal:** For every open lead, compute on the server an admission chance with summary, good signs, risks, objections, 2–5 next actions with reasons, a polite script, best time to call and next-call days — stored per provider, re-checked when new activity arrives.

**Depends on:** 4.04, Phase 1 (leads, calls, notes, visits, follow-ups, hand-over), Phase 2 (fee talk, documents, payments).

**Plan chapters:** Ch 40 (40.3 input, output, prompt rules, levels/trend, queue, daily run, 40.6 compare mode and per-provider answers, 40.8, 40.9 #1, #2, #8, #9, #10), Ch 44 (AI daily run).

**Decisions:** D13, D20.

**Build**
- **Data:** `lead_chances(institution_id, lead_id, kind auto|manual|bulk, state pending|working|done|failed, attempts, next_try_at, given_up)`; `lead_chance_answers(institution_id, lead_id, provider, model, chance_pct, level hot|warm|cold, previous_pct, summary, good_signs, risks, objections jsonb, actions jsonb, script jsonb, best_time, next_call_days, created_at)` — one row set per provider; an answer from one provider never deletes another's.
- **Server:** SQL `ai_chance_input(lead_id)` (`SECURITY INVOKER` + RLS; history only from the record's own `institution_id`): lead story (stage, age, days since last contact, source, course, area, rating, visits, fee talk, documents, previous chance), each event (calls with direction/answered/minutes/notes, WhatsApp, notes, visits, fee offers, documents, hand-over, next call), per-P-code totals, answer-hour stats in the institution's time zone, next-call stats, "seen before" (last year, same course and source: admitted vs lost), today's date. Edge Function `ai-lead-chance`: JSON-schema output (objection types `fee`/`family`/`distance`/`time`/`other_college`/`job`/`doubt`/`documents`/`other`, display names from labels); prompt rules (calibrate from history, notes are strongest evidence, never promise discounts/scholarships/dates not in data, use "about our institution" text, pack words, no medical/legal/financial advice). Auto re-check after new call or note (once per lead per day); daily run at the institution's chosen hour (groups: changed since last check / never checked / older than N days); daily auto limit (up to 1000) counts only `auto`; manual "Check" always allowed even over budget.
- **App & web:** none in this milestone except an internal admin test page.
- **Settings & permissions:** setting `ai_chance` (on/off, auto, daily run hour, daily auto limit, stale N days).

**Tasks**
- [ ] 4.05-T1 Migrations `lead_chances`, `lead_chance_answers` + RLS + leak test.
- [ ] 4.05-T2 `ai_chance_input` SQL with all inputs listed; time-zone-aware answer-hour stats (no hard-coded Dhaka time).
- [ ] 4.05-T3 JSON schema for output; validation; level thresholds; previous chance kept for trend.
- [ ] 4.05-T4 Prompt with rules, labels and "about our institution"; notes as data-only block.
- [ ] 4.05-T5 Edge Function `ai-lead-chance` on the 4.04 queue; compare mode runs providers in parallel and stores both; list uses the Claude answer.
- [ ] 4.05-T6 Triggers enqueue `auto` after new call/note (max once per lead per day).
- [ ] 4.05-T7 Daily run scheduler per institution time zone with the three groups.
- [ ] 4.05-T8 Register `ai_chance` setting; enforce limits.
- [ ] 4.05-T9 Accuracy data: for closed leads, admitted % per level (for 4.06 display).
- [ ] 4.05-T10 **Proposed:** "low data" flag when history is thin; **Proposed:** Batch API for daily runs.

**Tests**
- Unit: schema validation rejects malformed answers; failed answer → `failed`, retried with back-off, given up after 3.
- Cross-tenant leak: `ai_chance_input` for a lead of A never includes B's history (two-membership user too).
- RPC-as-real-role: Caller can read answers for own leads; empty result is an error state, not silence.
- Cost: run 100 leads on Haiku in sandbox; ledger matches.

**Done when (acceptance criteria)**
- For a seeded institution, every open lead gets an answer within the daily run; auto rechecks happen after new activity at most once a day; budget stop works.

**Watch-outs (do not miss)**
- Hallucinated promises (Ch 40.9 #1); prompt injection in notes (Ch 40.9 #2); blind trust in % (Ch 40.9 #8); history leaking across institutions (Ch 40.9 #9); legal risk outside education (Ch 40.9 #10).

**Owner checkpoint:** Owner reads 20 sample answers in Bangla and judges tone and usefulness.

#### 4.06 Admission chance in the app and web

**Goal:** Show the AI answers where callers work: lead-page card, list chips, sorting and filtering, web column, Home "Call these first", and Settings → AI controls.

**Depends on:** 4.05, Phase 1 (lead list, lead page, peek, Home, follow-up creation).

**Plan chapters:** Ch 40.3 (lead page card, in the list, Settings → AI), Ch 15, Ch 16, Ch 45 (Home), Ch 47 (hot/warm/cold colours with icons), Ch 40.9 #1, #8.

**Decisions:** D13.

**Build**
- **Data:** none new.
- **Server:** list RPC adds chance %, level and trend columns (no N+1); Home RPC adds "Call these first" (my leads with good chance); RPC `request_chance_check(lead_id)` (manual); RPC `run_chance_group(group)` with count + estimated cost preview, progress and ⏹ stop.
- **App & web:** lead page AI card: chance, trend ▲▼, summary, objection chips, numbered actions, best time with "📅 set next call in N days" (creates a follow-up), "💬 What to say" (long-press copy), "why" (good/risks), "🔄 Look again" (warns if already checked today with nothing new), a tab per provider, error + Retry instead of an empty card; **Proposed:** "AI suggestion, please verify" note beside the script. List: 🔮 % chip (tap → quick sheet), AI Hot chip, sort and filter by AI; web table column; Home "Call these first"; Settings → AI: run a group now, progress, stop, accuracy by level.
- **Settings & permissions:** permission `ai.chance.view` (scoped; replaces the old "who sees chance" setting); permission `ai.chance.run_bulk` (sensitive).

**Tasks**
- [ ] 4.06-T1 Permissions and template defaults.
- [ ] 4.06-T2 Lead page AI card with every element listed; provider tabs; error/Retry state.
- [ ] 4.06-T3 "Set next call in N days" creates a follow-up through the Phase 1 follow-up RPC.
- [ ] 4.06-T4 List chip, quick sheet, AI Hot chip, AI sort and filter; web column.
- [ ] 4.06-T5 Home "Call these first" card.
- [ ] 4.06-T6 Settings → AI group run with count and estimated cost, progress, stop; accuracy by level.
- [ ] 4.06-T7 Levels shown with colour and icon 🔥🙂❄️; labels bn/en.
- [ ] 4.06-T8 **Proposed:** "verify" note and "low data" marker.

**Tests**
- UI (Maestro, Playwright): card states (loading, done, failed+Retry, given up), copy script, set next call.
- Role-matrix: users without `ai.chance.view` see no chip, card or column.
- Screenshot: card and list chips light/dark × bn/en.
- Performance: list RPC with chance columns on the ≈3,000-lead benchmark stays within the list budget.

**Done when (acceptance criteria)**
- A caller opens Home, sees "Call these first", taps a lead, reads the script, and sets the next call in one tap.
- No AI card is ever silently blank.

**Watch-outs (do not miss)**
- Old app showed empty AI cards for everyone due to a permission bug (Ch 51 lesson 1): error state + real-role tests.
- AI output never triggers actions by itself; only a user tap creates a follow-up (Ch 40.9 #2).

**Owner checkpoint:** Owner uses the card on a phone for a day with a pilot team.

#### 4.07 AI admission credit and Admission Contribution

**Goal:** When a lead is admitted, let AI split the admission among staff with reasons and confidence; let Admins rerun or fix it by hand; and build the Admission Contribution report on top.

**Depends on:** 4.04, 4.05, 4.02, Phase 1 (mark admitted, admission cancel), Phase 2 (admission flow, students).

**Plan chapters:** Ch 40 (40.4, 40.5, 40.9 #5), Ch 39.2 (admission credit by AI share), Ch 45 (More → REPORTS, web left menu), Ch 12 (branch split).

**Decisions:** D9, D13.

**Build**
- **Data:** `admission_credits(institution_id, lead_id, conversion_id, state, attempts, given_up)` queue; `admission_credit_answers(institution_id, conversion_id, provider, model, shares jsonb [{user, pct, reason}], decisive_moment, confidence, manual_override bool, override_reason, overridden_by)`; shares sum to 100.
- **Server:** Edge Function `ai-admission-credit` reading the story (calls, minutes, notes, visits, fee talk, documents, hand-over, who pressed Admitted) over the look-back window; weighting rules in the prompt (real influence over clicks, closer to decision weighs more, bringing the lead gets a fair part, pressing Admitted is office work and small); enqueue on admission; cancel shares on admission cancellation; RPC `rerun_admission_credit`, RPC `set_admission_credit_manual(shares, reason)` (audited); one-time "Work out past admissions" with count + cost preview. Report RPCs: summary per person for a period, per student coloured bar, split by source / course / branch, drill-down per student and per person, Excel export; viewer scope respected.
- **App & web:** Admission Contribution menu (More → REPORTS; web left menu), name from labels (e.g. "Sale contribution" in other packs); admin edit screen for shares.
- **Settings & permissions:** setting `ai_credit` (on/off, look-back 60/90/180/365 days); permissions `ai.credit.manage` (sensitive), `reports.contribution.view` (scoped).

**Tasks**
- [ ] 4.07-T1 Migrations + RLS + leak test for both tables.
- [ ] 4.07-T2 Edge Function with weighting prompt, JSON schema (sum = 100 check), confidence.
- [ ] 4.07-T3 Enqueue on admission; cancel on admission cancellation (Ch 17).
- [ ] 4.07-T4 Rerun and manual override RPCs with reason and audit.
- [ ] 4.07-T5 "Work out past admissions" one-time job with preview.
- [ ] 4.07-T6 Report RPCs and screens (summary, bars, splits, drill-downs, Excel).
- [ ] 4.07-T7 Labels for the menu and report titles.

**Tests**
- Unit: shares always sum to 100; cancel removes shares.
- Role-matrix: only `ai.credit.manage` can override; reports respect viewer scope.
- Leak test incl. report RPCs.

**Done when (acceptance criteria)**
- Admitting a seeded lead produces shares with reasons within minutes; an Admin can override with a reason and the audit log shows it; the report splits by source, course and branch.

**Watch-outs (do not miss)**
- AI split can feel unfair (Ch 40.9 #5): reasons, confidence, manual fix, feature can be off.

**Owner checkpoint:** Owner reviews splits on 10 real-looking admissions and approves the weighting.

#### 4.08 Credit rules and points calculation

**Goal:** Let each institution define points per activity with daily caps and versioned rule sets, and compute points from stored activity data in the institution's time zone.

**Depends on:** 4.03, 4.07 (admission points by AI share), Phase 1/2 activity tables (call log, notes, voice notes, follow-ups, leads, imports, stage moves, visits, documents, payments, templates, WhatsApp), Phase 0 (behaviour switch "count on leaderboard and scorecard", audit log).

**Plan chapters:** Ch 39 (39.2, 39.3, 39.8 #1, #3, #4, #5, #7, #8), Ch 44 (credit retro recalculation job), Ch 9 (module "Credits and leaderboard", Pro).

**Decisions:** D23, D25.

**Build**
- **Data:** `credit_rule_sets(institution_id, version, effective_from, rules jsonb, retro bool)`; `credit_adjustments(institution_id, user_id, points, reason, by, at)`; `credit_hidden_users`; **Proposed:** `credit_daily_totals(institution_id, user_id, day, points jsonb)` snapshot.
- **Server:** points function deriving from stored data (no separate event table; `domain_events` not used for this): groups — calls (call, connected, per talk minute, incoming), WhatsApp and templates (`wa_message`, `wa_call`, `template`), notes and follow-ups (note, voice note, follow-up set, on-time follow-up), leads (add, import, stage advance), visits and admission (visit planned/done, documents, admission by AI share or fallback rule — who pressed Admitted / lead owner — payment per ৳1,000), other (app time, overdue follow-up penalty); daily caps; retro recalculation job in small batches; refunds/cancellations appear as explicit minus lines (**Proposed**).
- **App & web:** Settings → Credits (rule editor with caps, version history, retro switch); Super Admin adjustments (reason required) and hide-from-leaderboard.
- **Settings & permissions:** settings `credits`, `credit_extras`; permission `credits.adjust` (sensitive, audited); behaviour switch read for who is counted (D23: any role on).

**Tasks**
- [ ] 4.08-T1 Register `credits`, `credit_extras` schemas with defaults that weigh results (admission, money) higher.
- [ ] 4.08-T2 Rule-set versioning with `effective_from`; retro on/off semantics.
- [ ] 4.08-T3 Points function per activity group and caps; institution time zone.
- [ ] 4.08-T4 Admission points via AI shares (4.07) or the fixed fallback rule when AI is off.
- [ ] 4.08-T5 Retro recalculation job in small batches (Ch 44).
- [ ] 4.08-T6 Adjustments with mandatory reason + audit; hide user.
- [ ] 4.08-T7 **Proposed:** daily totals snapshot; minus lines on cancel/refund; declared winners stay fixed.
- [ ] 4.08-T8 Module gate (Pro) and settings screen.

**Tests**
- Unit: each activity's points and daily caps; minimum connected seconds respected.
- Unit: retro on vs off across a rule change date.
- Leak: credits never cross institutions for a two-membership user.
- Performance: full retro on the ≈3,000-lead benchmark runs in batches without blocking other institutions.

**Done when (acceptance criteria)**
- Points for a seeded week match a hand-calculated sheet; changing rules with retro off leaves past days unchanged.

**Watch-outs (do not miss)**
- Gaming with short calls and empty notes (Ch 39.8 #1); heavy retro (#3); deleted/restored data changing old ranks (#4); adjustment abuse (#5); mixing institutions (#8).

**Owner checkpoint:** Owner approves the default point table.

#### 4.09 Leaderboard, levels, badges and weekly scorecard

**Goal:** Show the team their rank, streak, level and badges, announce weekly winners, nudge people close to the next rank, and send Admins a weekly scorecard.

**Depends on:** 4.08, Phase 1 (notifications and recipient matrix, Home, per-institution scheduler, export).

**Plan chapters:** Ch 39 (39.4, 39.5, 39.6, 39.7, 39.8 #2, #6), Ch 44 (`credit-tick`, `credit-level-tick`, `weekly-scorecard`), Ch 45 (Rank card, streak chip), Ch 25 (`leaderboard`, `scorecard`), Ch 13 (week start, time zone).

**Decisions:** D5, D9, D13, D23.

**Build**
- **Data:** `credit_announcements(institution_id, period, winners jsonb, announced_at)` (fixed once announced); `user_levels(institution_id, user_id, level, reached_at)`; `user_badges(institution_id, user_id, badge_key, earned_at)`.
- **Server:** leaderboard RPC (podium top 3, own rank, streak, level, breakdown; branch filter; admission season filter); jobs `credit-tick` (15 min: winner announcement at the configured time e.g. Friday 14:00, rank notices "You are now #2", 16:00 nudge when close to next rank), `credit-level-tick` (hourly: level-up notices), `weekly-scorecard` (hourly check; sends on each institution's day/time, default Sunday 9:00); all per institution, time zone aware, skipped when module off.
- **App & web:** Leaderboard screen; Home Rank card and streak chip in the top bar; levels (10 levels, Starter 100 → Legend 100,000 points) and badges over the last 365 days (`calls100`, `talk2h`, early bird, fast responder, `leads10`, `notes30`, `wa50`, `admit5`, `visits5`, `money50k` …) with names from labels; scorecard as cards on phone and sortable table with Excel export on web (metrics: leads, calls, connected, admissions, money, response time, missed follow-ups; this week vs last; week Saturday–Friday by default).
- **Settings & permissions:** setting `scorecard` (day, time, week start from locale); winner time in `credits`; notification types `leaderboard`, `scorecard` (default channel email for scorecard, changeable by Master Admin D5); **Proposed:** show only top N.

**Tasks**
- [ ] 4.09-T1 Leaderboard RPC with branch and season filters; INVOKER + RLS.
- [ ] 4.09-T2 Leaderboard screen, podium, breakdown; Home Rank card and streak chip.
- [ ] 4.09-T3 Levels and badges computation; label keys for names.
- [ ] 4.09-T4 Jobs `credit-tick`, `credit-level-tick`, `weekly-scorecard` on the per-institution scheduler.
- [ ] 4.09-T5 Notifications `leaderboard`, `scorecard` registered in the recipient matrix.
- [ ] 4.09-T6 Scorecard RPC; phone cards; web table + Excel export.
- [ ] 4.09-T7 **Proposed:** "top N only" option.

**Tests**
- Unit: announcement fires once at the institution's local time across two time zones; winners stay fixed after later data changes.
- Role-matrix: users without the "counted" switch never appear.
- Screenshot: leaderboard and scorecard light/dark × bn/en, long labels.

**Done when (acceptance criteria)**
- In a seeded institution, Friday 14:00 local announces winners, Sunday 9:00 sends the scorecard email, level-ups notify within an hour.

**Watch-outs (do not miss)**
- Office staff compared unfairly with callers (Ch 39.8 #2); demotivation at the bottom (#6).

**Owner checkpoint:** Owner sees a week of demo leaderboard and the scorecard email.

#### 4.10 Phase 4 release: performance, safety sweep and Pro plan readiness

**Goal:** Prove Phase 4 is fast and safe for big and small institutions together, then release with beta institutions first; Pro plan can now be sold in full.

**Depends on:** 4.01–4.09.

**Plan chapters:** Ch 52.11 #6, Ch 48 (48.6, 48.7), Ch 50 (O6, T16, R10, M7), Ch 9 (Pro plan modules: AI, credits and leaderboard), Ch 52.9.

**Decisions:** —

**Build**
- **Data / Server / App & web:** fixes only.
- **Settings & permissions:** plan table updated: AI, Credits and leaderboard, Android call sync on Pro; AI add-on billing active.

**Tasks**
- [ ] 4.10-T1 Benchmark every Phase 4 RPC on ≈3,000 leads and a big+small institution mix; record before/after.
- [ ] 4.10-T2 Leak, RPC-as-real-role, DEFINER and role-matrix sweeps include all Phase 4 tables, RPCs and reports.
- [ ] 4.10-T3 Queue tests for AI and credit jobs.
- [ ] 4.10-T4 Feature flags on beta institutions; watch AI cost and error dashboards for one week.
- [ ] 4.10-T5 Update plan/module mapping and AI add-on price config; announce via Master Admin; What's new bn/en.
- [ ] 4.10-T6 Risk register review (Ch 50) for O6, T16, R10, M7.

**Tests**
- As listed; E2E (Maestro, Playwright) of Home → AI card → follow-up and Reports → drill-down.

**Done when (acceptance criteria)**
- All suites pass; one week on beta without cost or error spikes; Pro plan sells with all its modules.

**Watch-outs (do not miss)**
- AI cost spikes (Ch 40.9 #3) — watch the ledger during beta.

**Owner checkpoint:** Owner approves Pro plan launch and AI add-on price.

### Phase 5: Everything else

#### 5.01 Alumni records (`network`)

**Goal:** Keep records of former students with contact, study, work and place details, custom fields, a unique ref code and a timeline, with list, detail and import screens.

**Depends on:** Phase 2 (Students tab, courses/batches/sessions, student IDs), Phase 1 (custom field builder use, import with column mapping and phone duplicate check, contact import, timeline, soft delete), 3.03 (contact groups), Phase 0 (labels, permission registry, modules).

**Plan chapters:** Ch 37 (37.1, 37.2, 37.3, 37.7, 37.8 #5, #6), Ch 49.3 (`network`), Ch 45 (More → ALUMNI, web left menu), Ch 9 (module "Alumni and referrals", Pro).

**Decisions:** D13.

**Build**
- **Data:** `network_members(institution_id, branch_id, name, phone, whatsapp, email, photo, offering_id, cohort_id, session, pass_year, client_number, workplace, designation, district, upazila, address, tags, notes, owner_id, do_not_contact, lead_id, client_id, ref_code, deleted_at)`; `ref_code` 6 characters without confusing characters (0/O, 1/I), unique across the platform; custom fields via the same builder (text, long text, number, date, select, phone, email, url, yes/no; required, show in list, order); timeline events (notes, calls, messages). RLS by `institution_id`.
- **Server:** RPCs for list/search/filter, multi-select bulk change of course/batch, soft delete; import from Students (by batch or course; existing linked student → update, not duplicate), from Excel/CSV (phone dedupe), from phone contact groups.
- **App & web:** Alumni list, detail/edit, import wizard; More → ALUMNI section; web left menu.
- **Settings & permissions:** setting `alumni` (Settings → ADMISSIONS → Alumni); permissions `alumni.view`, `alumni.manage` (scoped); labels `alumnus` (Former student / Ex-trainee / Graduate), `module.alumni`.

**Tasks**
- [ ] 5.01-T1 Migration, RLS, leak-test registration; ref-code generator (platform-unique, no confusing characters).
- [ ] 5.01-T2 Custom fields on the `network` entity via the existing builder.
- [ ] 5.01-T3 List RPC with search, filter, multi-select, bulk course/batch change, soft delete.
- [ ] 5.01-T4 Detail/edit and timeline (notes, calls, messages).
- [ ] 5.01-T5 Import from Students, Excel/CSV, contact groups with dedupe/update rules.
- [ ] 5.01-T6 Module gate, settings, labels, permissions, menu entries.
- [ ] 5.01-T7 Respect do-not-contact and channel opt-out in bulk SMS (Phase 1 campaign checks).

**Tests**
- Leak test and role-matrix for view/manage scopes.
- Unit: re-import from Students updates linked records; ref codes never contain 0/O/1/I and never collide (property test).
- Screenshot: list and detail light/dark × bn/en.

**Done when (acceptance criteria)**
- An Admin imports a batch of students as alumni, edits one, and finds them by search; repeating the import creates no duplicates.

**Watch-outs (do not miss)**
- Promotion without consent (Ch 37.8 #5): do-not-contact and opt-out honoured.
- Repeated imports creating duplicates (Ch 37.8 #6).

**Owner checkpoint:** Owner reviews the alumni screens with seeded data.

#### 5.02 Referrals: inbox, public refer page and `?ref=` counting

**Goal:** Let former students refer friends through a public `/refer/<code>` page or a `?ref=` link on the application form, and let staff handle referrals in a Referral inbox.

**Depends on:** 5.01, Phase 1 (public form infrastructure, `/apply/<slug>`, rate limits, CAPTCHA, `public_forms`, custom domain D16, lead `referred_by`, lead score rules, assignment), Phase 0 (branding, labels).

**Plan chapters:** Ch 37 (37.4, 37.5, 37.8 #1, #2, #3, #4), Ch 27 (27.2 `/refer/<code>`, `?ref=`, 27.5, 27.6 #2, #9, 27.7 Phase 5), Ch 14 (`referred_by`), Ch 22 (referral as lead-score signal).

**Decisions:** D13, D16.

**Build**
- **Data:** `referrals(institution_id, network_member_id, friend_name, friend_phone, offering_id, source refer_page|apply_ref|lead_page, status new|imported|credited|rejected, lead_id, handled_by, handled_at)`; RLS.
- **Server:** public RPC `submit_referral(code, name, phone, offering)` — resolves institution only from the code on the server, returns only needed fields, shows only institution name and referrer's first name; rate limits (3 per phone per hour, 60 per 10 minutes site-wide), CAPTCHA; block when referrer phone = friend phone; `/apply/<slug>?ref=<code>` marks the new lead as referred (only when the alumni module is on); inbox actions RPCs: import as lead (choose course and assignee), credit an existing lead, reject — each written to the timeline.
- **App & web:** public `/refer/<code>` page (no login), bilingual with institution-written text, branding and labels, works on custom domain; Referral inbox (More → ALUMNI); "Add referral" on the lead page.
- **Settings & permissions:** `public_forms` switch for the refer form; permissions `referrals.view`, `referrals.manage`; labels `referrer` (Ambassador, Partner), `module.referrals`.

**Tasks**
- [ ] 5.02-T1 Migration + RLS + leak test (incl. the public RPC).
- [ ] 5.02-T2 Public RPC with server-side institution resolution, rate limits, CAPTCHA, self-referral block, phone duplicate check.
- [ ] 5.02-T3 `/refer/<code>` page bilingual, branded, on platform sub-path and custom domain.
- [ ] 5.02-T4 `?ref=` handling in `/apply/<slug>` submission.
- [ ] 5.02-T5 Referral inbox with three actions; timeline entries.
- [ ] 5.02-T6 Lead page "Add referral" sets `referred_by`; lead score uses referral signal.
- [ ] 5.02-T7 **Proposed:** credit rule setting (e.g. lead existed within N days → not a referral).

**Tests**
- Cross-tenant: a ref code of A can never create data in B; the public page shows only first name.
- Rate-limit tests (4th submission from one phone in an hour refused; 61st site-wide in 10 minutes refused).
- UI (Playwright): refer page in bn and en; CAPTCHA path.

**Done when (acceptance criteria)**
- A friend submits on `/refer/<code>`; the referral appears in the right institution's inbox; importing creates a lead with `referred_by` set.

**Watch-outs (do not miss)**
- Fake/self referrals (Ch 37.8 #1); who gets credit when the lead already existed (#2); spam and bots (#3); code guessing and cross-institution leaks (#4, Ch 27.6 #9).

**Owner checkpoint:** Owner submits a referral from a phone and handles it in the inbox.

#### 5.03 Referral rewards

**Goal:** Create a reward automatically when a referred lead is admitted, cancel it if the admission is cancelled, and let staff record payment of the reward.

**Depends on:** 5.02, Phase 2 (admission, admission cancellation, message templates for students), Phase 1 (notifications, templates, recipient matrix incl. referrer, approval engine).

**Plan chapters:** Ch 37 (37.6, 37.8 #1, #7, 37.9), Ch 24 (messages to referrer), Ch 25 (`alumni` notification type).

**Decisions:** D6.

**Build**
- **Data:** `referral_rewards(institution_id, referral_id, network_member_id, amount, status pending|paid|cancelled, payment_method, note, paid_at)`; reward amount default or per course in the `alumni` setting.
- **Server:** trigger on admission → create reward; on admission cancel → cancel reward; messages to the referrer ("referral received", "reward given") through templates written by the institution (D6), sent only when the alumni module is on; notification type `alumni` for staff.
- **App & web:** rewards list and edit (status, method, note).
- **Settings & permissions:** `alumni` setting (default amount, per-course amounts); permission `referrals.rewards.manage` (sensitive); **Proposed:** reward payment as an approval-engine policy; **Proposed:** rewards report (pending / paid) beside the collection report.

**Tasks**
- [ ] 5.03-T1 Migration + RLS + leak test.
- [ ] 5.03-T2 Admission / cancellation triggers.
- [ ] 5.03-T3 Template variables and recipient "referrer" for the two messages; module check.
- [ ] 5.03-T4 Notification type `alumni`.
- [ ] 5.03-T5 Rewards screens.
- [ ] 5.03-T6 **Proposed:** approval policy for paying rewards; rewards report.

**Tests**
- Unit: admit → reward pending; cancel → reward cancelled; per-course amount wins over default.
- Role-matrix for rewards permission.

**Done when (acceptance criteria)**
- Admitting a referred lead creates a reward with the right amount and sends the referrer the institution's message.

**Watch-outs (do not miss)**
- Reward money outside accounts (Ch 37.8 #7): status, method, note recorded.

**Owner checkpoint:** Owner decides whether reward payment needs approval (Proposed).

#### 5.04 Applicant status page

**Goal:** Let an applicant check their own status (current state, exam date, result, next step) with application number + phone verified by OTP, without calling the office.

**Depends on:** Phase 1 (application form, application number, OTP route, public page infrastructure, rate limits, CAPTCHA, custom domain), Phase 2 (admission tests, merit list, waiting list, admission state).

**Plan chapters:** Ch 27 (27.1, 27.2 status page, 27.5 OTP limits, 27.6 #2, 27.7 Phase 5 and open question), Ch 10 (OTP rules).

**Decisions:** D13, D16.

**Build**
- **Data:** none new beyond an `applicant_status_views` log (institution, application number, at).
- **Server:** public RPC `request_status_otp(slug, application_no, phone)` and `get_applicant_status(slug, application_no, phone, otp)` — institution from slug on the server; returns only state, exam date, result and next step; OTP 6 digits, valid 5 minutes, single use; per number max 3 per 10 minutes and 10 per day; 5 wrong tries → 15-minute lock; CAPTCHA before OTP.
- **App & web:** public status page (bilingual, branded, platform sub-path and custom domain); toggle in `public_forms`.
- **Settings & permissions:** `public_forms` status-page switch; next-step texts per state written by the institution (bn/en).

**Tasks**
- [ ] 5.04-T1 Public RPCs with server-side institution resolution and minimal fields.
- [ ] 5.04-T2 OTP via the Phase 0/1 OTP route with all limits and lock.
- [ ] 5.04-T3 Status page UI bilingual and branded.
- [ ] 5.04-T4 Next-step texts editable in settings.
- [ ] 5.04-T5 Add the public RPCs to the leak test.
- [ ] 5.04-T6 Raise with owner: application-number format as an institution series (open question, Ch 27.7).

**Tests**
- Cross-tenant: application number of A with slug of B returns nothing.
- OTP limit tests (4th OTP in 10 minutes refused; lock after 5 wrong tries).
- UI (Playwright) bn/en.

**Done when (acceptance criteria)**
- An applicant enters number + phone, receives an OTP, and sees state, exam date, result and next step for that institution only.

**Watch-outs (do not miss)**
- Wrong slug/code showing another institution's data (Ch 27.6 #2).

**Owner checkpoint:** Owner tries the page with a test application.

#### 5.05 Photo Studio (web)

**Goal:** Give officers a web tool to turn any photo into a correct passport/board photo: face detection, background removal, presets, download, print sheet, or save to a student's photo document.

**Depends on:** Phase 2 (documents and upload rules, passport photo editor, `photo-cutout` via remove.bg in the hub, Drive/storage), Phase 1 (web version).

**Plan chapters:** Ch 31 (31.5, 31.6 #2, #3, #5, #8), Ch 42 (remove.bg connections), Ch 48.4 (MediaPipe assets in web deploy), Ch 9 (module "Google Drive files and Photo Studio", Pro).

**Decisions:** D22.

**Build**
- **Data:** shared presets in setting `photo_presets` (px / mm / in, dpi, face %, background, KB, format).
- **Server:** reuse `photo-cutout` (remove.bg accounts in priority order with monthly counters).
- **App & web:** Photo Studio page (web left menu; Settings → Web only → Photo Studio): load any image, MediaPipe face detection, background removal, presets from paper sizes / shared presets / custom size, editor (move, zoom, rotate, background, light), output: download JPG/PNG within KB limit, print sheet 4R / A4, or save to a student's photo document.
- **Settings & permissions:** `photo_presets`; permission `photostudio.use`; module gate.

**Tasks**
- [ ] 5.05-T1 Bundle MediaPipe assets and include them in `deploy-web.yml`.
- [ ] 5.05-T2 Photo Studio page with face detection and fallback to plain crop with a message when detection fails.
- [ ] 5.05-T3 Background removal via `photo-cutout`; quota-out message and "continue without" path.
- [ ] 5.05-T4 Preset sources and editor.
- [ ] 5.05-T5 Outputs: download within KB, 4R/A4 print sheet, save to a student's document (permission and scope checked).
- [ ] 5.05-T6 `photo_presets` setting screen.

**Tests**
- UI (Playwright): preset → download size ≤ KB limit; save to student document appears on the student.
- Unit: KB-targeted compression loop.
- Manual: hijab, low light and old photos fall back gracefully.

**Done when (acceptance criteria)**
- An officer makes a board-ready photo of the configured size and KB, prints a 4R sheet, and saves it to a student, all in the browser.

**Watch-outs (do not miss)**
- Third-party processing of student photos (Ch 31.6 #2); quota running out mid-season (#3); detection failures (#5); heavy on cheap phones — web only (#8).

**Owner checkpoint:** Owner makes a photo with a real board's size rule.

#### 5.06 Feedback chat (Contact developer)

**Goal:** Let any user chat with the platform Developer/Support team from inside the app with topics, attachments and screenshots.

**Depends on:** Phase 1 (crash collection, notifications, Realtime use, storage paths with `institution_id`), Phase 0 (platform roles Developer and Support, masking D24).

**Plan chapters:** Ch 46 (46.2, 46.7 #2, #3, #7), Ch 25 (`feedback` notification type).

**Decisions:** D13, D24.

**Build**
- **Data:** `feedback_threads(institution_id, user_id)` (one per person), `feedback_topics(thread_id, kind problem|idea|question, status, priority)`, `feedback_messages(topic_id, author, body, reactions, deleted_at, seen_at)`, attachments in storage under `institution_id` paths (max 3 images + 1 voice per message); RLS: user sees own; platform Developer/Support see all.
- **Server:** RPCs send / react / delete own message within 5 minutes / mark seen; Realtime typing and seen ticks; job deletes files of resolved topics after 90 days.
- **App & web:** Contact developer screen (More → HELP and web avatar menu): topics with status, chat, attachments, voice; three-finger tap → screenshot → new problem report (screenshot shown to user before sending; masked numbers stay masked); first-time tip; "Report a problem" button in Help.
- **Settings & permissions:** platform-level only (no institution `developer_email`); notification type `feedback`.

**Tasks**
- [ ] 5.06-T1 Migrations, RLS, storage policies, leak test incl. storage and Realtime.
- [ ] 5.06-T2 Chat RPCs and Realtime typing/seen.
- [ ] 5.06-T3 Attachments (3 images + 1 voice) with size limits.
- [ ] 5.06-T4 Three-finger tap screenshot flow with preview; masked fields stay masked.
- [ ] 5.06-T5 Help menu entry and first-time tip.
- [ ] 5.06-T6 90-day file cleanup job for resolved topics.

**Tests**
- Leak: user of A cannot read B's thread, files or Realtime channel.
- Unit: delete allowed at 4:59, refused at 5:01.
- UI (Maestro): three-finger tap → report sent with screenshot.

**Done when (acceptance criteria)**
- A user reports a problem with a screenshot in under 30 seconds and sees replies live.

**Watch-outs (do not miss)**
- Screenshots carrying personal data to the platform (Ch 46.7 #2); storage not separated per institution (#3); accidental gesture (#7).

**Owner checkpoint:** Owner sends a test problem from a phone.

#### 5.07 Developer inbox and full crash inbox

**Goal:** Give the platform Developer/Support team one inbox for chats, topics and crashes, filterable by institution, linked to the feature-request list.

**Depends on:** 5.06, Phase 1 (crash collection and error dashboard), Phase 0 (Master Admin panel, requests list with votes).

**Plan chapters:** Ch 46 (46.2 developer inbox, ideas → requests list, 46.3 crash reopen, 46.7 #1), Ch 52.11 #3, Ch 43 (requests list).

**Decisions:** —

**Build**
- **Data:** link `feedback_topics` (idea) → requests list item; crash groups with status and "reopened on new version".
- **Server:** inbox RPCs (platform roles only): filter by institution, kind, status, priority; reply; set status/priority; move idea to requests list (votes counted across institutions); crash group resolve / auto-reopen when it reappears in a newer version.
- **App & web:** Developer inbox in the Master Admin panel: chats, topics, crashes; institution filter.
- **Settings & permissions:** platform permission `platform.inbox.manage` for Developer and Support.

**Tasks**
- [ ] 5.07-T1 Inbox RPCs restricted to platform roles; audit of support access.
- [ ] 5.07-T2 Inbox UI with filters and reply.
- [ ] 5.07-T3 Idea → requests list with vote counting.
- [ ] 5.07-T4 Crash groups: resolve, reopen on newer version.
- [ ] 5.07-T5 Notification to the user when the developer replies or changes topic status (type `feedback`).
- [ ] 5.07-T6 **Proposed:** first-tier support by institution Admin or platform Support; merging similar topics.

**Tests**
- Role-matrix: institution Super Admin cannot open the developer inbox; platform Support can.
- Unit: resolved crash reappearing in a newer version reopens.

**Done when (acceptance criteria)**
- The developer sees all chats and crashes in one place, filters by institution, and moves an idea to the requests list.

**Watch-outs (do not miss)**
- Inbox flood for a single developer (Ch 46.7 #1).

**Owner checkpoint:** Owner (as platform staff) triages the inbox.

#### 5.08 Branded app build pipeline

**Goal:** Build a separate, paid branded Android app per institution from the same code, with its own name, icon, package, signing key, push project, OAuth client and deep-link scheme, generated from data.

**Depends on:** 3.10 (native module released), Phase 0 (EAS profiles, `build-android.yml`, app identity, push token table with `app_id`), Phase 1 (OTA channels, min app version).

**Plan chapters:** Ch 48 (48.2, 48.3, 48.4, 48.5, 48.9, 48.10 #5, 48.11 Phase 5), Ch 46.6 (separate update channel per branded app), Ch 41.7, Ch 5.16, Ch 6 (branding), Ch 10 (OAuth per app), Ch 25 (tokens with `app_id`), Ch 50 (M13, I13).

**Decisions:** D12, D21.

**Build**
- **Data:** `branded_apps(institution_id, app_id, display_name, package, scheme, icon_asset, firebase_project, oauth_client_ref, eas_channel, play_listing_state, declaration_state, created_at)` (platform-managed).
- **Server:** push send path selects credentials by token `app_id`; OAuth accepts the app's client; deep links use the app's scheme.
- **App & web:** `app.config` generated from `branded_apps` data (no code copy); `build-android.yml` takes an app id input and pulls that app's keystore and `google-services.json` from per-app GitHub secrets; separate OTA channel per app; same release goes to all apps.
- **Settings & permissions:** Master Admin screen to register a branded app (platform role only).

**Tasks**
- [ ] 5.08-T1 `branded_apps` table (platform-only RLS) and Master Admin form.
- [ ] 5.08-T2 Data-driven `app.config` (name, icon, package, scheme, runtime version).
- [ ] 5.08-T3 `build-android.yml` per-app input; per-app secrets; Firebase-in-build check per app.
- [ ] 5.08-T4 Per-app OTA channel; release script pushes the same update to all channels.
- [ ] 5.08-T5 Push and OAuth selection by `app_id`.
- [ ] 5.08-T6 Keystore backup via Play App Signing; document recovery.
- [ ] 5.08-T7 Branded app opens directly to its institution (no picker), still multi-membership safe.

**Tests**
- CI builds the shared app and one sample branded app on every release PR.
- Push to a branded-app token uses that app's Firebase project (mock adapter).
- Leak test with a user logged in to a branded app.

**Done when (acceptance criteria)**
- A sample branded APK builds from data alone, installs beside the shared app, receives push and OTA from its own channel.

**Watch-outs (do not miss)**
- Lost signing key = app can never update (Ch 48.10 #5).
- Everything multiplies per app (I13): push, OAuth, listing, declaration.

**Owner checkpoint:** Owner installs the sample branded app.

#### 5.09 Branded app onboarding: Play listing, declarations, OAuth and billing

**Goal:** Turn a paid branded-app order into a live Play app: listing, call-log declaration and Data Safety form for that package, Google OAuth consent, and the charge on the institution's bill.

**Depends on:** 5.08, 3.01 (declaration templates), Phase 0 (billing core, plans: branded app on Enterprise / paid option).

**Plan chapters:** Ch 41.7, Ch 41.8 #10, Ch 48.9, Ch 10 (OAuth consent per branded app), Ch 9 (branded app paid option), Ch 5.16, Ch 53.4 #4.

**Decisions:** D12.

**Build**
- **Data:** billing line item type "branded app" in the billing core; `branded_apps.play_listing_state`, `declaration_state`.
- **Server:** none new.
- **App & web:** Master Admin checklist per branded app (listing, declaration, Data Safety, OAuth consent, first release, status).
- **Settings & permissions:** platform only.

**Tasks**
- [ ] 5.09-T1 Per-app checklist in the Master Admin panel.
- [ ] 5.09-T2 Repeat 3.01 declarations and Data Safety for each package.
- [ ] 5.09-T3 Google OAuth consent screen verification for each app's client.
- [ ] 5.09-T4 Billing: setup fee / recurring charge line items (amounts from config).
- [ ] 5.09-T5 What's new and announcements reach branded apps as well.
- [ ] 5.09-T6 Store listing for the branded package carries the privacy-policy link and the web account-deletion path (Ch 10, Ch 48.9).

**Tests**
- Manual: one pilot branded app goes through Play review end to end.

**Done when (acceptance criteria)**
- One pilot institution's branded app is live on Play with approved declarations and appears on its invoice.

**Watch-outs (do not miss)**
- Each branded app has its own Play review time and cost (Ch 41.8 #10): price must cover it.

**Owner checkpoint:** Owner sets branded-app pricing and approves the pilot.

#### 5.10 Phase 5 release and full-plan readiness review

**Goal:** Release Phase 5 safely and confirm that every chapter of the plan is either built or explicitly parked in "Later".

**Depends on:** 5.01–5.09.

**Plan chapters:** Ch 52.7, Ch 52.9, Ch 50, Ch 53.

**Decisions:** —

**Build**
- **Data / Server / App & web:** fixes only.
- **Settings & permissions:** plan table: Alumni and referrals, Photo Studio on Pro; branded app paid option.

**Tasks**
- [ ] 5.10-T1 Leak, RPC-as-real-role, DEFINER, role-matrix and screenshot suites include all Phase 5 objects and public pages.
- [ ] 5.10-T2 Load test public pages (`/refer`, status page) before the next admission season.
- [ ] 5.10-T3 Beta institutions first via feature flags; What's new bn/en.
- [ ] 5.10-T4 Walk the risk register (Ch 50) and open questions (Ch 53) with the owner; move answered items to D#.
- [ ] 5.10-T5 Update plan/module mapping (Alumni and referrals, Photo Studio on Pro) and announce via Master Admin.
- [ ] 5.10-T6 Confirm each "Later" item (L.01–L.10) has an owner trigger written down.

**Tests**
- Full E2E suites; public-page load test.

**Done when (acceptance criteria)**
- All Phase 5 modules live for Pro institutions; owner signs off the readiness review.

**Watch-outs (do not miss)**
- No big release in admission busy weeks (Ch 48.6).

**Owner checkpoint:** Owner signs the readiness review and picks the first "Later" item.

### Later

#### L.01 First non-education industry pack

**Goal:** Open the first industry pack outside education, built only from the common core, once the education release is stable.

**Depends on:** 5.10, Phase 0 (industry packs as data, neutral keys, labels, type profiles, wizard with hidden industry step).

**Plan chapters:** Ch 49 (49.2, 49.4, 49.5, 49.6, 49.7, 49.8 #1–#10, 49.9), Ch 50 (X1–X6), Ch 53.5 #1, #2, Ch 7, Ch 8.

**Decisions:** D18, D19, D20, D21.

**Build**
- **Data:** new rows in `industry_packs` and `type_profiles` (versioned): labels bn/en (e.g. Patient, Property, Booking), pipeline stages, modules on/off (education-only modules off), custom fields, message templates, lost reasons, sources, document list, report presets, AI prompt words, lead score rules, role templates; per-pack sensitive-field declarations, retention limits and view audit; **Proposed:** `institutions.pack_version`.
- **Server:** pack apply/upgrade with preview that never overwrites what the institution changed; industry change later with warning and preview, data never deleted; Master Admin can limit which industries are open for sign-up.
- **App & web:** wizard shows the industry step once more than one industry is open; "Other (general)" neutral setup; multiple types per institution with merged seeds.
- **Settings & permissions:** pack-declared sensitive permissions; AI excludes sensitive fields.

**Tasks**
- [ ] L.01-T1 Owner chooses the first industry and answers Ch 53.5 #1 (excluded industries) and #2 (pricing per industry).
- [ ] L.01-T2 Legal check of the industry's data rules in Bangladesh before sale.
- [ ] L.01-T3 Write the pack data (all items listed above) in both languages.
- [ ] L.01-T4 Seeded test institution for the pack; CI runs its main flow; screenshot tests with the pack's labels.
- [ ] L.01-T5 Unhide the wizard industry step; Master Admin sign-up restriction per industry.
- [ ] L.01-T6 **Proposed:** pack version per institution and preview-before-upgrade.
- [ ] L.01-T7 Check no neutral key leaks into user-visible text (exports, PDFs, errors); API/webhook docs map keys to labels.
- [ ] L.01-T8 Landing page, demo data, pack help texts, support training.

**Tests**
- Seeded-institution E2E for the pack; label/screenshot suite; AI prompt test that gives no medical/legal/financial advice.

**Done when (acceptance criteria)**
- A new institution of the chosen industry signs up and the app looks made for it; education institutions see no change.

**Watch-outs (do not miss)**
- Scope creep (X1); too generic (X2); sensitive data (X3); testing every pack (X4); new pack versions surprising existing institutions (Ch 49.8 #9); neutral keys leaking (#10).

**Owner checkpoint:** Owner approves opening the industry for sign-up.

#### L.02 More industry packs and industry-specific modules

**Goal:** Add further packs one at a time, and build an industry-specific module (e.g. unit/flat inventory, memberships with renewals) only when two or more customers need it.

**Depends on:** L.01.

**Plan chapters:** Ch 49 (49.5, 49.9 later), Ch 43 (custom request rule), Ch 52.8.

**Decisions:** D18, D20.

**Build**
- **Data:** pack rows as in L.01; module tables only when justified, with `institution_id`, RLS and leak test.
- **Server / App & web:** per module, as specified when it is approved.
- **Settings & permissions:** module registry entries and permissions per new module.

**Tasks**
- [ ] L.02-T1 For each pack: repeat L.01-T1 to T8.
- [ ] L.02-T2 For each requested special module: confirm settings / custom records / automation cannot do it and at least two customers need it (Ch 43); then write a separate milestone.

**Tests**
- As L.01 per pack.

**Done when (acceptance criteria)**
- Each pack opens only with its templates, reports and help ready.

**Watch-outs (do not miss)**
- X1 scope creep: no special module for a single customer (that is an extension, L.09).

**Owner checkpoint:** Owner approves each pack and each special module.

#### L.03 Guardian / student portal and portal users

**Goal:** Only when the owner reverses D10: add portal users (guardian / student) on the existing user-type structure.

**Depends on:** 5.10, Phase 0 (user types staff / portal / API reserved).

**Plan chapters:** Ch 11 (user types, R19), Ch 52.8, Ch 53.5 #5, Ch 1 / Ch 2 (out-of-scope list).

**Decisions:** D10.

**Build**
- **Data / Server / App & web / Settings & permissions:** to be specified when the owner decides; must reuse `institution_members` user type `portal`, RLS and leak test.

**Tasks**
- [ ] L.03-T1 Owner decision on D10; write a full milestone set if approved.

**Tests**
- To be defined with the milestone.

**Done when (acceptance criteria)**
- Owner decision recorded.

**Watch-outs (do not miss)**
- Do not build any portal screen before the decision (D10).

**Owner checkpoint:** Decide whether and when a portal is built.

#### L.04 Official WhatsApp Business API connection

**Goal:** Add the official WhatsApp Business API as a per-institution integration-hub connection, keeping the current "open WhatsApp and log" method.

**Depends on:** 5.10, Phase 0 (integration hub, usage ledger), Phase 2 (more adapters pattern, billing statements).

**Plan chapters:** Ch 20 (20.7, 20.8 #3, #4, #7, 20.9), Ch 42 (WhatsApp row), Ch 9 (usage billing), Ch 53.5 #4.

**Decisions:** D6, D15.

**Build**
- **Data:** hub connection kind `whatsapp_api` per institution (verified business account, approved templates); usage ledger rows per message.
- **Server:** adapter (send template message, delivery status webhook through the webhook router); per-message cost into ledger and billing.
- **App & web:** send-from-app option where a connection exists; numbers stay hidden (**Proposed**, Ch 20.8 #3).
- **Settings & permissions:** add-on module; cost option like D15 (open question).

**Tasks**
- [ ] L.04-T1 Owner decides timing and who pays (Ch 20.9, Ch 53.5 #4).
- [ ] L.04-T2 Adapter, sandbox contract test, mock adapter.
- [ ] L.04-T3 Template approval workflow and Master Admin setup per institution.
- [ ] L.04-T4 Usage ledger and billing.

**Tests**
- Mock adapter in CI; two institutions each use their own connection.

**Done when (acceptance criteria)**
- One pilot institution sends approved templates through its own connection; cost appears on its statement.

**Watch-outs (do not miss)**
- Per-message cost, template approval and business verification add Master Admin work (Ch 20.8 #7).

**Owner checkpoint:** Owner decides go/no-go and pricing.

#### L.05 WhatsApp campaigns and WhatsApp OTP

**Goal:** Use the L.04 connection for bulk campaigns and as an OTP channel.

**Depends on:** L.04, Phase 1 (bulk SMS campaigns, OTP route).

**Plan chapters:** Ch 26 (campaign channel), Ch 10 (OTP channel), Ch 20.7, Ch 52.8.

**Decisions:** D22.

**Build**
- **Data:** campaign channel `whatsapp`; OTP channel option.
- **Server:** campaign sender and OTP route use the WhatsApp adapter with the same consent, opt-out, quiet-hours and rate rules as SMS.
- **App & web:** channel choice in campaign and OTP settings.
- **Settings & permissions:** existing campaign and OTP settings gain the channel option (D22).

**Tasks**
- [ ] L.05-T1 Add channel to campaign builder and sender; respect opt-out/do-not-contact.
- [ ] L.05-T2 Add WhatsApp to OTP channel order.

**Tests**
- Campaign and OTP queue tests with mock adapter.

**Done when (acceptance criteria)**
- A campaign and an OTP can be sent by WhatsApp for a pilot institution.

**Watch-outs (do not miss)**
- Promotional messages must honour opt-out (Ch 20.8 #5).

**Owner checkpoint:** Owner approves enabling the channel.

#### L.06 Branded app connections in the integration hub

**Goal:** Move each branded app's push and OAuth credentials into the hub as an "app" connection so they are managed like other connections.

**Depends on:** 5.09, Phase 0 (integration hub, Vault).

**Plan chapters:** Ch 42 (I13, 42 phase "later"), Ch 25 (tokens with `app_id`), Ch 52.8.

**Decisions:** D12.

**Build**
- **Data:** hub connection kind `app` (push credentials, OAuth client, store listing state) linked to `branded_apps`.
- **Server:** push and OAuth read credentials from the hub connection; health check and last error.
- **App & web:** Master Admin connection screen for apps.
- **Settings & permissions:** `integration.manage` (platform).

**Tasks**
- [ ] L.06-T1 Connection kind and Vault storage; migrate 5.08 secrets.
- [ ] L.06-T2 Health checks for push credentials.

**Tests**
- Mock push adapter per app; leak test on connections.

**Done when (acceptance criteria)**
- Rotating a branded app's push credential needs no rebuild.

**Watch-outs (do not miss)**
- Keystores stay outside the hub (CI secrets, Play App Signing).

**Owner checkpoint:** —

#### L.07 More online payment gateways

**Goal:** Add direct gateways after SSLCommerz (bKash, Nagad, Rocket, card …), one adapter each, money still going to the institution's own merchant account.

**Depends on:** Phase 2 (online payments with SSLCommerz, reconciliation).

**Plan chapters:** Ch 35, Ch 42 (payments), Ch 53.5 #3, Ch 52.8.

**Decisions:** D11, D14, D17.

**Build**
- **Data:** new providers in the hub provider list.
- **Server:** one adapter per gateway; server-side verification; idempotent callbacks; daily reconciliation.
- **App & web:** gateway choice in Master Admin per institution.
- **Settings & permissions:** existing payment permissions.

**Tasks**
- [ ] L.07-T1 Owner picks the next gateway (Ch 53.5 #3).
- [ ] L.07-T2 Adapter, sandbox contract test, mock adapter, reconciliation.

**Tests**
- Contract test daily in sandbox; duplicate callback test.

**Done when (acceptance criteria)**
- A pilot institution receives a payment through the new gateway into its own merchant account and it reconciles.

**Watch-outs (do not miss)**
- Amount always from server; platform never holds money (D17).

**Owner checkpoint:** Owner chooses gateway order.

#### L.08 More SMS adapters on demand

**Goal:** Add an SMS gateway adapter when two or more institutions want the same gateway.

**Depends on:** Phase 2 (more SMS adapters).

**Plan chapters:** Ch 42 (adapter rule "later"), Ch 52.8.

**Decisions:** D3, D22.

**Build**
- **Data / Server:** one adapter per gateway on the existing interface; Custom HTTP adapter remains the fallback.
- **App & web / Settings & permissions:** provider appears in the hub list.

**Tasks**
- [ ] L.08-T1 Confirm demand (2+ institutions); check the gateway's API, price and masking rules (Ch 53.4 #3).
- [ ] L.08-T2 Adapter, contract test, mock.

**Tests**
- Contract and mock tests.

**Done when (acceptance criteria)**
- Institutions can pick the new gateway without code changes elsewhere.

**Watch-outs (do not miss)**
- One institution only → use Custom HTTP instead.

**Owner checkpoint:** —

#### L.09 Extensions, one at a time

**Goal:** Build a separate extension for a single institution's special need when settings, custom records, automation and webhook/API cannot cover it, charged separately.

**Depends on:** Phase 0 (extension structure, `domain_events`), Phase 2 (custom records, incoming API, webhooks).

**Plan chapters:** Ch 43 (layers, extension rules, 43.8 later), Ch 9 (Enterprise / add-on), Ch 52.8, Ch 52.9 (custom requests rule).

**Decisions:** —

**Build**
- **Data:** extension tables with `institution_id`, RLS, included in export, backup and leak test.
- **Server:** listens to versioned `domain_events` and versioned RPC/API contracts; declares its own permissions; disabling it never breaks the core.
- **App & web / Settings & permissions:** per extension.

**Tasks**
- [ ] L.09-T1 For each request: check the layer order (setting → custom record → automation → webhook/API → extension) and the requests-list votes.
- [ ] L.09-T2 Write a milestone for the extension with price (open question: extension pricing, Ch 43.8).
- [ ] L.09-T3 Yearly review of every extension.

**Tests**
- Leak test includes extension tables; disabling the extension leaves core suites green.

**Done when (acceptance criteria)**
- Per extension.

**Watch-outs (do not miss)**
- Extensions piling up bring custom code back (Ch 43 critique #4).

**Owner checkpoint:** Owner approves each extension and its price.

#### L.10 Alternative distribution for the native module (only if Play refuses)

**Goal:** **Proposed:** if 3.01 ends with Play refusing call-log access, evaluate distributing the APK outside Play or a default-dialer model, after a legal and policy check.

**Depends on:** 3.01 (refusal recorded).

**Plan chapters:** Ch 41.8 #1, Ch 41.9 (open question), Ch 52.11 #4, Ch 50 O5.

**Decisions:** —

**Build**
- **Data / Server / App & web / Settings & permissions:** to be specified after the evaluation.

**Tasks**
- [ ] L.10-T1 Legal/policy check of direct APK distribution and of a default-dialer app.
- [ ] L.10-T2 Write a cost/risk note for the owner (update path, trust, support).
- [ ] L.10-T3 If approved, write milestones for the chosen path.

**Tests**
- —

**Done when (acceptance criteria)**
- Owner decision recorded.

**Watch-outs (do not miss)**
- The manual call log must remain the full product in every case.

**Owner checkpoint:** Owner answers the Ch 41.9 open question.

## 7. Cross-cutting tracks (run in every phase)

These tracks are not separate milestones; every milestone contributes to them.

| Track | What every milestone must do | Plan |
|---|---|---|
| **Security and tenancy** | New tables / RPCs / storage / channels in the leak test; RLS; no DEFINER without checks; secrets in the Vault. | Ch 4, 42, 48 |
| **Permissions** | Register new actions in the registry with scope, sensitivity and defaults for system roles and role templates; add them to the role-matrix test. | Ch 11 |
| **Labels and languages** | Register new terms as labels (neutral key + English / Bangla forms); all strings in both translation files. | Ch 8, 13 |
| **Settings** | New per-institution settings in the settings registry with defaults per type profile; shown in the right Settings area with its own permission. | Ch 9, Appendix A |
| **Modules and plans** | New features belong to a module; hidden when the module is off; limits enforced by the limits engine. | Ch 9 |
| **Events and audit** | Important actions write `domain_events` / timeline rows; admin changes go to the audit log. | Ch 21, 43 |
| **UX** | Every screen passes the UX checklist (Section 9.4). | Ch 47 |
| **Performance** | Measure lists and pages against the benchmark; denormalise counters with triggers; one RPC per screen where possible. | Ch 2, 47 |
| **Observability** | Errors and logs tagged with institution and user; no personal data in logs. | Ch 46, 48 |
| **Docs** | "What's new" entry, deploy type, plan / roadmap updated. | Ch 46, 48 |
| **Risks** | Before each phase, review the risk register rows for that phase. | Ch 50 |

## 8. Testing strategy

| Level | Tool / method | What it proves | When |
|---|---|---|---|
| Unit | TypeScript test runner; SQL tests (pgTAP or equivalent) | Functions and rules work | Every PR |
| RPC as real role | Tests sign in as each role template and call RPCs | Permissions and RLS work for real users | Every PR |
| Cross-tenant leak | Two (or more) institutions; every table, RPC, storage path and channel checked from the other side | No data leaks between institutions | Every PR (gate) |
| Role matrix | For each role template × permission × in-scope / out-of-scope record | Scopes, field masking and approvals are correct | Every PR touching access |
| Integration (fake adapters) | "Fake" SMS / email / payment / AI adapters in CI; sandbox adapters in staging | Hub, outbox, retries and callbacks work without real money or SMS | Every PR / nightly in staging |
| UI flows | Maestro (phone), Playwright (web) | Main flows work end to end | Every PR for touched flows |
| Screenshot | Light / dark × Bangla / English, with long labels | Layouts don't break | Every PR touching UI |
| Performance | Benchmark data set (S.06) | No regression; lists fast at 3,000+ leads | Every milestone end; before each admission season |
| Type profiles | One seeded institution per type profile runs the main flows | All education types work from one codebase | Nightly |
| Pilot acceptance | Pilot institutions use staging, then production | It works for real people | End of each phase |

## 9. Checklists

### 9.1 Pull request checklist
- [ ] Linked to milestone and task IDs.
- [ ] Ground rules G1–G20 respected.
- [ ] Migrations additive; RLS on new tables; indexes start with `institution_id`.
- [ ] Leak test and role-matrix test updated and green.
- [ ] New permissions, labels, settings and translations registered.
- [ ] Errors shown in the UI; no silent failures.
- [ ] Performance checked for lists and pages touched.
- [ ] "What's new" entry and deploy type.

### 9.2 New table checklist
- [ ] `institution_id` (and `branch_id` if relevant), `created_at`, `created_by`, `deleted_at` (soft delete) where relevant.
- [ ] RLS policies (select / insert / update / delete) based on the session's active institution and `user_access`.
- [ ] Indexes starting with `institution_id`.
- [ ] Added to the leak test, exports and backups / per-institution snapshots.
- [ ] Neutral names; no education words in table or column names.

### 9.3 New RPC / Edge Function checklist
- [ ] `SECURITY INVOKER` unless justified; if DEFINER, explicit institution and `can()` check.
- [ ] Permission checked with `can()`; scope respected.
- [ ] Idempotency key for anything that creates money, messages or records from a retryable call.
- [ ] Writes `domain_events` / timeline rows for important actions.
- [ ] Backward-compatible signature; tested as a real role.

### 9.4 New screen checklist (UX)
- [ ] Light and dark; brand colour readable in both.
- [ ] Bangla and English; long labels; large system font; Bangla line height.
- [ ] Keyboard never covers the focused field; Save visible; right keyboard type; Bangla digits converted in number fields.
- [ ] Loading skeleton, empty state with an action, error state with Retry.
- [ ] Android Back closes sheets first; no double-submit; unsaved-changes warning.
- [ ] Works on a low-end phone and a small screen; 48 dp touch targets.
- [ ] Money in lakh format where shown.

### 9.5 New integration adapter checklist
- [ ] Implements the hub interface for its kind; sandbox and live modes.
- [ ] Secrets in the Vault; hint-only display; never logged.
- [ ] Callbacks verified with the connection's own secret; idempotent.
- [ ] Errors mapped to clear messages; last error visible to the Master Admin.
- [ ] Usage and cost written to the ledger; limits respected.
- [ ] Fake adapter for CI; contract test run daily in sandbox.

### 9.6 New setting checklist
- [ ] Registered with type, default per type profile, description and label.
- [ ] Placed in the correct Settings area, guarded by that area's permission.
- [ ] Change written to the audit / change log; cache refreshed at once.

### 9.7 Release checklist
- [ ] Phase / milestone acceptance criteria met; pilot feedback addressed.
- [ ] Database migrations run in staging with production-like data; rollback plan written.
- [ ] Deploy type stated: database / functions / OTA app update / store build / web.
- [ ] Minimum app version updated if an RPC changed incompatibly (avoid this).
- [ ] Feature flags: beta institutions first, then everyone.
- [ ] Not during an admission-season freeze week.
- [ ] "What's new" published; Master Admin announcement if needed.

### 9.8 Phase exit checklist
- [ ] Every milestone of the phase done (Definition of Done).
- [ ] Exit criteria in Section 4 met.
- [ ] Risk register rows for the phase reviewed (Ch 50).
- [ ] Traceability table (Section 11) shows every plan item of the phase covered.
- [ ] Owner sign-off.

## 10. Environments and releases

| Item | Rule | Plan |
|---|---|---|
| Environments | dev → staging → production, each its own Supabase project and secrets | Ch 48 |
| App releases | OTA updates through channels (`preview`, `production`); store builds only when native code or the runtime version changes | Ch 46, 48 |
| Web | Built from the same codebase; atomic deploys; stale-build reload | Ch 45, 48 |
| Feature flags | Per institution; beta institutions first | Ch 9, 48 |
| Admission season | Load test before each season; no large releases in peak weeks | Ch 44, 48 |
| Rollback | Every release has a written rollback; database changes are additive so the previous app keeps working | Ch 48 |
| Branded apps (Phase 5) | Separate store builds from the same code; own push, OAuth, listing and permission declaration | Ch 48 |

## 11. Traceability: plan chapter → milestones

Every chapter of the plan must appear here. If a row is empty, something has been missed.

| Plan chapter | Block | Covered by milestones | Notes |
|---|---|---|---|
| Ch 1 Product at a glance | 0B | 0B.02 (working name D21, naming criteria **Proposed**, name/package/deep-link fixed before first store build), 0B.03 (education pack, all nine types D8, D18–D20), 0B.09 (institution = tenant, first user Super Admin), 0B.10 (shared-app branding D12) | Narrative 1.1–1.2 is covered by the whole roadmap. rest: final product name is an open question (Ch 53.2 row 1, owner); iOS-via-web (1.7 row 4) = Block 1B (Ch 45 web); branded app D12 = Block 3–5 (Phase 5); portal D10 = later (L). |
| Ch 2 Goals, principles and boundaries | 0A | 0A.01 (2.3 principles, 2.4 never hard-coded, 2.6 scope incl. dropped legacy items), 0A.04 (2.7 #5 `institution_type` lint, Proposed), 0A.08 (2.7 #1/#3 typed settings), 0A.11 (2.4 locale), 0A.20 (2.5 speed rule, 2.7 #4 CI benchmark, Proposed) | Branding/product-level values (app name, domain, privacy contact, developer inbox owner): rest: 0B (Ch 5, 6). "Reset to profile defaults" for settings beyond labels: rest: 0B (Ch 6, 7). |
| Ch 3 Tech stack and architecture | 0A | 0A.01 (3.2 stack, 3.3–3.6 rules, 3.8 identity, 3.9 #3/#4/#8), 0A.02 (3.6 release, 3.8 secrets), 0A.04 (3.3 INVOKER/DEFINER, guard triggers, 3.9 #1/#2/#6), 0A.06 (3.7 tagged-log foundation), 0A.07 (3.8 per-institution keys), 0A.09 (3.3 `domain_events`), 0A.14 (3.4 settings cache, ask-before-risky) | Error dashboard, alerts, staged rollout: rest: 1B (Ch 46, 48). Outbox: rest: 0B (Ch 42). Append-only `lead_activity`, `notes`, denormalised lead columns: rest: 1A (Ch 14, 21). Native module: rest: Phase 3. AI prices in config: config framework 0A.01, values rest: Phase 4 (Ch 40). Custom-domain-capable hosting (Proposed): rest: 1B (Ch 45). |
| Ch 4 Multi-tenancy and isolation | 0A | 0A.03 (4.2, 4.6, 4.7 access version), 0A.04 (4.2 indexes, 4.4 uniqueness, 4.13 #1/#8), 0A.05 (4.12 leak test 1–4), 0A.06 (4.3 storage/Realtime/Edge/logs), 0A.07 (4.10 secrets), 0A.08 (4.4 counters, 4.5 settings), 0A.14 (4.3 client cache), 0A.15 (4.2 `branch_id`), 0A.17 (4.7 `can()`, `user_access`), 0A.20 (4.8 big/small benchmark, 4.12 #6 role matrix) | 4.5 integrations, 4.12 #5 external-connection leak test, 4.10 closure flow: rest: 0B (Ch 5, 42). 4.8 per-institution rate limits: rest: 0B (OTP) and 1B (public pages, bulk), Block 2 (API). 4.9 job scheduler and 4.11 export snapshots: rest: 1B (Ch 44). 4.8 custom-field/record/automation limits: rest: 0B/1B/Block 2. 4.13 #10 group-owner leak test: rest: 1B. Push tokens per institution+user+app: rest: 1B (Ch 25). Export isolation: rest: 1A (Ch 23). Public page slug isolation: rest: 1B (Ch 27). |
| Ch 4 Multi-tenancy (4.9 job scheduler, 4.11 export snapshots) | 1B | 1.16; leak-test extensions in 1.19, 1.29, 1.30, 1.31 | Only the phase-1 parts (scheduler with fair share, per-institution snapshots). rest: Phase 0 (Block 0A). |
| Ch 5 Master Admin panel | 0B | 0B.02 (platform roles, separate login, 2-step, alerts, audit, menu shell, platform users), 0B.04 (Labels tab, product-default labels, 5.10), 0B.05 (Plan & billing tab: modules/limits), 0B.07 (institution list, approval, duplicate check, states, notices, full export, close), 0B.08 (support entry, Audit tab), 0B.10 (checklist progress per institution), 0B.11 (Providers, Integrations tab, secrets), 0B.12 (delivery log, ledger), 0B.13–0B.15 (Messaging tab, summary, alerts, Notifications tab D5), 0B.16 (billing core, 5.7) | rest: health dashboard and alerts 5.8, announcements 5.9, groups and group dashboard 5.11 (D25), monthly cost view = Block 1B (Phase 1); Domain tab D16 = Block 1B; Payments tab (institution merchant, D11) = Block 2; developer inbox 5.12 and branded app 5.16 = Block 3–5 (Phase 5); feature Requests list 5.13 has no phase in Ch 52 — only a menu placeholder here, coordinator to place (suggest Phase 5 with developer inbox); busy-season load tests/status page 5.15 = cross-cutting (Ch 48 / Block 1B jobs). Legal check of data-protection rules = owner task in 0B.07. |
| Ch 5 Master Admin panel (5.3 Dashboard / Groups / Announcements / Domain, 5.8, 5.9, 5.11, 5.17 #4 #9) | 1B | 1.19 (groups, group dashboard), 1.30 (Domain menu), 1.33 (health dashboard, alerts, announcements, cost view) | Targeted announcements and the panel menu structure marked Proposed. rest: Phase 0 (Block 0B: list, approval, status, support entry, messaging setup, plans, profiles, platform users); payments setup → Block 2; developer inbox (5.12), feature-request list (5.13), branded apps (5.16) → Block 3–5. Support-role setup rights (5.17 #1, Proposed) → Block 0B. |
| Ch 6 Institution setup and onboarding | 0B | 0B.07 (approval, trial, lifecycle 6.4, 6.7, trial-abuse limit **Proposed**), 0B.04 (change type/industry later 6.6, industry stored as education), 0B.09 (who opens, wizard 6.2–6.3, CAPTCHA, SMS/bulk off before approval), 0B.10 (checklist 6.5, branding, copy-from-institution, video guides, Support notice **Proposed**) | rest: Excel import of courses/staff/leads (6.5 help) = Block 1A (Ch 23); payment merchant setup = Block 2; own domain = Block 1B; Google/OTP option in wizard added by 0B.17/0B.18. Trial length is an open question (Ch 53.2 row 2). |
| Ch 7 Institution types and type profiles | 0B | 0B.03 (packs/profiles as versioned data, nine profiles, role templates D26, presets, schema validation, no-`institution_type` lint), 0B.04 (applier, mixed institutions, reset, new-version opt-in **Proposed**, seeded test institution per profile), 0B.05 (modules off until blocks exist 7.8) | Profile parts for later blocks (stages, documents, fees, ID pattern, lead score, templates, reports, AI words) are stored now; their areas plug into the applier in Blocks 1A, 1B, 2, 3–5. |
| Ch 8 Terminology (labels) and neutral keys | 0A | 0A.12 (8.2–8.7, 8.9, 8.10, Proposed neutral status/module keys), 0A.19 (8.8 Settings → Terminology, 8.10 #4), 0A.10 (8.9 rules 1–2 lint), 0A.04 (8.10 #5 schema naming lint, Proposed), 0A.16 (8.6 permission labels), 0A.20 (8.9 rule 4 weird-label screenshots) | Master Admin label view and lock UI: rest: 0B (Ch 5); lock column/enforcement in 0A.12/0A.19. Type-profile label defaults data: rest: 0B (Ch 7). Label use in notifications, templates, prints, public pages, exports (technical-name option), AI prompts: rest: 1A/1B/Block 2/Phase 4 (each feature adds its words, Ch 8.9 rule 6). |
| Ch 9 Modules, plans, limits and billing | 0B | 0B.05 (modules, dependencies **Proposed**, plans as data, limits, counters, 80/100 %, server enforcement, downgrade check, add-on catalog), 0B.12 (usage ledger with payer D15, monthly limit gate), 0B.13 (per-part cost, 70/160), 0B.16 (subscription billing core, manual + platform SSLCommerz, invoices/receipts, reminders, grace → read-only, Settings → Billing, institution view 9.8) | rest: monthly cost view, budgets and alerts (Phase 1) = Block 1B; SMS billing statements Excel/PDF (Phase 2) = Block 2; group single invoice and group discount (D25) = Block 1B with groups; plans by industry = later (L). Open questions: prices, limits, trial length, modules per plan, price by type (Ch 53.2 rows 2–4). |
| Ch 9 Modules, plans, limits, billing (9.6 group invoice / discount, 9.7 monthly cost view, campaign and automation limits, 80% / 100% rules) | 1B | 1.19 (group invoice and discount), 1.22 (monthly SMS limit, usage ledger by type), 1.27 (campaign daily limit, prepaid balance, SMS pack add-on), 1.32 (automation limits), 1.33 (cost view, budgets) | rest: Phase 0 (Block 0B: plans, trial, billing core); SMS billing statements → Block 2. |
| Ch 9 Modules, plans, billing (SMS billing statements) | 2 | 2.19 (statements), 2.02 (Fees / Hostel & transport modules), 2.04, 2.10, 2.14, 2.16, 2.17, 2.20 (module registration), 2.10 (gateway fee ledger, D15) | rest: Phase 0 (plans, limits, billing core, usage ledger), Phase 1 (monthly cost view). Starter module list vs phase: owner checkpoint in 2.02. |
| Ch 10 Login, account and session | 0B | 0B.02 (Master Admin login page with 2-step), 0B.17 (Google + modes, identity linking, method enable/disable **Proposed**, last-method rule), 0B.18 (OTP SMS + email, limits, forgot password **Proposed**, OTP step-up **Proposed**), 0B.19 (staff sign-up, pending approval, invitations, app states, admin password reset rules, reset format), 0B.20 (profile, account deletion, privacy page, sign-out, inactivity sign-out, sign out everywhere, app lock) | Password login basics, `institution_members` structure and access version = Block 0A. rest: institution switcher, `choose_institution` state (**Proposed**) and groups (Phase 1) = Block 1B; OTP on applicant status page = Block 3–5 (Phase 5); WhatsApp OTP = later (L); branded-app OAuth clients = later (L). |
| Ch 10 Login, account, session (10.3 switcher, 10.6 `choose_institution`, 10.9 phone security, 10.10 #1 #4 #7) | 1B | 1.19 (switcher, chooser, groups), 1.23 (push deep link institution switch), 1.33 (OTP anomaly alert), 1.34 (app lock, idle sign-out, sign out all devices) | `choose_institution` marked Proposed. rest: Phase 0 (Block 0A / 0B: password, Google modes, OTP, sign-up, reset, profile, delete, access version). |
| Ch 11 Users, roles and permissions (phase-0 parts) | 0A | 0A.03 (`institution_members`, user kind, platform separation), 0A.16 (11.5 registry, 11.7 templates D26, 11.9 behaviour flags, 11.10 who rules, sensitive permissions and field registry, R20), 0A.17 (11.6 scopes, 11.7 multiple roles D23, temporary roles, no escalation, 11.13 `can()`, `user_access`, access version, protections), 0A.18 (11.14 Users screen, role editor, compare/copy, new permissions, basic access explainer, audit log), 0A.20 (role-matrix test) | rest: 1B — 11.11 field masking (D24) and export controls, 11.12 approval engine, 11.8 delegation and collaborators, access review report, 11.15 groups/group owner/group dashboard (D25), Proposed ban on delegating sensitive permissions. rest: 0B — 2-step login enrolment and Proposed trusted-device memory (Ch 10), support entry and platform roles UI (Ch 5), password reset (Ch 10.7). rest: Phase 3 — per-user call-log sync override (Proposed). rest: later — portal users (D10). Proposed "simple mode": 0A.18-T9 if approved. |
| Ch 11 Users, roles, permissions (phase-1 parts: 11.8, 11.11, 11.12, 11.14 access review, 11.15 groups, 11.16) | 1B | 1.24 (approval engine, simple mode Proposed), 1.25 (field rules D24, sensitive fields, export controls), 1.26 (delegation, collaborators, access review), 1.19 (group owner role, group dashboard) | Sensitive permissions not delegable marked Proposed. rest: Phase 0 (Block 0A: registry, scopes, multi-role, org units, behaviour switches, `user_access`, `can()`, templates, explainer, 2-step and its "remember trusted device" Proposed); per-user call-log-sync override (11.9) → Block 3–5 (phase 3); portal users (D10) → later. |
| Ch 11 (parts used here) | 3–5 | 3.06, 4.03, 4.08 | Behaviour switches "call log sync mandatory", "show in team activity", "count as manager", "count on leaderboard and scorecard" consumed; portal users — L.03. rest: Phase 0/1. |
| Ch 12 Branches and org structure | 0A | 0A.15 (12.3, 12.4, 12.6 guidance, 12.7 #1/#7), 0A.19 (12.2 Settings → Branches, hide when off), 0A.04 (nullable `branch_id` lint), 0A.17 (branch scope), 0A.20 (12.7 #6 benchmark) | Branch module on/off and plan limits (Starter 1, Standard 2–3, Pro unlimited, add-on): rest: 0B (Ch 9). Branch info on receipts/templates/forms: rest: 1B (Ch 24, 27), Block 2 (Ch 35). Proposed branch filter/column, bulk assign branch, lead branch change: rest: 1A. Branch-split reports/leaderboard/Master Admin dashboard: rest: 1B, Phase 4. Per-branch series (Proposed) and merchant/SMS open questions: rest: Block 2 / Ch 53. Per-branch calendar override: rest: later. |
| Ch 13 Language, locale, calendar and time | 0A | 0A.10 (13.2 bn+en UI, D13), 0A.11 (13.3 locale settings, 13.4 lakh/digits/dates, 13.6 timestamptz, keys `working_days`/`working_hours`/`quiet_hours` registered, Proposed ICU collation spike), 0A.13 (13.4 Bangla line height) | 13.5 office calendar (holidays, Settings → OFFICE, follow-up presets): rest: 1A (Ch 18). Quiet hours in sending: rest: 1B (Ch 25, 26). 13.6 per-institution jobs: rest: 1B (Ch 44). 13.7 academic calendar and admission windows: rest: 1B (Ch 27); roll over to next session: rest: Block 2 (Ch 28). Bangla search: rest: 1A (Ch 15). Recipient preferred language (Proposed): rest: 1B (Ch 24). Master Admin yearly holiday draft (Proposed): rest: 1A. |
| Ch 13 Language, locale, calendar (13.7 academic calendar and admission seasons; 13.5 used by scheduler) | 1B | 1.28 (sessions / intakes, open-closed, season key), 1.16 (working days, holidays, quiet hours in job selection), 1.20 (locale money / date formatting) | rest: Phase 0 (Block 0A: UI languages, locale settings); office calendar settings with follow-ups → Block 1A; "Roll over to next session" → Block 2 (Ch 28); season filters in reports / leaderboard → Block 3–5 (phase 4). |
| Ch 14 Leads — custom field builder only | 0B | 0B.06 (builder for lead/client/network, all field types incl. GPA and file, options, presets from profile, `custom_field_values` with GIN/expression indexes, plan limit, sensitive flag, benchmark) | rest: everything else in Ch 14 (lead fields, guardian, duplicates, form, assignment, visibility, use of custom fields in forms/filters/templates/eligibility/reports) = Block 1A / 1B / 2 / 3–5; active-lead limit enforcement uses 0B.05 counters. |
| Ch 14 Leads | 1A | 1.01, 1.02, 1.03, 1.14, 1.15 | 14.2–14.6 data and custom-field use 1.01; 14.10 access 1.02; 14.3, 14.7–14.9, 14.11 form, duplicates, assignment, hand-over, plan limit 1.03; 14.12 #4 guardian matching on import 1.14; merge (Proposed) 1.15. Rest: data skeleton, custom field builder, `branch_id`, roles v2 base — Phase 0; field-level masking (D24 policy), delegation, collaborators, approval engine `lead.delete`, automation-rule assignment, public-form leads over limit (Proposed) — Block 1B; sibling discount — Block 2 (Ch 34); one message per guardian, under-18 to guardian — Block 1B (Ch 24); sensitive fields never to AI — Phase 4 (Ch 40). |
| Ch 15 Lead list, board, search, filter | 1A | 1.04, 1.05, 1.12, 1.13 | Search, chips, sort, cards, paging, cache 1.04; Recent / Starred chips 1.05; filters, saved filters, bulk, quick menu, board 1.12; score / visit sort and filter 1.13. Rest: AI chip / filter / sorts — Phase 4; admission-window filter — Block 1B (Ch 27); papers / fee / batch / not-eligible filters and sorts, student ID / board ID search fields, bulk fee / placement / board-flow actions — Block 2; call-lock chip "X is on a call" — Phase 3; SMS button with template choice — Block 1B (Ch 24); bulk delete approval — Block 1B. |
| Ch 16 Lead page and peek | 1A | 1.05 | Pipeline card filled by 1.07–1.08, timeline by 1.09–1.10, Visit card by 1.13, next-call card by 1.06. Rest: Fee, Papers, Files, board-flow cards and eligibility warning — Block 2; AI chance and Admission credit cards, AI in peek — Phase 4; institution-wide change log — Phase 4 (Ch 38); notification deep-link delivery — Block 1B (Ch 25). |
| Ch 17 Stages, admission, lost, reopen | 1A | 1.01, 1.07, 1.08 | Stage table 1.01; stage settings, rules, moves, history, events 1.07; lost, revive, reopen, basic mark admitted, basic cancel, undo admission 1.08; conversion records Proposed in 1.08. Rest: full admission (batch / section / seat lock, papers, eligibility, pay now, fee lock, student ID, board-flow reset, welcome message, Students tab) and full cancel side effects, payment check before undo — Block 2; AI credit — Phase 4; stage automation — Block 1B (Ch 43); funnel / lost-reason reports — Phase 4 (Ch 38). |
| Ch 17 Pipeline, admission, cancel (full side effects) | 2 | 2.05, 2.16 (board flow reset / clear), 2.06 (pay now) | rest: Phase 1 (stages, lost, reopen, admitted basics); AI credit at admit: Phase 4. |
| Ch 18 Follow-ups and reminders | 1A | 1.06, 1.10, 1.11, 1.13 | Model, presets, holidays, outcome defaults, Today 1.06; auto-done in call trigger 1.10; reminders, speed-to-lead, quiet hours, `notifications_tick` 1.11; visit reminders 1.13. "Done only when connected" Proposed in 1.06. Rest: inbox / push delivery — Block 1B (Ch 25, 42); Home placement of Today — Block 1B (Ch 45); automation-created follow-ups — Block 1B (Ch 43); per-institution job scheduler taking over the tick — Block 1B (Ch 44); multiple tasks per lead — later (Proposed). |
| Ch 19 Calls, call log, call lock | 1A | 1.01, 1.02, 1.10 | Call-log schema 1.01; masked dial path 1.02; manual log, popup, post-call trigger, unreachable, missed-call rules, talk time 1.10. Rest: auto mode, call-log sync, ±10-min matching, call lock, incoming-call lock, caller card, `call-lock-clean` job — Phase 3 (Block 3–5); double-call warning — Phase 3 per Ch 52.5 and the block plan, although Ch 19.12 lists it for phase 1 (owner to confirm); weekday × hour heatmap and team reports — Phase 4 (Ch 38); outcome correction with approval — Proposed, needs Block 1B approval engine; offline call queue — Block 1B (Ch 47); SMS-button logs with template id — Block 1B (Ch 24). |
| Ch 19 Calls, call log and call lock | 3–5 | 3.02, 3.04, 3.05, 3.07 | Call lock (19.7), double-call warning (19.8), auto mode (19.5), sync summary (19.10), exact durations (19.9) here. rest: manual call log, popup, triggers, manual reports — Phase 1 (Block 1A). Ch 19.12 Proposed items (lock in Phase 1, admin-approved outcome correction) noted in 3.02; call-log daily summary / partition Proposed in 4.02. Team activity report — 4.03. |
| Ch 20 WhatsApp | 1A | 1.10 | Phase-1 part is Proposed: open (number / phone / username), manual log, Ask after WhatsApp, WhatsApp calls screen, own delete 24 h, module gate. Rest: template pre-fill and do-not-contact warning — Block 1B (Ch 24); notification-listener auto-log and WhatsApp lock — Phase 3; WhatsApp reports in Reports / Team activity — Phase 4; official WhatsApp Business API — later (Ch 52.8). |
| Ch 20 WhatsApp | 3–5 | 3.02 (WhatsApp lock), 3.08, 4.02, 4.03, L.04, L.05 | Native auto-log (20.5) in 3.08; WhatsApp report in Reports/Team activity (20.6) in 4.02/4.03; official API, campaigns, OTP Later. rest: open, templates, manual log, Ask after WhatsApp, WhatsApp calls screen — Phase 1 (Block 1A). |
| Ch 21 Notes, voice notes, timeline, delete, restore | 1A | 1.09, 1.12 | Notes, voice notes (platform storage), timeline, delete rules, 10-min undo, admin restore, lead soft delete 1.09; bulk note 1.12; Deleted filter + lead restore and phone-pattern warning Proposed in 1.09. Rest: Drive storage — Block 2 (Ch 32); change-log screen — Phase 4 (Ch 38); permanent-deletion job — Block 1B (Ch 44); AI de-identification — Phase 4; frequent-delete visibility in team activity — Phase 4. Open question (24 h / 10 min configurable) kept as constants. |
| Ch 22 Visits, lead score, Recent, Starred | 1A | 1.05, 1.13 | Recent / Starred 1.05; visits, walk-in, reminders, stage effect, score engine, nightly recalc 1.13. Rest: lead-facing visit SMS / email and `{visit_time}` / map-link variables — Block 1B (Ch 24); Home "Today's visits" and "Recent" placement — Block 1B (Ch 45); fee-discussed signal live once Fee module exists — Block 2; AI-vs-score comparison report — Phase 4; multiple appointments — later (Ch 49). Open question: default N days after missed visit per type profile. |
| Ch 23 Import, export, phone contacts | 1A | 1.14 | Contacts, Excel/CSV import with mapping, dry run, duplicates, round robin, error / template files, 24-h undo, Excel export, Export my work; undo-activity warning Proposed. Rest: export controls (scope approval `export.large`, log, watermark, daily limits, masking in export Proposed) — Block 1B (Ch 23.5, Ch 11); background import / export jobs with signed links — Block 1B (Ch 44); consent for contact-imported leads — Block 1B (Ch 24); fee / board-flow export columns — Block 2; alumni import — Phase 5 (Ch 37); course / staff import — Phase 0 setup (Ch 6) and Block 2 (Ch 28); whole-institution export — Phase 0 (Ch 5). Open question: N rows for large export and daily limit defaults (Block 1B). |
| Ch 24 Message templates, recipients, consent | 1B | 1.20 (24.1–24.4, 24.7 #1–#3 #7–#9), 1.21 (24.5–24.6, 24.7 #4–#6) | Neutral variable aliases `{offering}` Proposed (1.20). Recipients matrix, consent / opt-out, minors rule marked Proposed. rest: staff recipient matrix → Phase 0 (Block 0B); student receipt and installment messages → Block 2. |
| Ch 24 Templates, recipients, consent (student messages) | 2 | 2.07 (receipt), 2.09 (due / late), 2.16 (welcome, batch start, ID issued), 2.19 (template report wording) | rest: Phase 0 (staff recipient matrix), Phase 1 (templates, lead / student / guardian matrix, consent). |
| Ch 25 Notifications — staff recipient matrix | 0B | 0B.15 (notification kinds registry, staff kind × channel matrix set by Master Admin D5, profile defaults, cost estimate, `notifications` setting schema), 0B.12 (outbox, OTP priority lane, delivery log, ledger categories), 0B.13/0B.14 (SMS and email channels D1, D3, D4) | rest: inbox, push, `notify()` with dedupe/quiet hours/urgent, email/SMS notification delivery, Settings → TEAM → Notifications, user mute, push check/health, token table with `app_id`, device ownership (Phase 1) = Block 1B; branded-app push = later (L). Ch 24.5 recipient rows for lead/student/guardian/referrer and consent = Block 1B. |
| Ch 25 Notifications | 1B | 1.22 (25.1–25.5, 25.8 #1–#4 #6 #7), 1.23 (25.6–25.7, 25.8 #5 #8 #9), 1.21 (channel matrix) | Mute only non-urgent and urgent SMS fallback marked Proposed. rest: per-institution SMS / email setup and staff matrix → Phase 0 (Block 0B); branded-app push connections → Block 3–5 (phase 5 / later); kinds of later modules registered by those modules. |
| Ch 26 Bulk SMS campaigns | 1B | 1.27 | Whole module, auto-pause and comparative effect report marked Proposed. rest: campaign effect report, email campaigns, more SMS adapters → Block 2; WhatsApp campaigns → later (official API). Open questions Ch 53.2 #3, 53.4 #2 at owner checkpoint. |
| Ch 26 Bulk SMS campaigns (effect report, email campaigns) | 2 | 2.19 | rest: Phase 1 (SMS campaigns); WhatsApp campaigns: later (official API). |
| Ch 27 Public forms, application form, admission windows | 1B | 1.28 (27.4), 1.29 (27.1–27.3, 27.5–27.7), 1.30 (27.2 custom domain, 27.6 #4) | Form builder, application number, suspicious-submission flag, conversion rate marked Proposed; application-number format is an open question. rest: online application fee → Block 2 (with D11 / D17 payments); `/refer/<code>` and applicant status page → Block 3–5 (phase 5); roll-over → Block 2. |
| Ch 27 Public forms (application fee, roll-over) | 2 | 2.10 (application fee), 2.01 (roll-over), 2.12 (eligibility on form), 2.13 (upload mapping), 2.18 (result page) | rest: Phase 1 (form builder, windows, custom domain); Phase 5 (status page, `/refer`). |
| Ch 27 Public forms, application form, admission windows | 3–5 | 5.02, 5.04 | `/refer/<code>` and `?ref=` counting (5.02), applicant status page with OTP (5.04). rest: form builder, `/apply/<slug>`, rate limits, calendar, custom domain — Phase 1 (Block 1B); online application fee — Phase 2 (Block 2). Open question on application-number format raised in 5.04-T6. |
| Ch 28 Courses, batches, sections and seats | 2 | 2.01, 2.02 (fee lines, fee sync), 2.05 (seat lock at admit / cancel), 2.08 (placement seat check), 2.18 (quota seats, seat hold) | 28.8 master lists come from Phase 1 (checked in 2.01-T12); `branch_id` column, labels and neutral keys from Phase 0; season filter for reports / leaderboards: rest Phase 4 (Ch 38, 39). |
| Ch 29 Eligibility rules | 2 | 2.12, 2.05 (check hook) | Custom field builder and presets: Phase 0. |
| Ch 30 Admission test, merit list, waiting list | 2 | 2.17, 2.18 | Applicant status page showing test date / result: rest Phase 5 (Block 3–5). Special merit formulas: extension, later (Ch 43). |
| Ch 31 Papers, uploads, passport photo (not Photo Studio) | 2 | 2.13, 2.14 (server re-check in `drive-upload`), 2.15 | Photo Studio (31.5) and `photo_presets`: rest Phase 5 (Block 3–5). |
| Ch 31 Documents, uploads, passport photo, Photo Studio | 3–5 | 5.05 | Photo Studio (31.5) only. rest: documents, upload rules, passport photo, iLovePDF/remove.bg connections — Phase 2 (Block 2). |
| Ch 32 File storage (Google Drive / storage) | 2 | 2.14 | Voice-note recording itself: Phase 1 (Ch 21); Phase 2 stores its files. |
| Ch 33 Student ID | 2 | 2.04, 2.05 (assign at admit, keep on cancel), 2.08 (new ID on placement), 2.16 (board-submitted flag) | — |
| Ch 34 Fee structure, discounts, approval | 2 | 2.02, 2.03, 2.05 (fee lock, Change final fee), 2.09 (invoices, late fee, per-credit input) | Approval engine itself: Phase 1. Credit transfers via custom records: 2.20. |
| Ch 35 Payments, installments, receipts, refunds, online payment | 2 | 2.06, 2.07, 2.09, 2.10, 2.11 | Other gateways (bKash, Nagad direct …): later (Ch 52.8). |
| Ch 36 Students tab, placement, board flow | 2 | 2.08, 2.16 | Guardian / student portal: later (D10). |
| Ch 37 Alumni and referrals | 3–5 | 5.01, 5.02, 5.03 | All of Ch 37 (records, screens, referrals, public refer page, rewards, Proposed approval policy / credit rule / rewards report). |
| Ch 38 Team activity, change log and reports | 3–5 | 4.01, 4.02, 4.03 | Placed per Ch 52.6 (Phase 4). Ch 38.6 Proposed moving change log and core reports to Phase 1 and collection to Phase 2 — flagged in 4.01 watch-outs; if Phase 1/2 build them, 4.01/4.02 only fill gaps. Group-dashboard cross-institution totals stay in Phase 1 (Block 1B). |
| Ch 39 Credits, leaderboard, milestones, scorecard | 3–5 | 4.08, 4.09 | All of Ch 39, incl. jobs `credit-tick`, `credit-level-tick`, `weekly-scorecard`, retro recalculation. |
| Ch 40 AI features and Admission Contribution | 3–5 | 4.04, 4.05, 4.06, 4.07 | All of Ch 40. rest: AI connection structure in the hub — Phase 0 (Block 0B) per Ch 40.10; 4.04 fills in the `ai` kind. Open questions (key ownership, AI pricing) at 4.04 owner checkpoint. |
| Ch 41 Android native module and call-log sync | 3–5 | 3.01, 3.03, 3.04, 3.05, 3.06, 3.07, 3.08, 3.09, 3.10, 5.09, L.10 | Play gate first (3.01). Branded-app declarations per package in 5.09. Alternative distribution if Play refuses — L.10 (Proposed). |
| Ch 42 Integration hub — hub + SMS/email adapters + OTP route | 0B | 0B.11 (catalog, connections, sandbox/live, Vault secrets, rotation, payer D15, close hook I14, I1–I3, I9–I11), 0B.12 (adapter interfaces, outbox, fair limits I6, webhook router I4, circuit breaker I5, health/test, usage ledger I7, time zone I12, mock adapters for tests), 0B.13 (SMS presets, Custom HTTP with SSRF limits **Proposed**, platform gateway, sender ID, routes, delivery reports, low balance, contract tests), 0B.14 (SMTP/API email, SPF/DKIM/DMARC, platform mail, bounce watch), 0B.15 (Messaging summary and rules 42.3), 0B.16 (platform's own SSLCommerz merchant 42.6), 0B.17/0B.18 (Google/OTP login row 42.7) | rest: push per app, outgoing webhooks, full sandbox/fake adapter set in CI, custom domain + SSL D16 (Phase 1) = Block 1B; institution payments (manual + SSLCommerz, reconciliation D11/D14/D17), incoming API, PDF/photo services, Drive, more SMS adapters (Phase 2) = Block 2; AI connection = Block 3–5 (Phase 4); official WhatsApp API, branded-app connections, other payment gateways = later (L). Open question: first institutions' SMS gateways (Ch 53.2 row 5). |
| Ch 42 Integration hub (phase-1 parts: push per app, outgoing webhooks, sandbox / fake adapters, custom domain + SSL) | 1B | 1.17 (fakes, sandbox contract tests, I1 / I3 / I5 / I8), 1.23 (push per app), 1.30 (domain + SSL), 1.31 (outgoing webhooks) | rest: Phase 0 (Block 0B: hub core, SMS / email adapters, Custom HTTP, OTP route, Vault, key rotation reminder Proposed); payments, reconciliation, incoming API, PDF / photo, Drive, more SMS adapters → Block 2; official WhatsApp API, branded-app connections → later. |
| Ch 42 Integration hub (payments, reconciliation, PDF / photo, Drive, incoming API, more SMS adapters) | 2 | 2.10, 2.11, 2.14, 2.15, 2.19, 2.20 | rest: Phase 0 (hub core, first SMS adapter, email, login), Phase 1 (push per app, outgoing webhooks, sandbox / fake adapters, custom domain); later: official WhatsApp API, branded app connections, more adapters on demand. |
| Ch 42 (parts used here) | 3–5 | 4.04, 5.08, L.04, L.06, L.07, L.08 | AI kind, branded "app" connection, WhatsApp API, gateways, SMS adapters. rest: Phase 0–2. |
| Ch 43 Custom features (event log + extension conventions) | 0A | 0A.09 (43.2–43.5, 43.7 #4/#5/#6, Proposed partitioning), 0A.05/0A.09 (43.4 #6 leak test on ext tables), 0A.16 (43.5 permission declaration path) | Custom fields: rest: 0B (Ch 14). Automation rules and Proposed loop guard/dry run: rest: 1B. Custom records, incoming API, API key scopes: rest: Block 2. Outgoing webhooks: rest: 1B. Individual extensions and pricing: rest: later / Ch 53. |
| Ch 43 Custom features (automation rules; webhook layer) | 1B | 1.32 (automation), 1.31 (webhooks, event contract versioning) | Loop protection, dry run, rule log marked Proposed. Note Ch 43.8 lists webhooks in phase 2 but Ch 42.11 / 52.3 / 52.11 #3 place outgoing webhooks in phase 1 (followed here). rest: `domain_events`, extension framework, custom fields, event partitioning (Proposed) → Phase 0 (Block 0A / 0B); custom records and incoming API → Block 2; extensions → later. |
| Ch 43 Custom features (custom records, API) | 2 | 2.20 | rest: Phase 0 (`domain_events`, extension conventions, custom fields), Phase 1 (automation rules, outgoing webhooks); extensions: later. |
| Ch 44 Background jobs | 1B | 1.16 (scheduler, run log, catch-up, snapshots), plus the jobs placed in their feature milestones: push receipts 1.23, campaign send 1.27, domain / SSL check 1.30, access review and temp-role expiry 1.26, automation date rules 1.32, health aggregation 1.33 | rest: outbox worker base → Phase 0 (Block 0B); fee, payment, invoice, reconciliation, waitlist jobs → Block 2; credit, scorecard, AI jobs → Block 3–5 (phase 4); held-calls / call-lock cleanup → phase 3. |
| Ch 44 Background jobs (Phase 2 jobs) | 2 | 2.03 (`fee-discounts`), 2.09 (invoices, `fee-payments`), 2.11 (reconciliation), 2.18 (waiting list), 2.12 / 2.13 (recompute / counter jobs) | Scheduler: Phase 1 / Phase 0. |
| Ch 44 (jobs used here) | 3–5 | 3.02 (`call-lock-clean`), 3.05 (`held-calls-cleanup`), 4.04/4.05 (`ai-*` kicks, daily run), 4.08 (retro), 4.09 (credit and scorecard jobs), 5.06 (90-day cleanup) | Scheduler itself — Phase 1 (Block 1B). |
| Ch 45 Home, More, Settings, website | 1B | 1.35 | Role-based Home cards, Settings search, new hosting marked Proposed (hosting decided in 1.30). Web landing on Leads is an interim until Students exist. rest: shell, branding, Settings structure → Phase 0; later cards and Settings entries arrive with their features (Blocks 2, 3–5); live approval toast → Block 2. |
| Ch 46 Feedback, crash, speed check, app update | 1B | 1.18 (crash collection, error dashboard, speed check, app versions, OTA banner, What's new, min version, store-update card data), 1.22 (`app_update` "ask to update"), 1.23 (Push health), 1.33 (announcements) | Crash in phase 1 and automatic speed sampling marked Proposed. rest: feedback chat and full developer inbox (46.2) → Block 3–5 (phase 5); native crash collection (`takeNativeCrashes`) → phase 3. |
| Ch 46 Feedback, crash, speed check, app update | 3–5 | 3.03 (native crashes), 3.10 (store-update card, min version), 5.06, 5.07, 5.08 (branded update channels) | Feedback chat and developer inbox here. rest: crash collection, error dashboard, speed check, app versions, push health, OTA banner, What's new, announcements — Phase 1 (Block 1B). |
| Ch 47 UX, theme, offline and quality checklist (design system) | 0A | 0A.13 (47.2–47.5, 47.8, 47.11 design system, screenshot harness, checklist in PR template), 0A.14 (47.6 navigation, 47.7 offline strip/slow net/server time, 47.9 cache rules, 47.10 app lock, idle sign-out, sign out all devices), 0A.11 (47.3 Bangla digit input, 47.8 lakh), 0A.04 (47.9 RLS init-plan, `jit = off`) | Offline queues, SWR list caches, Home/list speed tricks (single Home RPC, page size 30, lazy board columns): rest: 1A/1B. Image size/data cost, battery: rest: Block 2 / Phase 3. Full E2E suites: rest: 1B. Checklist applies to every later screen (cross-cutting). |
| Ch 47 UX, theme, offline, quality (offline queues, caching, phone security) | 1B | 1.34 (47.7, 47.9, 47.10, 47.12 #3–#5), 1.35 (single Home RPC, counts RPC) | rest: design system → Phase 0 (Block 0A); the per-screen quality checklist (keyboard, forms, states, accessibility, low-end phones, data use, battery, app size) is a cross-cutting track applied to every milestone (coordinator). |
| Ch 48 Build, release, testing and deploy (repo, CI, environments, leak test, lint) | 0A | 0A.01 (48.2 identity, D21), 0A.02 (48.3 EAS, 48.4 Actions, 48.5 secrets, 48.6 PR/What's new/expand-contract, Proposed secret scan and deploy-type check), 0A.04 (DEFINER audit, RPC-as-role, sweep), 0A.05 (leak test), 0A.08 (settings validation, `min_app_version` check), 0A.10 (i18n lint), 0A.13 (screenshot tests), 0A.20 (role matrix, seed institutions, benchmark, Proposed CI benchmark gate) | Per-profile seed institutions for every type profile (D8): harness 0A.20, profile data rest: 0B. Feature flags, beta institutions, channel rollout/rollback, observability, fake adapters, E2E: rest: 1B. Contract/queue tests: rest: 0B/1B. 48.9 Play declarations and Data Safety: rest: Phase 3; account-deletion web path: rest: 0B (Ch 10). Branded app pipeline: rest: Phase 5. |
| Ch 48 Build, release, testing (per-institution feature flags, beta institutions, channel OTA, rollback — Ch 52.3 phase-1 row) | 1B | 1.18 (flags, beta, channel OTA, rollback), 1.17 (fake adapters in CI) | Placed here because Ch 52.3 lists them as phase-1 platform work; check for overlap with Block 0A's Ch 48 scope. rest: Block 0A (CI, environments, leak test, lint, min version mechanism); branded apps → phase 5. |
| Ch 48 Build, release, testing, deploy | 3–5 | 3.01, 3.10 (Play declaration, Data Safety), 5.08, 5.09 (branded app pipeline) | rest: app identity, EAS, Actions, secrets, leak test, test suites — Phase 0 (Block 0A); flags, beta, rollback, observability, mocks, E2E — Phase 1 (Block 1B). Every milestone in this block adds its objects to the leak/role/screenshot suites. |
| Ch 49 Industry packs (packs as data, D20) | 0B | 0B.03 (`industry_packs` / `type_profiles` versioned data, education only open, industry list stored, sensitive-field rules 49.7), 0B.04 (multiple types, industry change with preview, pack-version opt-in **Proposed**, neutral keys stay out of user-facing output), 0B.09 (industry step hidden while one industry open) | Neutral keys themselves = Block 0A (Ch 8). rest: other industry packs, their landing pages, demo data, help texts and industry-specific modules = later (L, Block 3–5). Open questions on excluded industries and pricing by industry = later. |
| Ch 49 Industry packs | 3–5 | L.01, L.02 | rest: neutral keys and packs as data, education-only, hidden industry step — Phase 0 (Blocks 0A/0B). Open questions Ch 53.5 #1, #2 in L.01-T1. |
| Ch 50 Risks (rows for this block) | 0A | 0A.20 risk review; T1 (0A.03–0A.06, 0A.14), T2 (0A.08, 0A.20), T3 (0A.10, 0A.12, 0A.13), T4 (0A.04, 0A.17, 0A.20), T5 (0A.01, 0A.02, 0A.08), T9/I2 (0A.07), X7 (0A.12, 0A.09), R1–R8, R14–R16, R18–R20, R+ (0A.16–0A.18), R10 marking (0A.16) | R9, R11, R13, R12 delegation, R16 full review: rest: 1B. R17: rest: Block 2. M4/M12/I1/I14/O1/X4 per-pack seeds: rest: 0B. |
| Ch 50 Risks (rows for this block) | 0B | M1 0B.10; M2 0B.07/0B.09; M4 0B.08; M5 0B.16; M6 0B.13/0B.14/0B.15; M9 0B.07/0B.20; M10 0B.07; M12 0B.02; T9 0B.11; T10 0B.17/0B.18; I1–I12, I14 0B.11–0B.15; X7 0B.03; R15 0B.19 (with 0A); R19 0B.19 (structure in 0A) | M7, M11, T16 = Block 1B; I13 = later; X2–X6, X8 = later. |
| Ch 50 Risk register (rows for this block) | 1A | 1.02, 1.04, 1.09, 1.11, 1.14, 1.15 | M1 (import part) 1.14; M9 (minor data, access) 1.02 / 1.14; T4 1.04, 1.12, 1.15; T6 1.09; T7 1.11; T14 1.14; R9 partly 1.02 / 1.14, rest Block 1B; O5 / T11 deferred to Phase 3 (manual logging in 1.10). |
| Ch 50 Risk register (rows used) | 1B | M7 → 1.33; M8 → 1.16, 1.29; M11 → 1.18, 1.33; T5, T12, T13 → 1.18; T6 → 1.16; T7 → 1.16; T15 → 1.29, 1.30; T16 → 1.33; I1, I3, I5, I8 → 1.17; I6 → 1.16, 1.22, 1.27; I7 → 1.27, 1.33; I12 → 1.21, 1.22; I14 → 1.30, 1.31; O4 → 1.21, 1.27; R9, R10 → 1.25; R11 → 1.24; R12, R13, R16 → 1.26; R17 → 1.31; R19 → 1.19 | Other rows belong to other blocks. |
| Ch 50 Risks (Phase 2 rows) | 2 | O2 → 2.10; O3 → 2.06; I3, I4 → 2.10, 2.11; I5 → 2.11, 2.19; I14 → 2.14, 2.20; R10 → 2.02, 2.13; R11 → 2.03, 2.06; R17 → 2.20; M5 → 2.19; T8 → 2.10, 2.14, 2.15, 2.19; O1 → 2.02, 2.17 | — |
| Ch 50 Risk register (rows for this block) | 3–5 | 3.01 (O5, T11), 3.09, 3.10 (T12), 4.04 (O6, T16, I11, R10), 4.10 (M7), 5.08/5.09 (M13, I13), L.01 (X1–X6) | Reviewed at each phase release milestone (3.10, 4.10, 5.10). |
| Ch 51 Lessons from the previous version | 0A | 0A.01 (lessons page + incident template, 51.4 #1), 0A.02 (51.3 review checklist, lessons 7, 12), 0A.04 (lessons 1, 4), 0A.07 (lesson 12), 0A.08/0A.14 (lesson 7 min app version), 0A.20 (51.3 automated checks) | Lesson 2 (queues): rest: 0B/1B. Lessons 3, 5, 6 (Edge timeouts, AI providers, cost): rest: 0B (hub) and Phase 4. Lesson 8 (batch badges): rest: 1A. Lesson 9 (phone duplicate): rest: 1A. Lesson 10 (soft delete/timeline): rest: 1A. Lesson 11 (Play): rest: Phase 3, 0B. |
| Ch 51 Lessons (rows for this block) | 0B | Lesson 2 (queues) 0B.12; lesson 5 (no silent fallback) 0B.12/0B.13; lesson 7 (server decides from session) 0B.01/0B.19; lesson 11 (web deletion path) 0B.20; lesson 12 (no secrets in code) 0B.11; 51.1 hard-coding 0B.01 | Other lessons = Block 0A / later blocks. |
| Ch 51 Lessons (rows for this block) | 1A | 1.01, 1.02, 1.04, 1.03, 1.09, 1.11, 1.15 | Lesson 1 (RPC as real role, sweep) every milestone; 2 (queue design) 1.11; 4 (`jit = off`) 1.02, 1.10; 7 (server-side decisions, idempotent RPCs) 1.02, 1.03; 8 (batch badges) 1.04; 9 (duplicate across invisible leads) 1.03, 1.14; 10 (soft delete + append-only timeline) 1.09. |
| Ch 51 Lessons (rows used) | 1B | Lesson 1 → RPC-as-real-role tests in every milestone; lesson 2 → 1.16, 1.22, 1.27; lesson 3 → 1.16; lesson 7 → 1.18; lesson 8 → 1.35; lesson 11 → 1.23; lesson 12 → 1.17, 1.23, 1.31 | Lessons 4, 5, 6, 9, 10 belong to other blocks. |
| Ch 51 Lessons (applied here) | 2 | 2 → 2.03, 2.09, 2.11, 2.18; 4 → 2.01, 2.07; 8 → 2.01, 2.08, 2.13; 12 → 2.10, 2.14 | — |
| Ch 51 Lessons (rows for this block) | 3–5 | 3.01 (11), 3.09 (1), 4.02 (4), 4.04 (2, 3, 5, 6), 4.06 (1), 4.01 (10) | — |
| Ch 52 Roadmap (phase-0 rows for this block) | 0A | 0A.01–0A.20 | Rows for Ch 5, 6, 7, 9, 10, 14, 25, 42, 49: rest: 0B. 52.11 #1 phase-0 split is **Proposed**. |
| Ch 52 Phases (phase-0 rows for this block) | 0B | Master Admin 0B.02/0B.07/0B.08; setup 0B.09/0B.10; type profiles 0B.03/0B.04; industry packs 0B.03; modules/plans/billing 0B.05/0B.16; login (Google, OTP) 0B.17/0B.18; custom fields 0B.06; hub 0B.11–0B.15; notifications matrix 0B.15; name 0B.02 | 52.11 row 1 (**Proposed** split 0A/0B) is reflected by this block. |
| Ch 52 Roadmap (52.3 rows for Ch 14–23, 52.10 rows for Ch 20, 22, 23) | 1A | 1.01–1.15 | Lead merge row (Proposed) 1.15. Other 52.3 rows belong to Block 1B. |
| Ch 52 Roadmap (52.3 phase-1 rows for this block, 52.10 #45–#47, 52.11 #3) | 1B | 1.16–1.35 | Phase-1 rows for leads, lists, pipeline, follow-ups, calls, notes, import / export → Block 1A; lead merge (Proposed, open) → not in this block. |
| Ch 52 Roadmap (52.4 Phase 2, 52.11 #2) | 2 | all of 2.01–2.20; fees first per 52.11 #2 (2.02–2.11 before papers / tests) | — |
| Ch 52 Roadmap (52.5–52.8, 52.11 #4, #6) | 3–5 | 3.01–3.10, 4.01–4.10, 5.01–5.10, L.01–L.10 | 52.8 rows: other industry → L.01/L.02; portal → L.03; WhatsApp API → L.04/L.05; branded app connections → L.06; payments → L.07; extensions → L.09; SMS adapters → L.08. 52.11 #4 → 3.01; #6 → 4.10. |
| Ch 53 Open questions (for this block) | 1A | 1.15, 1.10, 1.13, 1.09 | 53.2 #6 lead merge 1.15; call lock / WhatsApp in phase 1 (Ch 19.12, 20.9) noted in 1.10; missed-visit N default 1.13; delete / undo windows 1.09. |
| Ch 53 Open questions (Phase 2 related) | 2 | 2.02 (plan modules), 2.10 (next gateway), 2.19 (SMS gateways, promotional SMS law) | Lead merge (Ch 53 Q6, "end of Phase 1 or Phase 2"): not in this block; owned by Phase 1 block. |
| Ch 53 Open questions (rows for this block) | 3–5 | 3.01 (53.4 #5), 4.04 (53.3 #6), L.01 (53.5 #1, #2), L.03 (53.5 #5), L.04 (53.5 #4), L.07 (53.5 #3), 5.10 (review) | — |
| Appendix A Settings keys | 0B | 0B.01 (registry, all keys with JSON schema, profile defaults, versioning/migration, area permissions, dropped keys not created, locale defaults, product-level vs institution-level, neutral renaming **Proposed**) | Each key's feature behaviour and screen is built by its owning milestone (e.g. `assignment`, `board` = Block 1A; `quiet_hours`, `notifications` screen, `public_forms` = Block 1B; `fees`, `files`, `upload_rules` = Block 2; `call_sync`, `call_lock`, `ai_*`, `photo_presets`, `alumni` = Block 3–5). Other-config rows: branding 0B.10, reset format 0B.19, login 0B.17/0B.18, plan & billing 0B.05/0B.16, external accounts 0B.11, types & packs 0B.03/0B.04, notifications matrix 0B.15, custom fields 0B.06; roles/access, branches, locale framework = Block 0A; campaigns, public pages = Block 1B; counters, board flow = Block 2. |
| Appendix A setting keys (keys used here) | 1B | `message_templates` 1.20; `notifications` 1.22; `public_forms` 1.29; `web` 1.35; `min_app_version` 1.18; `quiet_hours`, `working_days` read by 1.16 / 1.22; campaign, public page, notification and role / access configuration rows → 1.21, 1.25, 1.27, 1.29 | Key registry itself → Block 0B. |
| Appendix A (keys `admission`, `admission_approval`, `students`, `files`, `upload_rules`, `fees`, `receipt_prefix`) | 2 | 2.05, 2.08, 2.13, 2.14, 2.02, 2.06, 2.07, 2.09 | `photo_presets`: Phase 5. |
| Appendix A (keys used here) | 3–5 | `call_sync` 3.04; `call_lock`, `double_call` 3.02; `activity` 4.03; `reports` 4.02; `ai_chance` 4.05; `ai_credit` 4.07; `ai_providers` 4.04; `credits`, `credit_extras` 4.08; `scorecard` 4.09; `alumni` 5.01/5.03; `public_forms` 5.02/5.04; `photo_presets` 5.05; `min_app_version` 3.10 | Keys registered in Phase 0 (Block 0B); schemas/screens filled here. |

## 12. Open decisions found while writing this roadmap

> **Owner answers, round 6 (decided):** the proposed defaults in the table below are **accepted** (D28).
> Also decided: secret scan and the migration deploy-type check stay in CI (D27); the five-plan structure with
> **changeable prices, discounts and promotional offers** (D29); prices and limits set by the Master Admin in settings (D30);
> custom trial length (D31); prices may differ by institution type (D32); institution and platform SMS gateways can be
> switched at any time (D33, D34); SMS masking (D35); Android package **`com.leadora.leads`** (D36).
> Product name decided: **Leadora** (D37). Round 7 (0A.14 owner checkpoint): idle sign-out is **off by default** (`idle_signout_minutes` = 0; an institution turns it on, D38); with app lock on, the app locks after **30 seconds** in the background (D39). Round 8 (0A.20): a measured path may get at most **25 % and 2 ms** slower — for a small institution next to a large one and against the last `main` / nightly run (D40); the CI slow-down gate (0A.20-T5) is **built** (D41). Round 9 (0A.20 sign-off, 0B.01 checkpoint): Phase 0A approved by the owner (preview checked, PR #1 merged); setting keys use neutral names — `campus_visit` → `appointment`, `alumni` → `network`, `students` → `clients`, `admission` → `conversion` (D42). **Still open:** the actual price numbers (entered later in settings); the pilot institutions' SMS gateways (Q3) — until then 0B.13 builds Custom HTTP and the platform gateway first, and the ready-made adapters follow when gateways are known.

These came up while turning the plan into milestones. Each is also written at the milestone's owner checkpoint.

| # | Question | Milestone | Proposed default |
|---|---|---|---|
| Q1 | Final product name (affects app id, package, deep-link scheme) | S.01, 0A.01 | Keep the working name until decided |
| Q2 | Prices, limits, trial length, and which modules go in which plan (fees arrive only in Phase 2) | 0B.05, 0B.16, 2.02 | Build with placeholder values |
| Q3 | SMS gateways of the first institutions | 0B.13 | Ask the pilot institutions (S.04) |
| Q4 | Lead merge: keep, and in Phase 1 or 2? | 1.15 | End of Phase 1 |
| Q5 | **Double-call warning:** the plan lists it in Phase 1 (Ch 19) and Phase 3 (Ch 52) | 1.10, 3.02 | Phase 3, with call lock |
| Q6 | **Server call lock** earlier, in Phase 1, for large calling teams? | 3.02 | Phase 3 unless a pilot needs it |
| Q7 | **Outgoing webhooks:** Phase 1 (Ch 42, 52) or Phase 2 (Ch 43)? | 1.31 | Phase 1 |
| Q8 | **Change log and core reports:** Phase 1 (Ch 38 proposal) or Phase 4 (Ch 52)? | 4.01, 4.02 | Basic change log view in Phase 1, the rest in Phase 4 |
| Q9 | Manual WhatsApp (open, template, log) in Phase 1 instead of Phase 3 | 1.10 | Phase 1 (no native code needed) |
| Q10 | The website opens on Students (Ch 45) but Students arrive in Phase 2 | 1.35 | Open on Leads until Phase 2 |
| Q11 | Application number format | 1.29, 5.04 | Own number series per institution |
| Q12 | Neutral renaming of education-worded setting keys (`campus_visit`, `alumni`, `students`, `admission`) | 0A.12, 0B.01 | Rename to neutral keys now (cheap in Phase 0) |
| Q13 | Feature requests list in the Master Admin panel (Ch 5) has no phase | 0B.02 | Phase 5, next to the developer inbox |
| Q14 | Salted (HMAC) phone hashes for call-log sync instead of plain SHA-256 | 3.04 | Yes (safer) |
| Q15 | Who owns the AI key by default (institution or platform), and the AI add-on price | 4.04 | Institution's own key; platform key as a paid add-on |
| Q16 | Branded-app price | 5.09 | Owner to decide |
| Q17 | Permission key names that the plan does not name (e.g. `lead.merge`, `calls.lock.override`, `ai.chance.view`) | several | Register them as written; review once in 0A.16 |
| Q18 | The plan's other **Proposed** items (seat hold, cash close, payment link, "to verify" step for manual payments …) | Phase 2 milestones | Build behind switches after approval |

## 13. Glossary

| Term | Meaning |
|---|---|
| Institution (tenant) | A customer organisation using the app (school, college, coaching centre …). Its data is fully separate. |
| Master Admin | The platform owner side: approves institutions, sets up integrations, billing and support. |
| Super Admin | The highest role inside one institution. |
| Type profile / industry pack | Data that seeds labels, stages, fees, papers, roles and settings for an institution type or industry. |
| Neutral key / label | The fixed internal name (`client`) vs the word shown on screen ("Student", "Trainee"). |
| RLS | Row Level Security: database rules that decide who can read or change each row. |
| RPC | A server function the app calls. |
| `can()` | The single permission check used by all RPCs. |
| `user_access` | A precomputed table of what each user may see, used by RLS for speed. |
| Integration hub | One structure for all outside services: adapters, connections, secrets, outbox, callbacks, usage ledger. |
| Outbox | A queue of messages or calls waiting to be sent, with retries and back-off. |
| Leak test | An automated test proving one institution can never see another's data. |
| Role matrix test | An automated test of every role template against every permission and scope. |
| OTA update | An app update delivered without the Play Store. |
| Gate | A check that must pass before the next step starts. |
