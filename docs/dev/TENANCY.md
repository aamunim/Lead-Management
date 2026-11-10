# Tenancy: institutions, memberships and the active institution (0A.03)

## The rule

**Every request runs for exactly one active institution, and that institution comes from the server — never from
the client.** A person may belong to several institutions (D25); every check uses only the active one.

## How it works

| Part | What it does |
|---|---|
| `institutions` | The tenants. `status` (pending / trial / active / read_only / suspended / closed) is managed in 0B.07. |
| `profiles` | One row per auth user: display name, phone, email, `user_kind` (staff / portal / api; portal not enabled, D10), preferred language, and the server-side `last_active_institution_id`. |
| `institution_members` | Membership per (institution, user): `status` pending / active / deactivated, `access_version`. |
| `platform_members` | Master Admin side roles (master_admin / support / billing / developer). **Never mixed with institution membership**; a platform role gives no institution data by itself. |
| `custom_access_token_hook` | Supabase Auth hook. Adds `active_institution_id`, `access_version` and `user_kind` to every token: the last selection if still an active membership, otherwise the only active membership, otherwise none (the app shows the chooser, 1.19). |
| `set_active_institution(id)` | RPC (INVOKER). Checks the caller is an active member, records the choice. The app then calls `refreshSession()` and clears every cache (`src/lib/session.ts → switchInstitution`). |
| `app.auth_institution_id()` | The active institution of this request — **only** if the membership is still active and the token's `access_version` is current; otherwise NULL, so RLS returns nothing. |
| `app.require_active_session()` | For RPCs: raises a typed error instead of silently returning nothing (see error codes). |
| `app.set_institution_id()` | BEFORE INSERT trigger for tenant tables: fills `institution_id` from the session; rejects a different value sent by the client; background jobs (no user) must state it. |

## Policy template for every tenant table

```sql
alter table public.<table> enable row level security;
create trigger <table>_institution before insert on public.<table>
  for each row execute function app.set_institution_id();
create policy <table>_tenant on public.<table> to authenticated
  using (institution_id = (select app.auth_institution_id()))
  with check (institution_id = (select app.auth_institution_id()));
create index <table>_institution_idx on public.<table> (institution_id, ...);
```

Always wrap the helper in `(select ...)` so Postgres evaluates it once per query (init-plan caching, Ch 47.9).
Permission checks (`can()`) are added on top in 0A.17.

## Access changes take effect on the next request

- Deactivating a membership (or any later access change, 0A.17) bumps `access_version`.
- A token with the old version no longer resolves an institution: RLS returns nothing and RPCs raise
  `session_refresh_required`. The app then refreshes the session (`refreshAfterAccessChange`).
- A deactivated member's new tokens carry no institution.
- "Sign out of all other devices" uses Supabase's `signOut({ scope: 'others' })` (`signOutOtherDevices`).

## Error codes raised by the database

| Message | SQLSTATE | Meaning | App reaction |
|---|---|---|---|
| `not_signed_in` | P0401 | No user in the session | Go to sign-in |
| `no_active_institution` | P0402 | Several memberships and none chosen, or none | Show the institution chooser |
| `institution_id_required` | P0402 | A background job inserted without an institution | Bug in the job |
| `membership_not_active` | P0403 | Membership ended | Sign out of that institution / chooser |
| `not_a_member` | P0403 | Tried to activate an institution the user does not belong to | Show error |
| `institution_mismatch` | P0403 | Client sent another institution's id | Bug / tampering |
| `session_refresh_required` | P0409 | Access changed since the token was issued | Refresh the session and retry |

## A person in several institutions (D25)

- They sign in once. With one active membership the app opens it; with several (and no last choice) the token has no
  institution and the app shows the chooser.
- Switching creates a new session for the chosen institution and **clears all client caches**; caches are keyed by
  user + institution.
- Nothing from one institution is ever visible while another is active.

## SECURITY DEFINER exceptions

Every DEFINER function must be registered in `app.definer_registry` with a reason (a test fails otherwise):

| Function | Why |
|---|---|
| `app.handle_new_auth_user` | Trigger on `auth.users`; creates the user's own profile row. |

## Enabling the hook

- Local: `supabase/config.toml` → `[auth.hook.custom_access_token]` (already enabled).
- Staging / production: Supabase Dashboard → Authentication → Hooks → Custom Access Token →
  `public.custom_access_token_hook`. **Do this before the first real sign-in**, or tokens will have no institution.

## Tests

- `npm run test:db` — SQL tests as the real `authenticated` role with claims made by the real hook (`supabase/tests/`).
- `npm run test:e2e` — real email / password sign-in through Supabase Auth and the REST API (`scripts/e2e/`).
- Local setup: `npx supabase start` then `npx supabase db reset` (applies migrations and `supabase/seeds/`).
- Seed users (local only, password `password123`): `a.member@example.test` (A), `b.member@example.test` (B),
  `both.member@example.test` (A and B), `gone.member@example.test` (deactivated in A), `platform.admin@example.test`.
