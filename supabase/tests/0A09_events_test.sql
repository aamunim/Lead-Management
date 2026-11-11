-- 0A.09 tests: event log (catalogue + schema-checked payloads), append-only audit log, writers hooked in,
-- extension on/off per institution, dispatcher, and removing an extension without breaking the core.
-- Needs the example extension applied (scripts/apply-extensions.sh).
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
create function pg_temp.as_backend() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'service_role', true);
end $$;
create function pg_temp.error_of(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return ''; exception when others then return sqlerrm; end $$;
grant execute on all functions in schema pg_temp to authenticated, service_role;
create temp table out (k text primary key, v jsonb);
grant all on out to authenticated, service_role;

\set inst_a '''a0000000-0000-4000-8000-00000000000a'''
\set inst_b '''b0000000-0000-4000-8000-00000000000b'''
\set user_a '''11111111-1111-4111-8111-111111111111'''
\set user_b '''22222222-2222-4222-8222-222222222222'''
\set user_both '''33333333-3333-4333-8333-333333333333'''
\set user_platform '''55555555-5555-4555-8555-555555555555'''
update public.profiles set last_active_institution_id = null where user_id in (:user_a, :user_b);
select pg_temp.check(exists (select 1 from public.extensions where key = 'example'),
                     'the example extension is installed (run scripts/apply-extensions.sh after db reset)');
insert into public.setting_definitions (key, scope, schema, default_value, area, description) values
  ('test.event_days', 'institution', '{"type":"integer","minimum":1}', '3', 'settings.followups', 'test');
create temp table base as
  select (select count(*) from public.domain_events) as events, (select count(*) from public.audit_log) as audits;

-- 1. Events: only catalogued keys, payloads checked against the schema, never for another institution.
select pg_temp.check(pg_temp.error_of(format('select app.emit_event(%L, %L, 1, %L, null, %L)', :inst_a, 'no.such_event', 'setting', '{}'))
                     like 'event_unknown%', 'an event key that is not in the catalogue is rejected');
select pg_temp.check(pg_temp.error_of(format('select app.emit_event(%L, %L, 1, %L, null, %L)', :inst_a, 'setting.changed', 'setting', '{"value":1}'))
                     like 'event_payload_invalid%', 'a payload that breaks the event schema is rejected');
select pg_temp.check(pg_temp.error_of(format('select app.emit_event(%L, %L, 1, %L, null, %L)', :inst_a, 'setting.changed', 'secret', '{"key":"k","value":1}'))
                     like 'event_entity_mismatch%', 'an event with the wrong entity type is rejected');
select pg_temp.act_as(pg_temp.claims_for(:user_a));
select pg_temp.check(pg_temp.error_of(format('select app.emit_event(%L, %L, 1, %L, null, %L)', :inst_b, 'setting.changed', 'setting', '{"key":"k","value":1}'))
                     like 'institution_mismatch%', 'a member of A cannot emit an event for B');
select pg_temp.check(pg_temp.error_of(format('select app.audit(%L, %L, %L, null, null, null)', :inst_b, 'setting.changed', 'setting'))
                     like 'institution_mismatch%', 'a member of A cannot write audit entries for B');
select pg_temp.check(pg_temp.error_of('insert into public.audit_log (institution_id, action, target_type) values ('
                     || quote_literal(:inst_a) || ', ''x.y'', ''t'')') like 'permission denied%',
                     'the app cannot insert audit rows directly');
select pg_temp.check(pg_temp.error_of('insert into public.domain_events (institution_id, event_key, event_version, entity_type) values ('
                     || quote_literal(:inst_a) || ', ''setting.changed'', 1, ''setting'')') like 'permission denied%',
                     'the app cannot insert events directly');
select pg_temp.check(pg_temp.error_of('select app.dispatch_events()') like 'permission denied%',
                     'the app cannot run the dispatcher');
reset role;

-- 2. Writers are hooked in: setting / secret / membership changes leave an audit row and an event.
select pg_temp.act_as((pg_temp.claims_for(:user_platform) || '{"aal":"aal2"}'));
select public.setting_set('test.event_days', '5', :inst_a);
select public.setting_reset('test.event_days', :inst_a);
select public.secret_set('sms.test_events.key', 'abcd-efgh-ijkl-mnop-qrst', null, :inst_a);
select public.secret_revoke('sms.test_events.key', :inst_a);
reset role;
select pg_temp.check((select count(*) from public.audit_log where institution_id = :inst_a and action = 'setting.changed'
                      and target_id = 'test.event_days' and actor_user_id = :user_platform and after = '{"value":5}') = 1,
                     'setting_set writes an audit row (who, what, after)');
select pg_temp.check((select count(*) from public.domain_events where institution_id = :inst_a and event_key = 'setting.changed'
                      and payload ->> 'key' = 'test.event_days') = 1, 'setting_set emits setting.changed');
select pg_temp.check((select count(*) from public.audit_log where institution_id = :inst_a and action = 'setting.reset'
                      and target_id = 'test.event_days' and before = '{"value":5}') = 1, 'setting_reset is audited with the old value');
select pg_temp.check((select count(*) from public.domain_events where institution_id = :inst_a and event_key = 'setting.reset') >= 1,
                     'setting_reset emits setting.reset');
select pg_temp.check((select count(*) from public.audit_log where institution_id = :inst_a and action in ('secret.set', 'secret.revoked')
                      and target_id = 'sms.test_events.key') = 2, 'secret set and revoke are audited');
select pg_temp.check(not exists (select 1 from public.audit_log where after::text like '%efgh-ijkl%')
                     and not exists (select 1 from public.domain_events where payload::text like '%efgh-ijkl%'),
                     'a secret value never reaches the audit log or the event log (hint only)');
select pg_temp.check((select count(*) from public.domain_events where institution_id = :inst_b and payload ->> 'key' = 'test.event_days') = 0
                     and (select count(*) from public.audit_log where institution_id = :inst_b and target_id = 'test.event_days') = 0,
                     'changes in A leave nothing in B''s logs');
update public.institution_members set status = 'deactivated' where institution_id = :inst_a and user_id = :user_both;
select pg_temp.check((select count(*) from public.audit_log where institution_id = :inst_a and action = 'membership.status_changed'
                      and target_id = :user_both and after = '{"status":"deactivated"}') = 1, 'deactivating a member is audited');
select pg_temp.check((select count(*) from public.domain_events where institution_id = :inst_a and event_key = 'membership.status_changed'
                      and payload ->> 'to' = 'deactivated' and entity_id = :user_both) = 1, '...and emits membership.status_changed');
update public.institution_members set status = 'active' where institution_id = :inst_a and user_id = :user_both;

-- 3. The audit log is append-only.
select pg_temp.check(pg_temp.error_of('update public.audit_log set reason = ''x''') like 'audit_log_is_append_only%',
                     'audit rows cannot be updated (not even by the owner)');
select pg_temp.check(pg_temp.error_of('delete from public.audit_log') like 'audit_log_is_append_only%',
                     'audit rows cannot be deleted outside an institution purge');
select pg_temp.check(pg_temp.error_of('update public.platform_audit_log set reason = ''x''') like 'audit_log_is_append_only%'
                     or not exists (select 1 from public.platform_audit_log), 'platform audit rows cannot be updated');
savepoint before_purge;
delete from public.institutions where id = :inst_b;
select pg_temp.check((select count(*) from public.audit_log where institution_id = :inst_b) = 0,
                     'deleting an institution still removes its audit rows (cascade is allowed)');
rollback to savepoint before_purge;

-- 4. Reading events and audit: fail-closed for staff until permissions exist (0A.17).
select pg_temp.act_as(pg_temp.claims_for(:user_a));
select pg_temp.check((select count(*) from public.audit_log) = 0 and (select count(*) from public.domain_events) = 0,
                     'staff see no audit rows or events before permissions exist');
select pg_temp.check((select count(*) from public.event_definitions where event_key = 'setting.changed') = 1,
                     'the event catalogue is readable (contract for clients)');
select pg_temp.check(pg_temp.error_of(format('select public.extension_set_enabled(%L, %L, true)', :inst_a, 'example'))
                     like 'permission_denied%', 'staff cannot switch extensions on');
select pg_temp.check(pg_temp.error_of('select public.ext_example_note_add(''hello'')') like 'extension_disabled%',
                     'an extension RPC fails with extension_disabled while the extension is off');
reset role;

-- 5. Extension on for A only: A uses it, B does not, and the core keeps working for both.
select pg_temp.act_as((pg_temp.claims_for(:user_platform) || '{"aal":"aal2"}'));
select pg_temp.check(pg_temp.error_of(format('select public.extension_set_enabled(%L, %L, true)', :inst_a, 'no_such_ext'))
                     like 'extension_unknown%', 'an unknown extension cannot be switched on');
select public.extension_set_enabled(:inst_a, 'example', true);
reset role;
select pg_temp.check((select count(*) from public.audit_log where institution_id = :inst_a and action = 'extension.toggled') >= 1
                     and (select count(*) from public.domain_events where institution_id = :inst_a and event_key = 'extension.toggled') >= 1,
                     'switching an extension is audited and emitted');
select pg_temp.act_as(pg_temp.claims_for(:user_a));
insert into out select 'note', to_jsonb(public.ext_example_note_add('first note of A'));
select pg_temp.check((select count(*) from public.ext_example_notes_list()) = 1, 'A adds and lists its note');
reset role;
select pg_temp.check((select count(*) from public.domain_events where institution_id = :inst_a and event_key = 'example.note_added'
                      and entity_id = (select v #>> '{}' from out where k = 'note')) = 1,
                     'the extension emits its own catalogued event');
select pg_temp.act_as(pg_temp.claims_for(:user_b));
select pg_temp.check(pg_temp.error_of('select public.ext_example_note_add(''x'')') like 'extension_disabled%',
                     'B (extension off) cannot use the extension');
select pg_temp.check((select count(*) from public.ext_example_notes_list()) = 0, 'B sees none of A''s notes');
select pg_temp.check((select count(*) from ext_example.notes) = 0, '...not even through the table');
select pg_temp.check(public.settings_get_all() ? 'values', 'the core keeps working for B');
reset role;

-- 6. Dispatcher: the extension's listener runs only for institutions that have the extension on; errors are kept.
update public.domain_events set processed_at = now() where processed_at is null;
select pg_temp.act_as((pg_temp.claims_for(:user_platform) || '{"aal":"aal2"}'));
select public.setting_set('test.event_days', '6', :inst_a);
select public.setting_set('test.event_days', '7', :inst_a);
select public.setting_set('test.event_days', '8', :inst_b);
reset role;
create function pg_temp.failing_listener(p_event jsonb) returns void language plpgsql as $$
begin raise exception 'listener exploded'; end $$;
grant execute on function pg_temp.failing_listener(jsonb) to service_role;
insert into public.event_listeners (listener_key, event_key, function_name)
values ('test.failing', 'setting.changed', 'pg_temp.failing_listener');
select pg_temp.as_backend();
insert into out select 'dispatched', to_jsonb(app.dispatch_events());
reset role;
select pg_temp.check((select (v #>> '{}')::int from out where k = 'dispatched') = 3, 'the dispatcher processes pending events');
select pg_temp.check((select changes from ext_example.setting_change_counts where institution_id = :inst_a) = 2,
                     'the extension listener ran for A (extension on)');
select pg_temp.check(not exists (select 1 from ext_example.setting_change_counts where institution_id = :inst_b),
                     'the extension listener did not run for B (extension off)');
select pg_temp.check((select count(*) from public.domain_events where processed_at is null) = 0,
                     'a failing listener does not block the queue');
select pg_temp.check((select count(*) from public.domain_events where listener_errors::text like '%listener exploded%') = 3,
                     'listener errors are recorded on the event');
delete from public.event_listeners where listener_key = 'test.failing';

-- 7. Switching it off: A's data is hidden, the RPC refuses, the core keeps working.
select pg_temp.act_as((pg_temp.claims_for(:user_platform) || '{"aal":"aal2"}'));
select public.extension_set_enabled(:inst_a, 'example', false);
reset role;
select pg_temp.act_as(pg_temp.claims_for(:user_a));
select pg_temp.check(pg_temp.error_of('select public.ext_example_note_add(''x'')') like 'extension_disabled%',
                     'after switching off, the RPC refuses');
select pg_temp.check((select count(*) from public.ext_example_notes_list()) = 0, '...and the data is hidden (kept, not deleted)');
select pg_temp.check(public.settings_get_all() -> 'values' ->> 'test.event_days' = '7', 'the core keeps working for A');
reset role;

-- 8. Removing the extension completely never breaks the core.
\i supabase/extensions/example/uninstall.sql
select pg_temp.check(to_regnamespace('ext_example') is null and to_regproc('public.ext_example_note_add') is null,
                     'uninstall removes the schema and its public RPCs');
select pg_temp.check(not exists (select 1 from public.event_listeners where extension_key = 'example')
                     and not exists (select 1 from public.institution_extensions where extension_key = 'example'),
                     '...and its listeners and switches');
select pg_temp.check((select count(*) from public.domain_events where event_key = 'example.note_added') >= 1,
                     'its emitted events stay as history');
select pg_temp.act_as((pg_temp.claims_for(:user_platform) || '{"aal":"aal2"}'));
select public.setting_set('test.event_days', '9', :inst_a);
reset role;
select pg_temp.as_backend();
insert into out select 'after_uninstall', to_jsonb(app.dispatch_events());
reset role;
select pg_temp.check((select (v #>> '{}')::int from out where k = 'after_uninstall') >= 1,
                     'the core writes and dispatches events without the extension');
rollback;
