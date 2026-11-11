-- 0A.16 tests: permission registry, templates (college / school / coaching), `*` and sensitive permissions,
-- new-release rollout, aal2 for sensitive changes, platform permissions never on institution roles, isolation.
-- Needs the registry loaded (npm run db:permissions after db reset).
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
grant execute on all functions in schema pg_temp to authenticated;
create temp table out (k text primary key, v jsonb);
grant all on out to authenticated;

\set inst_a '''a0000000-0000-4000-8000-00000000000a'''
\set inst_b '''b0000000-0000-4000-8000-00000000000b'''
\set user_a '''11111111-1111-4111-8111-111111111111'''
\set user_b '''22222222-2222-4222-8222-222222222222'''
\set user_platform '''55555555-5555-4555-8555-555555555555'''
update public.profiles set last_active_institution_id = null where user_id in (:user_a, :user_b);

-- 1. Registry.
select pg_temp.check((select count(*) from public.permissions where key in ('settings.users', 'settings.roles', 'settings.terminology',
  'settings.organisation', 'integration.manage')) = 5, 'the 0A.16 permissions are registered from the manifest');
select pg_temp.check((select sensitive from public.permissions where key = 'settings.roles') and (select sensitive from public.permissions where key = 'integration.manage'),
  'settings.roles and integration.manage are sensitive');
select pg_temp.check(not exists (select 1 from public.permissions where key ~ '(^|[._])(students?|courses?|batch(es)?|admissions?|guardians?|alumni|college|school)($|[._])'),
  'no permission key contains an education word');
select pg_temp.check(pg_temp.error_of('insert into public.permissions (key, module, action, introduced_in_release) values (''student.view'', ''x'', ''view'', ''t'')')
  like '%permissions_key_check%', 'the database refuses an education-word permission key');
select pg_temp.check(not exists (select 1 from public.setting_definitions d where d.scope = 'institution' and d.area not like 'settings.followups'
  and not exists (select 1 from public.permissions p where p.key = d.area)), 'every institution setting area is a registered permission');
select pg_temp.check((select count(*) from public.field_registry where sensitive) >= 5, 'sensitive fields are registered (fee, discount, national IDs …)');

-- 2. Templates: a college, a school and a coaching centre (Done-when).
insert into public.institutions (id, slug, name, status) values
  ('c1000000-0000-4000-8000-000000000001', 'tpl-college', 'Template College', 'active'),
  ('c2000000-0000-4000-8000-000000000002', 'tpl-school', 'Template School', 'active'),
  ('c3000000-0000-4000-8000-000000000003', 'tpl-coaching', 'Template Coaching', 'active');
select app.apply_role_template('c1000000-0000-4000-8000-000000000001', 'college');
select app.apply_role_template('c2000000-0000-4000-8000-000000000002', 'school');
select app.apply_role_template('c3000000-0000-4000-8000-000000000003', 'coaching');
select pg_temp.check((select count(*) from public.roles where institution_id = 'c1000000-0000-4000-8000-000000000001') = 11, 'college: 11 template roles');
select pg_temp.check((select count(*) from public.roles where institution_id = 'c2000000-0000-4000-8000-000000000002') = 14, 'school: 14 (college roles + head teacher, assistant head, class teacher)');
select pg_temp.check((select count(*) from public.roles where institution_id = 'c3000000-0000-4000-8000-000000000003') = 3, 'coaching: owner, manager, counsellor');
select pg_temp.check((select template_key from public.roles where institution_id = 'c1000000-0000-4000-8000-000000000001' and is_super_admin) = 'principal'
  and (select template_key from public.roles where institution_id = 'c3000000-0000-4000-8000-000000000003' and is_super_admin) = 'owner',
  'the principal (college) and the owner (coaching) are Super Admin');
select pg_temp.check((select name_key from public.roles where institution_id = 'c1000000-0000-4000-8000-000000000001' and template_key = 'caller') = 'labels:caller.singular',
  'caller / team lead / conversion officer names come from labels');
select pg_temp.check((select flags from public.roles where institution_id = 'c1000000-0000-4000-8000-000000000001' and template_key = 'caller')
  = '{assignable,call_log_sync_required,counts_on_leaderboard,shown_in_team_activity}', 'the caller template has its behaviour flags');
select pg_temp.check(exists (select 1 from public.role_permissions rp join public.roles r on r.id = rp.role_id
  where r.institution_id = 'c1000000-0000-4000-8000-000000000001' and r.template_key = 'admin' and rp.permission_key = 'settings.users')
  and not exists (select 1 from public.role_permissions rp join public.roles r on r.id = rp.role_id
  where r.institution_id = 'c1000000-0000-4000-8000-000000000001' and r.template_key = 'admin' and rp.permission_key in ('settings.roles', 'integration.manage')),
  'admin gets non-sensitive settings, not the sensitive ones');
select pg_temp.check((select scope from public.role_permissions rp join public.roles r on r.id = rp.role_id
  where r.institution_id = 'c1000000-0000-4000-8000-000000000001' and r.template_key = 'accountant' and rp.permission_key = 'sensitive_field.view') = 'all',
  'scoped template grants carry their scope');
select pg_temp.check(app.apply_role_template('c1000000-0000-4000-8000-000000000001', 'college') = 0, 'applying a template again changes nothing');

-- 3. `*` only on Super Admin; platform permissions never on institution roles.
select pg_temp.check(pg_temp.error_of($$insert into public.role_permissions (institution_id, role_id, permission_key)
  select institution_id, id, '*' from public.roles where institution_id = 'c1000000-0000-4000-8000-000000000001' and template_key = 'admin'$$)
  like 'role_invalid%', '* cannot be given to any role but Super Admin');
select pg_temp.check(pg_temp.error_of($$insert into public.role_permissions (institution_id, role_id, permission_key)
  select institution_id, id, 'platform.billing' from public.roles where institution_id = 'c1000000-0000-4000-8000-000000000001' and template_key = 'admin'$$)
  like '%foreign key%', 'a platform permission cannot be granted to an institution role (database constraint)');

-- 4. Custom roles and the new-release rollout (R20).
select app.apply_role_template(:inst_a, 'college');
-- Read ids as the owner: the Master Admin has no active institution, so RLS would hide A's roles from them.
insert into out select 'admin', to_jsonb(id) from public.roles where institution_id = :inst_a and template_key = 'admin';
insert into out select 'super', to_jsonb(id) from public.roles where institution_id = :inst_a and is_super_admin;
select pg_temp.act_as((pg_temp.claims_for(:user_platform) || '{"aal":"aal2"}') );
insert into out select 'custom', to_jsonb(public.role_create('Admission desk', (select (v #>> '{}')::uuid from out where k = 'admin'),
  '{assignable}', 75, :inst_a));
reset role;
select pg_temp.check((select count(*) from public.role_permissions where role_id = (select (v #>> '{}')::uuid from out where k = 'custom')
  and permission_key = 'settings.users') = 1, 'a custom role inheriting from Admin starts with Admin''s non-sensitive grants');
select app.sync_permissions('[{"module":"test","release":"9.9","permissions":[
  {"key":"test.view","scopable":true,"sensitive":false,"defaults":{"admin":"branch","caller":"own"}},
  {"key":"test.purge","scopable":false,"sensitive":true,"defaults":{"admin":true}}]}]');
select pg_temp.check((select scope from public.role_permissions rp join public.roles r on r.id = rp.role_id
  where r.institution_id = :inst_a and r.template_key = 'caller' and rp.permission_key = 'test.view') = 'own',
  'a new permission reaches system roles with the declared default scope');
select pg_temp.check(exists (select 1 from public.role_permissions where role_id = (select (v #>> '{}')::uuid from out where k = 'custom') and permission_key = 'test.view'),
  'a custom role inheriting from Admin gets the new non-sensitive permission');
select pg_temp.check(not exists (select 1 from public.role_permissions where role_id = (select (v #>> '{}')::uuid from out where k = 'custom') and permission_key = 'test.purge')
  and exists (select 1 from public.role_permissions rp join public.roles r on r.id = rp.role_id where r.institution_id = :inst_a and r.template_key = 'admin' and rp.permission_key = 'test.purge'),
  '...but not the new sensitive one (the system Admin role does get it)');
select pg_temp.check(exists (select 1 from public.role_permissions rp join public.roles r on r.id = rp.role_id
  where r.institution_id = :inst_a and r.is_super_admin and rp.permission_key = '*'), 'Super Admin covers new and sensitive permissions through *');

-- 5. Changing roles: Master Admin only until 0A.17; sensitive changes need two-step sign-in (aal2).
select pg_temp.act_as(pg_temp.claims_for(:user_a));
select pg_temp.check(pg_temp.error_of('select public.role_create(''X'')') like 'permission_denied%', 'staff cannot create roles before permissions exist');
reset role;
-- With a one-step session the platform admin has no platform rights at all (0B.02); the "sensitive change needs
-- two-step sign-in" rule for institution admins is tested in 0A18 (mfa_required).
select pg_temp.act_as((pg_temp.claims_for(:user_platform) || '{"aal":"aal2"}') || '{"aal":"aal1"}');
select pg_temp.check(pg_temp.error_of(format('select public.role_set_grants(%L, %L, %L)', (select v #>> '{}' from out where k = 'custom'),
  '{"settings.users":true,"integration.manage":true}', :inst_a)) like 'permission_denied%', 'a platform admin without the second step can change nothing');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:user_platform) || '{"aal":"aal2"}');
select pg_temp.check(pg_temp.error_of(format('select public.role_set_grants(%L, %L, %L)', (select v #>> '{}' from out where k = 'custom'),
  '{"platform.billing":true}', :inst_a)) like 'role_invalid%', 'platform permissions are refused by the RPC as well');
select public.role_set_grants((select (v #>> '{}')::uuid from out where k = 'custom'), '{"settings.users":true,"test.view":"team"}', :inst_a);
reset role;
select pg_temp.act_as((pg_temp.claims_for(:user_platform) || '{"aal":"aal2"}') || '{"aal":"aal2"}');
insert into out select 'grants', public.role_set_grants((select (v #>> '{}')::uuid from out where k = 'custom'),
  '{"settings.users":true,"test.view":"team","integration.manage":true}', :inst_a);
select pg_temp.check(pg_temp.error_of(format('select public.role_set_grants(%L, %L, %L)', (select v #>> '{}' from out where k = 'super'), '{}', :inst_a))
  like 'role_invalid%', 'the Super Admin role''s grants cannot be changed');
select pg_temp.check(pg_temp.error_of(format('select public.role_update(%L, %L, %L, null, %L)', (select v #>> '{}' from out where k = 'custom'), 'X', '{flies}', :inst_a))
  like 'role_invalid%', 'unknown behaviour flags are refused');
reset role;
select pg_temp.check((select v from out where k = 'grants') = '{"settings.users":true,"test.view":"team","integration.manage":true}',
  'with aal2 the sensitive permission is added; scopes are kept');
select pg_temp.check(exists (select 1 from public.audit_log where institution_id = :inst_a and action = 'role.grants_changed'), 'role changes are audited');

-- 6. "Who" selector for non-access settings never offers the Super Admin role.
select pg_temp.check(pg_temp.error_of(format('select app.validate_who(%L, %L)', :inst_a,
  jsonb_build_object('mode', 'roles', 'roles', jsonb_build_array((select id from public.roles where institution_id = :inst_a and is_super_admin)))))
  like 'who_invalid%', 'the who selector refuses the Super Admin role');
select pg_temp.check(app.validate_who(:inst_a, '{"mode":"all"}') ->> 'mode' = 'all', 'mode all is accepted');

-- 7. Isolation.
select pg_temp.act_as(pg_temp.claims_for(:user_b));
select pg_temp.check((select count(*) from public.roles) = 0 and jsonb_array_length(public.roles_get()) = 0, 'B sees none of A''s roles');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:user_a));
select pg_temp.check(jsonb_array_length(public.roles_get()) = 12, 'A sees its 11 template roles and the custom one');
reset role;
rollback;
