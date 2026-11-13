-- 0B.08 tests: no support entry without platform.support_access, a reason and a time limit; the token carries the
-- institution and the session; read only by default (writes refused on the server), sensitive permissions never
-- given; scoped strictly to one institution; edit mode needs another Master Admin; every action is in both audit logs;
-- an expired session is refused; the institution's Super Admin sees the support access log.
\set ON_ERROR_STOP on
begin;
create function pg_temp.check(cond boolean, what text) returns void language plpgsql as $$
begin
  if cond is distinct from true then raise exception 'FAILED: %', what; end if;
  raise notice 'ok - %', what;
end $$;
create function pg_temp.claims_for(p_user uuid, p_aal text default 'aal2') returns jsonb language sql as $$
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
\set owner '''77777777-7777-4777-8777-777777777777'''
\set master '''55555555-5555-4555-8555-555555555555'''
\set support '''e1000000-0000-4000-8000-0000000000e1'''
\set billing '''e2000000-0000-4000-8000-0000000000e2'''
insert into public.app_settings (institution_id, key, value) values (:inst_b, 'receipt_prefix', '"B-SECRET"')
  on conflict (institution_id, key) do update set value = excluded.value;

-- 1. Who may enter, and only with a reason and a time limit.
select pg_temp.act_as(pg_temp.claims_for(:support));
select pg_temp.check(pg_temp.error_of(format('select public.support_session_start(%L, ''check settings'', 30)', :inst_a)) = 'permission_denied',
  'Support without setup rights cannot enter');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:master));
select pg_temp.check(pg_temp.error_of(format('select public.support_session_start(%L, '''', 30)', :inst_a)) = 'reason_required', 'no entry without a reason');
select pg_temp.check(pg_temp.error_of(format('select public.support_session_start(%L, ''check settings'', 600)', :inst_a)) = 'support_minutes_invalid',
  'no entry beyond the time limit');
insert into out select 'session', public.support_session_start(:inst_a, 'help with the fee settings', 30);
reset role;

-- 2. The token: the institution and the session; read only by default.
insert into out select 'claims', pg_temp.claims_for(:master);
select pg_temp.check(pg_temp.v('claims') ->> 'active_institution_id' = :inst_a
  and pg_temp.v('claims') ->> 'support_session_id' = pg_temp.v('session') ->> 'id', 'the token carries the institution and the session');
select pg_temp.act_as(pg_temp.v('claims'));
select pg_temp.check(app.auth_institution_id() = :inst_a and app.require_active_session() = :inst_a and app.support_mode() = 'read_only',
  'the session stands in for a membership (read only)');
select pg_temp.check(app.can('settings.users') and not app.can('custom_field.view_sensitive') and not app.can('sensitive_field.view'),
  'non-sensitive permissions yes, sensitive ones never');
select pg_temp.check(public.get_setting('receipt_prefix') ? 'value', 'reading works');
select pg_temp.check(pg_temp.error_of('select public.setting_set(''fees'', ''{"enabled": true}'')') = 'support_read_only', 'writing is refused (read only)');

-- 3. Scoped strictly to A (leak case 0B.08-T7).
select pg_temp.check(not exists (select 1 from public.app_settings where institution_id = :inst_b), 'B''s rows are invisible');
select pg_temp.check(pg_temp.error_of(format('select public.setting_set(''fees'', ''{"enabled": true}'', %L)', :inst_b)) <> '',
  'and B cannot be written by naming it');
reset role;

-- 4. Edit mode: requested with a reason, approved by another Master Admin; writes are then logged with the session.
select pg_temp.act_as(pg_temp.v('claims'));
select public.support_edit_request('the fee setting must be fixed now');
select pg_temp.check(pg_temp.error_of(format('select public.support_edit_approve(%L)', pg_temp.v('session') ->> 'id')) = 'self_approval',
  'nobody approves their own edit request');
reset role;
update public.platform_members set platform_role = 'master_admin' where user_id = :billing;
select pg_temp.act_as(pg_temp.claims_for(:billing));
select pg_temp.check(jsonb_array_length(public.support_edit_requests()) = 1, 'Master Admins see the open edit request');
select public.support_edit_approve((pg_temp.v('session') ->> 'id')::uuid);
reset role;
select pg_temp.act_as(pg_temp.v('claims'));
select pg_temp.check(app.support_mode() = 'edit' and pg_temp.error_of('select public.setting_set(''fees'', ''{"enabled": true}'')') = '',
  'approved edit mode: the write works');
reset role;
select pg_temp.check(exists (select 1 from public.platform_audit_log where action = 'support.write' and support_session_id = (pg_temp.v('session') ->> 'id')::uuid
  and target_type = 'public.app_settings'), 'every write in edit mode is in the platform audit with the session');
select pg_temp.check((select count(*) from public.audit_log where institution_id = :inst_a and support_session_id = (pg_temp.v('session') ->> 'id')::uuid
  and action in ('support.started', 'support.edit_requested', 'support.edit_approved')) = 3, 'start, request and approval are in the institution''s audit');

-- 5. The institution sees it; the panel Audit tab lists it.
select pg_temp.act_as(pg_temp.claims_for(:owner, 'aal1'));
insert into out select 'log', public.support_access_log();
select pg_temp.check(pg_temp.v('log') -> 0 ->> 'reason' = 'help with the fee settings' and pg_temp.v('log') -> 0 ->> 'by' = 'platform.admin@example.test'
  and (pg_temp.v('log') -> 0 ->> 'writes')::int >= 1, 'the Super Admin sees who entered, why and what was changed');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:user_a, 'aal1'));
select pg_temp.check(pg_temp.error_of('select public.support_access_log()') = 'permission_denied', 'staff without settings.security do not');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:support));
select pg_temp.check(exists (select 1 from jsonb_array_elements(public.platform_institution_audit(:inst_a)) x where x ->> 'action' = 'support.started'),
  'the panel Audit tab lists the entry');
reset role;

-- 6. Expiry and ending.
update public.support_sessions set started_at = now() - interval '10 minutes', expires_at = now() - interval '9 minutes'
 where id = (pg_temp.v('session') ->> 'id')::uuid;
select pg_temp.act_as(pg_temp.v('claims'));
select pg_temp.check(pg_temp.error_of('select public.get_setting(''fees'')') = 'support_session_ended' and app.auth_institution_id() is null,
  'an expired session token is refused');
reset role;
select pg_temp.check(pg_temp.claims_for(:master) ->> 'support_session_id' is null, 'after expiry the next token has no support session');
select pg_temp.act_as(pg_temp.claims_for(:master));
select public.support_session_start(:inst_a, 'second look at the users', 15);
select public.support_session_end();
reset role;
select pg_temp.check(not exists (select 1 from public.support_sessions where platform_user_id = :master and ended_at is null)
  and exists (select 1 from public.audit_log where institution_id = :inst_a and action = 'support.ended'), 'leaving ends the session and is audited');

rollback;
