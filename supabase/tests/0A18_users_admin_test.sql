-- 0A.18 tests: Users list / detail, approve / deactivate / reactivate, contact change, access explainer, audit viewer,
-- role matrix (settings.users / settings.roles / audit.view) and two-step sign-in for sensitive role changes.
-- Needs the seeds (owner.admin = Super Admin of A, pending.member) and the registry (npm run db:permissions).
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
create function pg_temp.v(p_k text) returns jsonb language sql as $$ select v from out where k = p_k $$;
grant execute on function pg_temp.id(text), pg_temp.v(text) to authenticated;

\set inst_a '''a0000000-0000-4000-8000-00000000000a'''
\set user_a '''11111111-1111-4111-8111-111111111111'''
\set user_b '''22222222-2222-4222-8222-222222222222'''
\set user_both '''33333333-3333-4333-8333-333333333333'''
\set user_platform '''55555555-5555-4555-8555-555555555555'''
\set user_owner '''77777777-7777-4777-8777-777777777777'''
\set user_pending '''88888888-8888-4888-8888-888888888888'''
update public.profiles set last_active_institution_id = :inst_a where user_id = :user_both;
update public.profiles set last_active_institution_id = null where user_id in (:user_a, :user_b);

-- Set-up (as the owner): a test permission, branches X and Y, two roles, a manager (Admin template role) for both.member.
select app.sync_permissions('[{"module":"test","release":"t","permissions":[
  {"key":"test.view","scopable":true,"sensitive":false,"defaults":{}}]}]');
insert into public.app_settings (institution_id, key, value) values (:inst_a, 'branches_enabled', 'true')
  on conflict (institution_id, key) do update set value = excluded.value;
insert into ids values ('x', gen_random_uuid()), ('y', gen_random_uuid());
insert into public.org_units (institution_id, id, kind, name) values (:inst_a, pg_temp.id('x'), 'branch', 'X'), (:inst_a, pg_temp.id('y'), 'branch', 'Y');
insert into public.branches (institution_id, org_unit_id) values (:inst_a, pg_temp.id('x')), (:inst_a, pg_temp.id('y'));
with r as (insert into public.roles (institution_id, name) values (:inst_a, 'Branch viewer') returning id) insert into ids select 'branch_view', id from r;
with r as (insert into public.roles (institution_id, name) values (:inst_a, 'Caller (own)') returning id) insert into ids select 'caller_own', id from r;
insert into public.role_permissions (institution_id, role_id, permission_key, scope) values
  (:inst_a, pg_temp.id('branch_view'), 'test.view', 'all'), (:inst_a, pg_temp.id('caller_own'), 'test.view', 'own');
insert into ids select 'admin_role', id from public.roles where institution_id = :inst_a and template_key = 'admin';
insert into ids select 'super_role', id from public.roles where institution_id = :inst_a and is_super_admin;
insert into public.role_assignments (institution_id, user_id, role_id) values (:inst_a, :user_both, pg_temp.id('admin_role'));
select app.flush_access_queue(:inst_a);

-- 1. Role matrix: no settings.users → every Users RPC refused; Admin (settings.users, no settings.roles) → Users yes, roles no.
select pg_temp.act_as(pg_temp.claims_for(:user_a));
select pg_temp.check(pg_temp.error_of('select public.users_list()') = 'permission_denied', 'matrix: users_list refused without settings.users');
select pg_temp.check(pg_temp.error_of(format('select public.user_detail(%L)', :user_both)) = 'permission_denied', 'matrix: user_detail refused');
select pg_temp.check(pg_temp.error_of(format('select public.user_approve(%L)', :user_pending)) = 'permission_denied', 'matrix: user_approve refused');
select pg_temp.check(pg_temp.error_of(format('select public.user_deactivate(%L)', :user_both)) = 'permission_denied', 'matrix: user_deactivate refused');
select pg_temp.check(pg_temp.error_of(format('select public.access_explain(%L, %L)', :user_both, '{"permission":"test.view"}')) = 'permission_denied', 'matrix: access_explain refused');
select pg_temp.check(pg_temp.error_of('select public.audit_list()') = 'permission_denied', 'matrix: audit_list refused without audit.view');
select pg_temp.check(public.record_entities_get() = '[]'::jsonb, 'matrix: record types are not listed without settings.users');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:user_both));
select pg_temp.check(pg_temp.error_of('select public.users_list()') = '', 'matrix: the Admin role opens the Users screen');
select pg_temp.check(pg_temp.error_of('select public.role_create(''Mine'')') = 'permission_denied', 'matrix: the Admin role cannot change roles (no settings.roles)');
select pg_temp.check(pg_temp.error_of('select public.audit_list()') = 'permission_denied', 'matrix: the Admin role cannot read the audit log (audit.view is sensitive)');
reset role;

-- 2. Users list and search (Super Admin of A).
select pg_temp.act_as(pg_temp.claims_for(:user_owner));
insert into out select 'all', public.users_list();
select pg_temp.check((pg_temp.v('all') -> 'counts' ->> 'pending')::int = 1 and (pg_temp.v('all') -> 'counts' ->> 'deactivated')::int = 1,
  'list: counts per status');
select pg_temp.check(pg_temp.v('all') -> 'items' -> 0 ->> 'status' = 'pending', 'list: pending requests come first');
select pg_temp.check(not exists (select 1 from jsonb_array_elements(pg_temp.v('all') -> 'items') i where i ->> 'user_id' = :user_b),
  'list: members of another institution never appear');
select pg_temp.check(exists (select 1 from jsonb_array_elements(pg_temp.v('all') -> 'items') i
  where i ->> 'user_id' = :user_owner and i -> 'roles' -> 0 ->> 'name_key' is not null), 'list: active roles shown with their label key');
select pg_temp.check(jsonb_array_length(public.users_list('pending') -> 'items') = 1, 'list: filter by status');
select pg_temp.check(public.users_list(null, 'PENDING.mem') -> 'items' -> 0 ->> 'user_id' = :user_pending, 'list: search by name ignores case');
select pg_temp.check(public.users_list(null, '1711-000') -> 'items' -> 0 ->> 'user_id' = :user_pending, 'list: search by phone digits');
select pg_temp.check(jsonb_array_length(public.users_list(null, '%') -> 'items') = 0, 'list: % in a search is a literal character');
select pg_temp.check(pg_temp.error_of('select public.users_list(''removed'')') = 'user_state_invalid', 'list: unknown status refused');
select pg_temp.check(jsonb_array_length(public.users_list(null, null, 2, 0) -> 'items') = 2, 'list: limit');

-- 3. Detail.
insert into out select 'both', public.user_detail(:user_both);
select pg_temp.check((pg_temp.v('both') ->> 'profile_shared')::boolean, 'detail: a person in two institutions has a shared profile');
select pg_temp.check(pg_temp.v('both') -> 'assignments' -> 0 ->> 'state' = 'active', 'detail: assignment with its state');
select pg_temp.check(pg_temp.v('both') -> 'permissions' ? 'settings.users', 'detail: resulting access summary');
select pg_temp.check(pg_temp.error_of(format('select public.user_detail(%L)', :user_b)) = 'user_unknown', 'detail: someone of another institution is unknown');

-- 4. Approve, deactivate, reactivate.
select public.user_approve(:user_pending);
reset role;
select pg_temp.check((select status from public.institution_members where institution_id = :inst_a and user_id = :user_pending) = 'active',
  'approve: pending → active');
select pg_temp.check(exists (select 1 from public.audit_log where institution_id = :inst_a and action = 'membership.status_changed'
  and target_id = :user_pending and after ->> 'status' = 'active' and actor_user_id = :user_owner), 'approve: audited with the actor');
select pg_temp.act_as(pg_temp.claims_for(:user_owner));
select pg_temp.check(pg_temp.error_of(format('select public.user_approve(%L)', :user_pending)) = 'user_state_invalid', 'approve: only pending requests');
select pg_temp.check(pg_temp.error_of(format('select public.user_deactivate(%L)', :user_owner)) = 'self_lockout', 'deactivate: never yourself');
reset role;
insert into auth.sessions (id, user_id, created_at, updated_at) values (gen_random_uuid(), :user_pending, now(), now()),
  (gen_random_uuid(), :user_both, now(), now());
insert into out select 'ver_before', to_jsonb(access_version) from public.institution_members where institution_id = :inst_a and user_id = :user_pending;
select pg_temp.act_as(pg_temp.claims_for(:user_owner));
select public.user_deactivate(:user_pending, 'left the job');
select public.user_deactivate(:user_both, null);
reset role;
select pg_temp.check((select access_version from public.institution_members where institution_id = :inst_a and user_id = :user_pending)
  > (pg_temp.v('ver_before'))::int, 'deactivate: the access version is bumped (next request refused)');
select pg_temp.check(not exists (select 1 from auth.sessions where user_id = :user_pending), 'deactivate: sessions end when no other institution is active');
select pg_temp.check(exists (select 1 from auth.sessions where user_id = :user_both), 'deactivate: sessions stay when another institution is still active');
select pg_temp.check(exists (select 1 from public.audit_log where institution_id = :inst_a and target_id = :user_pending
  and after ->> 'status' = 'deactivated' and reason = 'left the job'), 'deactivate: the reason is kept in the audit log');
select pg_temp.check(not exists (select 1 from public.user_access where institution_id = :inst_a and user_id = :user_both),
  'deactivate: access rows removed at once');
select pg_temp.act_as(pg_temp.claims_for(:user_owner));
select public.user_reactivate(:user_both);
select pg_temp.check(pg_temp.error_of(format('select public.user_reactivate(%L)', :user_both)) = 'user_state_invalid', 'reactivate: only deactivated people');
reset role;
select pg_temp.check(exists (select 1 from public.user_access where institution_id = :inst_a and user_id = :user_both and permission_key = 'settings.users'),
  'reactivate: access is back');
-- Last Super Admin and outranking.
select pg_temp.act_as((pg_temp.claims_for(:user_platform) || '{"aal":"aal2"}'));
select pg_temp.check(pg_temp.error_of(format('select public.user_deactivate(%L, null, %L)', :user_owner, :inst_a)) = 'last_super_admin',
  'deactivate: never the last Super Admin');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:user_both));
select pg_temp.check(pg_temp.error_of(format('select public.user_deactivate(%L)', :user_owner)) = 'permission_escalation',
  'deactivate: nobody can deactivate a person with more access than themselves');
reset role;

-- 5. Contact change (email applied at once).
select pg_temp.act_as(pg_temp.claims_for(:user_owner));
select public.user_reactivate(:user_pending);
select public.user_update_contact(:user_pending, ' New Name ', '01711-000099', 'New.Mail@Example.test');
reset role;
select pg_temp.check((select email from auth.users where id = :user_pending) = 'new.mail@example.test', 'contact: email changed in sign-in at once');
select pg_temp.check((select display_name || '|' || phone from public.profiles where user_id = :user_pending) = 'New Name|01711000099',
  'contact: name trimmed, phone normalised');
select pg_temp.check(exists (select 1 from public.audit_log where action = 'user.contact_changed' and target_id = :user_pending
  and before ->> 'email' = 'pending.member@example.test'), 'contact: audited with before / after');
select pg_temp.act_as(pg_temp.claims_for(:user_owner));
select pg_temp.check(pg_temp.error_of(format('select public.user_update_contact(%L, ''X'', null, ''a.member@example.test'')', :user_pending)) = 'email_taken',
  'contact: an email already used is refused');
select pg_temp.check(pg_temp.error_of(format('select public.user_update_contact(%L, ''X'', null, ''not-an-email'')', :user_pending)) = 'email_invalid',
  'contact: invalid email refused');
select pg_temp.check(pg_temp.error_of(format('select public.user_update_contact(%L, ''X'', ''12'', ''x@example.test'')', :user_pending)) = 'phone_invalid',
  'contact: invalid phone refused');
select pg_temp.check(pg_temp.error_of(format('select public.user_update_contact(%L, ''X'', null, ''both@example.test'')', :user_both)) = 'profile_shared',
  'contact: a profile shared with another institution is changed only by its owner');
reset role;

-- 6. Access explainer.
select pg_temp.act_as(pg_temp.claims_for(:user_owner));
select public.role_assign(:user_a, pg_temp.id('caller_own'), null, pg_temp.id('y'), null, now() + interval '30 days');
select public.role_assign(:user_a, pg_temp.id('branch_view'), null, pg_temp.id('x'), now() + interval '1 day');
insert into out select 'own', public.access_explain(:user_a, jsonb_build_object('permission', 'test.view', 'owner_id', :user_a, 'branch_id', pg_temp.id('y')));
insert into out select 'other', public.access_explain(:user_a, jsonb_build_object('permission', 'test.view', 'owner_id', :user_both, 'branch_id', pg_temp.id('y')));
insert into out select 'x', public.access_explain(:user_a, jsonb_build_object('permission', 'test.view', 'owner_id', :user_both, 'branch_id', pg_temp.id('x')));
insert into out select 'none', public.access_explain(:user_pending, jsonb_build_object('permission', 'test.view'));
select pg_temp.check((pg_temp.v('own') ->> 'allowed')::boolean and exists (select 1 from jsonb_array_elements(pg_temp.v('own') -> 'reasons') r
  where r ->> 'verdict' = 'allows' and r ->> 'rule' = 'scope_own' and r ->> 'role_id' = pg_temp.id('caller_own')::text),
  'explain: own record in the branch → allowed by the caller role, scope own');
select pg_temp.check(not (pg_temp.v('other') ->> 'allowed')::boolean and pg_temp.v('other') ->> 'summary' = 'blocked_by_limits'
  and exists (select 1 from jsonb_array_elements(pg_temp.v('other') -> 'reasons') r where r ->> 'rule' = 'owner_scope'),
  'explain: someone else''s record → blocked by the own scope');
select pg_temp.check(exists (select 1 from jsonb_array_elements(pg_temp.v('x') -> 'reasons') r where r ->> 'rule' = 'not_started')
  and exists (select 1 from jsonb_array_elements(pg_temp.v('x') -> 'reasons') r where r ->> 'rule' = 'branch_limit'),
  'explain: other branch → branch limit; the role starting tomorrow → not started yet');
select pg_temp.check(pg_temp.v('none') ->> 'summary' = 'no_roles', 'explain: a person without roles');
select pg_temp.check(pg_temp.error_of(format('select public.access_explain(%L, %L)', :user_a, '{"permission":"nope.view"}')) = 'permission_unknown',
  'explain: unknown permission refused');
select pg_temp.check(pg_temp.error_of(format('select public.access_explain(%L, %L)', :user_a, '{"entity":"nope","id":"1"}')) = 'record_unknown',
  'explain: unknown record type refused');
reset role;
-- A registered record type (as 1A registers leads): looked up by id within the active institution only.
create table public.test_explain_records (institution_id uuid not null, id uuid not null default gen_random_uuid(),
  owner_id uuid, branch_id uuid, offering_id uuid, created_by uuid, primary key (institution_id, id));
insert into app.record_entities (entity_key, table_name, view_permission, label_key, added_in)
  values ('test_record', 'public.test_explain_records', 'test.view', 'entity.test_record', 'test');
with r as (insert into public.test_explain_records (institution_id, owner_id, branch_id, created_by)
  values (:inst_a, :user_a, pg_temp.id('y'), :user_owner) returning id) insert into ids select 'rec', id from r;
with r as (insert into public.test_explain_records (institution_id, owner_id, branch_id)
  values ('b0000000-0000-4000-8000-00000000000b', :user_a, null) returning id) insert into ids select 'rec_b', id from r;
select pg_temp.act_as(pg_temp.claims_for(:user_owner));
select pg_temp.check((public.access_explain(:user_a, jsonb_build_object('entity', 'test_record', 'id', pg_temp.id('rec'))) ->> 'allowed')::boolean,
  'explain: a registered record is looked up by id');
select pg_temp.check(pg_temp.error_of(format('select public.access_explain(%L, %L)', :user_a,
  jsonb_build_object('entity', 'test_record', 'id', pg_temp.id('rec_b')))) = 'record_unknown', 'explain: another institution''s record is unknown');
select pg_temp.check(public.record_entities_get() -> 0 ->> 'entity' = 'test_record', 'explain: record types listed for the picker');

-- 7. Audit viewer.
select public.role_create('Audit test role');
insert into out select 'roles', public.audit_list('{"area":"roles"}');
select pg_temp.check(pg_temp.v('roles') -> 'items' -> 0 ->> 'action' = 'role.created'
  and pg_temp.v('roles') -> 'items' -> 0 ->> 'actor_name' = 'owner.admin', 'audit: role changes with the actor''s name');
select pg_temp.check(not exists (select 1 from jsonb_array_elements(public.audit_list('{"area":"assignments"}') -> 'items') i
  where i ->> 'target_type' <> 'role_assignment'), 'audit: area filter');
select pg_temp.check(jsonb_array_length(public.audit_list(jsonb_build_object('actor_user_id', :user_platform)) -> 'items') = 0
  or not exists (select 1 from jsonb_array_elements(public.audit_list(jsonb_build_object('actor_user_id', :user_platform)) -> 'items') i
  where i ->> 'actor_user_id' <> :user_platform), 'audit: actor filter');
select pg_temp.check(jsonb_array_length(public.audit_list(jsonb_build_object('from', now() + interval '1 hour')) -> 'items') = 0, 'audit: date filter');
insert into out select 'page1', public.audit_list('{}', 2);
select pg_temp.check((pg_temp.v('page1') ->> 'has_more')::boolean and (public.audit_list(jsonb_build_object(
  'before_at', pg_temp.v('page1') -> 'items' -> 1 ->> 'at', 'before_id', pg_temp.v('page1') -> 'items' -> 1 ->> 'id'), 2) -> 'items' -> 0 ->> 'id')
  <> pg_temp.v('page1') -> 'items' -> 1 ->> 'id', 'audit: next page starts after the last row');
select pg_temp.check(pg_temp.error_of('select public.audit_list(''{"area":"secrets_values"}'')') = 'audit_filter_invalid', 'audit: unknown area refused');

-- 8. Two-step sign-in: a role change that adds a sensitive permission without aal2 is refused (R6).
insert into ids select 'new_role', public.role_create('Sensitive test');
select pg_temp.check(pg_temp.error_of(format('select public.role_set_grants(%L, %L)', pg_temp.id('new_role'), '{"audit.view": true}')) = 'mfa_required',
  'aal2: adding a sensitive permission without two-step sign-in is refused');
select pg_temp.check(pg_temp.error_of(format('select public.role_set_grants(%L, %L)', pg_temp.id('new_role'), '{"settings.general": true}')) = '',
  'aal2: non-sensitive changes work with a normal session');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:user_owner) || '{"aal":"aal2"}');
select pg_temp.check(pg_temp.error_of(format('select public.role_set_grants(%L, %L)', pg_temp.id('new_role'), '{"audit.view": true}')) = '',
  'aal2: with two-step sign-in the sensitive change is allowed');
reset role;

rollback;
