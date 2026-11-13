-- 0A.12 tests: label keys and defaults, resolution layers, derived module names, Bangla forms, length limits,
-- platform lock, permissions, isolation, settings version and audit.
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
create temp table out (k text primary key, v jsonb);
grant all on out to authenticated;

\set inst_a '''a0000000-0000-4000-8000-00000000000a'''
\set inst_b '''b0000000-0000-4000-8000-00000000000b'''
\set inst_c '''c0000000-0000-4000-8000-00000000000c'''
\set user_a '''11111111-1111-4111-8111-111111111111'''
\set user_b '''22222222-2222-4222-8222-222222222222'''
\set user_platform '''55555555-5555-4555-8555-555555555555'''
update public.profiles set last_active_institution_id = null where user_id in (:user_a, :user_b);
delete from public.institution_labels where institution_id in (:inst_a, :inst_b);

-- 1. Every Ch 8.4 key exists with English singular/plural and all Bangla forms, in product and education pack.
select pg_temp.check((select count(*) from public.label_keys where key in ('lead', 'client', 'contact_person', 'network',
  'referrer', 'offering', 'cohort', 'slot_group', 'branch', 'external_board', 'board_id', 'conversion', 'converted',
  'conversion_cancelled', 'lost', 'appointment', 'assessment', 'merit_list', 'documents', 'client_number', 'fee',
  'installment', 'receipt', 'discount', 'caller', 'team_lead', 'conversion_officer', 'module.leads', 'module.clients',
  'module.network', 'module.conversion_contribution', 'module.conversion_flow', 'module.leaderboard', 'module.scorecard',
  'module.referrals', 'doc.receipt_title', 'doc.admit_card_title', 'doc.application_form_title', 'doc.id_card_title')) = 39,
  'every Ch 8.4 key exists (neutral names)');
select pg_temp.check(not exists (select 1 from public.label_keys k where not exists
    (select 1 from public.label_defaults d where d.key = k.key and d.scope = 'product'))
  and not exists (select 1 from public.label_keys k where not exists
    (select 1 from public.label_defaults d where d.key = k.key and d.scope = 'pack' and d.scope_key = 'education')),
  'every key has a product default and an education-pack default');
select pg_temp.check(not exists (select 1 from public.label_defaults d
  where not (d.bn_forms ?& array['base', 'plural', 'possessive', 'objective', 'plural_oblique'])),
  'every default has all five Bangla forms');
select pg_temp.check((select legacy_key from public.label_keys where key = 'module.clients') = 'module.students',
  'the old education key is kept as legacy_key');
select pg_temp.check(pg_temp.error_of('insert into public.label_keys (key, label_group, max_length, description) values (''student_card'', ''people'', 20, ''x'')')
  like '%label_keys_key_check%', 'a new key with an education word is refused (keys stay neutral)');

-- 2. Bangla forms.
select pg_temp.check(app.bn_forms('শিক্ষার্থী', true) = '{"base":"শিক্ষার্থী","plural":"শিক্ষার্থীরা","possessive":"শিক্ষার্থীর","objective":"শিক্ষার্থীকে","plural_oblique":"শিক্ষার্থীদের"}',
  'people: শিক্ষার্থী / শিক্ষার্থীরা / শিক্ষার্থীর / শিক্ষার্থীকে / শিক্ষার্থীদের');
select pg_temp.check(app.bn_forms('কোর্স', false) ->> 'plural' = 'কোর্সগুলো' and app.bn_forms('কোর্স', false) ->> 'possessive' = 'কোর্সের',
  'things: কোর্সগুলো, কোর্সের (consonant ending)');
select pg_temp.check(app.bn_forms('শাখা', false) ->> 'possessive' = 'শাখার', 'vowel-sign ending takes র');
select pg_temp.check(app.bn_forms('ID', false) ->> 'possessive' = 'ID-এর', 'Latin ending takes -এর');
select pg_temp.check(app.bn_forms('শিক্ষার্থী', true, '{"plural":"ছাত্রছাত্রীরা"}') ->> 'plural' = 'ছাত্রছাত্রীরা',
  'a manual form overrides the generated one');

-- 3. Resolution: pack (education) by default; profile and institution layers win; the product layer is the floor.
select pg_temp.check(app.label(:inst_a, 'client') = 'Student' and app.label(:inst_a, 'client', 'bn') = 'শিক্ষার্থী',
  'education pack default applies (Student / শিক্ষার্থী)');
select pg_temp.check(app.label(:inst_a, 'client', 'en', 'plural') = 'Students' and app.label(:inst_a, 'client', 'bn', 'plural_oblique') = 'শিক্ষার্থীদের',
  'forms are served by the server resolver (notifications, prints)');
select pg_temp.check(app.label(:inst_a, 'lead') = 'Lead', 'words that are the same in every business (Lead) come through the pack unchanged');
-- A type profile (0B.04 applier, Ch 8.5 university) overrides the pack for that institution only.
select app.apply_profiles(:inst_a, array['university']);
select pg_temp.check(app.label(:inst_a, 'offering') = 'Program' and app.label(:inst_b, 'offering') = 'Course',
  'a type profile (Ch 8.5 university) overrides the pack for that institution only');
delete from public.seeded_items where institution_id = :inst_a;
delete from public.institution_profiles where institution_id = :inst_a;
-- Without a pack (an industry whose pack is not published) the neutral product default applies.
insert into public.industries (key, name, sort) values ('no_pack', '{"en":"x","bn":"x"}', 999);
update public.institutions set industry = 'no_pack' where id = :inst_a;
select pg_temp.check(app.label(:inst_a, 'client') = 'Client', 'without a pack the neutral product default applies');
update public.institutions set industry = 'education' where id = :inst_a;

-- 4. Writes: staff refused until permissions exist; the Master Admin renames client → Trainee for A only.
select pg_temp.act_as(pg_temp.claims_for(:user_a));
select pg_temp.check(pg_temp.error_of('select public.label_set(''client'', ''Trainee'', ''Trainees'', ''{"base":"প্রশিক্ষণার্থী"}'')')
  like 'permission_denied%', 'staff cannot rename words before permissions exist (settings.terminology)');
insert into out select 'v_before', to_jsonb((public.labels_get() ->> 'settings_version')::bigint);
reset role;
select pg_temp.act_as((pg_temp.claims_for(:user_platform) || '{"aal":"aal2"}'));
insert into out select 'set', public.label_set('client', 'Trainee', 'Trainees', '{"base":"প্রশিক্ষণার্থী"}', :inst_a);
select pg_temp.check(pg_temp.error_of(format('select public.label_set(%L, %L, %L, %L, %L)', 'client', repeat('x', 41), 'Xs', '{"base":"x"}', :inst_a))
  like 'label_too_long%', 'a label longer than the key''s limit is refused (Ch 8.8)');
select pg_temp.check(pg_temp.error_of(format('select public.label_set(%L, %L, %L, %L, %L)', 'module.leaderboard', 'Leaderboard', 'Leaderboard', '{"base":"' || repeat('ক', 29) || '"}', :inst_a))
  like 'label_too_long%', '...also for Bangla forms');
select pg_temp.check(pg_temp.error_of(format('select public.label_set(%L, %L, %L, %L, %L)', 'client', ' ', 'Xs', '{"base":"x"}', :inst_a))
  like 'label_invalid%', 'empty words are refused');
select pg_temp.check(pg_temp.error_of(format('select public.label_set(%L, %L, %L, %L, %L)', 'no_such_key', 'X', 'Xs', '{"base":"x"}', :inst_a))
  like 'label_unknown%', 'an unknown key is refused');
reset role;
select pg_temp.check((select v -> 'label' ->> 'en_singular' from out where k = 'set') = 'Trainee', 'renamed: Trainee');
select pg_temp.check((select v -> 'label' -> 'bn_forms' ->> 'plural_oblique' from out where k = 'set') = 'প্রশিক্ষণার্থীদের',
  'Bangla forms generated for the new word (প্রশিক্ষণার্থীদের)');
select pg_temp.check(app.label(:inst_a, 'module.clients', 'en') = 'Trainees' and app.label(:inst_a, 'module.clients', 'bn') = 'প্রশিক্ষণার্থী',
  'the module name follows its base word (menu shows "Trainees")');
select pg_temp.check(app.label(:inst_b, 'client') = 'Student' and app.label(:inst_b, 'module.clients') = 'Students',
  'B is unchanged');
select pg_temp.check(exists (select 1 from public.audit_log where institution_id = :inst_a and action = 'label.changed' and target_id = 'client')
  and exists (select 1 from public.domain_events where institution_id = :inst_a and event_key = 'label.changed' and payload ->> 'en_singular' = 'Trainee'),
  'renaming is audited and emitted');

-- 5. What the app gets: labels_get for the active institution; the settings version rose; B cannot see A's rows.
select pg_temp.act_as(pg_temp.claims_for(:user_a));
insert into out select 'a', public.labels_get();
select pg_temp.check((select v -> 'labels' -> 'client' -> 'resolved' ->> 'en_singular' from out where k = 'a') = 'Trainee', 'A gets Trainee');
select pg_temp.check((select v -> 'labels' -> 'client' -> 'default' ->> 'en_singular' from out where k = 'a') = 'Student',
  '...with the default underneath (for search and reset)');
select pg_temp.check((select (v ->> 'settings_version')::bigint from out where k = 'a') > (select (v #>> '{}')::bigint from out where k = 'v_before'),
  'renaming bumps the settings version (every device refreshes, Ch 8.10 #7)');
select pg_temp.check((select count(*) from public.institution_labels) = 1, 'A sees only its own label rows');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:user_b));
select pg_temp.check((public.labels_get() -> 'labels' -> 'client' -> 'resolved' ->> 'en_singular') = 'Student', 'B gets Student');
select pg_temp.check((select count(*) from public.institution_labels) = 0, 'B sees none of A''s label rows');
select pg_temp.check(pg_temp.error_of(format('select public.label_set(%L, %L, %L, %L, %L)', 'client', 'X', 'Xs', '{"base":"x"}', :inst_a))
  like 'permission_denied%', 'B cannot write A''s labels');
select pg_temp.check(pg_temp.error_of('insert into public.institution_labels (institution_id, key, en_singular, en_plural, bn_forms) values ('''
  || :inst_b || ''', ''client'', ''x'', ''x'', ''{}'')') like 'permission denied%', 'the app cannot write label rows directly');
reset role;

-- 6. Platform lock: the Master Admin freezes the receipt title of A; the lock survives a reset by staff later.
select pg_temp.act_as((pg_temp.claims_for(:user_platform) || '{"aal":"aal2"}'));
select pg_temp.check(pg_temp.error_of(format('select public.label_lock(%L, %L, true)', :inst_a, 'client')) like 'label_not_lockable%',
  'only lockable keys can be locked');
select public.label_lock(:inst_a, 'doc.receipt_title', true);
reset role;
select pg_temp.check((select locked_by_platform from public.institution_labels where institution_id = :inst_a and key = 'doc.receipt_title'),
  'the receipt title of A is locked (current value frozen)');
-- A non-platform writer (simulated: staff granted the area later) is refused by the lock.
create or replace function app.settings_write_allowed(p_institution uuid, p_area text) returns boolean
language sql stable set search_path = '' as $$ select true $$;
select pg_temp.act_as(pg_temp.claims_for(:user_a));
select pg_temp.check(pg_temp.error_of('select public.label_set(''doc.receipt_title'', ''Bill'', ''Bills'', ''{"base":"বিল"}'')')
  like 'label_locked%', 'a locked label cannot be changed by the institution');
select pg_temp.check(pg_temp.error_of('select public.label_reset(''doc.receipt_title'')') like 'label_locked%',
  '...nor reset');
insert into out select 'reset', public.label_reset('client');
reset role;
select pg_temp.check((select v -> 'label' ->> 'en_singular' from out where k = 'reset') = 'Student', 'reset returns to the default');

-- 7. The weird-labels test institution exists for screenshot tests (T10).
select pg_temp.check(app.label(:inst_c, 'client', 'en', 'plural') = 'Professional Development Participants'
  and app.label(:inst_c, 'module.clients') = 'Professional Development Participants', 'weird labels institution is seeded');
rollback;
