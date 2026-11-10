-- 0A.10 tests: UI language resolution (user choice → institution default → English) and set_my_language.
\set ON_ERROR_STOP on
begin;
create function pg_temp.check(cond boolean, what text) returns void language plpgsql as $$
begin
  if cond is distinct from true then raise exception 'FAILED: %', what; end if;
  raise notice 'ok - %', what;
end $$;
create function pg_temp.claims_for(p_user uuid) returns jsonb language sql as $$
  select (public.custom_access_token_hook(jsonb_build_object('user_id', p_user,
          'claims', jsonb_build_object('sub', p_user, 'role', 'authenticated', 'aud', 'authenticated')))) -> 'claims'
$$;
create function pg_temp.act_as(p_claims jsonb) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', p_claims::text, true);
  perform set_config('role', 'authenticated', true);
end $$;
create function pg_temp.error_of(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return ''; exception when others then return sqlerrm; end $$;
grant execute on all functions in schema pg_temp to authenticated, anon;
create temp table out (k text primary key, v jsonb);
grant all on out to authenticated;

\set inst_a '''a0000000-0000-4000-8000-00000000000a'''
\set inst_b '''b0000000-0000-4000-8000-00000000000b'''
\set user_a '''11111111-1111-4111-8111-111111111111'''
\set user_b '''22222222-2222-4222-8222-222222222222'''
\set user_platform '''55555555-5555-4555-8555-555555555555'''
update public.profiles set last_active_institution_id = null where user_id in (:user_a, :user_b);
update public.profiles set preferred_language = null where user_id in (:user_a, :user_b);
delete from public.app_settings where key = 'default_language';

-- 1. Nothing chosen anywhere → English.
select pg_temp.act_as(pg_temp.claims_for(:user_a));
select pg_temp.check(public.my_language() ->> 'language' = 'en', 'no choice and no institution default → English');
select pg_temp.check(public.settings_get_all() -> 'values' ->> 'default_language' = 'en', 'default_language is a registered setting');
reset role;

-- 2. Institution A defaults to Bangla → A's members get Bangla; B is unchanged.
select pg_temp.act_as(pg_temp.claims_for(:user_platform));
select public.setting_set('default_language', '"bn"', :inst_a);
select pg_temp.check(pg_temp.error_of(format('select public.setting_set(%L, %L, %L)', 'default_language', '"fr"', :inst_a))
                     like 'setting_invalid%', 'an unsupported institution language is rejected');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:user_a));
select pg_temp.check(public.my_language() ->> 'language' = 'bn', 'institution default applies when the person has no choice');
select pg_temp.check(public.my_language() ->> 'institution_default' = 'bn', '...and is reported to the app');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:user_b));
select pg_temp.check(public.my_language() ->> 'language' = 'en', 'B keeps English (A''s default does not leak)');
reset role;

-- 3. The person's own choice wins over the institution default.
select pg_temp.act_as(pg_temp.claims_for(:user_a));
insert into out select 'set_en', public.set_my_language('en');
select pg_temp.check((select v ->> 'language' from out where k = 'set_en') = 'en', 'own choice (en) wins over the institution default (bn)');
select pg_temp.check(public.my_language() ->> 'choice' = 'en', 'the choice is stored');
select pg_temp.check(pg_temp.error_of('select public.set_my_language(''fr'')') like 'language_unsupported%',
                     'an unsupported language is rejected');
insert into out select 'clear', public.set_my_language(null);
select pg_temp.check((select v ->> 'language' from out where k = 'clear') = 'bn', 'clearing the choice follows the institution again');
reset role;
select pg_temp.check((select preferred_language from public.profiles where user_id = :user_b) is null,
                     'setting my language never touches another person''s profile');

-- 4. Not signed in.
set local role anon;
select pg_temp.check(pg_temp.error_of('select public.set_my_language(''bn'')') like 'permission denied%',
                     'anonymous callers cannot call set_my_language');
reset role;
rollback;
