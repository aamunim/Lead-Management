-- 0B.07 tests: valid transitions only, history and audit; approval starts the trial; read-only refuses writes by people
-- on the server (reads and the full export still work; platform staff can still fix things); suspended refuses
-- sign-in to that institution only (D25); duplicate and trial-abuse flags; the full export holds only the institution's
-- rows; closing needs an export and purges after the notice period without touching anyone else; permissions.
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
\set inst_b '''b0000000-0000-4000-8000-00000000000b'''
\set user_a '''11111111-1111-4111-8111-111111111111'''
\set both '''33333333-3333-4333-8333-333333333333'''
\set owner '''77777777-7777-4777-8777-777777777777'''
\set master '''55555555-5555-4555-8555-555555555555'''
\set support '''e1000000-0000-4000-8000-0000000000e1'''
\set billing '''e2000000-0000-4000-8000-0000000000e2'''
update public.profiles set last_active_institution_id = null where user_id in (:user_a, :both);

-- 1. Transitions, approval, history.
insert into public.institutions (id, slug, name, eiin, contact_phone, created_by)
values ('d0000000-0000-4000-8000-0000000000e1', 'life-new', 'New Ideal School', '123456', '01711000099', :owner);
update public.institution_plan set expires_at = now() - interval '1 day' where institution_id = 'd0000000-0000-4000-8000-0000000000e1';
select pg_temp.act_as(pg_temp.claims_for(:master, 'aal2'));
select pg_temp.check(pg_temp.error_of('select public.platform_institution_set_status(''d0000000-0000-4000-8000-0000000000e1'', ''read_only'', ''x'')')
  = 'status_transition_invalid', 'pending cannot become read only');
select pg_temp.check(pg_temp.error_of(format('select public.platform_institution_set_status(%L, ''suspended'')', :inst_b)) = 'reason_required',
  'suspending needs a reason');
select public.platform_institution_set_status('d0000000-0000-4000-8000-0000000000e1', 'trial', 'checked the EIIN');
reset role;
select pg_temp.check((select status = 'trial' and approved_by = :master from public.institutions where id = 'd0000000-0000-4000-8000-0000000000e1')
  and (select expires_at > now() + interval '13 days' from public.institution_plan where institution_id = 'd0000000-0000-4000-8000-0000000000e1'),
  'approval: pending → trial, the trial runs from approval');
select pg_temp.check(exists (select 1 from public.institution_status_history where institution_id = 'd0000000-0000-4000-8000-0000000000e1'
  and from_status = 'pending' and to_status = 'trial' and reason = 'checked the EIIN')
  and exists (select 1 from public.platform_audit_log where action = 'institution.status_changed' and institution_id = 'd0000000-0000-4000-8000-0000000000e1')
  and exists (select 1 from public.domain_events where event_key = 'institution.status_changed' and institution_id = 'd0000000-0000-4000-8000-0000000000e1'),
  'history, platform audit and event written');

-- 2. Read only: writes by people refused on the server; reads and the export work; platform staff can still act.
select pg_temp.act_as(pg_temp.claims_for(:master, 'aal2'));
select public.platform_institution_set_status(:inst_a, 'read_only', 'payment overdue');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:owner));
select pg_temp.check(pg_temp.error_of('select public.setting_set(''fees'', ''{"enabled": true}'')') = 'institution_read_only', 'read only: a setting change fails');
select pg_temp.check(pg_temp.error_of('select public.label_set(''client'', ''Trainee'', ''Trainees'', ''{"base":"প্রশিক্ষণার্থী"}'')') = 'institution_read_only',
  'read only: renaming a word fails');
select pg_temp.check(pg_temp.error_of('select public.custom_field_save(''lead'', null, ''{"key":"ro","label":{"en":"R","bn":"R"},"type":"text"}'')') = 'institution_read_only',
  'read only: adding a field fails');
select pg_temp.check(public.get_setting('fees') ? 'value', 'read only: reading still works');
insert into out select 'export', public.institution_export_create();
select pg_temp.check((pg_temp.v('export') ->> 'size_bytes')::int > 0, 'read only: the full export still works');
select pg_temp.check((public.institution_status() ->> 'status') = 'read_only', 'the institution sees its status (banner)');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:master, 'aal2'));
select pg_temp.check(pg_temp.error_of(format('select public.label_lock(%L, ''doc.receipt_title'', true, ''legal'')', :inst_a)) = '',
  'platform staff can still act on a read-only institution');
select public.platform_institution_set_status(:inst_a, 'active', 'paid');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:owner));
select pg_temp.check(pg_temp.error_of('select public.setting_set(''fees'', ''{"enabled": true}'')') = '', 'active again: writes work; nothing was deleted');
reset role;

-- 3. Suspended: no sign-in to that institution; other memberships of the same person work (D25).
select pg_temp.act_as(pg_temp.claims_for(:master, 'aal2'));
select public.platform_institution_set_status(:inst_a, 'suspended', 'abuse report');
reset role;
select pg_temp.check(pg_temp.claims_for(:owner) ->> 'active_institution_id' is null, 'a person only in A gets no active institution');
select pg_temp.check(pg_temp.claims_for(:both) ->> 'active_institution_id' = :inst_b, 'a person in A and B is signed in to B');
select pg_temp.act_as(jsonb_build_object('sub', :owner, 'role', 'authenticated', 'active_institution_id', :inst_a,
  'access_version', (select access_version from public.institution_members where institution_id = :inst_a and user_id = :owner)));
select pg_temp.check(pg_temp.error_of('select public.get_setting(''fees'')') = 'institution_suspended', 'an old token for A is refused');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:master, 'aal2'));
select public.platform_institution_set_status(:inst_a, 'active', 'resolved');
reset role;

-- 4. Duplicates and trial abuse (Proposed).
insert into public.institutions (id, slug, name, eiin, contact_phone, created_by, status) values
  ('d0000000-0000-4000-8000-0000000000e2', 'life-dup', 'Another school', '123456', null, :owner, 'pending'),
  ('d0000000-0000-4000-8000-0000000000e3', 'life-name', 'New Ideal School', null, '01711000099', :owner, 'pending');
select pg_temp.check((select jsonb_agg(x ->> 'match' order by x ->> 'match') from jsonb_array_elements(app.institution_duplicates('d0000000-0000-4000-8000-0000000000e1')) x)
  = '["eiin", "name_phone"]'::jsonb, 'duplicates: the same EIIN, and the same name with the same phone');
select pg_temp.check((app.trial_abuse('d0000000-0000-4000-8000-0000000000e3') ->> 'flagged')::boolean, 'three open trials by one person are flagged (limit 2)');
select pg_temp.act_as(pg_temp.claims_for(:master, 'aal2'));
select pg_temp.check(jsonb_array_length(public.platform_approval_queue()) >= 2, 'pending institutions are in the approval queue');
select pg_temp.check((select x ->> 'id' from jsonb_array_elements(public.platform_institutions_list()) x limit 1) is not null
  and (select bool_and(jsonb_array_length(x -> 'problems') > 0) from (select x from jsonb_array_elements(public.platform_institutions_list()) x limit 2) y),
  'the list shows institutions with problems first');
reset role;

-- 5. The full export holds only A's rows (every tenant table; the two-membership person included only as A's member).
select pg_temp.check(not exists (
  select 1 from public.institution_exports e, jsonb_each(e.content -> 'tables') t, jsonb_array_elements(t.value) row
   where e.institution_id = :inst_a and (row ->> 'institution_id')::uuid <> :inst_a), 'the export contains only the institution''s rows');
select pg_temp.check((select (content -> 'counts' ->> 'public.institution_members')::int from public.institution_exports where institution_id = :inst_a)
  = (select count(*) from public.institution_members where institution_id = :inst_a), 'every member row is in it');

-- 6. Closing needs a recent export; purge after the notice period touches nothing else.
select pg_temp.act_as(pg_temp.claims_for(:billing, 'aal2'));
select pg_temp.check(pg_temp.error_of(format('select public.platform_institution_set_status(%L, ''closed'', ''left'')', :inst_b)) = 'permission_denied',
  'only platform.institutions_close may close');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:support, 'aal2'));
select pg_temp.check(pg_temp.error_of(format('select public.platform_institution_set_status(%L, ''suspended'', ''x'')', :inst_b)) = 'permission_denied',
  'Support (view only) cannot change a status');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:master, 'aal2'));
select pg_temp.check(pg_temp.error_of(format('select public.platform_institution_set_status(%L, ''closed'', ''left'')', :inst_b)) = 'export_required',
  'closing without a full export is impossible');
select public.institution_export_create(:inst_b);
select public.platform_institution_set_status(:inst_b, 'closed', 'left the platform');
reset role;
select pg_temp.check((select purge_after between now() + interval '89 days' and now() + interval '91 days' from public.institutions where id = :inst_b)
  and exists (select 1 from public.domain_events where event_key = 'institution.closed' and institution_id = :inst_b), 'closed: purge scheduled, institution.closed emitted');
insert into out select 'a_rows', to_jsonb((select count(*) from public.institution_members where institution_id = :inst_a));
update public.institutions set purge_after = now() - interval '1 minute' where id = :inst_b;
insert into out select 'purged', to_jsonb(app.institution_purge_due());
select pg_temp.check((pg_temp.v('purged'))::int = 1 and not exists (select 1 from public.institutions where id = :inst_b)
  and not exists (select 1 from public.institution_members where institution_id = :inst_b), 'after the notice period the institution''s data is purged');
select pg_temp.check((select count(*) from public.institution_members where institution_id = :inst_a) = (pg_temp.v('a_rows'))::int
  and exists (select 1 from public.platform_audit_log where action = 'institution.purged'), 'nothing else is affected; the purge is in the platform audit');

-- 7. Only the Super Admin (or platform staff) exports.
select pg_temp.act_as(pg_temp.claims_for(:user_a));
select pg_temp.check(pg_temp.error_of('select public.institution_export_create()') = 'permission_denied', 'staff cannot export the institution');
reset role;

rollback;
