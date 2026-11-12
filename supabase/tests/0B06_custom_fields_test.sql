-- 0B.06 tests: preset fields from the type profile (sensitive ones flagged), definitions with typed options, indexes
-- only for filterable fields, value validation (GPA 0–5 with two decimals, choices, phone, email, required), the
-- idempotency key, sensitive values hidden without the permission, the plan limit on field count, retire / restore,
-- reorder, export, isolation.
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
declare v text;
begin execute p_sql; return ''; exception when others then get stacked diagnostics v = pg_exception_detail; return sqlerrm || coalesce(' / ' || v, ''); end $$;
grant execute on all functions in schema pg_temp to authenticated;
create temp table out (k text primary key, v jsonb);
grant all on out to authenticated;
create function pg_temp.v(p_k text) returns jsonb language sql as $$ select v from out where k = p_k $$;
grant execute on function pg_temp.v(text) to authenticated;

\set inst_a '''a0000000-0000-4000-8000-00000000000a'''
\set user_a '''11111111-1111-4111-8111-111111111111'''
\set user_b '''22222222-2222-4222-8222-222222222222'''
\set owner '''77777777-7777-4777-8777-777777777777'''
\set rec '''0b060000-0000-4000-8000-000000000001'''
update public.profiles set last_active_institution_id = null where user_id in (:user_a, :user_b);

-- 1. Presets from the type profile.
select pg_temp.check((select count(*) from public.custom_field_definitions d join public.institutions i on i.id = d.institution_id
  where i.slug = 'profile-school' and d.created_from_preset is not null and d.entity = 'lead') = 7, 'the school profile installs its 7 preset fields');
select pg_temp.check((select array_agg(d.key order by d.key) from public.custom_field_definitions d join public.institutions i on i.id = d.institution_id
  where i.slug = 'profile-school' and d.sensitive) = '{birth_registration_no,guardian_nid}', 'guardian NID and birth registration no. are sensitive');
select pg_temp.check((select d.type from public.custom_field_definitions d join public.institutions i on i.id = d.institution_id
  where i.slug = 'profile-college' and d.key = 'ssc_gpa') = 'gpa'
  and (select jsonb_array_length(d.options -> 'choices') from public.custom_field_definitions d join public.institutions i on i.id = d.institution_id
  where i.slug = 'profile-college' and d.key = 'board') = 11, 'preset types: SSC GPA is a GPA field; Board is a select with its choices');

-- 2. Definitions (Super Admin of A).
select pg_temp.act_as(pg_temp.claims_for(:owner));
insert into out select 'gpa', public.custom_field_save('lead', null, '{"key":"hsc_gpa","label":{"en":"HSC GPA","bn":"এইচএসসি জিপিএ"},"type":"gpa","filterable":true}');
insert into out select 'shift', public.custom_field_save('lead', null, '{"key":"shift","label":{"en":"Shift","bn":"শিফট"},"type":"select",
  "options":{"choices":[{"key":"morning","label":{"en":"Morning","bn":"প্রভাতী"}},{"key":"day","label":{"en":"Day","bn":"দিবা"}}]}}');
select public.custom_field_save('lead', null, '{"key":"father_phone","label":{"en":"Father''s phone","bn":"বাবার ফোন"},"type":"phone"}');
select public.custom_field_save('lead', null, '{"key":"email2","label":{"en":"Second email","bn":"দ্বিতীয় ইমেইল"},"type":"email"}');
select public.custom_field_save('lead', null, '{"key":"birth_cert","label":{"en":"Birth certificate no.","bn":"জন্ম সনদ নম্বর"},"type":"text","sensitive":true}');
select public.custom_field_save('lead', null, '{"key":"source_note","label":{"en":"Note","bn":"নোট"},"type":"long_text","required":true}');
select pg_temp.check(pg_temp.error_of('select public.custom_field_save(''lead'', null, ''{"key":"x","label":{"en":"X","bn":"X"},"type":"select"}'')')
  like 'custom_field_invalid%choices%', 'a select field needs choices');
select pg_temp.check(pg_temp.error_of('select public.custom_field_save(''lead'', null, ''{"key":"shift","label":{"en":"X","bn":"X"},"type":"text"}'')')
  like 'custom_field_invalid%already used%', 'keys are unique per entity');
reset role;
select pg_temp.check(exists (select 1 from pg_indexes where indexname = 'cfv_f_' || replace(pg_temp.v('gpa') ->> 'id', '-', ''))
  and not exists (select 1 from pg_indexes where indexname = 'cfv_f_' || replace(pg_temp.v('shift') ->> 'id', '-', '')),
  'only filterable fields get an index');

-- 3. Values with validation.
select pg_temp.act_as(pg_temp.claims_for(:owner));
select pg_temp.check(pg_temp.error_of(format('select public.custom_field_values_set(''lead'', %L, ''{"hsc_gpa": 5.01, "source_note": "x"}'')', :rec))
  like 'custom_field_invalid%GPA%', 'GPA 5.01 is refused');
select pg_temp.check(pg_temp.error_of(format('select public.custom_field_values_set(''lead'', %L, ''{"hsc_gpa": 3.456, "source_note": "x"}'')', :rec))
  like 'custom_field_invalid%GPA%', 'GPA 3.456 is refused');
select pg_temp.check(pg_temp.error_of(format('select public.custom_field_values_set(''lead'', %L, ''{"shift": "night"}'')', :rec))
  like 'custom_field_invalid%unknown choice%', 'an unknown choice is refused');
select pg_temp.check(pg_temp.error_of(format('select public.custom_field_values_set(''lead'', %L, ''{"source_note": ""}'')', :rec))
  like 'custom_field_invalid%required%', 'a required field cannot be emptied');
select pg_temp.check(pg_temp.error_of(format('select public.custom_field_values_set(''lead'', %L, ''{"email2": "not-an-email"}'')', :rec))
  like 'custom_field_invalid%email%', 'email format checked');
insert into out select 'set', public.custom_field_values_set('lead', :rec,
  '{"hsc_gpa": "৪.৫", "shift": "day", "father_phone": "+880 1711-000001", "email2": "Parent@Example.TEST", "birth_cert": "2009123", "source_note": "fair"}', 'idem-key-0001');
select pg_temp.check(pg_temp.v('set') ->> 'hsc_gpa' = '4.5' and pg_temp.v('set') ->> 'father_phone' = '01711000001'
  and pg_temp.v('set') ->> 'email2' = 'parent@example.test', 'values stored typed (Bangla digits, phone normalised, email lower case)');
insert into out select 'again', public.custom_field_values_set('lead', :rec, '{"shift": "morning"}', 'idem-key-0001');
select pg_temp.check(pg_temp.v('again') ->> 'shift' = 'day' and public.custom_field_values_get('lead', :rec) ->> 'shift' = 'day',
  'the same idempotency key returns the first result and changes nothing');
reset role;
select pg_temp.check((select value_num from public.custom_field_values where institution_id = :inst_a and field_id = (pg_temp.v('gpa') ->> 'id')::uuid) = 4.5,
  'values live in custom_field_values (typed columns), not on the record');

-- 4. Sensitive values: hidden without custom_field.view_sensitive.
select pg_temp.act_as(pg_temp.claims_for(:user_a));
select pg_temp.check(public.custom_field_values_get('lead', :rec) ->> 'birth_cert' = '•••' and public.custom_field_values_get('lead', :rec) ->> 'shift' = 'day',
  'without the permission a sensitive value is masked');
select pg_temp.check(not exists (select 1 from public.custom_field_values v join public.custom_field_definitions d on d.id = v.field_id where d.sensitive),
  'and its row is not readable');
select pg_temp.check(pg_temp.error_of('select public.custom_field_save(''lead'', null, ''{"key":"y","label":{"en":"Y","bn":"Y"},"type":"text"}'')') like 'permission_denied%',
  'role matrix: without settings.custom_fields no builder');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:owner));
select pg_temp.check(public.custom_field_values_get('lead', :rec) ->> 'birth_cert' = '2009123', 'with it (Super Admin) the value is shown');
reset role;

-- 5. Plan limit on the number of fields; retire / restore; reorder; filterable off drops the index.
update public.institution_plan set limit_overrides = jsonb_build_object('custom_fields', app.usage_of(:inst_a, 'custom_fields')) where institution_id = :inst_a;
select pg_temp.act_as(pg_temp.claims_for(:owner));
select pg_temp.check(pg_temp.error_of('select public.custom_field_save(''lead'', null, ''{"key":"one_more","label":{"en":"One more","bn":"আরও একটি"},"type":"text"}'')')
  like 'limit_reached%', 'the plan limit on fields is enforced on the server');
select public.custom_field_retire((pg_temp.v('shift') ->> 'id')::uuid, true);
select pg_temp.check(pg_temp.error_of('select public.custom_field_save(''lead'', null, ''{"key":"one_more","label":{"en":"One more","bn":"আরও একটি"},"type":"text"}'')') = '',
  'retiring a field makes room; its values are kept');
select pg_temp.check(pg_temp.error_of(format('select public.custom_field_retire(%L, false)', pg_temp.v('shift') ->> 'id')) like 'limit_reached%',
  'bringing a field back needs room');
select public.custom_fields_reorder('lead', jsonb_build_array(jsonb_build_object('id', pg_temp.v('gpa') ->> 'id', 'group_label', '{"en":"Results","bn":"ফলাফল"}'::jsonb)));
select public.custom_field_save('lead', (pg_temp.v('gpa') ->> 'id')::uuid, '{"key":"hsc_gpa","label":{"en":"HSC GPA","bn":"এইচএসসি জিপিএ"},"type":"gpa","filterable":false}');
select pg_temp.check(jsonb_array_length(public.custom_fields_export('lead')) >= 5
  and not (public.custom_fields_export('lead') -> 0 ? 'id'), 'export of definitions for copying (no ids)');
reset role;
select pg_temp.check((select sort from public.custom_field_definitions where id = (pg_temp.v('gpa') ->> 'id')::uuid) = 10
  and (select group_label ->> 'en' from public.custom_field_definitions where id = (pg_temp.v('gpa') ->> 'id')::uuid) = 'Results', 'order and groups saved');
select pg_temp.check(not exists (select 1 from pg_indexes where indexname = 'cfv_f_' || replace(pg_temp.v('gpa') ->> 'id', '-', '')),
  'turning filterable off drops the index');
select pg_temp.check(exists (select 1 from public.custom_field_values where field_id = (pg_temp.v('shift') ->> 'id')::uuid), 'a retired field keeps its values');
select pg_temp.check(exists (select 1 from public.audit_log where institution_id = :inst_a and action = 'custom_field.created'), 'changes are audited');

-- 6. Isolation.
select pg_temp.act_as(pg_temp.claims_for(:user_b));
select pg_temp.check(not exists (select 1 from public.custom_field_definitions where institution_id = :inst_a)
  and not exists (select 1 from public.custom_field_values where institution_id = :inst_a), 'B sees no fields or values of A');
select pg_temp.check(public.custom_field_values_get('lead', :rec) = '{}'::jsonb, 'and gets nothing for A''s record');
reset role;

rollback;
