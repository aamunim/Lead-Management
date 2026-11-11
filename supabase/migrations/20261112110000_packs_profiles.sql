-- 0B.03 Industry packs and type profiles as versioned data (Ch 7.1–7.10, Ch 49.2–49.7; D8, D18, D19, D20, D26).
-- Two levels: industry → pack (industry_packs) → type profiles (type_profiles). Rows are versioned: a draft is edited in
-- the panel, publishing validates it and freezes it; a published version never changes (a change is a new version).
-- The seed content (education pack, nine profiles, industry list) is generated from config/packs by
-- scripts/profiles/gen-seed.mjs into the next migration. Applying a profile to an institution is 0B.04.
-- See docs/dev/PROFILES.md.

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------------------------------------------------------
-- JSON schemas the server validates data against (also the files in config/schemas; the seed migration copies them).
create table public.data_schemas (
  key        text primary key check (key ~ '^[a-z][a-z0-9_]*$'),
  schema     jsonb not null,
  updated_at timestamptz not null default now()
);

-- The industry list for the (hidden) first step of the setup wizard (Ch 6.3 step 1). Only industries with a published
-- pack can be opened for sign-up; now only education is open (D20).
create table public.industries (
  key         text primary key check (key ~ '^[a-z][a-z0-9_]*$'),
  name        jsonb not null check (jsonb_typeof(name -> 'en') = 'string' and jsonb_typeof(name -> 'bn') = 'string'),
  sort        integer not null,
  signup_open boolean not null default false,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references auth.users (id) on delete set null
);

create table public.industry_packs (
  industry_key text not null references public.industries (key) on delete cascade,
  version      integer not null check (version > 0),
  status       text not null default 'draft' check (status in ('draft', 'published')),
  payload      jsonb not null check (jsonb_typeof(payload) = 'object'),
  notes        text check (length(notes) <= 500),
  created_by   uuid references auth.users (id) on delete set null,
  created_at   timestamptz not null default now(),
  published_by uuid references auth.users (id) on delete set null,
  published_at timestamptz,
  primary key (industry_key, version),
  check ((status = 'published') = (published_at is not null))
);
create unique index industry_packs_one_draft on public.industry_packs (industry_key) where status = 'draft';

create table public.type_profiles (
  key          text not null check (key ~ '^[a-z][a-z0-9_]*$'),
  version      integer not null check (version > 0),
  industry_key text not null references public.industries (key) on delete cascade,
  status       text not null default 'draft' check (status in ('draft', 'published')),
  payload      jsonb not null check (jsonb_typeof(payload) = 'object'),
  notes        text check (length(notes) <= 500),
  sort         integer not null default 100,
  created_by   uuid references auth.users (id) on delete set null,
  created_at   timestamptz not null default now(),
  published_by uuid references auth.users (id) on delete set null,
  published_at timestamptz,
  primary key (key, version),
  check ((status = 'published') = (published_at is not null))
);
create unique index type_profiles_one_draft on public.type_profiles (key) where status = 'draft';
create index type_profiles_industry_idx on public.type_profiles (industry_key, key);

-- Published versions are immutable: no update, no delete (0B.03-T1). Drafts may change and be published once.
create or replace function app.pack_version_immutable() returns trigger
language plpgsql set search_path = '' as $$
begin
  if old.status = 'published' then
    raise exception 'version_published' using errcode = 'P0409', detail = 'a published version never changes; save a new version';
  end if;
  return case tg_op when 'DELETE' then old else new end;
end $$;
create trigger industry_packs_immutable before update or delete on public.industry_packs
  for each row execute function app.pack_version_immutable();
create trigger type_profiles_immutable before update or delete on public.type_profiles
  for each row execute function app.pack_version_immutable();

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. Who reads what: institutions (and the sign-up wizard) only published data of open industries; never write.
--    The panel works through the RPCs below (platform.profiles + aal2).
-- ---------------------------------------------------------------------------------------------------------------------
alter table public.data_schemas enable row level security;
alter table public.industries enable row level security;
alter table public.industry_packs enable row level security;
alter table public.type_profiles enable row level security;
revoke all on public.data_schemas, public.industries, public.industry_packs, public.type_profiles from anon, authenticated;
grant select on public.data_schemas, public.industries, public.industry_packs, public.type_profiles to authenticated;
create policy data_schemas_read on public.data_schemas for select to authenticated using (true);
create policy industries_read on public.industries for select to authenticated
  using (signup_open or (select app.is_platform('platform.profiles')));
create policy industry_packs_read on public.industry_packs for select to authenticated
  using ((status = 'published' and exists (select 1 from public.industries i where i.key = industry_key and i.signup_open))
         or (select app.is_platform('platform.profiles')));
create policy type_profiles_read on public.type_profiles for select to authenticated
  using ((status = 'published' and exists (select 1 from public.industries i where i.key = industry_key and i.signup_open))
         or (select app.is_platform('platform.profiles')));

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. Validation (0B.03 server): the JSON schema, then the references the schema cannot check
-- ---------------------------------------------------------------------------------------------------------------------
-- Keys that appear more than once in an array of {key: …} objects.
create or replace function app.duplicate_keys(p_items jsonb, p_where text, p_field text default 'key') returns text[]
language sql immutable set search_path = '' as $$
  select coalesce(array_agg(format('%s: "%s" appears more than once', p_where, k)), '{}')
    from (select e ->> p_field as k from jsonb_array_elements(coalesce(p_items, '[]')) e
           group by 1 having count(*) > 1) d
$$;

-- The latest published pack of an industry (what new profiles of the industry build on).
create or replace function app.current_pack(p_industry text) returns jsonb
language sql stable set search_path = '' as $$
  select payload from public.industry_packs where industry_key = p_industry and status = 'published' order by version desc limit 1
$$;

-- Fields a field rule may name besides the pack's custom-field presets (core lead fields, Ch 11).
create or replace function app.core_rule_fields() returns text[]
language sql immutable set search_path = '' as $$
  select array['phone', 'email', 'address', 'discount_history', 'fee_balance']
$$;

-- Every problem of a pack (p_kind 'pack') or profile ('profile') payload; empty = valid.
create or replace function app.pack_payload_errors(p_kind text, p_industry text, p_payload jsonb) returns text[]
language plpgsql stable set search_path = '' as $$
declare
  v_errors text[];
  v_pack   jsonb;
begin
  if p_kind not in ('pack', 'profile') then
    return array['kind: must be pack or profile'];
  end if;
  if jsonb_typeof(p_payload) is distinct from 'object' then
    return array['payload: must be a JSON object'];
  end if;
  v_errors := app.validation_errors((select schema from public.data_schemas
                                      where key = case p_kind when 'pack' then 'industry_pack' else 'type_profile' end), p_payload);
  if cardinality(v_errors) > 0 then
    return v_errors;
  end if;

  -- Words: registered keys, within the key's length limit.
  v_errors := v_errors || array(select format('labels.%s: not a registered label key', k)
                                  from jsonb_object_keys(p_payload -> 'labels') k
                                 where not exists (select 1 from public.label_keys lk where lk.key = k));
  v_errors := v_errors || array(select format('labels.%s: longer than %s characters', e.key, lk.max_length)
                                  from jsonb_each(p_payload -> 'labels') e join public.label_keys lk on lk.key = e.key
                                 where greatest(length(e.value ->> 'en_singular'), length(e.value ->> 'en_plural'),
                                                length(e.value -> 'bn' ->> 'base')) > lk.max_length);
  -- Stages: unique keys, at least one won and one lost stage.
  v_errors := v_errors || app.duplicate_keys(p_payload -> 'stages', 'stages');
  if not exists (select 1 from jsonb_array_elements(p_payload -> 'stages') s where s ->> 'kind' = 'won') then
    v_errors := v_errors || 'stages: needs a stage of kind won'::text;
  end if;
  if not exists (select 1 from jsonb_array_elements(p_payload -> 'stages') s where s ->> 'kind' = 'lost') then
    v_errors := v_errors || 'stages: needs a stage of kind lost'::text;
  end if;

  if p_kind = 'pack' then
    v_errors := v_errors || app.duplicate_keys(p_payload -> 'modules', 'modules')
                         || app.duplicate_keys(p_payload -> 'field_presets', 'field_presets')
                         || app.duplicate_keys(p_payload -> 'sensitive_fields', 'sensitive_fields', 'field');
    v_errors := v_errors || array(select format('sensitive_fields.%s: not a field preset of the pack', s ->> 'field')
                                    from jsonb_array_elements(p_payload -> 'sensitive_fields') s
                                   where not exists (select 1 from jsonb_array_elements(p_payload -> 'field_presets') f
                                                      where f ->> 'key' = s ->> 'field'));
    v_errors := v_errors || array(select format('field_presets.%s: a choice needs options', f ->> 'key')
                                    from jsonb_array_elements(p_payload -> 'field_presets') f
                                   where f ->> 'type' = 'choice' and jsonb_array_length(coalesce(f -> 'options', '[]')) = 0);
    return v_errors;
  end if;

  -- Profile: builds on the industry's published pack.
  v_pack := app.current_pack(p_industry);
  if v_pack is null then
    return v_errors || format('industry %s has no published pack', coalesce(p_industry, '?'));
  end if;
  if not exists (select 1 from public.role_templates where type_profile_key = p_payload ->> 'role_template_set') then
    v_errors := v_errors || format('role_template_set: "%s" has no role templates', p_payload ->> 'role_template_set');
  end if;
  v_errors := v_errors || array(select format('custom_fields: "%s" is not a field preset of the pack', c)
                                  from jsonb_array_elements_text(p_payload -> 'custom_fields') c
                                 where not exists (select 1 from jsonb_array_elements(v_pack -> 'field_presets') f where f ->> 'key' = c));
  v_errors := v_errors || array(select format('modules.%s: not a module of the pack', m)
                                  from jsonb_object_keys(p_payload -> 'modules') m
                                 where not exists (select 1 from jsonb_array_elements(v_pack -> 'modules') pm where pm ->> 'key' = m));
  -- Setting defaults: institution settings kept in app_settings, each value valid for its schema.
  v_errors := v_errors || array(select format('settings.%s: not an institution setting', s.key)
                                  from jsonb_each(p_payload -> 'settings') s
                                 where not exists (select 1 from public.setting_definitions d where d.key = s.key
                                                      and d.scope = 'institution' and d.stored_in = 'app_settings'));
  v_errors := v_errors || array(select format('settings.%s: %s', s.key, array_to_string(app.validation_errors(d.schema, s.value), '; '))
                                  from jsonb_each(p_payload -> 'settings') s join public.setting_definitions d on d.key = s.key
                                 where cardinality(app.validation_errors(d.schema, s.value)) > 0);
  -- Field rules: a template role of the set, a pack preset or a core field.
  v_errors := v_errors || array(select format('field_rules: role "%s" is not in role template set %s', r ->> 'role', p_payload ->> 'role_template_set')
                                  from jsonb_array_elements(p_payload -> 'field_rules') r
                                 where not exists (select 1 from public.role_templates t
                                                    where t.type_profile_key = p_payload ->> 'role_template_set' and t.role_key = r ->> 'role'));
  v_errors := v_errors || array(select format('field_rules: unknown field "%s"', r ->> 'field')
                                  from jsonb_array_elements(p_payload -> 'field_rules') r
                                 where not (r ->> 'field' = any (app.core_rule_fields()))
                                   and not exists (select 1 from jsonb_array_elements(v_pack -> 'field_presets') f where f ->> 'key' = r ->> 'field'));
  v_errors := v_errors || app.duplicate_keys(p_payload -> 'documents', 'documents')
                       || app.duplicate_keys(p_payload -> 'fees' -> 'heads', 'fees.heads')
                       || app.duplicate_keys(p_payload -> 'message_templates', 'message_templates')
                       || app.duplicate_keys(p_payload -> 'lost_reasons', 'lost_reasons')
                       || app.duplicate_keys(p_payload -> 'sources', 'sources')
                       || app.duplicate_keys(p_payload -> 'tags', 'tags');
  return v_errors;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 4. Publishing: freezes the version and writes its words into label_defaults (scope pack / profile)
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function app.pack_sync_labels(p_kind text, p_key text, p_payload jsonb) returns void
language plpgsql security definer set search_path = '' as $$
begin
  delete from public.label_defaults where scope = p_kind and scope_key = p_key;
  insert into public.label_defaults (scope, scope_key, key, en_singular, en_plural, bn_forms)
  select p_kind, p_key, e.key, btrim(e.value ->> 'en_singular'), btrim(e.value ->> 'en_plural'),
         app.bn_forms(btrim(e.value -> 'bn' ->> 'base'), lk.animate, e.value -> 'bn')
    from jsonb_each(coalesce(p_payload -> 'labels', '{}')) e join public.label_keys lk on lk.key = e.key;
end $$;

-- Validates and publishes a version (used by the panel RPC and by the seed). Raises profile_invalid with the problems.
create or replace function app.pack_publish(p_kind text, p_key text, p_version integer, p_notes text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_payload  jsonb;
  v_industry text;
  v_errors   text[];
begin
  if p_kind = 'pack' then
    select payload, industry_key into v_payload, v_industry from public.industry_packs
     where industry_key = p_key and version = p_version and status = 'draft';
  else
    select payload, industry_key into v_payload, v_industry from public.type_profiles
     where key = p_key and version = p_version and status = 'draft';
  end if;
  if not found then
    raise exception 'version_unknown' using errcode = 'P0404', detail = format('%s %s v%s is not a draft', p_kind, p_key, p_version);
  end if;
  v_errors := app.pack_payload_errors(p_kind, v_industry, v_payload);
  if cardinality(v_errors) > 0 then
    raise exception 'profile_invalid' using errcode = 'P0422', detail = array_to_string(v_errors, E'\n');
  end if;
  if p_kind = 'pack' then
    update public.industry_packs set status = 'published', published_at = now(), published_by = auth.uid(),
           notes = coalesce(nullif(btrim(p_notes), ''), notes)
     where industry_key = p_key and version = p_version;
  else
    update public.type_profiles set status = 'published', published_at = now(), published_by = auth.uid(),
           notes = coalesce(nullif(btrim(p_notes), ''), notes)
     where key = p_key and version = p_version;
  end if;
  perform app.pack_sync_labels(p_kind, p_key, v_payload);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 5. Panel RPCs (platform.profiles + aal2; every write in the platform audit log)
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function public.platform_packs_list() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not app.is_platform('platform.profiles') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'key', i.key, 'name', i.name, 'signup_open', i.signup_open,
      'pack', (select jsonb_build_object(
                 'published_version', max(p.version) filter (where p.status = 'published'),
                 'draft_version', max(p.version) filter (where p.status = 'draft'))
                 from public.industry_packs p where p.industry_key = i.key having count(*) > 0),
      'profiles', coalesce((select jsonb_agg(jsonb_build_object('key', x.key, 'name', x.name,
                    'published_version', x.published_version, 'draft_version', x.draft_version) order by x.sort, x.key)
                  from (select t.key, min(t.sort) as sort,
                               (array_agg(t.payload -> 'name' order by t.status = 'published' desc, t.version desc))[1] as name,
                               max(t.version) filter (where t.status = 'published') as published_version,
                               max(t.version) filter (where t.status = 'draft') as draft_version
                          from public.type_profiles t where t.industry_key = i.key group by t.key) x), '[]'::jsonb))
    order by i.sort) from public.industries i), '[]'::jsonb);
end $$;

-- One pack or profile: every version (newest first) with its payload.
create or replace function public.platform_pack_get(p_kind text, p_key text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_versions jsonb;
  v_industry text;
begin
  if not app.is_platform('platform.profiles') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  if p_kind = 'pack' then
    select jsonb_agg(jsonb_build_object('version', v.version, 'status', v.status, 'payload', v.payload, 'notes', v.notes,
             'created_at', v.created_at, 'created_by', (select email from auth.users u where u.id = v.created_by),
             'published_at', v.published_at, 'published_by', (select email from auth.users u where u.id = v.published_by))
             order by v.version desc), max(v.industry_key)
      into v_versions, v_industry from public.industry_packs v where v.industry_key = p_key;
  elsif p_kind = 'profile' then
    select jsonb_agg(jsonb_build_object('version', v.version, 'status', v.status, 'payload', v.payload, 'notes', v.notes,
             'created_at', v.created_at, 'created_by', (select email from auth.users u where u.id = v.created_by),
             'published_at', v.published_at, 'published_by', (select email from auth.users u where u.id = v.published_by))
             order by v.version desc), max(v.industry_key)
      into v_versions, v_industry from public.type_profiles v where v.key = p_key;
  else
    raise exception 'kind_invalid' using errcode = 'P0422';
  end if;
  if v_versions is null then
    raise exception 'version_unknown' using errcode = 'P0404', detail = p_key;
  end if;
  return jsonb_build_object('kind', p_kind, 'key', p_key, 'industry_key', v_industry, 'versions', v_versions);
end $$;

create or replace function public.platform_pack_validate(p_kind text, p_key text, p_payload jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_industry text;
begin
  if not app.is_platform('platform.profiles') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  v_industry := case p_kind when 'pack' then p_key
                  else (select industry_key from public.type_profiles where key = p_key order by version desc limit 1) end;
  return to_jsonb(app.pack_payload_errors(p_kind, coalesce(v_industry, 'education'), p_payload));
end $$;

-- Saves the draft (a new version after the newest one, or the existing draft). Drafts may be incomplete; publishing
-- checks them. A new profile key needs p_industry.
create or replace function public.platform_pack_save_draft(p_kind text, p_key text, p_payload jsonb, p_notes text default null,
                                                           p_industry text default null) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_version  integer;
  v_industry text;
  v_before   jsonb;
begin
  if not app.is_platform('platform.profiles') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  if jsonb_typeof(p_payload) is distinct from 'object' then
    raise exception 'profile_invalid' using errcode = 'P0422', detail = 'payload: must be a JSON object';
  end if;
  if p_kind = 'pack' then
    if not exists (select 1 from public.industries where key = p_key) then
      raise exception 'version_unknown' using errcode = 'P0404', detail = p_key;
    end if;
    select version, payload into v_version, v_before from public.industry_packs where industry_key = p_key and status = 'draft';
    if found then
      update public.industry_packs set payload = p_payload, notes = p_notes, created_by = auth.uid(), created_at = now()
       where industry_key = p_key and version = v_version;
    else
      select coalesce(max(version), 0) + 1 into v_version from public.industry_packs where industry_key = p_key;
      insert into public.industry_packs (industry_key, version, payload, notes, created_by) values (p_key, v_version, p_payload, p_notes, auth.uid());
    end if;
  elsif p_kind = 'profile' then
    if p_key !~ '^[a-z][a-z0-9_]*$' then
      raise exception 'profile_invalid' using errcode = 'P0422', detail = 'key: lower-case letters, digits and _';
    end if;
    select industry_key into v_industry from public.type_profiles where key = p_key order by version desc limit 1;
    v_industry := coalesce(v_industry, p_industry);
    if v_industry is null or not exists (select 1 from public.industries where key = v_industry) then
      raise exception 'version_unknown' using errcode = 'P0404', detail = 'industry';
    end if;
    select version, payload into v_version, v_before from public.type_profiles where key = p_key and status = 'draft';
    if found then
      update public.type_profiles set payload = p_payload, notes = p_notes, created_by = auth.uid(), created_at = now()
       where key = p_key and version = v_version;
    else
      select coalesce(max(version), 0) + 1 into v_version from public.type_profiles where key = p_key;
      insert into public.type_profiles (key, version, industry_key, payload, notes, created_by, sort)
      values (p_key, v_version, v_industry, p_payload, p_notes, auth.uid(),
              coalesce((select max(sort) from public.type_profiles where key = p_key), 100));
    end if;
  else
    raise exception 'kind_invalid' using errcode = 'P0422';
  end if;
  perform app.platform_audit(p_kind || '.draft_saved', null, p_kind, p_key || ' v' || v_version, v_before, p_payload, p_notes);
  return v_version;
end $$;

create or replace function public.platform_pack_publish(p_kind text, p_key text, p_version integer, p_notes text default null) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not app.is_platform('platform.profiles') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  perform app.pack_publish(p_kind, p_key, p_version, p_notes);
  perform app.platform_audit(p_kind || '.published', null, p_kind, p_key || ' v' || p_version, null,
                             jsonb_build_object('version', p_version), p_notes);
end $$;

create or replace function public.platform_pack_discard_draft(p_kind text, p_key text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_version integer;
begin
  if not app.is_platform('platform.profiles') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  if p_kind = 'pack' then
    delete from public.industry_packs where industry_key = p_key and status = 'draft' returning version into v_version;
  else
    delete from public.type_profiles where key = p_key and status = 'draft' returning version into v_version;
  end if;
  if v_version is null then
    raise exception 'version_unknown' using errcode = 'P0404', detail = p_key;
  end if;
  perform app.platform_audit(p_kind || '.draft_discarded', null, p_kind, p_key || ' v' || v_version, null, null, null);
end $$;

-- Opens or closes an industry for sign-up (D19, D20). Opening needs a published pack with at least one published profile.
create or replace function public.platform_industry_set_open(p_key text, p_open boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_before boolean;
begin
  if not app.is_platform('platform.profiles') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  select signup_open into v_before from public.industries where key = p_key;
  if not found then
    raise exception 'version_unknown' using errcode = 'P0404', detail = p_key;
  end if;
  if p_open and (app.current_pack(p_key) is null
                 or not exists (select 1 from public.type_profiles where industry_key = p_key and status = 'published')) then
    raise exception 'industry_not_ready' using errcode = 'P0409', detail = 'publish the pack and a profile first';
  end if;
  update public.industries set signup_open = p_open, updated_at = now(), updated_by = auth.uid() where key = p_key;
  perform app.platform_audit('industry.signup_changed', null, 'industry', p_key,
                             jsonb_build_object('signup_open', v_before), jsonb_build_object('signup_open', p_open), null);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 6. The sign-up wizard: open industries with their published pack and profiles (names only; Ch 6.3 steps 1–2)
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function public.list_open_packs() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('key', i.key, 'name', i.name,
           'pack_version', (select max(p.version) from public.industry_packs p where p.industry_key = i.key and p.status = 'published'),
           'profiles', coalesce((select jsonb_agg(jsonb_build_object('key', t.key, 'version', t.version, 'name', t.payload -> 'name',
                                                                    'description', t.payload -> 'description') order by t.sort, t.key)
                                   from public.type_profiles t
                                  where t.industry_key = i.key and t.status = 'published'
                                    and t.version = (select max(t2.version) from public.type_profiles t2
                                                      where t2.key = t.key and t2.status = 'published')), '[]'::jsonb))
           order by i.sort), '[]'::jsonb)
    from public.industries i
   where i.signup_open and exists (select 1 from public.industry_packs p where p.industry_key = i.key and p.status = 'published')
$$;

revoke all on function app.pack_sync_labels(text, text, jsonb), app.pack_publish(text, text, integer, text) from public, anon, authenticated;
revoke all on function public.platform_packs_list(), public.platform_pack_get(text, text), public.platform_pack_validate(text, text, jsonb),
  public.platform_pack_save_draft(text, text, jsonb, text, text), public.platform_pack_publish(text, text, integer, text),
  public.platform_pack_discard_draft(text, text), public.platform_industry_set_open(text, boolean) from public, anon;
grant execute on function public.platform_packs_list(), public.platform_pack_get(text, text), public.platform_pack_validate(text, text, jsonb),
  public.platform_pack_save_draft(text, text, jsonb, text, text), public.platform_pack_publish(text, text, integer, text),
  public.platform_pack_discard_draft(text, text), public.platform_industry_set_open(text, boolean) to authenticated;
grant execute on function public.list_open_packs() to anon, authenticated;

insert into app.definer_registry (function_name, reason, added_in, reviewer, tenant_check)
select f, r, '0B.03', 'architecture review 0B.03', 'not_tenant_data' from (values
  ('app.pack_sync_labels', 'Writes product-level pack / profile default words (label_defaults) when a version is published.'),
  ('app.pack_publish', 'Validates and freezes a pack / profile version; called by the panel RPC and the seed only.'),
  ('public.platform_packs_list', 'Lists industries, packs and profiles (product data); needs platform.profiles + aal2.'),
  ('public.platform_pack_get', 'Versions of one pack / profile (product data); needs platform.profiles + aal2.'),
  ('public.platform_pack_validate', 'Checks a payload against the schema and references; needs platform.profiles + aal2.'),
  ('public.platform_pack_save_draft', 'Saves a draft version; needs platform.profiles + aal2; audited.'),
  ('public.platform_pack_publish', 'Publishes a validated draft; needs platform.profiles + aal2; audited.'),
  ('public.platform_pack_discard_draft', 'Removes a draft version; needs platform.profiles + aal2; audited.'),
  ('public.platform_industry_set_open', 'Opens / closes an industry for sign-up; needs platform.profiles + aal2; audited.'),
  ('public.list_open_packs', 'Sign-up wizard: names of open industries and their published profiles; product data, no tenant data.')
) as v (f, r)
on conflict (function_name) do update set reason = excluded.reason, added_in = excluded.added_in, tenant_check = excluded.tenant_check;
