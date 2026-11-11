-- 0A.08 tests: typed settings (validation, layers, versions, migrations, permissions), min app version, counters.
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
begin execute p_sql; return ''; exception when others then return sqlerrm || coalesce(' | ' || nullif(pg_temp.last_detail(), ''), ''); end $$;
create function pg_temp.last_detail() returns text language sql as $$ select '' $$;
create function pg_temp.err_detail(p_sql text) returns text language plpgsql as $$
declare d text;
begin execute p_sql; return ''; exception when others then get stacked diagnostics d = pg_exception_detail; return coalesce(d, ''); end $$;
grant execute on all functions in schema pg_temp to authenticated;
create temp table out (k text primary key, v jsonb);
grant all on out to authenticated;

\set inst_a '''a0000000-0000-4000-8000-00000000000a'''
\set inst_b '''b0000000-0000-4000-8000-00000000000b'''
\set user_a '''11111111-1111-4111-8111-111111111111'''
\set user_b '''22222222-2222-4222-8222-222222222222'''
\set user_platform '''55555555-5555-4555-8555-555555555555'''
update public.profiles set last_active_institution_id = null where user_id in (:user_a, :user_b);

-- A setting is data: one definition row, no code change.
insert into public.setting_definitions (key, scope, schema, default_value, area, description) values
  ('test.followup_days', 'institution', '{"type":"integer","minimum":1,"maximum":30}', '3', 'settings.followups', 'test');
select pg_temp.check(pg_temp.error_of($$insert into public.setting_definitions (key, scope, schema, default_value, area, description)
  values ('test.bad_default', 'institution', '{"type":"integer"}', '"x"', 'settings.x', 'test')$$) like '%default_matches_schema%',
  'a definition whose default breaks its own schema is refused');

-- 1. Default when unset; the version comes along.
select pg_temp.act_as(pg_temp.claims_for(:user_a));
insert into out select 'a1', public.settings_get_all();
reset role;
select pg_temp.check((select v -> 'values' -> 'test.followup_days' from out where k = 'a1') = '3', 'unset key returns the definition default');
select pg_temp.check((select (v ->> 'settings_version')::int from out where k = 'a1') >= 1, 'settings_version is returned');
select pg_temp.check((select v -> 'values' ->> 'min_app_version' from out where k = 'a1') = '0.0.0', 'product-level values are included');

-- 2. Writes: staff refused until permissions exist; the Master Admin writes for A; values are validated.
select pg_temp.act_as(pg_temp.claims_for(:user_a));
select pg_temp.check(pg_temp.error_of('select public.setting_set(''test.followup_days'', ''7'')') like 'permission_denied%',
                     'staff cannot write settings before permissions exist (fail-closed)');
reset role;
select pg_temp.act_as((pg_temp.claims_for(:user_platform) || '{"aal":"aal2"}'));
insert into out select 'set7', public.setting_set('test.followup_days', '7', :inst_a);
select public.setting_set('test.followup_days', '9', :inst_a);
select pg_temp.check(pg_temp.error_of(format('select public.setting_set(%L, %L, %L)', 'test.followup_days', '0', :inst_a)) like 'setting_invalid%',
                     'a value outside the schema is rejected');
select pg_temp.check(pg_temp.err_detail(format('select public.setting_set(%L, %L, %L)', 'test.followup_days', '0', :inst_a))
                     like '%minimum of 1%', '...with a field-level message (minimum of 1)');
select pg_temp.check(pg_temp.error_of(format('select public.setting_set(%L, %L, %L)', 'test.followup_days', '"seven"', :inst_a)) like 'setting_invalid%',
                     'a value of the wrong type is rejected');
select pg_temp.check(pg_temp.error_of(format('select public.setting_set(%L, %L, %L)', 'no.such_key', '1', :inst_a)) like 'setting_unknown%',
                     'an unknown key is rejected');
select pg_temp.check(pg_temp.error_of(format('select public.setting_set(%L, %L, %L)', 'min_app_version', '"9.9.9"', :inst_a)) like 'setting_unknown%',
                     'a product-level key cannot be set per institution');
reset role;
select pg_temp.check((select (v ->> 'settings_version')::int from out where k = 'set7')
                     = (select (v ->> 'settings_version')::int from out where k = 'a1') + 1, 'a write bumps settings_version');
select pg_temp.check((select previous_value from public.app_settings where institution_id = :inst_a and key = 'test.followup_days') = '7',
                     'the previous value and author are kept');
select pg_temp.check((select updated_by from public.app_settings where institution_id = :inst_a and key = 'test.followup_days') = :user_platform,
                     '...with who changed it');

-- 3. Isolation: A sees its value; B keeps the default and sees none of A's rows.
select pg_temp.act_as(pg_temp.claims_for(:user_a));
select pg_temp.check((public.settings_get_all() -> 'values' -> 'test.followup_days') = '9', 'A resolves its own value');
select pg_temp.check((public.settings_get_all() ->> 'settings_version')::int
                     = (select (v ->> 'settings_version')::int from out where k = 'a1') + 2, 'A sees its new version');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:user_b));
select pg_temp.check((public.settings_get_all() -> 'values' -> 'test.followup_days') = '3', 'B still gets the default');
select pg_temp.check((select count(*) from public.app_settings) = 0, 'B sees none of A''s settings rows');
reset role;

-- 4. Layers: a type-profile default sits between the definition default and the institution value (0B hook).
create or replace function app.type_profile_setting_default(p_institution uuid, p_key text) returns jsonb
language sql stable set search_path = '' as $$
  select case when p_key = 'test.followup_days' then '5'::jsonb end
$$;
select pg_temp.act_as(pg_temp.claims_for(:user_b));
select pg_temp.check((public.settings_get_all() -> 'values' -> 'test.followup_days') = '5', 'type-profile default overrides the definition default');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:user_a));
select pg_temp.check((public.settings_get_all() -> 'values' -> 'test.followup_days') = '9', 'the institution value overrides the type-profile default');
reset role;

-- 5. Reset to default.
select pg_temp.act_as((pg_temp.claims_for(:user_platform) || '{"aal":"aal2"}'));
insert into out select 'reset', public.setting_reset('test.followup_days', :inst_a);
reset role;
select pg_temp.check((select v -> 'value' from out where k = 'reset') = '5', 'reset returns to the next layer (type-profile default)');
select pg_temp.check(not exists (select 1 from public.app_settings where institution_id = :inst_a and key = 'test.followup_days'),
                     'reset removes the override');

-- 6. Settings migrations: a definition moves to version 2 (integer -> object); stored values are upgraded.
select pg_temp.act_as((pg_temp.claims_for(:user_platform) || '{"aal":"aal2"}'));
select public.setting_set('test.followup_days', '9', :inst_a);
reset role;
create function app.test_migrate_followup(p_value jsonb, p_from integer) returns jsonb language sql set search_path = '' as $$
  select jsonb_build_object('days', p_value, 'skip_holidays', true)
$$;
update public.setting_definitions set version = 2, migrate_fn = 'app.test_migrate_followup',
  schema = '{"type":"object","properties":{"days":{"type":"integer","minimum":1},"skip_holidays":{"type":"boolean"}},"required":["days"]}',
  default_value = '{"days":3}' where key = 'test.followup_days';
select pg_temp.check(app.run_setting_migrations() = 1, 'the migration runner upgrades every outdated stored value');
select pg_temp.check((select value from public.app_settings where institution_id = :inst_a and key = 'test.followup_days')
                     = '{"days":9,"skip_holidays":true}', 'the old value is converted to the new shape');
select pg_temp.check((select schema_version from public.app_settings where institution_id = :inst_a and key = 'test.followup_days') = 2,
                     'the stored value now carries version 2');
update public.setting_definitions set version = 3, migrate_fn = null where key = 'test.followup_days';
select pg_temp.check(pg_temp.error_of('select app.run_setting_migrations()') like 'setting_migration_missing%',
                     'a version bump without a migration function stops the runner');
update public.setting_definitions set version = 2, migrate_fn = 'app.test_migrate_followup' where key = 'test.followup_days';

-- 7. Product-level settings and the minimum app version.
select pg_temp.act_as(pg_temp.claims_for(:user_a));
select pg_temp.check(pg_temp.error_of('select public.product_setting_set(''min_app_version'', ''"0.2.0"'')') like 'permission_denied%',
                     'staff cannot change product settings');
reset role;
select pg_temp.act_as((pg_temp.claims_for(:user_platform) || '{"aal":"aal2"}'));
select pg_temp.check(pg_temp.error_of('select public.product_setting_set(''min_app_version'', ''"abc"'')') like 'setting_invalid%',
                     'product settings are validated too');
select public.product_setting_set('min_app_version', '"0.2.0"');
reset role;
select set_config('request.headers', '{"x-app-version":"0.1.9"}', true);
select pg_temp.check(pg_temp.error_of('select app.pre_request()') like 'upgrade_required%', 'an app older than the minimum gets upgrade_required');
select set_config('request.headers', '{"x-app-version":"0.10.0"}', true);
select pg_temp.check(pg_temp.error_of('select app.pre_request()') = '', 'a newer app passes (numeric, not text, comparison: 0.10.0 > 0.2.0)');
select set_config('request.headers', '{}', true);
select pg_temp.check(pg_temp.error_of('select app.pre_request()') = '', 'a request without the header passes (web / tools)');
select pg_temp.act_as(pg_temp.claims_for(:user_a));
select set_config('request.headers', '{"x-app-version":"0.2.0"}', true);
select app.pre_request();
select pg_temp.check(current_setting('response.headers', true) like '%x-settings-version%',
                     'every response carries x-settings-version for the active institution');
reset role;

-- 8. Counters: per institution, per optional branch, gap-free inside a transaction.
select pg_temp.act_as(pg_temp.claims_for(:user_a));
select pg_temp.check(app.counter_next('test.receipt') = 1 and app.counter_next('test.receipt') = 2 and app.counter_next('test.receipt') = 3,
                     'A''s counter counts 1, 2, 3');
select pg_temp.check(app.counter_next('test.receipt', 'c0000000-0000-4000-8000-00000000000c') = 1, 'a branch series counts on its own');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:user_b));
select pg_temp.check(app.counter_next('test.receipt') = 1, 'B''s counter is independent of A''s');
select pg_temp.check((select count(*) from public.institution_counters where counter_key = 'test.receipt') = 1,
                     'B sees only its own counter rows');
select pg_temp.check(pg_temp.error_of('update public.institution_counters set next_value = 1') like 'permission denied%',
                     'counters cannot be edited directly');
reset role;
rollback;
