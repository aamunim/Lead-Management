-- 0A.12 Neutral keys and the label dictionary (Ch 8). See docs/dev/LABELS.md.
-- Internal keys are business-neutral and never change (tables, columns, RPCs, API fields, events, template variables).
-- What people see is a label: English singular/plural and Bangla forms, per institution, resolved in layers:
--   institution  →  type profile (0B)  →  pack (education now, D20)  →  product.
-- Renaming never needs a migration: it is a row in institution_labels.

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------------------------------------------------------
create table public.label_keys (
  key           text primary key
                check (key ~ '^[a-z][a-z0-9_]*(\.[a-z0-9_]+)*$')
                -- New keys must be neutral (Ch 8.10 #5): education words belong in labels, not keys.
                check (key !~ '(^|[._])(students?|courses?|batch(es)?|admissions?|guardians?|alumni|alumnus|college|school|papers)($|[._])'),
  label_group   text not null check (label_group in ('people', 'offering', 'conversion', 'money', 'roles', 'modules', 'documents')),
  animate       boolean not null default false,   -- people take রা / দের / কে in Bangla; things take গুলো
  max_length    integer not null check (max_length between 4 and 80),
  lockable      boolean not null default false,   -- the platform may lock it (e.g. the legal title of a receipt)
  derived_from  text references public.label_keys (key),  -- module names follow their base word unless renamed
  legacy_key    text,                             -- the old education key, for search and for the guide
  description   text not null,
  sort_order    integer not null default 0
);

create table public.label_defaults (
  scope        text not null check (scope in ('product', 'pack', 'profile')),
  scope_key    text not null default '' check ((scope = 'product') = (scope_key = '')),
  key          text not null references public.label_keys (key) on delete cascade,
  en_singular  text not null check (length(btrim(en_singular)) > 0),
  en_plural    text not null check (length(btrim(en_plural)) > 0),
  bn_forms     jsonb not null,
  primary key (scope, scope_key, key)
);

create table public.institution_labels (
  institution_id      uuid not null references public.institutions (id) on delete cascade,
  key                 text not null references public.label_keys (key) on delete cascade,
  en_singular         text not null,
  en_plural           text not null,
  bn_forms            jsonb not null,
  locked_by_platform  boolean not null default false,
  updated_by          uuid references auth.users (id) on delete set null,
  updated_at          timestamptz not null default now(),
  primary key (institution_id, key)
);

alter table public.label_keys enable row level security;
alter table public.label_defaults enable row level security;
alter table public.institution_labels enable row level security;
revoke all on public.label_keys, public.label_defaults, public.institution_labels from anon, authenticated;
grant select on public.label_keys, public.label_defaults, public.institution_labels to authenticated;
create policy label_keys_read on public.label_keys for select to authenticated using (true);
create policy label_defaults_read on public.label_defaults for select to authenticated using (true);
create policy institution_labels_read_own on public.institution_labels for select to authenticated
  using (institution_id = (select app.auth_institution_id()));

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. Bangla forms (Ch 8.7, 0A.12-T5). Generated from the base form; an admin may override any of them.
--   people (animate): শিক্ষার্থী → শিক্ষার্থীরা / শিক্ষার্থীর / শিক্ষার্থীকে / শিক্ষার্থীদের
--   things:           কোর্স → কোর্সগুলো / কোর্সের / কোর্স / কোর্সগুলোর
-- Possessive: after a vowel or vowel sign "র", after a consonant "ের", after Latin letters or digits "-এর".
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function app.bn_forms(p_base text, p_animate boolean, p_override jsonb default '{}'::jsonb)
returns jsonb language plpgsql immutable set search_path = '' as $$
declare
  v_base  text := btrim(coalesce(nullif(btrim(p_override ->> 'base'), ''), p_base));
  v_last  text := right(v_base, 1);
  v_poss  text;
  v_auto  jsonb;
begin
  if v_base is null or v_base = '' then
    return null;
  end if;
  v_poss := case
    when v_last ~ '[অআইঈউঊঋএঐওঔািীুূৃেৈোৌ]' then v_base || 'র'
    when v_last ~ '[ঀ-৾]' then v_base || 'ের'
    else v_base || '-এর' end;
  v_auto := case when p_animate then jsonb_build_object(
      'base', v_base, 'plural', v_base || 'রা', 'possessive', v_poss, 'objective', v_base || 'কে',
      'plural_oblique', v_base || 'দের')
    else jsonb_build_object(
      'base', v_base, 'plural', v_base || 'গুলো', 'possessive', v_poss, 'objective', v_base,
      'plural_oblique', v_base || 'গুলোর') end;
  -- Manual overrides win; empty overrides are ignored; unknown form names are dropped.
  return v_auto || coalesce((select jsonb_object_agg(k, btrim(v)) from jsonb_each_text(coalesce(p_override, '{}'::jsonb)) as e(k, v)
                             where k in ('base', 'plural', 'possessive', 'objective', 'plural_oblique') and btrim(v) <> ''), '{}'::jsonb);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. Resolution (0A.12-T3)
-- ---------------------------------------------------------------------------------------------------------------------
-- Which pack and type profile an institution uses. Education only for now (D20); 0B.04 replaces this with the
-- institution's type profile.
create or replace function app.institution_label_scopes(p_institution uuid)
returns table (pack text, profile text) language sql stable set search_path = '' as $$
  select 'education'::text, null::text
$$;

-- The default below the institution layer: profile → pack → product.
create or replace function app.label_default(p_institution uuid, p_key text) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object('en_singular', d.en_singular, 'en_plural', d.en_plural, 'bn_forms', d.bn_forms, 'source', d.scope)
  from public.label_defaults d, app.institution_label_scopes(p_institution) s
  where d.key = p_key
    and ((d.scope = 'profile' and d.scope_key = s.profile) or (d.scope = 'pack' and d.scope_key = s.pack) or d.scope = 'product')
  order by case d.scope when 'profile' then 1 when 'pack' then 2 else 3 end
  limit 1
$$;

-- The label in force: institution → (derived from its base word) → profile → pack → product.
create or replace function app.label_resolved(p_institution uuid, p_key text) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_row    public.institution_labels;
  v_key    public.label_keys;
  v_base   jsonb;
begin
  select * into v_key from public.label_keys where key = p_key;
  if not found then
    return null;
  end if;
  select * into v_row from public.institution_labels where institution_id = p_institution and key = p_key;
  if found then
    return jsonb_build_object('en_singular', v_row.en_singular, 'en_plural', v_row.en_plural, 'bn_forms', v_row.bn_forms,
                              'source', 'institution', 'locked', v_row.locked_by_platform);
  end if;
  if v_key.derived_from is not null then
    -- A module follows its base word when only the base word was renamed ("Trainees" menu for client = Trainee).
    v_base := app.label_resolved(p_institution, v_key.derived_from);
    if v_base ->> 'source' = 'institution' then
      return jsonb_build_object('en_singular', v_base ->> 'en_plural', 'en_plural', v_base ->> 'en_plural',
        'bn_forms', app.bn_forms(v_base -> 'bn_forms' ->> 'base', false), 'source', 'derived', 'locked', false);
    end if;
  end if;
  return app.label_default(p_institution, p_key) || jsonb_build_object('locked', false);
end $$;

-- Server-side lookup for notifications, prints and AI prompts later: one word in one language and form.
create or replace function app.label(p_institution uuid, p_key text, p_language text default 'en', p_form text default 'singular')
returns text language sql stable set search_path = '' as $$
  select case when p_language = 'bn'
              then coalesce(r -> 'bn_forms' ->> (case p_form when 'singular' then 'base' else p_form end), r -> 'bn_forms' ->> 'base')
              else case when p_form in ('plural', 'plural_oblique') then r ->> 'en_plural' else r ->> 'en_singular' end end
  from (select app.label_resolved(p_institution, p_key) as r) x
$$;

grant execute on function app.bn_forms(text, boolean, jsonb), app.institution_label_scopes(uuid),
  app.label_default(uuid, text), app.label_resolved(uuid, text), app.label(uuid, text, text, text)
  to authenticated, service_role;

-- All labels of the active institution, with the defaults underneath (for search and "reset to default").
create or replace function public.labels_get() returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'settings_version', (select s.settings_version from public.institution_settings_state s
                         where s.institution_id = app.auth_institution_id()),
    'labels', coalesce(jsonb_object_agg(k.key, jsonb_build_object(
        'group', k.label_group, 'animate', k.animate, 'max_length', k.max_length, 'lockable', k.lockable,
        'legacy_key', k.legacy_key, 'resolved', app.label_resolved(app.auth_institution_id(), k.key),
        'default', app.label_default(app.auth_institution_id(), k.key),
        'product', (select jsonb_build_object('en_singular', d.en_singular, 'en_plural', d.en_plural, 'bn_forms', d.bn_forms)
                    from public.label_defaults d where d.scope = 'product' and d.key = k.key))), '{}'::jsonb))
  from public.label_keys k
$$;
revoke all on function public.labels_get() from public, anon;
grant execute on function public.labels_get() to authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- 4. Writes (Settings → Terminology; permission settings.terminology, Master Admin until can() in 0A.17)
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function public.label_set(p_key text, p_en_singular text, p_en_plural text, p_bn_forms jsonb,
                                            p_institution_id uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.secret_target_institution(p_institution_id);
  v_key         public.label_keys;
  v_before      jsonb;
  v_forms       jsonb;
  v_text        text;
  v_locked      boolean;
begin
  select * into v_key from public.label_keys where key = p_key;
  if not found then
    raise exception 'label_unknown' using errcode = 'P0404', detail = p_key;
  end if;
  if not app.settings_write_allowed(v_institution, 'settings.terminology') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  select locked_by_platform into v_locked from public.institution_labels where institution_id = v_institution and key = p_key;
  if coalesce(v_locked, false) and not app.is_platform_admin() then
    raise exception 'label_locked' using errcode = 'P0423', detail = p_key;
  end if;
  if nullif(btrim(p_en_singular), '') is null or nullif(btrim(p_en_plural), '') is null
     or nullif(btrim(coalesce(p_bn_forms ->> 'base', '')), '') is null then
    raise exception 'label_invalid' using errcode = 'P0422', detail = 'English singular, plural and the Bangla base form are required';
  end if;
  v_forms := app.bn_forms(p_bn_forms ->> 'base', v_key.animate, p_bn_forms);
  -- Length limit per key (Ch 8.8): menus and buttons must not break.
  foreach v_text in array array[btrim(p_en_singular), btrim(p_en_plural)]
    || array(select value from jsonb_each_text(v_forms)) loop
    if length(v_text) > v_key.max_length then
      raise exception 'label_too_long' using errcode = 'P0422',
        detail = format('%s: "%s" is longer than %s characters', p_key, v_text, v_key.max_length);
    end if;
  end loop;
  v_before := app.label_resolved(v_institution, p_key);
  insert into public.institution_labels (institution_id, key, en_singular, en_plural, bn_forms, locked_by_platform, updated_by, updated_at)
  values (v_institution, p_key, btrim(p_en_singular), btrim(p_en_plural), v_forms, coalesce(v_locked, false), auth.uid(), now())
  on conflict (institution_id, key) do update
    set en_singular = excluded.en_singular, en_plural = excluded.en_plural, bn_forms = excluded.bn_forms,
        updated_by = excluded.updated_by, updated_at = now();
  perform app.audit(v_institution, 'label.changed', 'label', p_key, v_before - 'source' - 'locked',
                    jsonb_build_object('en_singular', btrim(p_en_singular), 'en_plural', btrim(p_en_plural), 'bn_forms', v_forms));
  perform app.emit_event(v_institution, 'label.changed', 1, 'label', p_key,
                         jsonb_build_object('key', p_key, 'en_singular', btrim(p_en_singular), 'bn_base', v_forms ->> 'base'));
  return jsonb_build_object('key', p_key, 'label', app.label_resolved(v_institution, p_key),
                            'settings_version', app.bump_settings_version(v_institution));
end $$;

create or replace function public.label_reset(p_key text, p_institution_id uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.secret_target_institution(p_institution_id);
  v_row         public.institution_labels;
begin
  if not exists (select 1 from public.label_keys where key = p_key) then
    raise exception 'label_unknown' using errcode = 'P0404', detail = p_key;
  end if;
  if not app.settings_write_allowed(v_institution, 'settings.terminology') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  select * into v_row from public.institution_labels where institution_id = v_institution and key = p_key;
  if v_row.locked_by_platform and not app.is_platform_admin() then
    raise exception 'label_locked' using errcode = 'P0423', detail = p_key;
  end if;
  delete from public.institution_labels where institution_id = v_institution and key = p_key;
  if found then
    perform app.audit(v_institution, 'label.changed', 'label', p_key,
                      jsonb_build_object('en_singular', v_row.en_singular, 'en_plural', v_row.en_plural, 'bn_forms', v_row.bn_forms), null,
                      'reset to default');
  end if;
  return jsonb_build_object('key', p_key, 'label', app.label_resolved(v_institution, p_key),
                            'settings_version', app.bump_settings_version(v_institution));
end $$;

-- Platform lock (Ch 8.8): the Master Admin freezes a label of an institution (e.g. the legal receipt title).
create or replace function public.label_lock(p_institution_id uuid, p_key text, p_locked boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_key  public.label_keys;
  v_cur  jsonb;
begin
  if not app.is_platform_admin() then
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
  perform app.audit(p_institution_id, 'label.locked', 'label', p_key, null, jsonb_build_object('locked', p_locked));
  perform app.bump_settings_version(p_institution_id);
  return app.label_resolved(p_institution_id, p_key);
end $$;

revoke all on function public.label_set(text, text, text, jsonb, uuid), public.label_reset(text, uuid),
  public.label_lock(uuid, text, boolean) from public, anon;
grant execute on function public.label_set(text, text, text, jsonb, uuid), public.label_reset(text, uuid),
  public.label_lock(uuid, text, boolean) to authenticated;

insert into app.definer_registry (function_name, reason, added_in, reviewer, tenant_check) values
  ('public.label_set', 'Writes institution_labels (no app write grant). Target = active institution via '
   || 'secret_target_institution(); explicit only for the Master Admin; length-checked, audited, emitted.', '0A.12',
   'architecture review 0A.12', 'filters_active_institution'),
  ('public.label_reset', 'Deletes the institution''s own label (back to default); same target rule as label_set.', '0A.12',
   'architecture review 0A.12', 'filters_active_institution'),
  ('public.label_lock', 'Platform action: Master Admin locks / unlocks a label of an institution; audited.', '0A.12',
   'architecture review 0A.12', 'not_tenant_data');

insert into public.event_definitions (event_key, version, entity_type, payload_schema, description) values
  ('label.changed', 1, 'label',
   '{"type":"object","required":["key","en_singular","bn_base"],"properties":{"key":{"type":"string"},"en_singular":{"type":"string"},"bn_base":{"type":"string"}},"additionalProperties":false}',
   'An institution renamed a word (Settings → Terminology).');
