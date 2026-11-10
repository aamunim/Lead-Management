# Progress

Status of roadmap milestones (`docs/DEVELOPMENT_ROADMAP.md`). Update this file in the same PR that finishes a milestone.

| Milestone | Status | Notes |
|---|---|---|
| Stage S | Open | Owner decisions (S.01) and accounts (S.02) still pending; working name used meanwhile. |
| 0A.01 Repository skeleton, architecture rules and developer guide | **Done (waiting for owner checkpoint)** | Expo SDK 58 / RN 0.88 app (Android + web), Supabase folder, `config/` with schema check, developer guide. Android run not tested in this environment (no emulator); web export and typecheck pass. |
| 0A.02 Environments, CI, secrets, release workflow | **Built; waiting for accounts** | EAS profiles, `app.config.ts` (Firebase file from secret, brand overrides), workflows `ci`, `app-update`, `build-android`, `deploy-web`, PR template, environments and release guide, unit tests. Not yet run on GitHub: needs the owner's Supabase projects, Expo token, Firebase file and hosting secrets (S.02), and branch protection with required checks. Secret scan and deploy-type check approved (D27). Android package changed to `com.leadora.leads` (D36). |
| 0A.03 Tenancy core | **Done (waiting for owner checkpoint)** | Tables `institutions`, `profiles`, `institution_members`, `platform_members`; access-token hook; `set_active_institution`; session helpers and the tenant policy template; access_version and immediate loss of access on deactivation; dev sign-in screen; seed with two institutions and a dual member. 42 SQL tests and 5 end-to-end tests (real Supabase Auth) pass locally; added to CI. See `docs/dev/TENANCY.md`. |
| 0A.04 Schema guardrails | Next | |
