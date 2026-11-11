-- 0B.03 tests: the education pack and nine profiles are published and valid; published versions never change; a broken
-- profile cannot be published; a new version publishes and updates the words; only education is open; institutions
-- read only published data of open industries and never write; the panel needs platform.profiles and the second step.
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
create function pg_temp.detail_of(p_sql text) returns text language plpgsql as $$
declare v text;
begin execute p_sql; return ''; exception when others then get stacked diagnostics v = pg_exception_detail; return v; end $$;
grant execute on all functions in schema pg_temp to authenticated, anon;
create temp table out (k text primary key, v jsonb);
grant all on out to authenticated;

\set master '''55555555-5555-4555-8555-555555555555'''
\set support '''e1000000-0000-4000-8000-0000000000e1'''
\set owner '''77777777-7777-4777-8777-777777777777'''

-- 1. Seeded data: the education pack and nine profiles, published, valid, with role templates.
select pg_temp.check((select count(*) from public.type_profiles where status = 'published' and industry_key = 'education'
  and key in ('school', 'college', 'university', 'polytechnic', 'madrasa', 'english_medium', 'coaching', 'training', 'health')) = 9,
  'nine education profiles are published');
select pg_temp.check(not exists (select 1 from public.type_profiles t
  where cardinality(app.pack_payload_errors('profile', t.industry_key, t.payload)) > 0)
  and not exists (select 1 from public.industry_packs p where cardinality(app.pack_payload_errors('pack', p.industry_key, p.payload)) > 0),
  'every pack and profile row passes the schema and its references');
select pg_temp.check(not exists (select 1 from public.type_profiles t where not exists
  (select 1 from public.role_templates r where r.type_profile_key = t.payload ->> 'role_template_set')), 'every profile has role templates (D26)');
select pg_temp.check((select payload -> 'labels' -> 'client' ->> 'en_singular' from public.industry_packs where industry_key = 'education') = 'Student'
  and (select payload -> 'stages' -> -2 ->> 'key' from public.industry_packs where industry_key = 'education') = 'admitted',
  'education pack: Lead → Student and the common pipeline');
select pg_temp.check((select jsonb_agg(s ->> 'field' order by s ->> 'field') from public.industry_packs p,
  jsonb_array_elements(p.payload -> 'sensitive_fields') s where (s ->> 'never_to_ai')::boolean)
  = '["birth_registration_no", "guardian_nid"]'::jsonb, 'guardian NID and birth registration no. are sensitive and never sent to AI');
select pg_temp.check((select payload ->> 'client_number_pattern' from public.type_profiles where key = 'school') = '{YYYY}{CLASS}{000}'
  and (select payload ->> 'client_number_pattern' from public.type_profiles where key = 'coaching') = '{CODE}-{000}',
  'student-ID patterns from Ch 7.5');
select pg_temp.check(exists (select 1 from public.label_defaults where scope = 'profile' and scope_key = 'school' and key = 'offering' and en_singular = 'Class')
  and exists (select 1 from public.label_defaults where scope = 'profile' and scope_key = 'coaching' and key = 'cohort' and en_singular = 'Batch'),
  'published profile words are in label_defaults');
select pg_temp.check((select count(*) from public.industries) = 14 and (select array_agg(key) from public.industries where signup_open) = '{education}'
  and exists (select 1 from public.industries where key = 'general'), 'industry list stored; only education is open (D20)');

-- 2. Published versions never change.
select pg_temp.check(pg_temp.error_of('update public.type_profiles set payload = ''{}'' where key = ''school'' and version = 1') = 'version_published',
  'a published profile cannot be edited');
select pg_temp.check(pg_temp.error_of('delete from public.industry_packs where industry_key = ''education''') = 'version_published',
  'a published pack cannot be deleted');

-- 3. Who may: institutions and platform users without platform.profiles get nothing.
select pg_temp.act_as(pg_temp.claims_for(:owner, 'aal2'));
select pg_temp.check(pg_temp.error_of('select public.platform_packs_list()') = 'permission_denied', 'an institution Super Admin cannot use the panel RPCs');
select pg_temp.check(pg_temp.error_of('update public.type_profiles set notes = ''x''') like 'permission denied%'
  and pg_temp.error_of('insert into public.industries (key, name, sort) values (''x'', ''{"en":"x","bn":"x"}'', 1)') like 'permission denied%',
  'institutions never write packs, profiles or industries');
select pg_temp.check((select count(*) from public.type_profiles) = 9 and (select count(*) from public.industries) = 1,
  'institutions read published profiles of open industries only');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:support, 'aal2'));
select pg_temp.check(pg_temp.error_of('select public.platform_packs_list()') = 'permission_denied', 'Support (view only) cannot edit profiles');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:master, 'aal1'));
select pg_temp.check(pg_temp.error_of('select public.platform_pack_get(''profile'', ''school'')') = 'permission_denied',
  'Master Admin without the second step: no access');
reset role;

-- 4. A broken profile fails validation and publishing; drafts are invisible to institutions.
select pg_temp.act_as(pg_temp.claims_for(:master, 'aal2'));
insert into out select 'broken', (select payload from public.type_profiles where key = 'school')
  || '{"labels": {"no_such_word": {"en_singular": "X", "en_plural": "Xs", "bn": {"base": "ক"}}}, "custom_fields": ["shoe_size"],
       "settings": {"fees": {"enabled": "yes"}, "institution_name": "X"}, "field_rules": [{"role": "pilot", "field": "phone", "access": "hidden"}]}'
  || jsonb_build_object('stages', '[{"key":"new","name":{"en":"New","bn":"নতুন"},"kind":"open"},{"key":"a","name":{"en":"A","bn":"ক"},"kind":"open"},{"key":"a","name":{"en":"A","bn":"ক"},"kind":"open"}]'::jsonb);
insert into out select 'errors', public.platform_pack_validate('profile', 'school', (select v from out where k = 'broken'));
select pg_temp.check((select v from out where k = 'errors') @> '["labels.no_such_word: not a registered label key",
  "custom_fields: \"shoe_size\" is not a field preset of the pack", "settings.institution_name: not an institution setting",
  "stages: needs a stage of kind won", "stages: needs a stage of kind lost", "stages: \"a\" appears more than once",
  "field_rules: role \"pilot\" is not in role template set school"]'::jsonb
  and exists (select 1 from jsonb_array_elements_text((select v from out where k = 'errors')) e where e like 'settings.fees:%'),
  'validation lists every problem (words, fields, settings, stages, roles)');
select pg_temp.check(jsonb_array_length(public.platform_pack_validate('profile', 'school', '{"name": 1}')) > 0,
  'a payload that breaks the schema returns schema errors');
select pg_temp.check(public.platform_pack_save_draft('profile', 'school', (select v from out where k = 'broken'), 'try') = 2, 'a draft is saved as version 2');
select pg_temp.check(pg_temp.error_of('select public.platform_pack_publish(''profile'', ''school'', 2)') = 'profile_invalid'
  and pg_temp.detail_of('select public.platform_pack_publish(''profile'', ''school'', 2)') like '%needs a stage of kind won%',
  'a broken profile cannot be published');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:owner, 'aal2'));
select pg_temp.check(not exists (select 1 from public.type_profiles where status = 'draft'), 'drafts are invisible to institutions');
reset role;

-- 5. A good new version publishes, replaces the words and is audited; version 1 stays as it was.
select pg_temp.act_as(pg_temp.claims_for(:master, 'aal2'));
select public.platform_pack_save_draft('profile', 'school', (select payload from public.type_profiles where key = 'school' and version = 1)
  || '{"labels": {"lead": {"en_singular": "Admission enquiry", "en_plural": "Admission enquiries", "bn": {"base": "ভর্তির জিজ্ঞাসা"}}}}', 'clearer word');
select public.platform_pack_publish('profile', 'school', 2, 'clearer word for leads');
insert into out select 'list', public.platform_packs_list();
reset role;
select pg_temp.check((select x -> 'published_version' from out, jsonb_array_elements(v -> 0 -> 'profiles') x
  where k = 'list' and x ->> 'key' = 'school') = '2'::jsonb, 'the list shows the new published version');
select pg_temp.check((select en_singular from public.label_defaults where scope = 'profile' and scope_key = 'school' and key = 'lead') = 'Admission enquiry'
  and (select payload -> 'labels' -> 'lead' ->> 'en_singular' from public.type_profiles where key = 'school' and version = 1) = 'Enquiry',
  'the new words are in force; version 1 is unchanged');
select pg_temp.check((select count(*) from public.platform_audit_log where action in ('profile.draft_saved', 'profile.published')
  and target_id like 'school v2') = 3, 'drafts and publishing are in the platform audit log');
select pg_temp.act_as(pg_temp.claims_for(:master, 'aal2'));
insert into out select 'get', public.platform_pack_get('profile', 'school');
select pg_temp.check(jsonb_array_length((select v from out where k = 'get') -> 'versions') = 2
  and (select v from out where k = 'get') -> 'versions' -> 0 ->> 'published_by' = 'platform.admin@example.test', 'version history with who published');

-- 6. Opening industries.
select pg_temp.check(pg_temp.error_of('select public.platform_industry_set_open(''healthcare'', true)') = 'industry_not_ready',
  'an industry without a pack cannot be opened');
select public.platform_industry_set_open('education', false);
reset role;
set local role anon;
select pg_temp.check(public.list_open_packs() = '[]'::jsonb, 'closed: the wizard lists nothing');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:master, 'aal2'));
select public.platform_industry_set_open('education', true);
reset role;
set local role anon;
select pg_temp.check(jsonb_array_length(public.list_open_packs()) = 1 and jsonb_array_length(public.list_open_packs() -> 0 -> 'profiles') = 9
  and public.list_open_packs() -> 0 -> 'profiles' -> 0 ->> 'key' = 'school', 'the wizard lists education with its nine profiles in order');
reset role;
select pg_temp.check(exists (select 1 from public.platform_audit_log where action = 'industry.signup_changed' and target_id = 'education'
  and after ->> 'signup_open' = 'true'), 'opening and closing is audited');

rollback;
