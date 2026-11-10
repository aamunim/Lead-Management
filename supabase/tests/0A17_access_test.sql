-- 0A.17 tests: role assignments, can() and RLS through user_access, per-assignment limits, null-branch / null-offering
-- rules, team scope, access version, safeguards, temporary roles, who_matches, and speed.
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
create temp table ids (k text primary key, id uuid);
create temp table out (k text primary key, v jsonb);
grant all on ids, out to authenticated;
create function pg_temp.id(p_k text) returns uuid language sql as $$ select id from ids where k = p_k $$;
grant execute on function pg_temp.id(text) to authenticated;

\set inst_a '''a0000000-0000-4000-8000-00000000000a'''
\set inst_b '''b0000000-0000-4000-8000-00000000000b'''
\set user_a '''11111111-1111-4111-8111-111111111111'''
\set user_b '''22222222-2222-4222-8222-222222222222'''
\set user_both '''33333333-3333-4333-8333-333333333333'''
\set user_platform '''55555555-5555-4555-8555-555555555555'''
update public.profiles set last_active_institution_id = :inst_a where user_id = :user_both;
update public.profiles set last_active_institution_id = null where user_id in (:user_a, :user_b);

-- The seeded Super Admins (0A.18) are removed inside this transaction: these tests build their own.
delete from public.role_assignments where institution_id = :inst_a;
select app.flush_access_queue(:inst_a);

-- Set-up (as the owner): a test permission, branches X and Y, roles, a synthetic record table with the RLS helper.
select app.sync_permissions('[{"module":"test","release":"t","permissions":[
  {"key":"test.view","scopable":true,"sensitive":false,"defaults":{}},
  {"key":"test.edit","scopable":true,"sensitive":false,"defaults":{}}]}]');
select app.apply_role_template(:inst_a, 'college');
insert into public.app_settings (institution_id, key, value) values (:inst_a, 'branches_enabled', 'true');
insert into ids values ('x', gen_random_uuid()), ('y', gen_random_uuid()), ('team', gen_random_uuid());
insert into public.org_units (institution_id, id, kind, name) values (:inst_a, pg_temp.id('x'), 'branch', 'X'), (:inst_a, pg_temp.id('y'), 'branch', 'Y');
insert into public.branches (institution_id, org_unit_id) values (:inst_a, pg_temp.id('x')), (:inst_a, pg_temp.id('y'));
insert into public.org_units (institution_id, id, parent_id, kind, name) values (:inst_a, pg_temp.id('team'), pg_temp.id('y'), 'team', 'Y callers');
with r as (insert into public.roles (institution_id, name) values (:inst_a, 'Branch admin') returning id) insert into ids select 'branch_admin', id from r;
with r as (insert into public.roles (institution_id, name) values (:inst_a, 'Caller (own)') returning id) insert into ids select 'caller_own', id from r;
with r as (insert into public.roles (institution_id, name) values (:inst_a, 'Team viewer') returning id) insert into ids select 'team_view', id from r;
insert into public.role_permissions (institution_id, role_id, permission_key, scope) values
  (:inst_a, pg_temp.id('branch_admin'), 'test.view', 'all'), (:inst_a, pg_temp.id('branch_admin'), 'test.edit', 'all'),
  (:inst_a, pg_temp.id('caller_own'), 'test.view', 'own'), (:inst_a, pg_temp.id('caller_own'), 'test.edit', 'own'),
  (:inst_a, pg_temp.id('team_view'), 'test.view', 'team');

create table public.test_records (
  institution_id uuid not null, id uuid not null default gen_random_uuid(), owner_id uuid, branch_id uuid, offering_id uuid,
  created_by uuid, label text, primary key (institution_id, id));
alter table public.test_records enable row level security;
grant select on public.test_records to authenticated;
select app.create_visibility_policy('public.test_records', 'test.view');
insert into public.test_records (institution_id, owner_id, branch_id, created_by, label) values
  (:inst_a, :user_a, pg_temp.id('x'), :user_a, 'r1 X owned by a'),
  (:inst_a, :user_a, pg_temp.id('y'), :user_a, 'r2 Y owned by a'),
  (:inst_a, :user_both, pg_temp.id('y'), :user_a, 'r3 Y owned by both'),
  (:inst_a, :user_a, null, :user_a, 'r4 no branch, created by a'),
  (:inst_a, :user_a, null, :user_both, 'r5 no branch, created by both');
-- Records are read once, as the owner: a person under RLS might not see the record they are being checked against.
create temp table recs as select left(label, 2) as k, jsonb_build_object('owner_id', owner_id, 'branch_id', branch_id,
  'offering_id', offering_id, 'created_by', created_by) as r from public.test_records;
grant select on recs to authenticated;
create function pg_temp.rec(p_label text) returns jsonb language sql as $$ select r from recs where k = p_label $$;
grant execute on function pg_temp.rec(text) to authenticated;

-- 1. Admin in branch X, caller in branch Y (roadmap test), assigned by the Master Admin.
insert into out select 'claims_before', pg_temp.claims_for(:user_both);
select pg_temp.act_as(pg_temp.claims_for(:user_platform));
insert into ids select 'asg_admin_x', public.role_assign(:user_both, pg_temp.id('branch_admin'), null, pg_temp.id('x'), p_institution_id => :inst_a);
insert into ids select 'asg_caller_y', public.role_assign(:user_both, pg_temp.id('caller_own'), null, pg_temp.id('y'), p_institution_id => :inst_a);
reset role;
select pg_temp.check((select count(*) from public.user_access where institution_id = :inst_a and user_id = :user_both) = 4,
  'user_access holds one row per permission and assignment');
select pg_temp.act_as(pg_temp.claims_for(:user_both));
select pg_temp.check(app.can('test.edit', pg_temp.rec('r1')), 'admin in X: may edit any record in X');
select pg_temp.check(not app.can('test.edit', pg_temp.rec('r2')), 'caller in Y: may not edit someone else''s record in Y');
select pg_temp.check(app.can('test.edit', pg_temp.rec('r3')), 'caller in Y: may edit own record in Y');
select pg_temp.check(not app.can('test.edit', pg_temp.rec('r4')), 'a record without a branch is hidden from branch-limited staff…');
select pg_temp.check(app.can('test.edit', pg_temp.rec('r5')), '…unless they created it (null-branch rule)');
select pg_temp.check((select array_agg(left(label, 2) order by label) from public.test_records) = '{r1,r3,r5}',
  'RLS shows exactly the same records (the all scope of X does not widen Y)');
reset role;

-- Offering limit on an assignment: only listed offerings; records without an offering only for their creator.
select pg_temp.act_as(pg_temp.claims_for(:user_platform));
select public.role_unassign(pg_temp.id('asg_admin_x'), :inst_a);
insert into ids values ('off1', gen_random_uuid());
insert into ids select 'asg_admin_x2', public.role_assign(:user_both, pg_temp.id('branch_admin'), null, pg_temp.id('x'), null, null,
  array[pg_temp.id('off1')], :inst_a);
reset role;
select pg_temp.act_as(pg_temp.claims_for(:user_both));
select pg_temp.check(app.can('test.edit', pg_temp.rec('r1') || jsonb_build_object('offering_id', pg_temp.id('off1'))), 'offering limit: listed offering allowed');
select pg_temp.check(not app.can('test.edit', pg_temp.rec('r1') || jsonb_build_object('offering_id', gen_random_uuid())), 'offering limit: other offering refused');
select pg_temp.check(not app.can('test.edit', pg_temp.rec('r1')), 'offering limit: record without an offering refused to non-creators');
reset role;

-- 2. Access version: the old token stops working on the next request after an assignment changes (R15).
select pg_temp.act_as((select v from out where k = 'claims_before'));
select pg_temp.check(pg_temp.error_of('select app.require_active_session()') like 'session_refresh_required%',
  'after a role change the old token is refused (session refresh required)');
reset role;

-- 3. Team scope: a manager sees records owned by the people of the units they manage (and sub-units).
insert into public.org_unit_members (institution_id, org_unit_id, user_id) values (:inst_a, pg_temp.id('team'), :user_both);
insert into public.org_unit_managers (institution_id, org_unit_id, user_id) values (:inst_a, pg_temp.id('y'), :user_a);
select pg_temp.act_as(pg_temp.claims_for(:user_platform));
insert into ids select 'asg_team', public.role_assign(:user_a, pg_temp.id('team_view'), p_institution_id => :inst_a);
reset role;
select pg_temp.act_as(pg_temp.claims_for(:user_a));
select pg_temp.check(app.can('test.view', pg_temp.rec('r3')), 'team scope: manager of Y sees records of a member of a team under Y');
select pg_temp.check(app.can('test.view', pg_temp.rec('r1')), 'team scope includes own records');
select pg_temp.check(not app.can('test.edit', pg_temp.rec('r3')), 'but only for the permissions the role gives (no edit)');
reset role;

-- 4. Safeguards.
insert into ids select 'principal', id from public.roles where institution_id = :inst_a and is_super_admin;
insert into ids select 'admin_tpl', id from public.roles where institution_id = :inst_a and template_key = 'admin';
select pg_temp.act_as(pg_temp.claims_for(:user_platform));
insert into ids select 'asg_super', public.role_assign(:user_a, pg_temp.id('principal'), p_institution_id => :inst_a);
select pg_temp.check(pg_temp.error_of(format('select public.role_unassign(%L, %L)', pg_temp.id('asg_super'), :inst_a)) like 'last_super_admin%',
  'the last Super Admin cannot be removed');
insert into ids select 'asg_users_both', public.role_assign(:user_both, pg_temp.id('admin_tpl'), p_institution_id => :inst_a);
reset role;
select pg_temp.act_as(pg_temp.claims_for(:user_both));
select pg_temp.check(pg_temp.error_of(format('select public.role_unassign(%L)', pg_temp.id('asg_users_both'))) like 'self_lockout%',
  'an admin cannot remove their own last way to manage users');
select pg_temp.check(pg_temp.error_of(format('select public.role_unassign(%L)', pg_temp.id('asg_super'))) like 'permission_escalation%',
  'nobody can change a person with more power (the Super Admin)');
select pg_temp.check(pg_temp.error_of(format('select public.role_assign(%L, %L)', :user_both, pg_temp.id('principal'))) like 'permission_escalation%',
  'an admin cannot give a role with permissions they do not have');
reset role;
-- An admin with settings.roles but without integration.manage cannot grant integration.manage (even with aal2).
select set_config('request.jwt.claims', '', true); -- owner set-up: no signed-in user
with r as (insert into public.roles (institution_id, name) values (:inst_a, 'Role editor') returning id) insert into ids select 'role_editor', id from r;
insert into public.role_permissions (institution_id, role_id, permission_key) values (:inst_a, pg_temp.id('role_editor'), 'settings.roles');
select pg_temp.act_as(pg_temp.claims_for(:user_platform));
select public.role_assign(:user_both, pg_temp.id('role_editor'), p_institution_id => :inst_a);
reset role;
select pg_temp.act_as(pg_temp.claims_for(:user_both) || '{"aal":"aal2"}');
select pg_temp.check(pg_temp.error_of(format('select public.role_set_grants(%L, %L)', pg_temp.id('caller_own'), '{"test.view":"own","integration.manage":true}'))
  like 'permission_escalation%', 'nobody can grant a permission they do not have (Admin cannot grant integration.manage)');
select pg_temp.check(pg_temp.error_of(format('select public.role_delete(%L)', pg_temp.id('caller_own'))) like 'role_has_members%',
  'a role with people cannot be deleted without moving them');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:user_platform));
insert into out select 'moved', to_jsonb(public.role_delete(pg_temp.id('caller_own'), pg_temp.id('branch_admin'), :inst_a));
select pg_temp.check(pg_temp.error_of(format('select public.role_delete(%L, null, %L)', pg_temp.id('principal'), :inst_a)) like 'role_invalid%',
  'system roles cannot be deleted');
reset role;
select pg_temp.check((select v #>> '{}' from out where k = 'moved')::int = 1 and (select archived_at is not null from public.roles where id = pg_temp.id('caller_own')),
  'with a target role, its people are moved and the role is archived');
select pg_temp.check(exists (select 1 from public.audit_log where institution_id = :inst_a and action = 'role.assigned')
  and exists (select 1 from public.domain_events where institution_id = :inst_a and event_key = 'role.unassigned'), 'assignments are audited and emitted');

-- 5. Earlier fail-closed checks now open through can(): user_both (Admin template) may change settings and words.
select pg_temp.act_as(pg_temp.claims_for(:user_both));
select pg_temp.check((public.setting_set('working_hours', '{"start":"10:00","end":"18:00"}') ->> 'key') = 'working_hours', 'Admin may change office settings (settings.office)');
select pg_temp.check(pg_temp.error_of('select public.secret_set(''sms.x.key'', ''abcdefgh'')') like 'permission_denied%',
  'Admin may not set secrets (integration.manage is sensitive and not in the Admin template)');
select pg_temp.check((public.my_access() -> 'permissions') ? 'settings.users' and (public.my_access() -> 'flags') ? 'receives_escalations',
  'my_access lists my permissions and behaviour flags (union of roles)');
reset role;

-- 6. Temporary roles: an expired assignment stops counting at once and is cleaned up by the job.
-- A season worker with only this one temporary role.
select set_config('request.jwt.claims', '', true);
insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000', '99999999-9999-4999-8999-999999999999', 'authenticated', 'authenticated', 'season@example.test', now(), now());
insert into public.institution_members (institution_id, user_id, status) values (:inst_a, '99999999-9999-4999-8999-999999999999', 'active');
select pg_temp.act_as(pg_temp.claims_for(:user_platform));
insert into ids select 'asg_temp', public.role_assign('99999999-9999-4999-8999-999999999999', pg_temp.id('branch_admin'), null, null, now(),
  now() + interval '30 days', null, :inst_a);
reset role;
update public.user_access set valid_to = now() - interval '1 minute' where assignment_id = pg_temp.id('asg_temp');
update public.role_assignments set valid_from = now() - interval '2 days', valid_to = now() - interval '1 minute' where id = pg_temp.id('asg_temp');
select pg_temp.act_as(pg_temp.claims_for('99999999-9999-4999-8999-999999999999'));
select pg_temp.check(not app.can('test.edit', pg_temp.rec('r2')), 'an expired temporary role gives nothing');
reset role;
select app.expire_temporary_roles();
select pg_temp.check(not exists (select 1 from public.user_access where assignment_id = pg_temp.id('asg_temp')), 'the expiry job removes its access rows');
select pg_temp.check(exists (select 1 from cron.job where jobname = 'expire-temporary-roles') and exists (select 1 from cron.job where jobname = 'access-rebuild-queue'),
  'the expiry and rebuild jobs are scheduled');

-- 7. who_matches (non-access settings).
select pg_temp.check(app.who_matches(:inst_a, jsonb_build_object('mode', 'roles', 'roles', jsonb_build_array(pg_temp.id('team_view'))), :user_a)
  and not app.who_matches(:inst_a, jsonb_build_object('mode', 'roles', 'roles', jsonb_build_array(pg_temp.id('team_view'))), :user_both)
  and app.who_matches(:inst_a, '{"mode":"all"}', :user_both) and app.who_matches(:inst_a, jsonb_build_object('mode', 'users', 'user_ids', jsonb_build_array(:user_b)), :user_b),
  'who_matches evaluates all / roles / users');

-- 8. Isolation: B sees none of A's access rows; a person sees only their own.
select pg_temp.act_as(pg_temp.claims_for(:user_b));
select pg_temp.check((select count(*) from public.user_access) = 0 and (select count(*) from public.role_assignments) = 0, 'B sees none of A''s access rows or assignments');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:user_a));
select pg_temp.check((select count(distinct user_id) from public.user_access) = 1, 'a person reads only their own access rows');
reset role;

-- 9. Speed. (a) Rebuild one user in an institution with 200 people and 50 units under 200 ms.
select set_config('request.jwt.claims', '', true); -- owner set-up
insert into public.institutions (id, slug, name, status) values ('d0000000-0000-4000-8000-00000000000d', 'perf-inst', 'Perf', 'active');
insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at)
select '00000000-0000-0000-0000-000000000000', ('00000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid, 'authenticated', 'authenticated',
       'perf' || n || '@example.test', now(), now() from generate_series(1, 200) n;
insert into public.institution_members (institution_id, user_id, status)
select 'd0000000-0000-4000-8000-00000000000d', ('00000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid, 'active' from generate_series(1, 200) n;
insert into public.org_units (institution_id, id, kind, name)
select 'd0000000-0000-4000-8000-00000000000d', ('00000000-0000-4000-9000-' || lpad(n::text, 12, '0'))::uuid, 'department', 'U' || n from generate_series(1, 5) n;
insert into public.org_units (institution_id, id, parent_id, kind, name)
select 'd0000000-0000-4000-8000-00000000000d', ('00000000-0000-4000-9000-' || lpad((10 + n)::text, 12, '0'))::uuid,
       ('00000000-0000-4000-9000-' || lpad((1 + n % 5)::text, 12, '0'))::uuid, 'team', 'T' || n from generate_series(1, 45) n;
insert into public.org_unit_members (institution_id, org_unit_id, user_id)
select 'd0000000-0000-4000-8000-00000000000d', ('00000000-0000-4000-9000-' || lpad((11 + n % 45)::text, 12, '0'))::uuid,
       ('00000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid from generate_series(1, 200) n;
insert into public.org_unit_managers (institution_id, org_unit_id, user_id)
select 'd0000000-0000-4000-8000-00000000000d', ('00000000-0000-4000-9000-' || lpad(n::text, 12, '0'))::uuid, '00000000-0000-4000-8000-000000000001'
from generate_series(1, 5) n;
select app.apply_role_template('d0000000-0000-4000-8000-00000000000d', 'college');
insert into public.role_permissions (institution_id, role_id, permission_key, scope)
select 'd0000000-0000-4000-8000-00000000000d', id, 'test.view', 'team' from public.roles where institution_id = 'd0000000-0000-4000-8000-00000000000d' and template_key = 'team_lead';
insert into public.role_assignments (institution_id, user_id, role_id)
select 'd0000000-0000-4000-8000-00000000000d', ('00000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
       (select id from public.roles where institution_id = 'd0000000-0000-4000-8000-00000000000d' and template_key = case when n = 1 then 'team_lead' else 'caller' end)
from generate_series(1, 200) n;
select app.flush_access_queue('d0000000-0000-4000-8000-00000000000d', 1000);
create function pg_temp.rebuild_ms() returns numeric language plpgsql as $$
declare t0 timestamptz; best numeric := 1e9;
begin
  for i in 1..5 loop
    t0 := clock_timestamp();
    perform app.rebuild_user_access('d0000000-0000-4000-8000-00000000000d', '00000000-0000-4000-8000-000000000001');
    best := least(best, extract(epoch from clock_timestamp() - t0) * 1000);
  end loop;
  return best;
end $$;
select pg_temp.check((select cardinality(user_ids) from public.user_access where institution_id = 'd0000000-0000-4000-8000-00000000000d'
  and user_id = '00000000-0000-4000-8000-000000000001' and permission_key = 'test.view') = 200, 'the manager of all units sees all 200 people (team scope)');
select pg_temp.check(pg_temp.rebuild_ms() < 200, 'rebuilding one user''s access (200 people, 50 units) takes under 200 ms');

-- (b) The RLS check on 3,000 rows adds under 10 ms.
insert into public.test_records (institution_id, owner_id, branch_id, created_by, label)
select :inst_a, case when n % 3 = 0 then :user_both::uuid else :user_a::uuid end, case when n % 2 = 0 then pg_temp.id('x') else pg_temp.id('y') end, :user_a, 'bulk'
from generate_series(1, 3000) n;
analyze public.test_records;
analyze public.user_access;
create function pg_temp.count_ms() returns numeric language plpgsql as $$
declare t0 timestamptz; best numeric := 1e9; n integer;
begin
  for i in 1..5 loop
    t0 := clock_timestamp();
    select count(*) into n from public.test_records;
    best := least(best, extract(epoch from clock_timestamp() - t0) * 1000);
  end loop;
  return best;
end $$;
grant execute on function pg_temp.count_ms() to authenticated;
insert into out select 'owner_ms', to_jsonb(pg_temp.count_ms());
select pg_temp.act_as(pg_temp.claims_for(:user_both));
insert into out select 'rls_ms', to_jsonb(pg_temp.count_ms());
reset role;
select pg_temp.check((select (v #>> '{}')::numeric from out where k = 'rls_ms') - (select (v #>> '{}')::numeric from out where k = 'owner_ms') < 10,
  format('the RLS check on 3,000 rows adds under 10 ms (%s ms vs %s ms)', round((select (v #>> '{}')::numeric from out where k = 'rls_ms'), 2),
         round((select (v #>> '{}')::numeric from out where k = 'owner_ms'), 2)));
rollback;
