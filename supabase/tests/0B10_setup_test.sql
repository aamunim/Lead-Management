-- 0B.10 tests: the checklist (owners, later items, rules tick themselves, manual marks, progress) for the institution
-- and the panel; isolation; branding (permission, logo only from the institution's own folder, audit, settings version);
-- copy setup (platform only, configuration only, keeps the target's own, refuses a bad source); the trial-end alert.
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
create function pg_temp.item(p_list jsonb, p_key text) returns jsonb language sql as $$
  select x from jsonb_array_elements(p_list -> 'items') x where x ->> 'key' = p_key
$$;
grant execute on function pg_temp.item(jsonb, text) to authenticated;

\set inst_a '''a0000000-0000-4000-8000-00000000000a'''
\set inst_b '''b0000000-0000-4000-8000-00000000000b'''
\set user_a '''11111111-1111-4111-8111-111111111111'''
\set owner '''77777777-7777-4777-8777-777777777777'''
\set master '''55555555-5555-4555-8555-555555555555'''
\set support '''e1000000-0000-4000-8000-0000000000e1'''
delete from public.app_settings where institution_id = :inst_a and key in ('brand_color', 'brand_logo_path');

-- 1. The checklist of A as its Super Admin.
select pg_temp.act_as(pg_temp.claims_for(:owner));
insert into out select 'list', public.checklist_get();
select pg_temp.check(pg_temp.item(pg_temp.v('list'), 'messaging') ->> 'state' = 'later' and pg_temp.item(pg_temp.v('list'), 'messaging') ->> 'owner' = 'master_admin'
  and pg_temp.item(pg_temp.v('list'), 'payment_merchant') ->> 'owner' = 'both', 'items carry who does them; later features say so');
select pg_temp.check(pg_temp.item(pg_temp.v('list'), 'branding') ->> 'state' = 'open' and (pg_temp.item(pg_temp.v('list'), 'branding') ->> 'auto')::boolean,
  'branding is open and ticks itself');
select pg_temp.check(pg_temp.item(pg_temp.v('list'), 'staff') ->> 'state' = 'done', 'two or more people: the team item is done by its rule');
select pg_temp.check(pg_temp.error_of('select public.checklist_mark(''branding'', true)') = 'checklist_item_locked'
  and pg_temp.error_of('select public.checklist_mark(''messaging'', true)') = 'checklist_item_locked', 'rule items and platform / later items cannot be ticked by hand');
insert into out select 'marked', public.checklist_mark('pipeline_words', true, 'checked with the principal');
select pg_temp.check(pg_temp.item(pg_temp.v('marked'), 'pipeline_words') ->> 'state' = 'done'
  and (pg_temp.v('marked') ->> 'done')::int = (pg_temp.v('list') ->> 'done')::int + 1, 'a manual item is ticked and the progress moves');
-- Branding set → its item ticks itself (the rule reads the data).
select public.setting_set('brand_color', '"#0F766E"');
select pg_temp.check(pg_temp.item(public.checklist_get(), 'branding') ->> 'state' = 'done', 'setting the colour ticks the branding item');
reset role;
select pg_temp.check(exists (select 1 from public.audit_log where institution_id = :inst_a and action = 'checklist.done'), 'marking is audited');

-- 2. Who sees it; isolation.
select pg_temp.act_as(pg_temp.claims_for(:user_a));
select pg_temp.check(pg_temp.error_of('select public.checklist_get()') = 'permission_denied', 'staff without a settings permission do not see the checklist');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:owner));
select pg_temp.check(pg_temp.error_of('select count(*) from public.institution_checklist') like 'permission denied%', 'checklist rows are never read directly');
reset role;

-- 3. The panel sees the same and ticks the platform's items.
select pg_temp.act_as(pg_temp.claims_for(:support, 'aal2'));
select pg_temp.check(pg_temp.item(public.platform_checklist(:inst_a), 'pipeline_words') ->> 'state' = 'done', 'the panel sees the same status');
select pg_temp.check(pg_temp.error_of(format('select public.platform_checklist_mark(%L, ''payment_merchant'', true)', :inst_a)) = 'permission_denied',
  'Support (view only) cannot tick');
select pg_temp.check((select (x -> 'setup' ->> 'total')::int > 0 from jsonb_array_elements(public.platform_institutions_list()) x where x ->> 'id' = :inst_a),
  'the institutions list shows what is left');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:master, 'aal2'));
select pg_temp.check(pg_temp.error_of(format('select public.platform_checklist_mark(%L, ''pipeline_words'', true)', :inst_a)) = 'checklist_item_locked',
  'the platform does not tick the institution''s own items');
select pg_temp.check(pg_temp.item(public.platform_checklist_mark(:inst_a, 'payment_merchant', true, 'merchant details entered'), 'payment_merchant') ->> 'state' = 'done',
  'the platform ticks a shared item');
reset role;

-- 4. Branding.
select pg_temp.act_as(pg_temp.claims_for(:user_a));
select pg_temp.check(pg_temp.error_of('select public.branding_set(''Hacked'', ''HK'')') = 'permission_denied', 'branding needs settings.branding');
select pg_temp.check(pg_temp.error_of('select public.setting_set(''brand_color'', ''"#000000"'')') <> '', 'and so does the colour');
reset role;
insert into storage.objects (bucket_id, name, owner) values
  ('institution-files', :inst_a || '/branding/logo-test.png', :owner),
  ('institution-files', :inst_b || '/branding/logo-b.png', :owner);
select pg_temp.act_as(pg_temp.claims_for(:owner));
select pg_temp.check(pg_temp.error_of(format('select public.branding_set(''A School'', ''AS'', %L)', :inst_b || '/branding/logo-b.png')) = 'branding_invalid',
  'a logo from another institution''s folder is refused');
insert into out select 'brand', public.branding_set('Ideal College Dhaka', 'ICD', :inst_a || '/branding/logo-test.png');
select pg_temp.check(pg_temp.v('brand') ->> 'name' = 'Ideal College Dhaka' and pg_temp.v('brand') ->> 'short_name' = 'ICD'
  and pg_temp.v('brand') ->> 'logo_path' = :inst_a || '/branding/logo-test.png' and pg_temp.v('brand') ->> 'brand_color' = '#0F766E',
  'name, short name, logo and colour are saved');
select pg_temp.check(pg_temp.error_of('select public.setting_set(''brand_color'', ''"teal"'')') <> '', 'a colour must be a #RRGGBB code');
reset role;
select pg_temp.check(exists (select 1 from public.audit_log where institution_id = :inst_a and action = 'branding.changed'), 'branding changes are audited');

-- 5. Copy setup (platform only; configuration only; the target keeps its own).
insert into public.institution_labels (institution_id, key, en_singular, en_plural, bn_forms)
values (:inst_a, 'cohort', 'Group', 'Groups', app.bn_forms('গ্রুপ', true)) on conflict (institution_id, key) do update set en_singular = 'Group';
insert into public.institution_labels (institution_id, key, en_singular, en_plural, bn_forms)
values (:inst_b, 'offering', 'Program', 'Programs', app.bn_forms('প্রোগ্রাম', true)) on conflict (institution_id, key) do update set en_singular = 'Program';
insert into public.institution_labels (institution_id, key, en_singular, en_plural, bn_forms)
values (:inst_a, 'offering', 'Course', 'Courses', app.bn_forms('কোর্স', true)) on conflict (institution_id, key) do update set en_singular = 'Course';
insert into out select 'b_records', to_jsonb((select count(*) from public.institution_members where institution_id = :inst_b));
select pg_temp.act_as(pg_temp.claims_for(:owner));
select pg_temp.check(pg_temp.error_of(format('select public.platform_copy_setup(%L, %L, ''{labels}'')', :inst_b, :inst_a)) = 'permission_denied',
  'an institution cannot copy into another');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:master, 'aal2'));
select pg_temp.check(pg_temp.error_of(format('select public.platform_copy_setup(%L, %L, ''{labels}'')', :inst_b, :inst_b)) = 'copy_source_invalid'
  and pg_temp.error_of(format('select public.platform_copy_setup(%L, %L, ''{leads}'')', :inst_b, :inst_a)) = 'copy_source_invalid',
  'a bad source or an unknown area is refused');
insert into out select 'preview', public.platform_copy_setup(:inst_b, :inst_a, '{labels,settings,custom_fields}');
select pg_temp.check(not (pg_temp.v('preview') ->> 'applied')::boolean
  and (select (x ->> 'keep')::int >= 1 from jsonb_array_elements(pg_temp.v('preview') -> 'areas') x where x ->> 'area' = 'labels'),
  'the preview counts what is added and what the target keeps');
insert into out select 'copy', public.platform_copy_setup(:inst_b, :inst_a, '{labels,settings,custom_fields}', true);
reset role;
select pg_temp.check((select en_singular from public.institution_labels where institution_id = :inst_b and key = 'cohort') = 'Group'
  and (select en_singular from public.institution_labels where institution_id = :inst_b and key = 'offering') = 'Program',
  'words are copied; the target''s own word stays');
select pg_temp.check(not exists (select 1 from public.app_settings where institution_id = :inst_b and key in ('brand_color', 'brand_logo_path')),
  'branding is never copied');
select pg_temp.check((select count(*) from public.institution_members where institution_id = :inst_b) = (pg_temp.v('b_records'))::int
  and not exists (select 1 from public.custom_field_values where institution_id = :inst_b and field_id in
    (select id from public.custom_field_definitions where institution_id = :inst_b)
    and record_id in (select record_id from public.custom_field_values where institution_id = :inst_a)), 'no records are copied');
select pg_temp.check(exists (select 1 from public.platform_audit_log where action = 'setup.copied' and institution_id = :inst_b)
  and exists (select 1 from public.audit_log where action = 'setup.copied' and institution_id = :inst_b), 'copying is audited on both sides');

-- 6. Trial ending with setup incomplete: an alert to Support and Master Admins, once.
update public.institutions set status = 'trial' where id = :inst_b;
update public.institution_plan set expires_at = now() + interval '2 days' where institution_id = :inst_b;
insert into out select 'alerts1', to_jsonb(app.checklist_trial_alerts());
insert into out select 'alerts2', to_jsonb(app.checklist_trial_alerts());
select pg_temp.check((pg_temp.v('alerts1'))::int = 1 and (pg_temp.v('alerts2'))::int = 0
  and exists (select 1 from public.platform_alerts where kind = 'setup_incomplete' and recipient_user_id = :support and payload ->> 'institution_id' = :inst_b),
  'Support is told once that the trial ends with setup incomplete');

rollback;
