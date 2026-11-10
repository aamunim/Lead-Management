# Developer guide

Read in this order before working on any milestone:

1. `ARCHITECTURE_RULES.md` — the non-negotiable design rules (principles, never hard-coded, database and app patterns, backward compatibility, speed, secrets).
2. `SCOPE.md` — what is in and out of the first release, and legacy items that must not come back.
3. `LESSONS.md` — the 12 lessons from the earlier app and where each is enforced; incident template.
4. `STACK_AND_SCALING.md` — the stack, libraries added later, Supabase limits and the large-institution path.
5. `ENVIRONMENTS_AND_RELEASES.md` — environments, secrets, workflows, release rules and the leaked-secret runbook.
6. `TENANCY.md` — institutions, memberships, the active institution, the RLS policy template and error codes.
7. `SCHEMA_LINT.md` — the schema lint rules, exceptions, DEFINER registry, guard trigger and the real-role test harness.
8. `LEAK_TEST.md` — the cross-tenant leak test: fixtures, viewers, probes, allow-list, self-test.
9. `ISOLATION.md` — every place institution data must stay separate, its status, and the storage / Realtime / Edge Function / log / error conventions.
10. `SECRETS.md` — per-institution keys in Vault: write-only, hint only, Edge-only read, rotation, log redaction.
11. `SETTINGS.md` — settings as data, layers, validation, versions on every response, min app version, counters.
12. `EVENTS.md` — the domain event log (catalogue, payload schemas, listeners, dispatcher) and the append-only audit log.
13. `EXTENSIONS.md` — the five layers, the triage rule, and the rules, runner and checklist for extensions.
14. `I18N.md` — English + Bangla: translation files, typed keys, language resolution, font, the UI string lint.
15. `GLOSSARY.md` — English ↔ Bangla terms and style; the release language review.
16. `LOCALE.md` — locale settings, lakh money, dates in the institution's time zone, ASCII digits, server clock.
17. `LABELS.md` — neutral keys (reference table) and the label dictionary: layers, Bangla forms, usage, rules.
18. `DESIGN_SYSTEM.md` — tokens (light / dark / brand, Bangla-safe typography), theme, components, form behaviours and the automatic checks.
19. `SHELL.md` — routes and guards, cache namespaces and wiping, the API wrapper, navigation rules, app lock and idle sign-out.
20. `TEST_DEVICES.md` — the three test phones and the manual pre-release pass.
21. `../DEVELOPMENT_ROADMAP.md` — the milestone you are working on (Depends on, Tasks, Done when, Watch-outs).
22. `../PLAN_BN.md` — background only. **`../DEVELOPMENT_ROADMAP.md` is the final guideline**; owner decisions are recorded there (section 12), not in the plan.
23. `PROGRESS.md` — which milestones are done.
