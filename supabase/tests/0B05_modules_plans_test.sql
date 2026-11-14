-- 0B.05 tests: module and plan catalogs; a module needs the plan (or an override), the institution's choice, its
-- industry and its dependencies; turning off keeps data; only settings.modules toggles and only the platform allows;
-- limits are enforced on the server (users beyond the limit fail even when the app skips the check), 80 % warns,
-- OTP / urgent never blocked; plan versions protect existing customers; downgrade fit check; counters reconcile;
-- isolation.
\set ON_ERROR_STOP on
begin;
create function pg_temp.check(cond boolean, what text) returns void language plpgsql as $$
begin
  if cond is distinct from true then raise exception 'FAILED: %', what; end if;
  raise notice 'ok - %', what;
end $$;
create function pg_temp.claims_for(p_user uuid, p_aal text default 'aal1') returns jsonb language sql as $$
  select (public.custom_access_token_hook(jsonb_build_object('user_id', p_user,
          'claims', jsonb_build_object('sub', p_user, 'role', 'authenticated', 'aud', 'authenticated')))) -> 'claims'
         || jsonb_build_object('aal', p_aal)
$$;
create function pg_temp.act_as(p_claims jsonb) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', p_claims::text, true);
  perform set_config('role', 'authenticated', true);
end $$;
create function pg_temp.error_of(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return ''; exception when others then return sqlerrm; end $$;
grant execute on all functions in schema pg_temp to authenticated;
create temp table out (k text primary key, v jsonb);
grant all on out to authenticated;
create function pg_temp.v(p_k text) returns jsonb language sql as $$ select v from out where k = p_k $$;
grant execute on function pg_temp.v(text) to authenticated;

\set inst_a '''a0000000-0000-4000-8000-00000000000a'''
\set user_a '''11111111-1111-4111-8111-111111111111'''
\set user_b '''22222222-2222-4222-8222-222222222222'''
\set owner '''77777777-7777-4777-8777-777777777777'''
\set pending '''88888888-8888-4888-8888-888888888888'''
\set master '''55555555-5555-4555-8555-555555555555'''
\set billing '''e2000000-0000-4000-8000-0000000000e2'''
update public.profiles set last_active_institution_id = null where user_id in (:user_a, :user_b);

-- 1. Catalogs and plans of institutions.
select pg_temp.check((select count(*) from public.modules) = 24 and (select always_on from public.modules where key = 'leads'),
  'the Ch 9.2 module list is seeded; core leads and follow-ups are always on');
select pg_temp.check((select count(distinct key) from public.plans) = 5 and (select count(*) from public.limit_metrics) = 12
  and (select count(*) from public.addons) = 9, 'five Proposed plans, the limits catalog (12 metrics with email_month, 0B.12) and add-ons are data');
select pg_temp.check(not exists (select 1 from public.institutions i where not exists
  (select 1 from public.institution_plan ip where ip.institution_id = i.id)), 'every institution has a plan');
insert into public.institutions (id, slug, name) values ('d0000000-0000-4000-8000-0000000000d9', 'plan-new-test', 'New institution');
select pg_temp.check((select plan_key = 'trial' and expires_at between now() + interval '13 days' and now() + interval '15 days'
  from public.institution_plan where institution_id = 'd0000000-0000-4000-8000-0000000000d9'), 'a new institution starts on the trial with an end date');
select pg_temp.check((select count(*) from public.institutions where slug in ('plan-trial', 'plan-starter', 'plan-standard', 'plan-pro', 'plan-enterprise')) = 5,
  'a test institution per plan (CI)');

-- 2. Modules in force for A (Standard).
select pg_temp.act_as(pg_temp.claims_for(:owner));
insert into out select 'mods', public.modules_get();
select pg_temp.check((select (m ->> 'enabled')::boolean from jsonb_array_elements(pg_temp.v('mods')) m where m ->> 'key' = 'branches')
  and not (select (m ->> 'allowed')::boolean from jsonb_array_elements(pg_temp.v('mods')) m where m ->> 'key' = 'ai'),
  'Standard: branches on; AI not in the plan');
select pg_temp.check(pg_temp.error_of('select public.module_set(''ai'', true, true)') = 'module_not_in_plan', 'a module outside the plan cannot be turned on');
select pg_temp.check(pg_temp.error_of('select public.module_set(''leads'', false, true)') = 'module_always_on', 'core leads cannot be turned off');
reset role;
insert into public.app_settings (institution_id, key, value) values (:inst_a, 'branches_enabled', 'true')
  on conflict (institution_id, key) do update set value = excluded.value;
insert into public.org_units (institution_id, kind, name) values (:inst_a, 'branch', 'Module test campus');
select pg_temp.act_as(pg_temp.claims_for(:owner));
select pg_temp.check(not (public.module_set('branches', false) ->> 'applied')::boolean and app.branches_enabled(:inst_a), 'preview first: nothing changes');
select public.module_set('branches', false, true);
select pg_temp.check(not app.branches_enabled(:inst_a), 'turned off: branches are off even with the setting on');
reset role;
select pg_temp.check(exists (select 1 from public.org_units where institution_id = :inst_a and name = 'Module test campus'), 'data is kept');
select pg_temp.act_as(pg_temp.claims_for(:owner));
select public.module_set('branches', true, true);
select pg_temp.check(app.branches_enabled(:inst_a), 'turned on again: everything returns');
reset role;

-- Dependencies and the platform override (only the platform allows modules beyond the plan).
select pg_temp.act_as(pg_temp.claims_for(:owner, 'aal2'));
select pg_temp.check(pg_temp.error_of(format('select public.platform_module_allow(%L, ''credits'', true)', :inst_a)) = 'permission_denied',
  'an institution cannot allow itself a module');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:billing, 'aal2'));
select public.platform_module_allow(:inst_a, 'credits', true, 'pilot');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:owner));
select public.module_set('credits', true, true);
select pg_temp.check(app.module_enabled(:inst_a, 'credits', 0), 'allowed by the platform, turned on by the institution');
select pg_temp.check(public.module_set('calls', false) -> 'impact' -> 'stops' = '["credits"]'::jsonb,
  'impact list: turning off calls also stops credits and leaderboard');
select public.module_set('calls', false, true);
select pg_temp.check(not app.module_enabled(:inst_a, 'credits', 0), 'a module whose dependency is off does not work');
select pg_temp.check(pg_temp.error_of('select public.module_set(''credits'', true, true)') like 'module_needs_other%'
  or pg_temp.error_of('select public.module_set(''credits'', true, true)') = 'module_needs_other', 'turning on needs its dependencies on');
select public.module_set('calls', true, true);
reset role;
update public.institutions set industry = 'healthcare' where id = :inst_a;
select pg_temp.check(not app.module_enabled(:inst_a, 'after_steps', 0), 'education-only modules do not work in another industry');
update public.institutions set industry = 'education' where id = :inst_a;
select pg_temp.act_as(pg_temp.claims_for(:user_a));
select pg_temp.check(pg_temp.error_of('select public.module_set(''branches'', false, true)') = 'permission_denied',
  'role matrix: without settings.modules no toggling');
reset role;

-- 3. Limits on the server: the (N+1)th user fails even when the app skips the check.
update public.institution_plan set limit_overrides = jsonb_build_object('users', app.usage_of(:inst_a, 'users')) where institution_id = :inst_a;
update public.institution_members set status = 'pending' where institution_id = :inst_a and user_id = :pending;
select app.usage_reconcile(:inst_a);
select pg_temp.act_as(pg_temp.claims_for(:owner));
select pg_temp.check(pg_temp.error_of(format('select public.user_approve(%L)', :pending)) = 'limit_reached',
  'approving one more user beyond the limit fails on the server');
reset role;
update public.institution_plan set limit_overrides = '{}' where institution_id = :inst_a;
select pg_temp.act_as(pg_temp.claims_for(:owner));
select pg_temp.check(pg_temp.error_of(format('select public.user_approve(%L)', :pending)) = '', 'with room it works');
reset role;
select pg_temp.check((app.check_limit(:inst_a, 'campaign_sms_day', 1700, null, false)) ->> 'level' = 'warning'
  and (app.check_limit(:inst_a, 'campaign_sms_day', 2001, null, false)) ->> 'level' = 'blocked', '80 % warns, beyond 100 % blocks');
select pg_temp.check(pg_temp.error_of(format('select app.check_limit(%L, ''sms_month'', 999999)', :inst_a)) = 'limit_reached'
  and (app.check_limit(:inst_a, 'sms_month', 999999, 'otp')) ->> 'level' = 'exempt'
  and (app.check_limit(:inst_a, 'sms_month', 999999, 'urgent')) ->> 'level' = 'exempt', 'OTP and urgent messages are never blocked');
select pg_temp.act_as(pg_temp.claims_for(:user_a));
select pg_temp.check(public.limits_status() -> 'plan' = 'null'::jsonb, 'without billing.view: no plan or numbers');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:owner));
select pg_temp.check(public.limits_status() -> 'plan' ->> 'key' = 'standard'
  and jsonb_array_length(public.limits_status() -> 'metrics') = (select count(*) from public.limit_metrics), 'with billing.view: the plan and every metric');
reset role;

-- 4. Plans: versions protect existing customers; changing plan, fit check; all logged.
select pg_temp.act_as(pg_temp.claims_for(:master, 'aal2'));
select public.platform_institution_plan_set('d0000000-0000-4000-8000-0000000000d2', 'starter', null, 'monthly', null, 0, '{}', 'test');
select pg_temp.check(public.platform_plan_save('starter', '{"en":"Starter","bn":"স্টার্টার"}', array['calls', 'fees'], '{"users": 2}', '{"currency":"BDT","monthly":1500}') = 2,
  'saving a plan makes a new version');
reset role;
select pg_temp.check((select plan_version from public.institution_plan where institution_id = 'd0000000-0000-4000-8000-0000000000d2') = 1,
  'an institution on the old version keeps it (price protection)');
select pg_temp.act_as(pg_temp.claims_for(:billing, 'aal2'));
insert into out select 'fit', public.platform_institution_plan(:inst_a, 'starter') -> 'fit';
select pg_temp.check(exists (select 1 from jsonb_array_elements(pg_temp.v('fit') -> 'over') x where x ->> 'metric' = 'users')
  and pg_temp.v('fit') -> 'modules_lost' ? 'whatsapp_log', 'downgrade fit check: what to reduce and which modules stop');
select public.platform_institution_plan_set(:inst_a, 'pro', now() + interval '1 year', 'yearly', 120000, 10, '{"sms_month": 20000}', 'upgrade');
select pg_temp.check(pg_temp.error_of(format('select public.platform_plan_save(''x'', ''{"en":"X","bn":"X"}'', ''{}'', ''{}'', ''{}'')')) = 'permission_denied',
  'Billing edits institution plans but not the plans catalog');
reset role;
select pg_temp.check(app.limit_of(:inst_a, 'sms_month') = 20000 and app.module_allowed(:inst_a, 'ai'), 'upgrade: the override wins; Pro modules allowed');
select pg_temp.check(exists (select 1 from public.platform_audit_log where action = 'institution.plan_changed' and institution_id = :inst_a and reason = 'upgrade')
  and exists (select 1 from public.audit_log where action = 'institution.plan_changed' and institution_id = :inst_a),
  'plan changes are logged on both sides');
select pg_temp.act_as(pg_temp.claims_for(:owner, 'aal2'));
select pg_temp.check(pg_temp.error_of(format('select public.platform_institution_plan_set(%L, ''enterprise'', null, ''monthly'', null, 0, ''{}'')', :inst_a)) = 'permission_denied',
  'an institution cannot change its own plan');
reset role;

-- 5. Counters reconcile; isolation.
update public.usage_counters set value = value + 7 where institution_id = :inst_a and metric = 'users' and period = '';
insert into out select 'rec', to_jsonb(app.usage_reconcile(:inst_a));
select pg_temp.check((pg_temp.v('rec'))::int >= 1 and app.usage_of(:inst_a, 'users')
  = (select count(*) from public.institution_members where institution_id = :inst_a and status = 'active'), 'reconciliation repairs a wrong counter');
select pg_temp.act_as(pg_temp.claims_for(:user_b));
select pg_temp.check(not exists (select 1 from public.usage_counters where institution_id <> app.auth_institution_id())
  and not exists (select 1 from public.institution_modules where institution_id <> app.auth_institution_id())
  and not exists (select 1 from public.institution_plan), 'other institutions'' usage, modules and plan are invisible (plan needs billing.view)');
reset role;

rollback;
