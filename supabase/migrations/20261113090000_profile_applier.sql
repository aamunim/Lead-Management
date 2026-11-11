-- 0B.04 Profile applier, reset to defaults and Master Admin label control (Ch 7.5, 7.6, 7.9 rows 4–5; Ch 6.6; Ch 49.4;
-- Ch 5.3 Labels tab; D8, D19, D20). This file is the profile applier: the only code that reads which type profiles an
-- institution has (Ch 7.2; scripts/profiles/lint-institution-type.mjs allows only *profile_applier* files).
--
-- How it works:
--   * Applying profiles computes the institution's seeds from the newest published pack + profile versions and stores a
--     snapshot of them per item in seeded_items. Later versions never change an institution by themselves (Ch 7.6).
--   * The institution's own values stay where they always were (institution_labels, app_settings). Resolution is
--     own value → seeded value → pack / product / definition default, so re-seeding never overwrites an edit.
--   * modified_by_institution is kept up to date by triggers on the own-value tables.
--   * Removing a type removes only unmodified seeds; roles and data are never deleted (Ch 6.6, Ch 49.4).
-- See docs/dev/PROFILES.md.

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Data
-- ---------------------------------------------------------------------------------------------------------------------
-- Every institution has an industry, even while the wizard step is hidden (0B.04-T8; education today, D20).
alter table public.institutions add column industry text not null default 'education' references public.industries (key);

create table public.institution_profiles (
  institution_id  uuid not null references public.institutions (id) on delete cascade,
  profile_key     text not null,
  profile_version integer not null,
  pack_key        text not null,
  pack_version    integer not null,
  position        integer not null,
  applied_at      timestamptz not null default now(),
  applied_by      uuid references auth.users (id) on delete set null,
  primary key (institution_id, profile_key),
  foreign key (profile_key, profile_version) references public.type_profiles (key, version),
  foreign key (pack_key, pack_version) references public.industry_packs (industry_key, version)
);
create index institution_profiles_profile_idx on public.institution_profiles (institution_id, profile_key, profile_version);

-- Where each part of a profile is used (0B.04-T2): parts used now are applied now; the others are stored as seeds and
-- read by the block that is built later (Ch 7.8).
create table public.profile_areas (
  area         text primary key check (area ~ '^[a-z][a-z0-9_]*$'),
  merge        text not null check (merge in ('labels', 'settings', 'modules', 'roles', 'presets', 'recipients', 'union_key',
                                                'union_value', 'partition', 'partition_single', 'max_points', 'field_rules', 'words')),
  path         text[] not null,
  used_from    text not null,
  reset_area   text,
  sort         integer not null
);
insert into public.profile_areas (area, merge, path, used_from, reset_area, sort) values
  ('labels', 'labels', '{labels}', '0B.04', 'settings.terminology', 10),
  ('settings', 'settings', '{settings}', '0B.04', null, 20),
  ('roles', 'roles', '{role_template_set}', '0B.04', null, 30),
  ('modules', 'modules', '{modules}', '0B.05', null, 40),
  ('custom_fields', 'presets', '{custom_fields}', '1.01', null, 50),
  ('notification_recipients', 'recipients', '{notification_recipients}', '1.21', null, 60),
  ('stages', 'partition', '{stages}', '1.07', null, 70),
  ('lost_reasons', 'union_key', '{lost_reasons}', '1.01', null, 80),
  ('sources', 'union_key', '{sources}', '1.01', null, 90),
  ('tags', 'union_key', '{tags}', '1.01', null, 100),
  ('lead_score', 'max_points', '{lead_score,points}', '1.13', null, 110),
  ('message_templates', 'union_key', '{message_templates}', '1.20', null, 120),
  ('field_rules', 'field_rules', '{field_rules}', '1.25', null, 130),
  ('report_presets', 'union_value', '{report_presets}', '1.35', null, 140),
  ('fees', 'union_key', '{fees,heads}', '2.02', null, 150),
  ('client_number_pattern', 'partition_single', '{client_number_pattern}', '2.04', null, 160),
  ('documents', 'union_key', '{documents}', '2.13', null, 170),
  ('blocks', 'partition_single', '{blocks}', '2.16', null, 180),
  ('ai_words', 'words', '{ai_words}', '3.x', null, 190);

create table public.seeded_items (
  institution_id          uuid not null references public.institutions (id) on delete cascade,
  area                    text not null references public.profile_areas (area),
  item_key                text not null,
  value                   jsonb not null,
  source_profile          text not null,
  source_version          integer not null,
  modified_by_institution boolean not null default false,
  seeded_at               timestamptz not null default now(),
  primary key (institution_id, area, item_key)
);

alter table public.institution_profiles enable row level security;
alter table public.profile_areas enable row level security;
alter table public.seeded_items enable row level security;
revoke all on public.institution_profiles, public.profile_areas, public.seeded_items from anon, authenticated;
grant select on public.institution_profiles, public.profile_areas, public.seeded_items to authenticated;
create policy institution_profiles_read_own on public.institution_profiles for select to authenticated
  using (institution_id = (select app.auth_institution_id()));
create policy seeded_items_read_own on public.seeded_items for select to authenticated
  using (institution_id = (select app.auth_institution_id()));
create policy profile_areas_read on public.profile_areas for select to authenticated using (true);

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. What a set of profiles seeds (newest published versions; profiles in the given order)
-- ---------------------------------------------------------------------------------------------------------------------
-- Merge rules for mixed institutions (0B.04-T4, Proposed): stages, number patterns and later blocks are kept per type
-- (item key "<profile>.<key>"); lists are joined by key (the first type wins); on / off settings and modules are on when
-- any type turns them on; lead-score points take the highest; a hidden field beats a masked one; different default
-- recipients become "both"; different words for the same key are a conflict the person chooses in the preview
-- (p_label_choices {key: profile}); without a choice the first type wins.
create or replace function app.profile_seed_set(p_profiles text[], p_label_choices jsonb default '{}')
returns table (area text, item_key text, value jsonb, source_profile text, source_version integer)
language sql stable set search_path = '' as $$
  with p as (
    select u.ord::integer as ord, t.key, t.version, t.industry_key, t.payload
      from unnest(p_profiles) with ordinality as u (key, ord)
      cross join lateral (select * from public.type_profiles t where t.key = u.key and t.status = 'published'
                           order by t.version desc limit 1) t
  ),
  pk as (
    select k.industry_key, k.version, k.payload from public.industry_packs k
     where k.industry_key = (select p.industry_key from p order by p.ord limit 1) and k.status = 'published'
     order by k.version desc limit 1
  ),
  lab as (
    select 0 as ord, 'pack:' || pk.industry_key as src, pk.version, e.key, e.value from pk, jsonb_each(pk.payload -> 'labels') e
    union all
    select p.ord, p.key, p.version, e.key, e.value from p, jsonb_each(p.payload -> 'labels') e
  ),
  labels as (
    select distinct on (lab.key) 'labels'::text as area, lab.key as item_key,
           jsonb_build_object('en_singular', btrim(lab.value ->> 'en_singular'), 'en_plural', btrim(lab.value ->> 'en_plural'),
                              'bn_forms', app.bn_forms(btrim(lab.value -> 'bn' ->> 'base'), lk.animate, lab.value -> 'bn')) as value,
           lab.src, lab.version
      from lab join public.label_keys lk on lk.key = lab.key
     order by lab.key, (lab.src = coalesce(p_label_choices ->> lab.key, '')) desc, (lab.ord = 0), lab.ord
  ),
  st as (select p.ord, p.key as src, p.version, e.key, e.value from p, jsonb_each(p.payload -> 'settings') e),
  settings as (
    select 'settings'::text, st.key,
           case when bool_and(jsonb_typeof(st.value) = 'object' and st.value ? 'enabled')
                then (array_agg(st.value order by st.ord))[1]
                     || jsonb_build_object('enabled', bool_or(coalesce(st.value -> 'enabled' = 'true'::jsonb, false)))
                else (array_agg(st.value order by st.ord))[1] end,
           (array_agg(st.src order by st.ord))[1], (array_agg(st.version order by st.ord))[1]
      from st group by st.key
  ),
  md as (
    select 0 as ord, 'pack:' || pk.industry_key as src, pk.version, m ->> 'key' as key, (m -> 'default_on') = 'true'::jsonb as on_
      from pk, jsonb_array_elements(pk.payload -> 'modules') m
    union all
    select p.ord, p.key, p.version, e.key, e.value = 'true'::jsonb from p, jsonb_each(p.payload -> 'modules') e
  ),
  modules as (
    select 'modules'::text, md.key,
           to_jsonb(coalesce(bool_or(md.on_) filter (where md.ord > 0), bool_or(md.on_))),
           (array_agg(md.src order by md.ord > 0 desc, md.ord))[1], (array_agg(md.version order by md.ord > 0 desc, md.ord))[1]
      from md group by md.key
  ),
  roles as (
    select distinct on (p.payload ->> 'role_template_set') 'roles'::text, p.payload ->> 'role_template_set',
           jsonb_build_object('set', p.payload ->> 'role_template_set'), p.key, p.version
      from p order by p.payload ->> 'role_template_set', p.ord
  ),
  presets as (
    select distinct on (c.value) 'custom_fields'::text, c.value, f.f, p.key, p.version
      from p cross join lateral jsonb_array_elements_text(p.payload -> 'custom_fields') c
      join lateral (select x as f from pk, jsonb_array_elements(pk.payload -> 'field_presets') x where x ->> 'key' = c.value) f on true
     order by c.value, p.ord
  ),
  recipients as (
    select 'notification_recipients'::text, 'default'::text,
           case when count(distinct p.payload -> 'notification_recipients' ->> 'default') = 1
                then to_jsonb(min(p.payload -> 'notification_recipients' ->> 'default')) else '"both"'::jsonb end,
           (array_agg(p.key order by p.ord))[1], (array_agg(p.version order by p.ord))[1]
      from p having count(*) > 0
  ),
  union_key as (
    select distinct on (a.area, e ->> 'key') a.area, e ->> 'key', e, p.key, p.version
      from public.profile_areas a cross join p cross join lateral jsonb_array_elements(coalesce(p.payload #> a.path, '[]')) e
     where a.merge = 'union_key'
     order by a.area, e ->> 'key', p.ord
  ),
  union_value as (
    select distinct on (a.area, e) a.area, e, '{}'::jsonb, p.key, p.version
      from public.profile_areas a cross join p cross join lateral jsonb_array_elements_text(coalesce(p.payload #> a.path, '[]')) e
     where a.merge = 'union_value'
     order by a.area, e, p.ord
  ),
  stages as (
    select 'stages'::text, p.key || '.' || (s.e ->> 'key'), s.e || jsonb_build_object('type', p.key, 'position', s.n), p.key, p.version
      from p cross join lateral jsonb_array_elements(p.payload -> 'stages') with ordinality as s (e, n)
  ),
  singles as (
    select a.area, p.key, p.payload #> a.path, p.key, p.version
      from public.profile_areas a cross join p where a.merge = 'partition_single' and p.payload #> a.path is not null
  ),
  points as (
    select 'lead_score'::text, e.key, to_jsonb(max(e.value::text::integer)),
           (array_agg(p.key order by p.ord))[1], (array_agg(p.version order by p.ord))[1]
      from p cross join lateral jsonb_each(p.payload -> 'lead_score' -> 'points') e group by e.key
  ),
  rules as (
    select 'field_rules'::text, (r ->> 'role') || '.' || (r ->> 'field'),
           jsonb_build_object('role', r ->> 'role', 'field', r ->> 'field',
                              'access', case when bool_or(r ->> 'access' = 'hidden') then 'hidden' else 'masked' end),
           (array_agg(p.key order by p.ord))[1], (array_agg(p.version order by p.ord))[1]
      from p cross join lateral jsonb_array_elements(p.payload -> 'field_rules') r group by r ->> 'role', r ->> 'field'
  ),
  words as (
    select 'ai_words'::text, l.lang, (select jsonb_agg(distinct w) from p p2, jsonb_array_elements_text(p2.payload -> 'ai_words' -> l.lang) w),
           (array_agg(p.key order by p.ord))[1], (array_agg(p.version order by p.ord))[1]
      from p cross join (values ('en'), ('bn')) as l (lang) group by l.lang
  )
  select * from labels union all select * from settings union all select * from modules union all select * from roles
  union all select * from presets union all select * from recipients union all select * from union_key
  union all select * from union_value union all select * from stages union all select * from singles
  union all select * from points union all select * from rules union all select * from words
$$;

-- Words two or more chosen types disagree on (shown in the preview for a choice).
create or replace function app.profile_label_conflicts(p_profiles text[], p_label_choices jsonb default '{}') returns jsonb
language sql stable set search_path = '' as $$
  with p as (
    select u.ord, t.key, t.payload from unnest(p_profiles) with ordinality as u (key, ord)
      cross join lateral (select * from public.type_profiles t where t.key = u.key and t.status = 'published'
                           order by t.version desc limit 1) t
  ), lab as (
    select p.ord, p.key as profile, e.key, e.value from p, jsonb_each(p.payload -> 'labels') e
  )
  select coalesce(jsonb_agg(jsonb_build_object('key', c.key,
           'chosen', coalesce(p_label_choices ->> c.key, c.first_profile), 'options', c.options) order by c.key), '[]'::jsonb)
    from (select lab.key, (array_agg(lab.profile order by lab.ord))[1] as first_profile,
                 jsonb_agg(jsonb_build_object('profile', lab.profile, 'en_singular', lab.value ->> 'en_singular',
                                              'bn', lab.value -> 'bn' ->> 'base') order by lab.ord) as options
            from lab group by lab.key
          having count(distinct (lab.value ->> 'en_singular', lab.value -> 'bn' ->> 'base')) > 1) c
$$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. "Modified by the institution" (0B.04-T3): own values live in institution_labels / app_settings
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function app.seeded_mark_modified() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_area        text := case tg_table_name when 'institution_labels' then 'labels' else 'settings' end;
  v_institution uuid;
  v_key         text;
begin
  if tg_op = 'DELETE' then
    v_institution := old.institution_id;
    v_key := old.key;
  else
    v_institution := new.institution_id;
    v_key := new.key;
  end if;
  update public.seeded_items set modified_by_institution = (tg_op <> 'DELETE')
   where institution_id = v_institution and area = v_area and item_key = v_key
     and modified_by_institution is distinct from (tg_op <> 'DELETE');
  return null;
end $$;
create trigger institution_labels_seed_modified after insert or update or delete on public.institution_labels
  for each row execute function app.seeded_mark_modified();
create trigger app_settings_seed_modified after insert or update or delete on public.app_settings
  for each row execute function app.seeded_mark_modified();

-- ---------------------------------------------------------------------------------------------------------------------
-- 4. Resolution: own value → seeded value → pack / product / definition default
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function app.institution_label_scopes(p_institution uuid)
returns table (pack text, profile text) language sql stable set search_path = '' as $$
  select coalesce((select i.industry from public.institutions i where i.id = p_institution), 'education'), null::text
$$;

create or replace function app.label_default(p_institution uuid, p_key text) returns jsonb
language sql stable set search_path = '' as $$
  select coalesce(
    (select jsonb_build_object('en_singular', s.value ->> 'en_singular', 'en_plural', s.value ->> 'en_plural',
                               'bn_forms', s.value -> 'bn_forms',
                               'source', case when s.source_profile like 'pack:%' then 'pack' else 'profile' end)
       from public.seeded_items s where s.institution_id = p_institution and s.area = 'labels' and s.item_key = p_key),
    (select jsonb_build_object('en_singular', d.en_singular, 'en_plural', d.en_plural, 'bn_forms', d.bn_forms, 'source', d.scope)
       from public.label_defaults d, app.institution_label_scopes(p_institution) s
      where d.key = p_key and ((d.scope = 'pack' and d.scope_key = s.pack) or d.scope = 'product')
      order by case d.scope when 'pack' then 1 else 2 end
      limit 1))
$$;

create or replace function app.type_profile_setting_default(p_institution uuid, p_key text) returns jsonb
language sql stable set search_path = '' as $$
  select s.value from public.seeded_items s where s.institution_id = p_institution and s.area = 'settings' and s.item_key = p_key
$$;

-- Template roles (0A.16), completed for a second or changed type: never a second Super Admin role.
create or replace function app.apply_role_template(p_institution uuid, p_profile text) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  t record;
  v_role uuid;
  v_count integer := 0;
begin
  if not exists (select 1 from public.role_templates where type_profile_key = p_profile) then
    raise exception 'role_template_unknown' using errcode = 'P0404', detail = p_profile;
  end if;
  for t in select * from public.role_templates where type_profile_key = p_profile order by sort loop
    select id into v_role from public.roles where institution_id = p_institution and is_system and template_key = t.role_key;
    -- One Super Admin role per institution: a second type's owner template is skipped (0B.04, mixed / changed types).
    if v_role is null and t.is_super_admin
       and exists (select 1 from public.roles r where r.institution_id = p_institution and r.is_super_admin) then
      continue;
    end if;
    if v_role is null then
      insert into public.roles (institution_id, name_key, is_system, is_super_admin, template_key, type_profile_key, rank_for_sorting, flags)
      values (p_institution, t.name_key, true, t.is_super_admin, t.role_key, p_profile, t.sort, t.flags)
      returning id into v_role;
      v_count := v_count + 1;
    end if;
    if t.is_super_admin then
      insert into public.role_permissions (institution_id, role_id, permission_key) values (p_institution, v_role, '*') on conflict do nothing;
    else
      insert into public.role_permissions (institution_id, role_id, permission_key, scope)
      select p_institution, v_role, p.key, case when p.scopable then coalesce(nullif(g.value #>> '{}', 'true'), 'own') end
        from public.permissions p
        cross join lateral (select coalesce(p.default_for_templates -> t.role_key, t.extra_grants -> p.key) as value) g
       where p.kind = 'institution' and p.key <> '*' and p.retired_at is null and g.value is not null
      on conflict do nothing;
    end if;
  end loop;
  return v_count;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 5. Preview and apply
-- ---------------------------------------------------------------------------------------------------------------------
-- Checks a choice of types: known, published, one industry, open for sign-up unless it is the current industry.
create or replace function app.profiles_check(p_institution uuid, p_profiles text[]) returns text
language plpgsql stable set search_path = '' as $$
declare
  v_industries text[];
begin
  if coalesce(cardinality(p_profiles), 0) = 0 or cardinality(p_profiles) > 9
     or (select count(distinct x) from unnest(p_profiles) x) <> cardinality(p_profiles) then
    raise exception 'profile_choice_invalid' using errcode = 'P0422', detail = 'choose one or more different types';
  end if;
  if exists (select 1 from unnest(p_profiles) x
              where not exists (select 1 from public.type_profiles t where t.key = x and t.status = 'published')) then
    raise exception 'profile_choice_invalid' using errcode = 'P0422', detail = 'unknown type';
  end if;
  select array_agg(distinct t.industry_key) into v_industries from public.type_profiles t where t.key = any (p_profiles);
  if cardinality(v_industries) <> 1 then
    raise exception 'profile_choice_invalid' using errcode = 'P0422', detail = 'all types must be of one industry';
  end if;
  if v_industries[1] is distinct from (select i.industry from public.institutions i where i.id = p_institution)
     and not exists (select 1 from public.industries i where i.key = v_industries[1] and i.signup_open) then
    raise exception 'profile_choice_invalid' using errcode = 'P0422', detail = 'industry not open';
  end if;
  return v_industries[1];
end $$;

-- What applying p_profiles would change for the institution, per area; never deletes data.
--   add: a new seed; change: a different seed (the institution sees it unless it changed the item itself);
--   remove: an unmodified seed of a type no longer chosen (back to the pack / product default);
--   kept: the institution changed the item itself, so it keeps its own value.
create or replace function app.profile_preview(p_institution uuid, p_profiles text[], p_exclude text[] default '{}',
                                               p_label_choices jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_industry text := app.profiles_check(p_institution, p_profiles);
begin
  return jsonb_build_object(
    'industry', v_industry,
    'profiles', (select jsonb_agg(jsonb_build_object('key', t.key, 'version', t.version, 'name', t.payload -> 'name') order by u.ord)
                   from unnest(p_profiles) with ordinality as u (key, ord)
                   cross join lateral (select * from public.type_profiles t where t.key = u.key and t.status = 'published'
                                        order by t.version desc limit 1) t),
    'label_conflicts', app.profile_label_conflicts(p_profiles, p_label_choices),
    'areas', coalesce((
      with d as (select * from app.profile_seed_set(p_profiles, p_label_choices) x where not (x.area = any (p_exclude))),
           c as (select * from public.seeded_items s where s.institution_id = p_institution and not (s.area = any (p_exclude))),
           j as (
             select coalesce(d.area, c.area) as area, coalesce(d.item_key, c.item_key) as item_key, c.value as before, d.value as after,
                    case when c.item_key is null then 'add'
                         when d.item_key is null and (c.modified_by_institution or c.area = 'roles') then 'kept'
                         when d.item_key is null then 'remove'
                         when d.value is not distinct from c.value then 'same'
                         when c.modified_by_institution then 'kept'
                         else 'change' end as action
               from d full join c on c.area = d.area and c.item_key = d.item_key)
      select jsonb_agg(jsonb_build_object('area', a.area, 'used_from', a.used_from,
               'add', (select count(*) from j where j.area = a.area and j.action = 'add'),
               'change', (select count(*) from j where j.area = a.area and j.action = 'change'),
               'remove', (select count(*) from j where j.area = a.area and j.action = 'remove'),
               'kept', (select count(*) from j where j.area = a.area and j.action = 'kept'),
               'items', coalesce((select jsonb_agg(jsonb_build_object('key', j.item_key, 'action', j.action, 'before', j.before, 'after', j.after)
                                                   order by j.item_key)
                                    from (select * from j where j.area = a.area and j.action <> 'same' order by j.item_key limit 60) j), '[]'::jsonb))
             order by a.sort)
        from public.profile_areas a
       where exists (select 1 from j where j.area = a.area and j.action <> 'same')), '[]'::jsonb));
end $$;

-- Applies the types (0B.04-T2, T4, T6): stores the seeds, completes the template roles, records the versions.
create or replace function app.apply_profiles(p_institution uuid, p_profiles text[], p_exclude text[] default '{}',
                                              p_label_choices jsonb default '{}', p_reason text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_industry text := app.profiles_check(p_institution, p_profiles);
  v_before   jsonb;
  v_after    jsonb;
  v_set      text;
  v_roles    integer := 0;
begin
  v_before := (select jsonb_agg(ip.profile_key || ' v' || ip.profile_version order by ip.position)
                 from public.institution_profiles ip where ip.institution_id = p_institution);
  drop table if exists pg_temp.profile_seed;
  create temp table profile_seed on commit drop as
    select * from app.profile_seed_set(p_profiles, p_label_choices) x where not (x.area = any (coalesce(p_exclude, '{}')));

  insert into public.seeded_items as s (institution_id, area, item_key, value, source_profile, source_version, modified_by_institution)
  select p_institution, d.area, d.item_key, d.value, d.source_profile, d.source_version,
         case d.area when 'labels' then exists (select 1 from public.institution_labels l where l.institution_id = p_institution and l.key = d.item_key)
                     when 'settings' then exists (select 1 from public.app_settings a where a.institution_id = p_institution and a.key = d.item_key)
                     else false end
    from pg_temp.profile_seed d
  on conflict (institution_id, area, item_key) do update
    set value = excluded.value, source_profile = excluded.source_profile, source_version = excluded.source_version, seeded_at = now()
    where s.value is distinct from excluded.value or s.source_profile is distinct from excluded.source_profile
       or s.source_version is distinct from excluded.source_version;

  -- A type no longer chosen: its unmodified seeds go (back to the defaults); edited items and roles stay.
  delete from public.seeded_items s
   where s.institution_id = p_institution and not (s.area = any (coalesce(p_exclude, '{}'))) and s.area <> 'roles'
     and not s.modified_by_institution
     and not exists (select 1 from pg_temp.profile_seed d where d.area = s.area and d.item_key = s.item_key);

  for v_set in select d.item_key from pg_temp.profile_seed d where d.area = 'roles' loop
    v_roles := v_roles + app.apply_role_template(p_institution, v_set);
  end loop;

  delete from public.institution_profiles where institution_id = p_institution;
  insert into public.institution_profiles (institution_id, profile_key, profile_version, pack_key, pack_version, position, applied_by)
  select p_institution, t.key, t.version, k.industry_key, k.version, u.ord, auth.uid()
    from unnest(p_profiles) with ordinality as u (key, ord)
    cross join lateral (select * from public.type_profiles t where t.key = u.key and t.status = 'published' order by t.version desc limit 1) t
    cross join lateral (select * from public.industry_packs k where k.industry_key = t.industry_key and k.status = 'published'
                         order by k.version desc limit 1) k;
  update public.institutions set industry = v_industry where id = p_institution and industry is distinct from v_industry;

  v_after := (select jsonb_agg(ip.profile_key || ' v' || ip.profile_version order by ip.position)
                from public.institution_profiles ip where ip.institution_id = p_institution);
  perform app.audit(p_institution, 'institution.profiles_applied', 'institution', p_institution::text,
                    jsonb_build_object('profiles', v_before),
                    jsonb_build_object('profiles', v_after, 'excluded', to_jsonb(coalesce(p_exclude, '{}')), 'label_choices', p_label_choices),
                    p_reason);
  return jsonb_build_object('profiles', v_after, 'roles_created', v_roles,
                            'seeds', (select count(*) from public.seeded_items where institution_id = p_institution),
                            'settings_version', app.bump_settings_version(p_institution));
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 6. Institution RPCs: Settings → Institution type, reset to profile defaults (settings.institution_type, sensitive)
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function public.profile_state() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_institution uuid := app.require_active_session();
  v_industry    text;
begin
  if not app.settings_write_allowed(v_institution, 'settings.institution_type') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  select industry into v_industry from public.institutions where id = v_institution;
  return jsonb_build_object(
    'industry', v_industry,
    'applied', coalesce((select jsonb_agg(jsonb_build_object('key', ip.profile_key, 'version', ip.profile_version,
                 'name', t.payload -> 'name',
                 'latest_version', (select max(t2.version) from public.type_profiles t2 where t2.key = ip.profile_key and t2.status = 'published'))
                 order by ip.position)
               from public.institution_profiles ip join public.type_profiles t on t.key = ip.profile_key and t.version = ip.profile_version
              where ip.institution_id = v_institution), '[]'::jsonb),
    'available', coalesce((select jsonb_agg(jsonb_build_object('key', t.key, 'version', t.version, 'name', t.payload -> 'name',
                   'description', t.payload -> 'description') order by t.sort, t.key)
                 from public.type_profiles t
                where t.industry_key = v_industry and t.status = 'published'
                  and t.version = (select max(t2.version) from public.type_profiles t2 where t2.key = t.key and t2.status = 'published')), '[]'::jsonb),
    'areas', coalesce((select jsonb_agg(jsonb_build_object('area', a.area, 'used_from', a.used_from,
                 'items', (select count(*) from public.seeded_items s where s.institution_id = v_institution and s.area = a.area),
                 'modified', (select count(*) from public.seeded_items s where s.institution_id = v_institution and s.area = a.area
                                and s.modified_by_institution)) order by a.sort)
               from public.profile_areas a), '[]'::jsonb),
    'reset_areas', coalesce((
      select jsonb_agg(jsonb_build_object('area', x.area, 'own', x.own) order by x.sort, x.area)
        from (select 'settings.terminology' as area, 0 as sort,
                     (select count(*) from public.institution_labels l where l.institution_id = v_institution and not l.locked_by_platform) as own
              union all
              select d.area, 1, count(*) from public.app_settings s join public.setting_definitions d on d.key = s.key
               where s.institution_id = v_institution and d.stored_in = 'app_settings' and d.scope = 'institution'
               group by d.area) x where x.own > 0), '[]'::jsonb));
end $$;

create or replace function public.profile_change_preview(p_profiles text[], p_exclude text[] default '{}', p_label_choices jsonb default '{}')
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_institution uuid := app.require_active_session();
begin
  if not app.settings_write_allowed(v_institution, 'settings.institution_type') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  return app.profile_preview(v_institution, p_profiles, coalesce(p_exclude, '{}'), coalesce(p_label_choices, '{}'));
end $$;

create or replace function public.profile_change_apply(p_profiles text[], p_exclude text[] default '{}', p_label_choices jsonb default '{}',
                                                       p_reason text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.require_active_session();
begin
  if not app.settings_write_allowed(v_institution, 'settings.institution_type') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  return app.apply_profiles(v_institution, p_profiles, coalesce(p_exclude, '{}'), coalesce(p_label_choices, '{}'), p_reason);
end $$;

-- Reset to profile defaults (0B.04-T5): p_area is 'settings.terminology' (the words) or a settings area such as
-- 'settings.fees'. Without p_confirm it only returns the preview: each own value and the default it goes back to.
create or replace function public.profile_reset(p_area text, p_confirm boolean default false) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.require_active_session();
  v_items       jsonb;
  v_count       integer := 0;
  v_key         text;
begin
  if not exists (select 1 from public.permissions p where p.key = p_area and p.kind = 'institution' and p.key like 'settings.%') then
    raise exception 'setting_unknown' using errcode = 'P0404', detail = p_area;
  end if;
  if not app.settings_write_allowed(v_institution, p_area) then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  if p_area = 'settings.terminology' then
    v_items := coalesce((select jsonb_agg(jsonb_build_object('key', l.key,
                 'current', jsonb_build_object('en_singular', l.en_singular, 'bn', l.bn_forms ->> 'base'),
                 'default', (select jsonb_build_object('en_singular', d ->> 'en_singular', 'bn', d -> 'bn_forms' ->> 'base', 'source', d ->> 'source')
                               from app.label_default(v_institution, l.key) d)) order by l.key)
               from public.institution_labels l where l.institution_id = v_institution and not l.locked_by_platform), '[]'::jsonb);
  else
    v_items := coalesce((select jsonb_agg(jsonb_build_object('key', s.key, 'current', s.value,
                 'default', jsonb_build_object('value', coalesce(app.type_profile_setting_default(v_institution, s.key), d.default_value),
                                               'source', case when app.type_profile_setting_default(v_institution, s.key) is null
                                                              then 'default' else 'type_profile' end)) order by s.key)
               from public.app_settings s join public.setting_definitions d on d.key = s.key
              where s.institution_id = v_institution and d.area = p_area and d.scope = 'institution' and d.stored_in = 'app_settings'), '[]'::jsonb);
  end if;
  if not coalesce(p_confirm, false) then
    return jsonb_build_object('area', p_area, 'items', v_items, 'applied', false);
  end if;
  if p_area = 'settings.terminology' then
    v_count := (public.label_reset_all(v_institution) ->> 'reset')::integer;
  else
    for v_key in select x ->> 'key' from jsonb_array_elements(v_items) x loop
      perform public.setting_reset(v_key, v_institution);
      v_count := v_count + 1;
    end loop;
    perform app.audit(v_institution, 'settings.reset_to_defaults', 'setting_area', p_area, jsonb_build_object('items', v_items), null,
                      'reset to profile defaults');
  end if;
  return jsonb_build_object('area', p_area, 'items', v_items, 'applied', true, 'reset', v_count,
                            'settings_version', app.bump_settings_version(v_institution));
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 7. Master Admin: institutions list, an institution's words and locks, product-default words (T9, T10)
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function public.platform_institutions_list() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not app.is_platform('platform.view') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'name', i.name, 'slug', i.slug, 'status', i.status,
           'industry', i.industry,
           'profiles', coalesce((select jsonb_agg(jsonb_build_object('key', ip.profile_key, 'version', ip.profile_version,
                          'name', t.payload -> 'name') order by ip.position)
                        from public.institution_profiles ip join public.type_profiles t on t.key = ip.profile_key and t.version = ip.profile_version
                       where ip.institution_id = i.id), '[]'::jsonb)) order by i.name)
    from public.institutions i), '[]'::jsonb);
end $$;

create or replace function public.platform_institution_labels(p_institution uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not app.is_platform('platform.view') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  if not exists (select 1 from public.institutions where id = p_institution) then
    raise exception 'record_unknown' using errcode = 'P0404', detail = p_institution::text;
  end if;
  return jsonb_build_object(
    'institution', (select jsonb_build_object('id', i.id, 'name', i.name, 'industry', i.industry) from public.institutions i where i.id = p_institution),
    'labels', (select jsonb_agg(jsonb_build_object('key', k.key, 'group', k.label_group, 'lockable', k.lockable,
                 'label', app.label_resolved(p_institution, k.key)) order by k.sort_order)
                 from public.label_keys k));
end $$;

-- Lock / unlock with a reason (0B.04-T9; platform.labels_lock). A locked word is read-only in the institution's
-- Terminology screen. Replaces the 0A.12 three-argument version (same calls still work: the reason is optional).
drop function public.label_lock(uuid, text, boolean);
create or replace function public.label_lock(p_institution_id uuid, p_key text, p_locked boolean, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_key  public.label_keys;
  v_cur  jsonb;
begin
  if not app.is_platform('platform.labels_lock') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  select * into v_key from public.label_keys where key = p_key;
  if not found then
    raise exception 'label_unknown' using errcode = 'P0404', detail = p_key;
  end if;
  if p_locked and not v_key.lockable then
    raise exception 'label_not_lockable' using errcode = 'P0422', detail = p_key;
  end if;
  v_cur := app.label_resolved(p_institution_id, p_key);
  insert into public.institution_labels (institution_id, key, en_singular, en_plural, bn_forms, locked_by_platform, updated_by)
  values (p_institution_id, p_key, v_cur ->> 'en_singular', v_cur ->> 'en_plural', v_cur -> 'bn_forms', p_locked, auth.uid())
  on conflict (institution_id, key) do update set locked_by_platform = p_locked, updated_by = auth.uid(), updated_at = now();
  perform app.audit(p_institution_id, 'label.locked', 'label', p_key, null, jsonb_build_object('locked', p_locked), p_reason);
  perform app.platform_audit(case when p_locked then 'label.locked' else 'label.unlocked' end, p_institution_id, 'label', p_key,
                             null, jsonb_build_object('locked', p_locked), p_reason);
  perform app.bump_settings_version(p_institution_id);
  return app.label_resolved(p_institution_id, p_key);
end $$;

-- Product-default words (the neutral words under every pack; T10). Never touches an institution's own words.
create or replace function public.platform_label_default_set(p_key text, p_en_singular text, p_en_plural text, p_bn_forms jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_key    public.label_keys;
  v_before jsonb;
  v_forms  jsonb;
  v_text   text;
begin
  if not app.is_platform('platform.profiles') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  select * into v_key from public.label_keys where key = p_key;
  if not found then
    raise exception 'label_unknown' using errcode = 'P0404', detail = p_key;
  end if;
  if nullif(btrim(p_en_singular), '') is null or nullif(btrim(p_en_plural), '') is null
     or nullif(btrim(coalesce(p_bn_forms ->> 'base', '')), '') is null then
    raise exception 'label_invalid' using errcode = 'P0422';
  end if;
  v_forms := app.bn_forms(btrim(p_bn_forms ->> 'base'), v_key.animate, p_bn_forms);
  foreach v_text in array array[btrim(p_en_singular), btrim(p_en_plural)] || array(select value from jsonb_each_text(v_forms)) loop
    if length(v_text) > v_key.max_length then
      raise exception 'label_too_long' using errcode = 'P0422', detail = format('%s: longer than %s characters', p_key, v_key.max_length);
    end if;
  end loop;
  select jsonb_build_object('en_singular', en_singular, 'en_plural', en_plural, 'bn_forms', bn_forms) into v_before
    from public.label_defaults where scope = 'product' and scope_key = '' and key = p_key;
  insert into public.label_defaults (scope, scope_key, key, en_singular, en_plural, bn_forms)
  values ('product', '', p_key, btrim(p_en_singular), btrim(p_en_plural), v_forms)
  on conflict (scope, scope_key, key) do update
    set en_singular = excluded.en_singular, en_plural = excluded.en_plural, bn_forms = excluded.bn_forms;
  perform app.platform_audit('label.product_default_changed', null, 'label', p_key, v_before,
                             jsonb_build_object('en_singular', btrim(p_en_singular), 'en_plural', btrim(p_en_plural), 'bn_forms', v_forms), null);
  return jsonb_build_object('key', p_key, 'en_singular', btrim(p_en_singular), 'en_plural', btrim(p_en_plural), 'bn_forms', v_forms);
end $$;

create or replace function public.platform_label_defaults() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not app.is_platform('platform.profiles') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  return (select jsonb_agg(jsonb_build_object('key', k.key, 'group', k.label_group, 'max_length', k.max_length,
            'en_singular', d.en_singular, 'en_plural', d.en_plural, 'bn_forms', d.bn_forms) order by k.sort_order)
            from public.label_keys k left join public.label_defaults d on d.key = k.key and d.scope = 'product' and d.scope_key = '');
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 8. Grants and registry
-- ---------------------------------------------------------------------------------------------------------------------
revoke all on function app.seeded_mark_modified(), app.profile_seed_set(text[], jsonb), app.profile_label_conflicts(text[], jsonb), app.profiles_check(uuid, text[]),
  app.profile_preview(uuid, text[], text[], jsonb), app.apply_profiles(uuid, text[], text[], jsonb, text) from public, anon, authenticated;
revoke all on function public.profile_state(), public.profile_change_preview(text[], text[], jsonb),
  public.profile_change_apply(text[], text[], jsonb, text), public.profile_reset(text, boolean), public.platform_institutions_list(),
  public.platform_institution_labels(uuid), public.label_lock(uuid, text, boolean, text),
  public.platform_label_default_set(text, text, text, jsonb), public.platform_label_defaults() from public, anon;
grant execute on function public.profile_state(), public.profile_change_preview(text[], text[], jsonb),
  public.profile_change_apply(text[], text[], jsonb, text), public.profile_reset(text, boolean), public.platform_institutions_list(),
  public.platform_institution_labels(uuid), public.label_lock(uuid, text, boolean, text),
  public.platform_label_default_set(text, text, text, jsonb), public.platform_label_defaults() to authenticated;

insert into app.definer_registry (function_name, reason, added_in, reviewer, tenant_check)
select f, r, '0B.04', 'architecture review 0B.04', t from (values
  ('app.seeded_mark_modified', 'Trigger: flags the institution''s own seeded item as modified when it saves its own word / setting (same institution row); not callable by app roles.', 'service_role_only'),
  ('app.profile_preview', 'Diff of seeds for one institution; called only by checked RPCs (active institution + permission); not callable by app roles.', 'service_role_only'),
  ('app.apply_profiles', 'The profile applier: writes seeds, template roles and versions of one institution; called by checked RPCs, seeds and onboarding; not callable by app roles.', 'service_role_only'),
  ('public.profile_state', 'Applied types, available types and seeded areas of the active institution; can(settings.institution_type).', 'filters_active_institution'),
  ('public.profile_change_preview', 'Preview of a type change for the active institution; can(settings.institution_type).', 'filters_active_institution'),
  ('public.profile_change_apply', 'Applies a type change to the active institution; can(settings.institution_type); audited.', 'filters_active_institution'),
  ('public.profile_reset', 'Preview / reset of one settings area of the active institution to profile defaults; can(that area); audited.', 'filters_active_institution'),
  ('public.platform_institutions_list', 'Institutions with industry and types for the panel; needs platform.view + aal2.', 'not_tenant_data'),
  ('public.platform_institution_labels', 'Words of one institution for the panel Labels tab; needs platform.view + aal2.', 'not_tenant_data'),
  ('public.label_lock', 'Platform lock of an institution word with a reason; needs platform.labels_lock + aal2; audited on both sides.', 'not_tenant_data'),
  ('public.platform_label_default_set', 'Edits a product-default word (label_defaults scope product); needs platform.profiles + aal2; audited.', 'not_tenant_data'),
  ('public.platform_label_defaults', 'Product-default words for the panel editor; needs platform.profiles + aal2.', 'not_tenant_data')
) as v (f, r, t)
on conflict (function_name) do update set reason = excluded.reason, added_in = excluded.added_in, tenant_check = excluded.tenant_check;
