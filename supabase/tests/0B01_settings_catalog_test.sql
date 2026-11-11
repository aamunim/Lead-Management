-- 0B.01 tests: the Appendix A catalog (neutral names, labels, owners, valid defaults, areas are real permissions),
-- dropped keys and tables absent, area permissions per key (RPC as a real role), history and rollback, read RPCs
-- with the value's source, keys stored elsewhere, product keys, history isolation.
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
grant all on ids to authenticated;
create function pg_temp.id(p_k text) returns uuid language sql as $$ select id from ids where k = p_k $$;
grant execute on function pg_temp.id(text) to authenticated;

\set inst_a '''a0000000-0000-4000-8000-00000000000a'''
\set user_a '''11111111-1111-4111-8111-111111111111'''
\set user_b '''22222222-2222-4222-8222-222222222222'''
\set user_owner '''77777777-7777-4777-8777-777777777777'''
update public.profiles set last_active_institution_id = null where user_id in (:user_a, :user_b);

-- 1. The catalog.
select pg_temp.check((select count(*) from public.setting_definitions where key in (
  'activity','reports','scorecard','credits','credit_extras','notifications','web',
  'conversion','conversion_approval','clients','files','upload_rules','photo_presets','fees','receipt_prefix',
  'assignment','board','lead_cards','lead_filters','lead_score','appointment','message_templates',
  'call_sync','call_lock','double_call','contacts_import','ai_chance','ai_credit','ai_providers','network','public_forms',
  'working_days','working_hours','quiet_hours','institution_name','developer_email','min_app_version',
  'speed_to_lead_minutes','early_reminder_minutes','repeat_reminder_minutes','escalate_team_lead_hours','escalate_admin_hours')) = 42,
  'every Appendix A key is registered (with the neutral names, D42)');
select pg_temp.check(not exists (select 1 from public.setting_definitions where key in
  ('campus_visit','alumni','students','admission','admission_approval','max_call_attempts','call_log_lock_hours','activity_retention_days')),
  'no education-worded or dropped keys');
select pg_temp.check(to_regclass('public.feature_flags') is null and to_regclass('public.call_results') is null
  and to_regclass('public.document_types') is null, 'dropped tables do not exist');
select pg_temp.check(not exists (select 1 from public.setting_definitions where label_key is null or owner_module is null or schema is null),
  'every key has a schema, a label key and an owner');
select pg_temp.check(not exists (select 1 from public.setting_definitions d where d.scope = 'institution'
  and not exists (select 1 from public.permissions p where p.key = d.area and p.kind = 'institution')),
  'every institution key is guarded by a registered area permission');
select pg_temp.check(not exists (select 1 from public.setting_definitions d where cardinality(app.validation_errors(d.schema, d.default_value)) > 0),
  'every default validates against its schema');
select pg_temp.check((select scope from public.setting_definitions where key = 'developer_email') = 'product'
  and (select scope from public.setting_definitions where key = 'app_name') = 'product', 'product-level values are platform config (T9)');
select pg_temp.check((select count(*) from public.config_groups) = 16, 'other per-institution configuration groups registered (T3)');

-- 2. Area permissions, as real roles: a role with only settings.fees changes fees but not assignment.
with r as (insert into public.roles (institution_id, name) values (:inst_a, 'Fees only') returning id) insert into ids select 'fees_role', id from r;
insert into public.role_permissions (institution_id, role_id, permission_key) values (:inst_a, pg_temp.id('fees_role'), 'settings.fees');
insert into public.role_assignments (institution_id, user_id, role_id) values (:inst_a, :user_a, pg_temp.id('fees_role'));
select app.flush_access_queue(:inst_a);
select pg_temp.act_as(pg_temp.claims_for(:user_a));
select pg_temp.check(pg_temp.error_of('select public.setting_set(''fees'', ''{"enabled": true}'')') = '', 'settings.fees may change fees');
select pg_temp.check(pg_temp.error_of('select public.setting_set(''assignment'', ''{"enabled": false}'')') = 'permission_denied',
  'settings.fees may not change assignment');
select pg_temp.check(pg_temp.error_of('select public.setting_set(''fees'', ''{"enabled": "yes"}'')') = 'setting_invalid', 'invalid value refused');
select pg_temp.check(pg_temp.error_of('select public.setting_set(''receipt_prefix'', ''"no spaces allowed"'')') = 'setting_invalid',
  'receipt prefix pattern enforced');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:user_owner));
select pg_temp.check(pg_temp.error_of('select public.setting_set(''institution_name'', ''"X"'')') = 'setting_unknown',
  'a key stored elsewhere (institution_name) cannot be set here, even by the Super Admin');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:user_a));
select pg_temp.check(pg_temp.error_of('select public.setting_set(''developer_email'', ''"x@example.test"'')') = 'setting_unknown',
  'a product key cannot be set by an institution');

-- 3. Read RPCs with the source of the value.
select pg_temp.check(public.get_setting('fees') ->> 'source' = 'institution' and (public.get_setting('fees') -> 'value' ->> 'enabled')::boolean,
  'get_setting: the institution''s value');
select pg_temp.check(public.get_setting('speed_to_lead_minutes') ->> 'source' = 'default'
  and (public.get_setting('speed_to_lead_minutes') ->> 'value')::int = 5, 'get_setting: the default when not set');
select pg_temp.check(public.get_setting('institution_name') ->> 'value' = 'Test College A', 'institution_name comes from the institution');
select pg_temp.check(public.get_settings(array['fees', 'board']) ? 'board', 'get_settings: several keys at once');
select pg_temp.check(pg_temp.error_of('select public.get_setting(''min_app_version'')') = 'setting_unknown', 'get_setting is for institution keys');

-- 4. History and rollback.
select public.setting_set('fees', '{"enabled": false}');
reset role;
select pg_temp.check((select count(*) from public.app_settings_history where institution_id = :inst_a and key = 'fees') = 2,
  'every change is kept in the history');
insert into ids select 'h_last', id from public.app_settings_history where institution_id = :inst_a and key = 'fees' order by at desc, new_value::text limit 1;
insert into ids select 'h_first', id from public.app_settings_history where institution_id = :inst_a and key = 'fees' and old_value is null;
select pg_temp.act_as(pg_temp.claims_for(:user_a));
select public.setting_rollback(pg_temp.id('h_last'));
select pg_temp.check((public.get_setting('fees') -> 'value' ->> 'enabled')::boolean, 'rollback restores the earlier value');
select public.setting_rollback(pg_temp.id('h_first'));
select pg_temp.check(public.get_setting('fees') ->> 'source' = 'default', 'rolling back the first change goes back to the default');
select pg_temp.check(exists (select 1 from public.app_settings_history where key = 'fees' and reason like 'rollback of %'),
  'rollbacks are recorded with a reason');
reset role;

-- 5. History isolation: another institution and people without the area see nothing.
select pg_temp.act_as(pg_temp.claims_for(:user_b));
select pg_temp.check(not exists (select 1 from public.app_settings_history where institution_id = :inst_a), 'B cannot read A''s history');
reset role;
delete from public.role_assignments where institution_id = :inst_a and user_id = :user_a;
select app.flush_access_queue(:inst_a);
select pg_temp.act_as(pg_temp.claims_for(:user_a));
select pg_temp.check(not exists (select 1 from public.app_settings_history), 'without the area permission the history is hidden');
select pg_temp.check(pg_temp.error_of(format('select public.setting_rollback(%L)', pg_temp.id('h_last'))) = 'permission_denied',
  'rollback needs the area permission');
reset role;

rollback;
