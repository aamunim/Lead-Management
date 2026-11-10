## Milestone and tasks
<!-- e.g. 0A.03-T1, 0A.03-T2 (docs/DEVELOPMENT_ROADMAP.md) -->

## What changed and why

## Deploy type (tick all that apply)
- [ ] Database (migrations)
- [ ] Edge Functions: <!-- names -->
- [ ] OTA app update
- [ ] New store build (native code or runtimeVersion changed)
- [ ] Web
- [ ] Docs only

## What's new (shown to users)
- **English:**
- **বাংলা:**

## Checklist (docs/DEVELOPMENT_ROADMAP.md Section 9.1; docs/dev/ARCHITECTURE_RULES.md)
- [ ] Ground rules G1–G20 respected; nothing hard-coded (words, institution data, secrets).
- [ ] New tables: `institution_id` (+ `branch_id` if relevant), RLS, indexes start with `institution_id`, added to the leak test; `npm run lint:schema` passes (exceptions only in `supabase/lint/allowlist.sql` with a reason).
- [ ] New SECURITY DEFINER function? Registered in `app.definer_registry` with reason, reviewer and tenant check.
- [ ] Server decides institution / permissions from the session, never from the client.
- [ ] Isolation beyond tables (docs/dev/ISOLATION.md): storage paths `<institution_id>/…`, Realtime `inst:<institution_id>:…`, Edge Functions use `withTenant`, logs tagged and redacted, errors use the error contract.
- [ ] Cross-tenant leak test green (`npm run test:leak`); a new table the generic fixtures cannot fill has a fixture in `supabase/tests/leak/fixtures/`; any new leak allow-list row has a reason.
- [ ] RPC signature changed? If yes: a new RPC instead, or an optional parameter with a default (lesson 7).
- [ ] New queue or job has attempts, back-off, "given up" and idempotency keys (lesson 2).
- [ ] New list badge / chip is batched into the screen's RPC, not one request per row (lesson 8).
- [ ] New permissions, labels, settings and translations (en + bn) registered; `npm run check:i18n` passes; new terms follow `docs/dev/GLOSSARY.md`.
- [ ] Bangla texts changed? Read by the owner or a native reader before release (docs/dev/ENVIRONMENTS_AND_RELEASES.md rule 8).
- [ ] Errors are shown in the UI with Retry; no silent blanks.
- [ ] Screens pass the per-screen checklist below (Ch 47; automated parts: `npm run check:i18n`, `npm run test:ui`).
- [ ] Performance checked for lists and pages touched ("never slower").
- [ ] `npm run check` passes locally.

## Per-screen release checklist (Ch 47, docs/dev/DESIGN_SYSTEM.md) — tick for every new or changed screen
- [ ] **Theme:** built from `@/ui` components and `useTheme()` tokens only; checked in light and dark; brand colour readable (no raw colours / font sizes — lint).
- [ ] **Keyboard:** focused field and Save stay above the keyboard (FormScreen / BottomSheet); Next / Done; right keyboard per field; tap outside or scroll closes it.
- [ ] **Bangla text:** every word from translations / labels; no clipped vowel signs; long words and the weird-labels institution checked (gallery harness).
- [ ] **Forms:** errors under the field; Back asks before discarding; draft survives a call / app kill; Save cannot run twice (idempotency key sent to the RPC).
- [ ] **States:** skeleton while loading; empty state with an action; error with Retry (never silent); pull-to-refresh on lists; Undo after delete; progress + Cancel for long tasks.
- [ ] **Navigation:** Android Back closes sheets and dialogs first; the list keeps its place when coming back.
- [ ] **Network and phone:** works on slow 3G and a 2–3 GB RAM phone; "now" from the server clock; long lists virtualised.
- [ ] **Accessibility:** 48 dp targets; screen-reader labels on icon buttons (lint); no colour-only meaning; large system font does not cut or overlap text.
- [ ] **Money:** lakh grouping through `useFormat()`; amounts and phones stored with ASCII digits.
- [ ] **Phone security:** no secrets or personal data in logs; cached data cleared on sign-out.
