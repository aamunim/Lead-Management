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
- [ ] Screens pass the UX checklist (roadmap Section 9.4): light/dark, bn/en, keyboard, large font, low-end phone.
- [ ] Performance checked for lists and pages touched ("never slower").
- [ ] `npm run check` passes locally.
