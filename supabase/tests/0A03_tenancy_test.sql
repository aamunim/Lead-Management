-- 0A.03 tests: tenancy core. Run with `npm run test:db` (needs the local database with the 0A.03 seed).
-- Every check runs as the real `authenticated` role with claims produced by the real access-token hook (lesson 1).
\set ON_ERROR_STOP on
begin;

-- ---------------------------------------------------------------------------------------------------------------------
-- Test helpers (temporary, removed at rollback)
-- ---------------------------------------------------------------------------------------------------------------------
create function pg_temp.check(cond boolean, what text) returns void language plpgsql as $$
begin
  if cond is distinct from true then raise exception 'FAILED: %', what; end if;
  raise notice 'ok - %', what;
end $$;

-- Claims exactly as Supabase Auth would issue them after running our hook.
create function pg_temp.claims_for(p_user uuid) returns jsonb language sql as $$
  select (public.custom_access_token_hook(jsonb_build_object(
            'user_id', p_user,
            'claims', jsonb_build_object('sub', p_user, 'role', 'authenticated', 'aud', 'authenticated')))) -> 'claims'
$$;

-- Switch this transaction to `authenticated` with the given claims.
create function pg_temp.act_as(p_claims jsonb) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', p_claims::text, true);
  perform set_config('role', 'authenticated', true);
end $$;

-- Run SQL and return the error message ('' when it succeeded).
create function pg_temp.error_of(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return '';
exception when others then
  return sqlerrm;
end $$;

grant execute on all functions in schema pg_temp to authenticated;

-- Fixed ids from supabase/seeds/0A03_tenancy.sql
\set inst_a '''a0000000-0000-4000-8000-00000000000a'''
\set inst_b '''b0000000-0000-4000-8000-00000000000b'''
\set user_a '''11111111-1111-4111-8111-111111111111'''
\set user_b '''22222222-2222-4222-8222-222222222222'''
\set user_both '''33333333-3333-4333-8333-333333333333'''
\set user_gone '''44444444-4444-4444-8444-444444444444'''
\set user_platform '''55555555-5555-4555-8555-555555555555'''

-- Start from a known state (earlier e2e runs or manual use may have stored a last selection).
update public.profiles set last_active_institution_id = null where user_id in (:user_a, :user_b, :user_both);

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Access-token hook
-- ---------------------------------------------------------------------------------------------------------------------
select pg_temp.check((pg_temp.claims_for(:user_a) ->> 'active_institution_id')::uuid = :inst_a,
                     'hook: single-membership user gets that institution');
select pg_temp.check((pg_temp.claims_for(:user_a) ->> 'access_version')::int >= 1, 'hook: access_version claim present');
select pg_temp.check(pg_temp.claims_for(:user_a) ->> 'user_kind' = 'staff', 'hook: user_kind claim is staff');
select pg_temp.check(pg_temp.claims_for(:user_both) -> 'active_institution_id' = 'null'::jsonb,
                     'hook: user in two institutions with no selection gets no active institution (D25)');
select pg_temp.check(pg_temp.claims_for(:user_gone) -> 'active_institution_id' = 'null'::jsonb,
                     'hook: deactivated member gets no active institution');
select pg_temp.check(pg_temp.claims_for(:user_platform) -> 'active_institution_id' = 'null'::jsonb,
                     'hook: platform member has no institution (platform and institution roles are separate)');
select pg_temp.check(pg_temp.claims_for(:user_a) ->> 'sub' = :user_a, 'hook: keeps the standard claims');

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. RLS: a member sees only their own institution and memberships
-- ---------------------------------------------------------------------------------------------------------------------
select pg_temp.act_as(pg_temp.claims_for(:user_a));
select pg_temp.check((select count(*) from public.institutions) = 1, 'RLS: user A sees exactly one institution');
select pg_temp.check((select id from public.institutions) = :inst_a, 'RLS: ...and it is institution A');
select pg_temp.check((select count(*) from public.institution_members) = 1, 'RLS: user A sees only own membership');
select pg_temp.check((select count(*) from public.profiles) = 1, 'RLS: user A sees only own profile');
select pg_temp.check((select count(*) from public.platform_members) = 0, 'RLS: user A sees no platform roles');
select pg_temp.check(app.auth_institution_id() = :inst_a, 'session: active institution resolves to A');
select pg_temp.check(app.require_active_session() = :inst_a, 'session: require_active_session passes for A');
reset role;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. set_active_institution
-- ---------------------------------------------------------------------------------------------------------------------
select pg_temp.act_as(pg_temp.claims_for(:user_a));
select pg_temp.check(pg_temp.error_of(format('select public.set_active_institution(%L)', :inst_b)) = 'not_a_member',
                     'switch: user A cannot activate institution B');
reset role;

select pg_temp.act_as(pg_temp.claims_for(:user_both));
select pg_temp.check(app.auth_institution_id() is null, 'switch: dual member starts with no active institution');
select pg_temp.check(pg_temp.error_of('select app.require_active_session()') = 'no_active_institution',
                     'switch: RPCs refuse until an institution is chosen');
select pg_temp.check((select count(*) from public.institutions) = 2, 'switch: dual member can list both institutions');
select pg_temp.check(public.set_active_institution(:inst_b) = :inst_b, 'switch: dual member activates B');
reset role;
-- New token after the switch (the app calls refreshSession()):
select pg_temp.check((pg_temp.claims_for(:user_both) ->> 'active_institution_id')::uuid = :inst_b,
                     'switch: refreshed token carries institution B');
select pg_temp.act_as(pg_temp.claims_for(:user_both));
select pg_temp.check(app.auth_institution_id() = :inst_b, 'switch: every check now uses B only');
select public.set_active_institution(:inst_a);
reset role;
select pg_temp.check((pg_temp.claims_for(:user_both) ->> 'active_institution_id')::uuid = :inst_a,
                     'switch: and back to A');

-- A user cannot trick the hook by writing another institution into their own profile directly.
select pg_temp.act_as(pg_temp.claims_for(:user_a));
update public.profiles set last_active_institution_id = :inst_b where user_id = :user_a;
reset role;
select pg_temp.check((pg_temp.claims_for(:user_a) ->> 'active_institution_id')::uuid = :inst_a,
                     'hook: ignores a last selection that is not an active membership');

-- ---------------------------------------------------------------------------------------------------------------------
-- 4. A forged institution_id from the client is rejected; a missing one is filled from the session
-- ---------------------------------------------------------------------------------------------------------------------
create temp table probe (id serial primary key, institution_id uuid not null, note text);
create trigger probe_institution before insert on probe for each row execute function app.set_institution_id();
alter table probe enable row level security;
create policy probe_rw on probe to authenticated
  using (institution_id = (select app.auth_institution_id()))
  with check (institution_id = (select app.auth_institution_id()));
grant select, insert on probe to authenticated;
grant usage on sequence probe_id_seq to authenticated;

select pg_temp.act_as(pg_temp.claims_for(:user_a));
select pg_temp.check(pg_temp.error_of(format('insert into probe (institution_id, note) values (%L, ''x'')', :inst_b))
                     = 'institution_mismatch', 'insert: forged institution_id is rejected');
insert into probe (note) values ('mine');
select pg_temp.check((select institution_id from probe where note = 'mine') = :inst_a,
                     'insert: institution_id is taken from the session');
reset role;
-- As the owner / a background job: no user claims, the institution must be stated explicitly.
select set_config('request.jwt.claims', '', true);
select pg_temp.check(pg_temp.error_of('insert into probe (note) values (''no institution'')') = 'institution_id_required',
                     'insert: jobs without a user must state the institution');
insert into probe (institution_id, note) values (:inst_b, 'theirs');
select pg_temp.act_as(pg_temp.claims_for(:user_a));
select pg_temp.check((select count(*) from probe) = 1, 'RLS template: user A never sees B''s rows');
reset role;

-- ---------------------------------------------------------------------------------------------------------------------
-- 5. access_version and deactivation take effect on the next request, even with an unexpired token
-- ---------------------------------------------------------------------------------------------------------------------
create temp table saved (k text primary key, v jsonb);
insert into saved values ('a_token', pg_temp.claims_for(:user_a));

update public.institution_members set access_version = access_version + 1
 where institution_id = :inst_a and user_id = :user_a;
select pg_temp.act_as((select v from saved where k = 'a_token'));
select pg_temp.check(app.auth_institution_id() is null, 'version: old token no longer resolves an institution');
select pg_temp.check((select count(*) from probe) = 0, 'version: old token sees no tenant rows');
select pg_temp.check(pg_temp.error_of('select app.require_active_session()') = 'session_refresh_required',
                     'version: RPCs get a typed "session refresh required" error');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:user_a));
select pg_temp.check(app.auth_institution_id() = :inst_a, 'version: a refreshed token works again');
reset role;

insert into saved values ('a_token2', pg_temp.claims_for(:user_a));
update public.institution_members set status = 'deactivated' where institution_id = :inst_a and user_id = :user_a;
select pg_temp.act_as((select v from saved where k = 'a_token2'));
select pg_temp.check(app.auth_institution_id() is null, 'deactivation: access ends on the very next request');
select pg_temp.check(pg_temp.error_of('select app.require_active_session()') = 'membership_not_active',
                     'deactivation: RPCs say the membership is not active');
reset role;
select pg_temp.check(pg_temp.claims_for(:user_a) -> 'active_institution_id' = 'null'::jsonb,
                     'deactivation: a new token has no institution');

-- ---------------------------------------------------------------------------------------------------------------------
-- 6. Profiles: users edit only allowed columns of their own row
-- ---------------------------------------------------------------------------------------------------------------------
select pg_temp.act_as(pg_temp.claims_for(:user_b));
update public.profiles set display_name = 'B renamed' where user_id = :user_b;
select pg_temp.check((select display_name from public.profiles where user_id = :user_b) = 'B renamed',
                     'profile: own display name can be changed');
select pg_temp.check(pg_temp.error_of(format('update public.profiles set user_kind = ''api'' where user_id = %L', :user_b))
                     like 'permission denied%', 'profile: user_kind cannot be changed by the user');
update public.profiles set display_name = 'hijack' where user_id = :user_a;
reset role;
select pg_temp.check((select display_name from public.profiles where user_id = :user_a) <> 'hijack',
                     'profile: another user''s profile cannot be changed');

-- ---------------------------------------------------------------------------------------------------------------------
-- 7. Platform roles stay separate; anonymous users see nothing
-- ---------------------------------------------------------------------------------------------------------------------
select pg_temp.act_as(pg_temp.claims_for(:user_platform));
select pg_temp.check((select platform_role from public.platform_members) = 'master_admin',
                     'platform: a platform member sees their own platform role');
select pg_temp.check((select count(*) from public.institutions) = 0,
                     'platform: a platform role gives no institution data by itself');
reset role;

select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;
select pg_temp.check(pg_temp.error_of('select count(*) from public.institutions') like 'permission denied%',
                     'anon: no access to institutions');
reset role;

-- ---------------------------------------------------------------------------------------------------------------------
-- 8. Every DEFINER function in our schemas is registered with a reason
-- ---------------------------------------------------------------------------------------------------------------------
select pg_temp.check(not exists (
  select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where p.prosecdef and n.nspname in ('public', 'app')
    and (n.nspname || '.' || p.proname) not in (select function_name from app.definer_registry)
), 'definer: every SECURITY DEFINER function is in app.definer_registry');

rollback;
