-- 0B.04 tests: applying types seeds the institution (words, settings, roles; later parts stored), mixed school + college
-- merges without duplicate stages, a word conflict surfaces in the preview, the institution's own edits survive a type
-- change, reset shows a preview and restores defaults only when confirmed, new versions never apply by themselves,
-- isolation of seeds, permissions, platform label lock with a reason, product-default words.
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
\set mixed '''f0000000-0000-4000-8000-0000000000fa'''
\set user_a '''11111111-1111-4111-8111-111111111111'''
\set user_b '''22222222-2222-4222-8222-222222222222'''
\set owner '''77777777-7777-4777-8777-777777777777'''
\set master '''55555555-5555-4555-8555-555555555555'''
update public.profiles set last_active_institution_id = null where user_id in (:user_a, :user_b);

-- 1. Seeded test institutions: one per profile and one mixed.
select pg_temp.check((select count(distinct ip.institution_id) from public.institution_profiles ip
  join public.institutions i on i.id = ip.institution_id where i.slug like 'profile-%') = 10, 'a test institution per profile plus a mixed one');
select pg_temp.check((select array_agg(profile_key order by position) from public.institution_profiles where institution_id = :mixed) = '{school,college}',
  'the mixed institution is school + college');
select pg_temp.check(not exists (select 1 from public.institutions where industry <> 'education'), 'every institution has industry education (T8)');

-- 2. Mixed: stages per type, no duplicates; words, settings and roles applied.
select pg_temp.check((select count(*) from public.seeded_items where institution_id = :mixed and area = 'stages')
  = (select jsonb_array_length(payload -> 'stages') from public.type_profiles where key = 'school' and version = 1)
  + (select jsonb_array_length(payload -> 'stages') from public.type_profiles where key = 'college' and version = 1)
  and not exists (select 1 from public.seeded_items s where s.institution_id = :mixed and s.area = 'stages'
                   group by s.value ->> 'type', s.value ->> 'key' having count(*) > 1),
  'mixed school + college: stages kept per type, none twice');
select pg_temp.check(app.label(:mixed, 'offering') = 'Class' and app.label(:mixed, 'client') = 'Student',
  'words: the profile word, else the pack word');
select pg_temp.check((select count(*) from public.seeded_items where institution_id = :mixed and area = 'documents')
  = (select count(distinct d ->> 'key') from public.type_profiles t, jsonb_array_elements(t.payload -> 'documents') d
      where t.key in ('school', 'college') and t.version = 1), 'documents joined by key');
select pg_temp.check(app.setting_value(:mixed, 'network') = '{"enabled": true}'::jsonb, 'on / off settings: on when any type turns it on');
select pg_temp.check((select value from public.seeded_items where institution_id = :mixed and area = 'notification_recipients') = '"both"'::jsonb,
  'different default recipients become both');
select pg_temp.check(exists (select 1 from public.roles where institution_id = :mixed and template_key = 'class_teacher')
  and exists (select 1 from public.roles where institution_id = :mixed and template_key = 'governing_body'), 'template roles of both sets (D26)');

-- 3. A word conflict surfaces in the preview, and the choice decides.
select pg_temp.check((select x -> 'options' -> 1 ->> 'profile' from jsonb_array_elements(app.profile_label_conflicts(array['school', 'coaching'])) x
  where x ->> 'key' = 'offering') = 'coaching', 'school + coaching: "Class" vs "Course" is a conflict');
select pg_temp.check((select x ->> 'chosen' from jsonb_array_elements(app.profile_label_conflicts(array['school', 'coaching'], '{"offering":"coaching"}')) x
  where x ->> 'key' = 'offering') = 'coaching', 'the choice is shown');
select pg_temp.check((select value ->> 'en_singular' from app.profile_seed_set(array['school', 'coaching'], '{"offering":"coaching"}')
  where area = 'labels' and item_key = 'offering') = 'Course', 'the chosen word is seeded');

-- 4. Institution A (Super Admin): apply school, edit a word and a setting, change type: own edits survive.
select pg_temp.act_as(pg_temp.claims_for(:owner));
insert into out select 'p1', public.profile_change_preview(array['school']);
select pg_temp.check(exists (select 1 from jsonb_array_elements(pg_temp.v('p1') -> 'areas') a where a ->> 'area' = 'labels' and (a ->> 'add')::int > 0),
  'preview before applying lists what will be added');
select public.profile_change_apply(array['school'], '{}', '{}', 'first set-up');
select pg_temp.check(public.labels_get() -> 'labels' -> 'offering' -> 'resolved' ->> 'en_singular' = 'Class', 'the app gets the profile words');
select public.label_set('offering', 'Grade', 'Grades', '{"base":"গ্রেড"}');
select public.setting_set('appointment', '{"enabled": false}');
reset role;
select pg_temp.check((select modified_by_institution from public.seeded_items where institution_id = :inst_a and area = 'labels' and item_key = 'offering')
  and (select modified_by_institution from public.seeded_items where institution_id = :inst_a and area = 'settings' and item_key = 'appointment'),
  'own edits are marked modified (T3)');
select pg_temp.act_as(pg_temp.claims_for(:owner));
insert into out select 'p2', public.profile_change_preview(array['coaching']);
select pg_temp.check(exists (select 1 from jsonb_array_elements(pg_temp.v('p2') -> 'areas') a, jsonb_array_elements(a -> 'items') i
  where a ->> 'area' = 'labels' and i ->> 'key' = 'offering' and i ->> 'action' = 'kept'), 'type-change preview: an edited word is kept');
select public.profile_change_apply(array['coaching'], '{}', '{}', 'became a coaching centre');
select pg_temp.check(public.labels_get() -> 'labels' -> 'offering' -> 'resolved' ->> 'en_singular' = 'Grade'
  and public.labels_get() -> 'labels' -> 'cohort' -> 'resolved' ->> 'en_singular' = 'Batch', 'type change: own word kept, unmodified words re-seeded');
select pg_temp.check((public.get_setting('appointment') -> 'value' ->> 'enabled')::boolean = false, 'type change: own setting kept');
reset role;
select pg_temp.check(exists (select 1 from public.roles where institution_id = :inst_a and template_key = 'class_teacher'),
  'roles of the earlier type stay (never deleted)');
select pg_temp.check(not exists (select 1 from public.seeded_items where institution_id = :inst_a and area = 'stages' and item_key like 'school.%'),
  'unmodified seeds of the removed type are gone');

-- 5. Reset to profile defaults: preview first, then only on confirm.
select pg_temp.act_as(pg_temp.claims_for(:owner));
insert into out select 'r1', public.profile_reset('settings.terminology');
select pg_temp.check(not (pg_temp.v('r1') ->> 'applied')::boolean and pg_temp.v('r1') -> 'items' -> 0 ->> 'key' = 'offering'
  and pg_temp.v('r1') -> 'items' -> 0 -> 'default' ->> 'en_singular' = 'Course', 'reset preview: own word and the default it returns to');
select pg_temp.check(public.labels_get() -> 'labels' -> 'offering' -> 'resolved' ->> 'en_singular' = 'Grade', 'nothing changes without confirmation');
select public.profile_reset('settings.terminology', true);
select pg_temp.check(public.labels_get() -> 'labels' -> 'offering' -> 'resolved' ->> 'en_singular' = 'Course', 'confirmed: the word is back to the profile default');
insert into out select 'r2', public.profile_reset('settings.leads');
select pg_temp.check(pg_temp.v('r2') -> 'items' -> 0 ->> 'key' = 'appointment', 'settings area preview');
select public.profile_reset('settings.leads', true);
select pg_temp.check((public.get_setting('appointment') ->> 'source') = 'type_profile', 'settings area reset: back to the type default');
reset role;

-- 6. New versions never apply by themselves (T7); the Admin sees them and opts in.
select pg_temp.act_as(pg_temp.claims_for(:master, 'aal2'));
select public.platform_pack_save_draft('profile', 'coaching', (select payload from public.type_profiles where key = 'coaching' and version = 1)
  || '{"labels": {"cohort": {"en_singular": "Group", "en_plural": "Groups", "bn": {"base": "গ্রুপ"}}}}', 'test');
select public.platform_pack_publish('profile', 'coaching', 2);
reset role;
select pg_temp.check(app.label(:inst_a, 'cohort') = 'Batch' and app.label('f0000000-0000-4000-8000-0000000000f7', 'cohort') = 'Batch',
  'a new profile version does not change institutions already set up');
select pg_temp.act_as(pg_temp.claims_for(:owner));
select pg_temp.check((public.profile_state() -> 'applied' -> 0 ->> 'latest_version')::int = 2
  and (public.profile_state() -> 'applied' -> 0 ->> 'version')::int = 1, 'the Admin sees that a new version is available');
select public.profile_change_apply(array['coaching']);
select pg_temp.check(public.labels_get() -> 'labels' -> 'cohort' -> 'resolved' ->> 'en_singular' = 'Group', 'opting in applies the new version');
reset role;

-- 7. Permissions and isolation.
select pg_temp.act_as(pg_temp.claims_for(:user_a));
select pg_temp.check(pg_temp.error_of('select public.profile_state()') = 'permission_denied'
  and pg_temp.error_of('select public.profile_change_apply(array[''school''])') = 'permission_denied',
  'without settings.institution_type: no type change');
select pg_temp.check(pg_temp.error_of('select public.profile_reset(''settings.terminology'', true)') = 'permission_denied',
  'reset needs the area permission');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:user_b));
select pg_temp.check(not exists (select 1 from public.seeded_items where institution_id <> :inst_b)
  and not exists (select 1 from public.institution_profiles where institution_id <> :inst_b), 'seeds and types of other institutions are invisible');
select pg_temp.check(pg_temp.error_of('insert into public.seeded_items (institution_id, area, item_key, value, source_profile, source_version) values ('
  || quote_literal(:inst_b) || ', ''labels'', ''x'', ''{}'', ''x'', 1)') like 'permission denied%', 'nobody writes seeds directly');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:owner));
select pg_temp.check(pg_temp.error_of('select public.profile_change_apply(array[''school'', ''no_such_type''])') = 'profile_choice_invalid',
  'unknown types are refused');

-- 8. Master Admin: an institution's words, lock with a reason (read-only for the institution), product defaults.
reset role;
select pg_temp.act_as(pg_temp.claims_for(:master, 'aal2'));
select pg_temp.check(jsonb_array_length(public.platform_institutions_list()) >= 13, 'institutions list for the panel');
select pg_temp.check((select x -> 'label' ->> 'en_singular' from jsonb_array_elements(public.platform_institution_labels(:inst_a) -> 'labels') x
  where x ->> 'key' = 'cohort') = 'Group', 'the panel sees the institution''s words');
select public.label_lock(:inst_a, 'doc.receipt_title', true, 'legal title');
select public.platform_label_default_set('lead', 'Prospect', 'Prospects', '{"base":"প্রসপেক্ট"}');
reset role;
select pg_temp.check(exists (select 1 from public.platform_audit_log where action = 'label.locked' and target_id = 'doc.receipt_title'
  and reason = 'legal title' and institution_id = :inst_a), 'the lock is audited with its reason');
select pg_temp.act_as(pg_temp.claims_for(:owner));
select pg_temp.check(pg_temp.error_of('select public.label_set(''doc.receipt_title'', ''Bill'', ''Bills'', ''{"base":"বিল"}'')') = 'label_locked',
  'a locked word is read-only for the institution');
reset role;
select pg_temp.check((select en_singular from public.label_defaults where scope = 'product' and key = 'lead') = 'Prospect'
  and app.label(:inst_a, 'lead') = 'Lead', 'product default changed; the pack word still wins for an education institution');
select pg_temp.act_as(pg_temp.claims_for(:owner, 'aal2'));
select pg_temp.check(pg_temp.error_of('select public.label_lock(' || quote_literal(:inst_a) || ', ''doc.receipt_title'', false)') = 'permission_denied'
  and pg_temp.error_of('select public.platform_label_default_set(''lead'', ''X'', ''Xs'', ''{"base":"ক"}'')') = 'permission_denied',
  'institution staff cannot lock words or edit product defaults');
reset role;

rollback;
