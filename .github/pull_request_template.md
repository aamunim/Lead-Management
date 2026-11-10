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
- [ ] New tables: `institution_id` (+ `branch_id` if relevant), RLS, indexes start with `institution_id`, added to the leak test.
- [ ] Server decides institution / permissions from the session, never from the client.
- [ ] RPC signature changed? If yes: a new RPC instead, or an optional parameter with a default (lesson 7).
- [ ] New queue or job has attempts, back-off, "given up" and idempotency keys (lesson 2).
- [ ] New list badge / chip is batched into the screen's RPC, not one request per row (lesson 8).
- [ ] New permissions, labels, settings and translations (en + bn) registered.
- [ ] Errors are shown in the UI with Retry; no silent blanks.
- [ ] Screens pass the UX checklist (roadmap Section 9.4): light/dark, bn/en, keyboard, large font, low-end phone.
- [ ] Performance checked for lists and pages touched ("never slower").
- [ ] `npm run check` passes locally.
