-- 0A.19 tests: branch archive guard and "move everything to another branch first", terminology reset (one / all)
-- with old and new values in the audit log, locked words, Bangla form preview, settings version, role matrix.
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
\set user_platform '''55555555-5555-4555-8555-555555555555'''
\set user_owner '''77777777-7777-4777-8777-777777777777'''
update public.profiles set last_active_institution_id = null where user_id = :user_a;
insert into public.app_settings (institution_id, key, value) values (:inst_a, 'branches_enabled', 'true')
  on conflict (institution_id, key) do update set value = excluded.value;
insert into ids select 'admin_role', id from public.roles where institution_id = :inst_a and template_key = 'admin';

-- 1. Role matrix.
select pg_temp.act_as(pg_temp.claims_for(:user_a));
select pg_temp.check(pg_temp.error_of(format('select public.branch_archive_check(%L)', gen_random_uuid())) = 'permission_denied',
  'matrix: archive check refused without settings.organisation');
select pg_temp.check(pg_temp.error_of(format('select public.branch_move_contents(%L, %L)', gen_random_uuid(), gen_random_uuid())) = 'permission_denied',
  'matrix: moving branch contents refused');
select pg_temp.check(pg_temp.error_of('select public.label_reset_all()') = 'permission_denied', 'matrix: reset all words refused without settings.terminology');
select pg_temp.check(pg_temp.error_of('select public.label_set(''client'', ''Trainee'', ''Trainees'', ''{"base":"প্রশিক্ষণার্থী"}'')') = 'permission_denied',
  'matrix: renaming refused without settings.terminology');
reset role;

-- 2. Archive guard and moving contents (as the Super Admin of A).
select pg_temp.act_as(pg_temp.claims_for(:user_owner));
insert into ids select 'x', public.branch_create('North campus', 'Road 1', '01711000001');
insert into ids select 'y', public.branch_create('South campus');
insert into ids select 'team', public.org_unit_create('North callers', 'team', pg_temp.id('x'));
select public.org_unit_add_member(pg_temp.id('x'), :user_a);
select public.set_manager(pg_temp.id('x'), :user_owner, true);
insert into ids select 'asg', public.role_assign(:user_a, pg_temp.id('admin_role'), null, pg_temp.id('x'));
reset role;
update public.institution_members set branch_id = pg_temp.id('x') where institution_id = :inst_a and user_id = :user_a;
select pg_temp.act_as(pg_temp.claims_for(:user_owner));
insert into out select 'usage', public.branch_archive_check(pg_temp.id('x'));
select pg_temp.check((pg_temp.v('usage') ->> 'units')::int = 1 and (pg_temp.v('usage') ->> 'unit_members')::int = 1
  and (pg_temp.v('usage') ->> 'managers')::int = 1 and (pg_temp.v('usage') ->> 'staff_home_branch')::int = 1
  and (pg_temp.v('usage') ->> 'role_assignments')::int = 1 and (pg_temp.v('usage') ->> 'total')::int = 5,
  'archive check counts sub-units, members, managers, home-branch staff and branch-limited roles');
select pg_temp.check(pg_temp.error_of(format('select public.branch_archive(%L)', pg_temp.id('x'))) = 'org_unit_not_empty',
  'a branch in use cannot be archived');
select pg_temp.check(pg_temp.error_of(format('select public.branch_move_contents(%L, %L)', pg_temp.id('x'), pg_temp.id('x'))) = 'org_unit_invalid',
  'moving to the same branch is refused');
select public.branch_move_contents(pg_temp.id('x'), pg_temp.id('y'));
select pg_temp.check((public.branch_archive_check(pg_temp.id('x')) ->> 'total')::int = 0, 'after moving, nothing uses the old branch');
reset role;
select pg_temp.check((select branch_id from public.role_assignments where institution_id = :inst_a and id = pg_temp.id('asg')) = pg_temp.id('y'),
  'the branch-limited role now covers the new branch');
select pg_temp.check((select branch_id from public.institution_members where institution_id = :inst_a and user_id = :user_a) = pg_temp.id('y'),
  'home branch moved');
select pg_temp.check((select parent_id from public.org_units where institution_id = :inst_a and id = pg_temp.id('team')) = pg_temp.id('y'),
  'sub-units moved with their subtree');
select pg_temp.check(exists (select 1 from public.user_access where institution_id = :inst_a and user_id = :user_a
  and pg_temp.id('y') = any (branch_ids)), 'access rebuilt for the new branch');
select pg_temp.act_as(pg_temp.claims_for(:user_owner));
select public.branch_archive(pg_temp.id('x'));
reset role;
select pg_temp.check((select archived_at is not null from public.org_units where id = pg_temp.id('x')), 'then the branch is archived');
select pg_temp.check(exists (select 1 from public.audit_log where institution_id = :inst_a and action = 'branch.contents_moved'
  and target_id = pg_temp.id('x')::text and (before ->> 'staff_home_branch')::int = 1 and after ->> 'to_name' = 'South campus'),
  'the move is audited with the counts and the target');

-- 3. Terminology.
select pg_temp.act_as(pg_temp.claims_for(:user_owner));
insert into out select 'forms', public.label_bn_forms('client', 'প্রশিক্ষণার্থী', '{}');
select pg_temp.check(pg_temp.v('forms') ->> 'plural' = 'প্রশিক্ষণার্থীরা' and pg_temp.v('forms') ->> 'objective' = 'প্রশিক্ষণার্থীকে',
  'Bangla forms preview: plural and object form derived from the base word');
select pg_temp.check(public.label_bn_forms('client', 'প্রশিক্ষণার্থী', '{"plural":"প্রশিক্ষণার্থীগণ"}') ->> 'plural' = 'প্রশিক্ষণার্থীগণ',
  'a manual form wins in the preview');
insert into out select 'ver0', to_jsonb((select settings_version from public.institution_settings_state where institution_id = :inst_a));
select public.label_set('client', 'Trainee', 'Trainees', '{"base":"প্রশিক্ষণার্থী"}');
select public.label_set('caller', 'Telecaller', 'Telecallers', '{"base":"টেলিকলার"}');
select pg_temp.check(pg_temp.error_of('select public.label_set(''client'', ''A very very very very long word for a menu'', ''x'', ''{"base":"ক"}'')') = 'label_too_long',
  'length limit enforced on the server');
select pg_temp.check(public.label_reset('caller') -> 'label' ->> 'en_singular' = 'Caller', 'reset one word');
reset role;
select pg_temp.check(exists (select 1 from public.audit_log where institution_id = :inst_a and action = 'label.changed' and target_id = 'caller'
  and before ->> 'en_singular' = 'Telecaller' and after ->> 'en_singular' = 'Caller'), 'reset audited with old and new values');
select pg_temp.act_as((pg_temp.claims_for(:user_platform) || '{"aal":"aal2"}'));
select public.label_lock(:inst_a, 'doc.receipt_title', true);
reset role;
select pg_temp.act_as(pg_temp.claims_for(:user_owner));
select pg_temp.check(pg_temp.error_of('select public.label_set(''doc.receipt_title'', ''Bill'', ''Bills'', ''{"base":"বিল"}'')') = 'label_locked',
  'a locked word cannot be renamed');
insert into out select 'all', public.label_reset_all();
select pg_temp.check((pg_temp.v('all') ->> 'reset')::int = 1, 'reset all: the renamed word is reset, the locked one stays');
reset role;
select pg_temp.check(not exists (select 1 from public.institution_labels where institution_id = :inst_a and key = 'client')
  and exists (select 1 from public.institution_labels where institution_id = :inst_a and key = 'doc.receipt_title' and locked_by_platform),
  'reset all leaves locked words');
select pg_temp.check(exists (select 1 from public.audit_log where institution_id = :inst_a and action = 'label.changed' and target_id = 'client'
  and reason = 'reset all to default' and before ->> 'en_singular' = 'Trainee' and after ->> 'en_singular' = 'Student'),
  'reset all audited per word with old and new values');
select pg_temp.check((select settings_version from public.institution_settings_state where institution_id = :inst_a) > (pg_temp.v('ver0'))::bigint,
  'every change bumps the settings version (other devices reload the words)');
select pg_temp.check(exists (select 1 from public.domain_events where institution_id = :inst_a and event_key = 'label.changed'
  and payload ->> 'key' = 'client' and payload ->> 'en_singular' = 'Student'), 'resets are emitted as label.changed');

rollback;
