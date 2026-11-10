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
10. `../DEVELOPMENT_ROADMAP.md` — the milestone you are working on (Depends on, Tasks, Done when, Watch-outs).
11. `../PLAN_BN.md` — the plan chapters the milestone points to.
12. `PROGRESS.md` — which milestones are done.
