-- 0A.03 Tenancy core: institutions, memberships and the active-institution session.
-- Plan: Ch 4 (4.2, 4.5, 4.6), Ch 11 (11.7, 11.13, 11.15), Ch 2.3 (principles 5, 6), Ch 3.6. Decisions: D9, D10, D25.
--
-- Rules applied here (docs/dev/ARCHITECTURE_RULES.md):
--   * The active institution comes only from the session (JWT claim set by the access-token hook), never from the client.
--   * One person may belong to several institutions (D25); every check uses only the ACTIVE one.
--   * Platform roles (Master Admin side) are kept completely separate from institution membership.
--   * SECURITY INVOKER by default. The two DEFINER functions here are listed in app.definer_registry with the reason.

-- ---------------------------------------------------------------------------------------------------------------------
-- Internal schema for helpers (not exposed through the API).
-- ---------------------------------------------------------------------------------------------------------------------
create schema if not exists app;
revoke all on schema app from public;
grant usage on schema app to authenticated, anon, service_role, supabase_auth_admin;

-- Every SECURITY DEFINER function must be registered here with its reason (checked by the DEFINER audit in 0A.04).
create table app.definer_registry (
  function_name text primary key,
  reason        text not null,
  added_in      text not null
);
revoke all on app.definer_registry from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------------------------------------------------

-- The tenant itself. `status` is reserved for the lifecycle built in 0B.07.
create table public.institutions (
  id          uuid primary key default gen_random_uuid(),
  slug        text not null unique check (slug ~ '^[a-z0-9]([a-z0-9-]{1,48}[a-z0-9])?$'),
  name        text not null check (length(btrim(name)) between 2 and 200),
  short_name  text check (short_name is null or length(btrim(short_name)) between 1 and 40),
  status      text not null default 'pending'
              check (status in ('pending', 'trial', 'active', 'read_only', 'suspended', 'closed')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
comment on table public.institutions is 'Tenants (any customer organisation). Lifecycle statuses are managed in 0B.07.';

-- One row per auth user. user_kind: staff today; portal (D10, not enabled) and api reserved for later.
create table public.profiles (
  user_id                    uuid primary key references auth.users (id) on delete cascade,
  display_name               text check (display_name is null or length(btrim(display_name)) between 1 and 120),
  phone                      text,
  email                      text,
  user_kind                  text not null default 'staff' check (user_kind in ('staff', 'portal', 'api')),
  preferred_language         text check (preferred_language is null or preferred_language in ('bn', 'en')),
  last_active_institution_id uuid references public.institutions (id) on delete set null,
  created_at                 timestamptz not null default now(),
  updated_at                 timestamptz not null default now()
);
comment on column public.profiles.last_active_institution_id is
  'Server-side record of the institution the user last selected; read only by the access-token hook.';

-- Membership of a person in an institution (D25: a person may have several).
-- access_version is bumped whenever this membership's access changes (deactivation now, roles in 0A.17);
-- a token carrying an older version is refused (R15, Ch 4.13 #4).
create table public.institution_members (
  institution_id  uuid not null references public.institutions (id) on delete cascade,
  user_id         uuid not null references auth.users (id) on delete cascade,
  status          text not null default 'pending' check (status in ('pending', 'active', 'deactivated')),
  access_version  integer not null default 1 check (access_version >= 1),
  joined_at       timestamptz,
  deactivated_at  timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  primary key (institution_id, user_id)
);
-- Documented exception to "indexes start with institution_id": membership is looked up by user in the
-- access-token hook and in the institution switcher, before any institution is active.
create index institution_members_user_idx on public.institution_members (user_id, status);

-- Platform-level roles (Master Admin side). Never mixed with institution roles (Ch 11.15).
create table public.platform_members (
  user_id        uuid primary key references auth.users (id) on delete cascade,
  platform_role  text not null check (platform_role in ('master_admin', 'support', 'billing', 'developer')),
  created_at     timestamptz not null default now()
);

-- updated_at maintenance
create or replace function app.touch_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;

create trigger institutions_touch before update on public.institutions
  for each row execute function app.touch_updated_at();
create trigger profiles_touch before update on public.profiles
  for each row execute function app.touch_updated_at();
create trigger institution_members_touch before update on public.institution_members
  for each row execute function app.touch_updated_at();

-- ---------------------------------------------------------------------------------------------------------------------
-- Session helpers used by every RLS policy. Wrap them in (select ...) inside policies so Postgres evaluates them
-- once per query (init-plan caching, Ch 47.9):   using (institution_id = (select app.auth_institution_id()))
-- ---------------------------------------------------------------------------------------------------------------------

create or replace function app.auth_user_id() returns uuid
language sql stable set search_path = '' as $$
  select auth.uid()
$$;

-- Raw claim values (no validation). Do not use these in policies; use app.auth_institution_id().
create or replace function app.claim_institution_id() returns uuid
language sql stable set search_path = '' as $$
  select nullif(auth.jwt() ->> 'active_institution_id', '')::uuid
$$;

create or replace function app.claim_access_version() returns integer
language sql stable set search_path = '' as $$
  select nullif(auth.jwt() ->> 'access_version', '')::integer
$$;

-- The active institution of this request, or NULL when the session is not valid for it:
-- the membership must still be active and the token's access_version must equal the current one.
-- Returning NULL makes every tenant RLS policy return no rows, so a deactivated member loses access
-- on the very next request, even with an unexpired token.
create or replace function app.auth_institution_id() returns uuid
language sql stable set search_path = '' as $$
  select m.institution_id
  from public.institution_members m
  where m.institution_id = app.claim_institution_id()
    and m.user_id = auth.uid()
    and m.status = 'active'
    and m.access_version = app.claim_access_version()
$$;

-- For RPCs: raise a typed error the app can recognise ("refresh your session") instead of silently returning nothing.
create or replace function app.require_active_session() returns uuid
language plpgsql stable set search_path = '' as $$
declare
  v_institution uuid := app.claim_institution_id();
  v_member      public.institution_members;
begin
  if auth.uid() is null then
    raise exception 'not_signed_in' using errcode = 'P0401', hint = 'Sign in first.';
  end if;
  if v_institution is null then
    raise exception 'no_active_institution' using errcode = 'P0402', hint = 'Choose an institution.';
  end if;
  select * into v_member from public.institution_members
   where institution_id = v_institution and user_id = auth.uid();
  if not found or v_member.status <> 'active' then
    raise exception 'membership_not_active' using errcode = 'P0403', hint = 'Your access to this institution has ended.';
  end if;
  if v_member.access_version is distinct from app.claim_access_version() then
    raise exception 'session_refresh_required' using errcode = 'P0409', hint = 'Refresh the session and retry.';
  end if;
  return v_institution;
end $$;

-- Reusable BEFORE INSERT trigger for tenant tables: the row's institution_id always comes from the session.
-- A different institution_id sent by the client is rejected (never trusted, principle 6).
create or replace function app.set_institution_id() returns trigger
language plpgsql set search_path = '' as $$
declare
  v_institution uuid := app.auth_institution_id();
begin
  if auth.uid() is null then
    -- service_role / migrations / jobs: must state the institution explicitly.
    if new.institution_id is null then
      raise exception 'institution_id_required' using errcode = 'P0402';
    end if;
    return new;
  end if;
  if v_institution is null then
    raise exception 'no_active_institution' using errcode = 'P0402';
  end if;
  if new.institution_id is not null and new.institution_id <> v_institution then
    raise exception 'institution_mismatch' using errcode = 'P0403',
      hint = 'institution_id is taken from the session; the client may not set another one.';
  end if;
  new.institution_id := v_institution;
  return new;
end $$;

grant execute on function app.auth_user_id(), app.claim_institution_id(), app.claim_access_version(),
  app.auth_institution_id(), app.require_active_session() to authenticated, anon, service_role;

-- ---------------------------------------------------------------------------------------------------------------------
-- Access changes: deactivation bumps access_version (immediate loss of access) and clears the last selection.
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function app.on_membership_change() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.status is distinct from old.status then
    new.access_version := old.access_version + 1;
    if new.status = 'active' and new.joined_at is null then
      new.joined_at := now();
    end if;
    if new.status = 'deactivated' then
      new.deactivated_at := now();
    end if;
  end if;
  return new;
end $$;

create trigger institution_members_access before update on public.institution_members
  for each row execute function app.on_membership_change();

create or replace function app.on_membership_insert() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.status = 'active' and new.joined_at is null then
    new.joined_at := now();
  end if;
  return new;
end $$;

create trigger institution_members_insert before insert on public.institution_members
  for each row execute function app.on_membership_insert();

-- ---------------------------------------------------------------------------------------------------------------------
-- Profile row for every new auth user (DEFINER: runs inside auth's insert, must write public.profiles).
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function app.handle_new_auth_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (user_id, email, phone)
  values (new.id, new.email, new.phone)
  on conflict (user_id) do nothing;
  return new;
end $$;
revoke all on function app.handle_new_auth_user() from public, anon, authenticated;
insert into app.definer_registry values
  ('app.handle_new_auth_user', 'Trigger on auth.users; creates the profile row. Touches only the new user''s own row.', '0A.03');

create trigger on_auth_user_created after insert on auth.users
  for each row execute function app.handle_new_auth_user();

-- ---------------------------------------------------------------------------------------------------------------------
-- Supabase Auth custom access-token hook: adds active_institution_id, user_kind and access_version claims.
-- Never accepts an institution from the client: it uses the server-side last selection, or the only membership.
-- Enable in Dashboard → Authentication → Hooks (production) and in supabase/config.toml (local).
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function public.custom_access_token_hook(event jsonb) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_user        uuid := (event ->> 'user_id')::uuid;
  v_claims      jsonb := coalesce(event -> 'claims', '{}'::jsonb);
  v_profile     public.profiles;
  v_institution uuid;
  v_version     integer;
  v_active_cnt  integer;
begin
  select * into v_profile from public.profiles where user_id = v_user;

  -- 1. The last selection, if that membership is still active.
  if v_profile.last_active_institution_id is not null then
    select m.institution_id, m.access_version into v_institution, v_version
    from public.institution_members m
    where m.user_id = v_user and m.institution_id = v_profile.last_active_institution_id and m.status = 'active';
  end if;

  -- 2. Otherwise the only active membership, if exactly one.
  if v_institution is null then
    select count(*) into v_active_cnt from public.institution_members m where m.user_id = v_user and m.status = 'active';
    if v_active_cnt = 1 then
      select m.institution_id, m.access_version into v_institution, v_version
      from public.institution_members m where m.user_id = v_user and m.status = 'active';
    end if;
  end if;

  -- 3. Several and none chosen (or none at all): no active institution; the app shows the chooser (1.19).
  v_claims := v_claims
    || jsonb_build_object('user_kind', coalesce(v_profile.user_kind, 'staff'))
    || jsonb_build_object('active_institution_id', v_institution)
    || jsonb_build_object('access_version', v_version);

  return jsonb_set(event, '{claims}', v_claims);
end $$;

grant execute on function public.custom_access_token_hook(jsonb) to supabase_auth_admin;
revoke execute on function public.custom_access_token_hook(jsonb) from public, anon, authenticated;
grant usage on schema public to supabase_auth_admin;
grant select on public.profiles, public.institution_members to supabase_auth_admin;

-- ---------------------------------------------------------------------------------------------------------------------
-- RPC: choose the active institution. INVOKER: the membership check runs under the caller's own RLS.
-- After calling it, the app must refresh the session (supabase.auth.refreshSession()) to get the new claims,
-- and clear every client cache (caches are keyed by user and institution).
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function public.set_active_institution(p_institution_id uuid) returns uuid
language plpgsql security invoker set search_path = '' as $$
begin
  if auth.uid() is null then
    raise exception 'not_signed_in' using errcode = 'P0401';
  end if;
  if not exists (
    select 1 from public.institution_members m
    where m.institution_id = p_institution_id and m.user_id = auth.uid() and m.status = 'active'
  ) then
    raise exception 'not_a_member' using errcode = 'P0403', hint = 'You are not an active member of that institution.';
  end if;
  update public.profiles set last_active_institution_id = p_institution_id where user_id = auth.uid();
  return p_institution_id;
end $$;

revoke execute on function public.set_active_institution(uuid) from public, anon;
grant execute on function public.set_active_institution(uuid) to authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------------------------------------------------
alter table public.institutions        enable row level security;
alter table public.profiles            enable row level security;
alter table public.institution_members enable row level security;
alter table public.platform_members    enable row level security;

revoke all on public.institutions, public.profiles, public.institution_members, public.platform_members from anon;
revoke all on public.institutions, public.profiles, public.institution_members, public.platform_members from authenticated;
grant select on public.institutions, public.institution_members, public.platform_members to authenticated;
grant select on public.profiles to authenticated;
-- Users may change only these columns of their own profile (user_kind and last selection are server-managed;
-- last_active_institution_id changes only through set_active_institution, which runs as the caller).
grant update (display_name, phone, preferred_language, last_active_institution_id) on public.profiles to authenticated;

-- institutions: readable by its active members (the switcher lists all of a person's institutions).
create policy institutions_select_members on public.institutions
  for select to authenticated
  using (exists (
    select 1 from public.institution_members m
    where m.institution_id = institutions.id and m.user_id = (select auth.uid()) and m.status = 'active'
  ));

-- profiles: own row only (colleagues' profiles become visible through the active institution in 0A.18).
create policy profiles_select_own on public.profiles
  for select to authenticated using (user_id = (select auth.uid()));
create policy profiles_update_own on public.profiles
  for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy profiles_select_auth_admin on public.profiles
  for select to supabase_auth_admin using (true);

-- institution_members: own memberships only (admins' member lists come in 0A.18).
create policy members_select_own on public.institution_members
  for select to authenticated using (user_id = (select auth.uid()));
create policy members_select_auth_admin on public.institution_members
  for select to supabase_auth_admin using (true);

-- platform_members: a person sees only their own platform role.
create policy platform_members_select_own on public.platform_members
  for select to authenticated using (user_id = (select auth.uid()));
