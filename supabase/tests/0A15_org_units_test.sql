-- 0A.15 tests: branches and the org-unit tree — create / move / archive rules, managers and members, the whole tree in
-- one call, branch gate, isolation, events and audit, and subtree speed with 500 units.
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
create function pg_temp.error_detail(p_sql text) returns text language plpgsql as $$
declare d text;
begin execute p_sql; return ''; exception when others then get stacked diagnostics d = pg_exception_detail; return sqlerrm || ' | ' || coalesce(d, ''); end $$;
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
update public.profiles set last_active_institution_id = null where user_id in (:user_a, :user_b);

-- 1. Gate and permissions.
select pg_temp.act_as(pg_temp.claims_for(:user_a));
select pg_temp.check(public.branches_enabled() = false, 'branches are off by default (placeholder until plans, 0B)');
select pg_temp.check(pg_temp.error_of('select public.org_unit_create(''Sales'', ''department'')') like 'permission_denied%',
  'staff cannot change the organisation before permissions exist');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:user_platform));
select pg_temp.check(pg_temp.error_of(format('select public.branch_create(%L, p_institution_id => %L)', 'Dhanmondi', :inst_a))
  like 'branches_disabled%', 'a branch cannot be created while branches are off');
select public.setting_set('branches_enabled', 'true', :inst_a);

-- 2. Three branches, each with a department and a team, managers assigned (Done-when).
insert into ids select 'b' || n, public.branch_create('Campus ' || n, 'Road ' || n, '০১৭১১-২২৩৩৪' || n, :user_a, :inst_a) from generate_series(1, 3) n;
insert into ids select 'd' || n, public.org_unit_create('Admissions ' || n, 'department', pg_temp.id('b' || n), :inst_a) from generate_series(1, 3) n;
insert into ids select 't' || n, public.org_unit_create('Callers ' || n, 'team', pg_temp.id('d' || n), :inst_a) from generate_series(1, 3) n;
select public.set_manager(pg_temp.id('b' || n), :user_a, true, :inst_a) from generate_series(1, 3) n;
select public.set_manager(pg_temp.id('t1'), :user_both, true, :inst_a);
select public.org_unit_add_member(pg_temp.id('t1'), :user_both, :inst_a);
select pg_temp.check(pg_temp.error_of(format('select public.org_unit_create(%L, %L, %L, %L)', 'X', 'branch', pg_temp.id('b1'), :inst_a))
  like 'org_unit_invalid%', 'a branch can only be created as a branch, directly under the institution');
select pg_temp.check(pg_temp.error_of(format('select public.org_unit_move(%L, %L, %L)', pg_temp.id('b2'), pg_temp.id('d1'), :inst_a))
  like 'org_unit_invalid%', 'a branch cannot be moved under another unit');
select pg_temp.check(pg_temp.error_of(format('select public.org_unit_add_member(%L, %L, %L)', pg_temp.id('t1'), :user_b, :inst_a))
  like 'not_a_member%', 'only members of the institution can join a unit');
select pg_temp.check(pg_temp.error_of(format('select public.org_unit_create(%L, %L, %L, %L)', 'Callers 1', 'team', pg_temp.id('d1'), :inst_a))
  like '%org_units_sibling_name_idx%', 'two active units with the same name under one parent are refused');
reset role;
select pg_temp.check((select phone from public.branches where org_unit_id = pg_temp.id('b1')) = '01711223341',
  'a branch phone typed with Bangla digits is stored normalised');
select pg_temp.check((select branch_id from public.org_units where id = pg_temp.id('t2')) = pg_temp.id('b2'),
  'units know their branch (team → department → branch)');

select pg_temp.act_as(pg_temp.claims_for(:user_a));
insert into out select 'tree', public.org_tree_get();
reset role;
select pg_temp.check(jsonb_array_length((select v -> 'units' from out where k = 'tree')) = 9, 'the whole tree comes in one call (9 units)');
select pg_temp.check((select count(*) from out, jsonb_array_elements(v -> 'units') u where k = 'tree' and u ->> 'kind' = 'branch'
  and u -> 'branch' ->> 'address' like 'Road %' and jsonb_array_length(u -> 'managers') = 1) = 3,
  '...with branch details and managers');
select pg_temp.check((select (u ->> 'depth')::int from out, jsonb_array_elements(v -> 'units') u where k = 'tree' and u ->> 'id' = pg_temp.id('t1')::text) = 2,
  '...and the depth of each unit');

-- 3. Moves keep the closure right; cycles are refused.
select pg_temp.act_as(pg_temp.claims_for(:user_platform));
select pg_temp.check(pg_temp.error_of(format('select public.org_unit_move(%L, %L, %L)', pg_temp.id('d1'), pg_temp.id('t1'), :inst_a))
  like 'org_unit_cycle%', 'moving a unit under its own team is refused (no cycles)');
select pg_temp.check(pg_temp.error_of(format('select public.org_unit_move(%L, %L, %L)', pg_temp.id('d1'), pg_temp.id('d1'), :inst_a))
  like 'org_unit_cycle%', 'moving a unit under itself is refused');
select public.org_unit_move(pg_temp.id('t1'), pg_temp.id('d2'), :inst_a);
reset role;
select pg_temp.check(pg_temp.id('t1') in (select app.org_subtree(:inst_a, pg_temp.id('b2'))) and pg_temp.id('t1') not in (select app.org_subtree(:inst_a, pg_temp.id('b1'))),
  'after a move the team is in the new branch''s subtree and not in the old one');
select pg_temp.check((select branch_id from public.org_units where id = pg_temp.id('t1')) = pg_temp.id('b2'), '...and its branch changed');
select pg_temp.check((select count(*) from public.org_unit_closure where institution_id = :inst_a and descendant_id = pg_temp.id('t1')) = 3
  and (select array_agg(depth order by depth) from public.org_unit_closure where institution_id = :inst_a and descendant_id = pg_temp.id('t1')) = '{0,1,2}',
  '...with exactly one closure row per ancestor (itself, the new department, the new branch)');

-- 4. Archive, never delete: only empty units.
select pg_temp.act_as(pg_temp.claims_for(:user_platform));
select pg_temp.check(pg_temp.error_of(format('select public.org_unit_archive(%L, %L)', pg_temp.id('t1'), :inst_a))
  like 'org_unit_not_empty%', 'a unit with members or managers cannot be archived');
select pg_temp.check(pg_temp.error_of(format('select public.branch_archive(%L, %L)', pg_temp.id('b3'), :inst_a))
  like 'org_unit_not_empty%', 'a branch with units in it cannot be archived');
select public.org_unit_remove_member(pg_temp.id('t1'), :user_both, :inst_a);
select public.set_manager(pg_temp.id('t1'), :user_both, false, :inst_a);
select public.org_unit_archive(pg_temp.id('t1'), :inst_a);
reset role;
select pg_temp.check((select archived_at is not null from public.org_units where id = pg_temp.id('t1')), 'once empty, a unit is archived');
select pg_temp.check(pg_temp.error_of(format('delete from public.org_units where id = %L', pg_temp.id('b1'))) like '%foreign key%',
  'deleting a branch that still has units, details or managers is refused by the database');
update public.institution_members set branch_id = pg_temp.id('b2') where institution_id = :inst_a and user_id = :user_a;
select pg_temp.act_as(pg_temp.claims_for(:user_platform));
select public.org_unit_archive(pg_temp.id('t2'), :inst_a);
select public.org_unit_archive(pg_temp.id('d2'), :inst_a);
select public.set_manager(pg_temp.id('b2'), :user_a, false, :inst_a);
select pg_temp.check(pg_temp.error_detail(format('select public.branch_archive(%L, %L)', pg_temp.id('b2'), :inst_a))
  like 'org_unit_not_empty | move these first: staff_home_branch', 'a branch that is still someone''s home branch cannot be archived (move them first)');
reset role;

-- 5. Isolation and the branch gate in answers.
select pg_temp.act_as(pg_temp.claims_for(:user_b));
select pg_temp.check((select count(*) from public.org_units) = 0 and jsonb_array_length(public.org_tree_get() -> 'units') = 0,
  'B sees none of A''s units');
select pg_temp.check(pg_temp.error_of(format('select public.org_unit_create(%L, %L, null, %L)', 'X', 'team', :inst_a)) like 'permission_denied%',
  'B cannot change A''s organisation');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:user_platform));
select public.setting_set('branches_enabled', 'false', :inst_a);
reset role;
select pg_temp.act_as(pg_temp.claims_for(:user_a));
select pg_temp.check(not exists (select 1 from jsonb_array_elements(public.org_tree_get() -> 'units') u where u ? 'branch' or u ? 'branch_id'),
  'with branches off, branch fields are left out of the answer');
reset role;

-- 6. Events and audit.
select pg_temp.check((select count(*) from public.domain_events where institution_id = :inst_a and event_key = 'branch.created' and occurred_at >= now()) = 3
  and exists (select 1 from public.domain_events where institution_id = :inst_a and event_key = 'org_unit.moved')
  and exists (select 1 from public.audit_log where institution_id = :inst_a and action = 'org_unit.archived'),
  'branch and org-unit changes are emitted and audited');

-- 7. Speed: subtree of a branch with 500 units under it (Ch 12.7 #6; target < 5 ms).
insert into ids values ('big', gen_random_uuid());
insert into public.org_units (institution_id, id, kind, name) values (:inst_a, pg_temp.id('big'), 'department', 'Big');
insert into public.org_units (institution_id, id, parent_id, kind, name)
select :inst_a, ('00000000-0000-4000-8000-' || lpad(d::text, 12, '0'))::uuid, pg_temp.id('big'), 'department', 'D' || d from generate_series(1, 20) d;
insert into public.org_units (institution_id, parent_id, kind, name)
select :inst_a, ('00000000-0000-4000-8000-' || lpad(d::text, 12, '0'))::uuid, 'team', 'T' || t
from generate_series(1, 20) d, generate_series(1, 24) t;
analyze public.org_unit_closure;
create function pg_temp.subtree_ms(p_inst uuid, p_unit uuid) returns numeric language plpgsql as $$
declare
  t0 timestamptz; n integer; best numeric := 1e9;
begin
  for i in 1..10 loop
    t0 := clock_timestamp();
    select count(*) into n from app.org_subtree(p_inst, p_unit);
    best := least(best, extract(epoch from clock_timestamp() - t0) * 1000);
  end loop;
  return best;
end $$;
select pg_temp.check((select count(*) from app.org_subtree(:inst_a, pg_temp.id('big'))) = 501, '501 units in the subtree (500 + itself)');
select pg_temp.check(pg_temp.subtree_ms(:inst_a, pg_temp.id('big')) < 5, 'subtree lookup for 500 units under 5 ms');
rollback;
