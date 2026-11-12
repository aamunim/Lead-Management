-- 0B.06 Custom field builder (Ch 14.2, 14.6, 14.12 rows 5 and 10, 14.13; Ch 43 values table; Ch 7.5 presets; D8, D20).
-- One builder for lead, client and network fields. Definitions per institution; values in custom_field_values (never
-- jsonb or extra columns on the core tables). Typed values with server validation; filterable fields get their own
-- partial index; sensitive fields are visible only with custom_field.view_sensitive and never sent to AI (phase 4).
-- Presets from the type profile are installed when the types are applied (0B.04). Field count is a plan limit.
-- See docs/dev/CUSTOM_FIELDS.md.

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------------------------------------------------------
create table public.custom_field_definitions (
  institution_id      uuid not null references public.institutions (id) on delete cascade,
  id                  uuid not null default gen_random_uuid(),
  entity              text not null check (entity in ('lead', 'client', 'network')),
  key                 text not null check (key ~ '^[a-z][a-z0-9_]{0,59}$'),
  label               jsonb not null check (jsonb_typeof(label -> 'en') = 'string' and jsonb_typeof(label -> 'bn') = 'string'),
  type                text not null check (type in ('text', 'long_text', 'number', 'date', 'select', 'multi_select', 'phone', 'email',
                                                    'url', 'yes_no', 'gpa', 'file')),
  -- select / multi_select: {"choices": [{"key", "label": {en, bn}}]}; number: {"min", "max", "decimals"}; text: {"max_length"}.
  options             jsonb not null default '{}' check (jsonb_typeof(options) = 'object'),
  required            boolean not null default false,
  show_on_card        boolean not null default false,
  show_in_list        boolean not null default false,
  filterable          boolean not null default false,
  searchable          boolean not null default false,
  include_in_export   boolean not null default true,
  show_on_public_form boolean not null default false,
  sort                integer not null default 0,
  group_label         jsonb check (group_label is null or (jsonb_typeof(group_label -> 'en') = 'string' and jsonb_typeof(group_label -> 'bn') = 'string')),
  sensitive           boolean not null default false,
  created_from_preset text,
  status              text not null default 'active' check (status in ('active', 'retired')),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  updated_by          uuid references auth.users (id) on delete set null,
  primary key (institution_id, id),
  unique (institution_id, entity, key)
);
create index custom_field_definitions_entity_idx on public.custom_field_definitions (institution_id, entity, status, sort);

create table public.custom_field_values (
  institution_id uuid not null references public.institutions (id) on delete cascade,
  field_id       uuid not null,
  entity         text not null check (entity in ('lead', 'client', 'network')),
  record_id      uuid not null,
  value_text     text,
  value_num      numeric,
  value_date     date,
  value_bool     boolean,
  value_json     jsonb,
  updated_at     timestamptz not null default now(),
  updated_by     uuid references auth.users (id) on delete set null,
  primary key (institution_id, field_id, record_id),
  foreign key (institution_id, field_id) references public.custom_field_definitions (institution_id, id) on delete cascade
);
-- All values of one record (forms, cards).
create index custom_field_values_record_idx on public.custom_field_values (institution_id, entity, record_id);

-- Idempotency keys for value saves (Ch 14.12 row 9): a repeated request returns the first result.
create table public.request_keys (
  institution_id uuid not null references public.institutions (id) on delete cascade,
  key            text not null check (length(key) between 8 and 100),
  rpc            text not null,
  response       jsonb,
  created_at     timestamptz not null default now(),
  primary key (institution_id, key)
);
create index request_keys_created_idx on public.request_keys (institution_id, created_at);

alter table public.custom_field_definitions enable row level security;
alter table public.custom_field_values enable row level security;
alter table public.request_keys enable row level security;
revoke all on public.custom_field_definitions, public.custom_field_values, public.request_keys from anon, authenticated;
grant select on public.custom_field_definitions, public.custom_field_values to authenticated;
create policy custom_field_definitions_read_own on public.custom_field_definitions for select to authenticated
  using (institution_id = (select app.auth_institution_id()));
-- A sensitive field's values only with custom_field.view_sensitive (Ch 14.12 row 10, minors' data).
create policy custom_field_values_read_own on public.custom_field_values for select to authenticated
  using (institution_id = (select app.auth_institution_id())
         and ((select app.can('custom_field.view_sensitive'))
              or not exists (select 1 from public.custom_field_definitions d
                              where d.institution_id = custom_field_values.institution_id and d.id = custom_field_values.field_id and d.sensitive)));
create policy request_keys_none on public.request_keys for select to authenticated using (false);
select cron.schedule('request-keys-cleanup', '23 4 * * *', $$delete from public.request_keys where created_at < now() - interval '7 days'$$);

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. Validation of a definition and of a value
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function app.custom_field_definition_errors(p_type text, p_options jsonb) returns text[]
language sql immutable set search_path = '' as $$
  select array_remove(array[
    case when p_type in ('select', 'multi_select') and jsonb_array_length(coalesce(p_options -> 'choices', '[]')) = 0
         then 'options.choices: a select field needs choices' end,
    case when p_type in ('select', 'multi_select') and exists (
           select 1 from jsonb_array_elements(coalesce(p_options -> 'choices', '[]')) c
            where coalesce(c ->> 'key', '') !~ '^[a-z0-9][a-z0-9_]{0,59}$'
               or jsonb_typeof(c -> 'label' -> 'en') is distinct from 'string' or jsonb_typeof(c -> 'label' -> 'bn') is distinct from 'string')
         then 'options.choices: each choice needs a key and a label in en and bn' end,
    case when p_type in ('select', 'multi_select') and (select count(*) <> count(distinct c ->> 'key')
           from jsonb_array_elements(coalesce(p_options -> 'choices', '[]')) c)
         then 'options.choices: keys must be different' end,
    case when p_type = 'number' and p_options ? 'min' and p_options ? 'max'
              and (p_options ->> 'min')::numeric > (p_options ->> 'max')::numeric then 'options: min is above max' end
  ], null)
$$;

-- A value for a field → the typed columns. Raises custom_field_invalid with the field key and the reason.
create or replace function app.custom_field_cast(p_institution uuid, p_def public.custom_field_definitions, p_value jsonb,
  out value_text text, out value_num numeric, out value_date date, out value_bool boolean, out value_json jsonb)
language plpgsql stable set search_path = '' as $$
declare
  v_text text := case when jsonb_typeof(p_value) = 'string' then btrim(p_value #>> '{}')
                      when jsonb_typeof(p_value) in ('number', 'boolean') then p_value #>> '{}' end;
  v_num  numeric;
begin
  if p_value is null or jsonb_typeof(p_value) = 'null' or v_text = '' then
    if p_def.required then
      raise exception 'custom_field_invalid' using errcode = 'P0422', detail = p_def.key || ': required';
    end if;
    return;
  end if;
  case p_def.type
    when 'text', 'long_text' then
      if length(v_text) > coalesce((p_def.options ->> 'max_length')::integer, case p_def.type when 'text' then 200 else 4000 end) then
        raise exception 'custom_field_invalid' using errcode = 'P0422', detail = p_def.key || ': too long';
      end if;
      value_text := v_text;
    when 'number', 'gpa' then
      begin
        v_num := app.ascii_digits(v_text)::numeric;
      exception when others then
        raise exception 'custom_field_invalid' using errcode = 'P0422', detail = p_def.key || ': not a number';
      end;
      if p_def.type = 'gpa' and (v_num < 0 or v_num > 5 or v_num <> round(v_num, 2)) then
        raise exception 'custom_field_invalid' using errcode = 'P0422', detail = p_def.key || ': GPA is 0 to 5 with at most two decimals';
      end if;
      if (p_def.options ? 'min' and v_num < (p_def.options ->> 'min')::numeric) or (p_def.options ? 'max' and v_num > (p_def.options ->> 'max')::numeric)
         or (p_def.options ? 'decimals' and v_num <> round(v_num, (p_def.options ->> 'decimals')::integer)) then
        raise exception 'custom_field_invalid' using errcode = 'P0422', detail = p_def.key || ': out of range';
      end if;
      value_num := v_num;
    when 'date' then
      begin
        value_date := v_text::date;
      exception when others then
        raise exception 'custom_field_invalid' using errcode = 'P0422', detail = p_def.key || ': not a date (YYYY-MM-DD)';
      end;
    when 'yes_no' then
      if jsonb_typeof(p_value) <> 'boolean' then
        raise exception 'custom_field_invalid' using errcode = 'P0422', detail = p_def.key || ': yes or no';
      end if;
      value_bool := (p_value #>> '{}')::boolean;
    when 'select' then
      if not exists (select 1 from jsonb_array_elements(p_def.options -> 'choices') c where c ->> 'key' = v_text) then
        raise exception 'custom_field_invalid' using errcode = 'P0422', detail = p_def.key || ': unknown choice';
      end if;
      value_text := v_text;
    when 'multi_select' then
      if jsonb_typeof(p_value) <> 'array' or exists (select 1 from jsonb_array_elements_text(p_value) x
            where not exists (select 1 from jsonb_array_elements(p_def.options -> 'choices') c where c ->> 'key' = x)) then
        raise exception 'custom_field_invalid' using errcode = 'P0422', detail = p_def.key || ': unknown choice';
      end if;
      value_json := (select coalesce(jsonb_agg(distinct x), '[]'::jsonb) from jsonb_array_elements_text(p_value) x);
    when 'phone' then
      begin
        value_text := app.require_valid_phone(v_text, p_institution);
      exception when others then
        raise exception 'custom_field_invalid' using errcode = 'P0422', detail = p_def.key || ': not a valid phone number';
      end;
    when 'email' then
      if lower(v_text) !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(v_text) > 254 then
        raise exception 'custom_field_invalid' using errcode = 'P0422', detail = p_def.key || ': not a valid email';
      end if;
      value_text := lower(v_text);
    when 'url' then
      if v_text !~* '^https?://[^\s/]+\.[^\s]+$' or length(v_text) > 2000 then
        raise exception 'custom_field_invalid' using errcode = 'P0422', detail = p_def.key || ': not a valid web address';
      end if;
      value_text := v_text;
    when 'file' then
      -- A document reference (the paper itself is stored by the files module, 2.13 / 2.14).
      if jsonb_typeof(p_value) <> 'object' or coalesce(p_value ->> 'document_id', '') !~ '^[0-9a-f-]{36}$' then
        raise exception 'custom_field_invalid' using errcode = 'P0422', detail = p_def.key || ': a document reference';
      end if;
      value_json := jsonb_build_object('document_id', p_value ->> 'document_id');
  end case;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. Indexes only for filterable fields (0B.06-T9, Ch 14.12 row 5)
-- ---------------------------------------------------------------------------------------------------------------------
-- One partial index per filterable field, on the column its type uses, leading with institution_id. Block 1A filters
-- query `where institution_id = $1 and field_id = $2 and value_<col> <op> $3` and hit it.
create or replace function app.custom_field_index_sync(p_institution uuid, p_field uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_def  public.custom_field_definitions;
  v_name text := 'cfv_f_' || replace(p_field::text, '-', '');
  v_col  text;
begin
  select * into v_def from public.custom_field_definitions where institution_id = p_institution and id = p_field;
  if found and v_def.filterable and v_def.status = 'active' then
    v_col := case v_def.type when 'number' then 'value_num' when 'gpa' then 'value_num' when 'date' then 'value_date'
                             when 'yes_no' then 'value_bool' when 'multi_select' then 'value_json' else 'value_text' end;
    if v_col = 'value_json' then
      execute format('create index if not exists %I on public.custom_field_values using gin (value_json) where field_id = %L', v_name, p_field);
    else
      execute format('create index if not exists %I on public.custom_field_values (institution_id, %I) where field_id = %L', v_name, v_col, p_field);
    end if;
  else
    execute format('drop index if exists public.%I', v_name);
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 4. Plan limit: active fields count as custom_fields (0B.05); presets from the type do not need room
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function app.usage_custom_fields() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_was boolean := tg_op in ('UPDATE', 'DELETE') and old.status = 'active';
  v_is  boolean := tg_op in ('INSERT', 'UPDATE') and new.status = 'active';
begin
  if tg_op = 'DELETE' then
    if v_was then perform app.usage_add(old.institution_id, 'custom_fields', -1); end if;
    return old;
  end if;
  -- An upsert of an existing field (insert … on conflict do update) is a change, not a new field.
  if tg_op = 'INSERT' and exists (select 1 from public.custom_field_definitions d where d.institution_id = new.institution_id
                                     and (d.id = new.id or (d.entity = new.entity and d.key = new.key))) then
    return new;
  end if;
  if v_is and not v_was then
    if auth.uid() is not null and new.created_from_preset is null then
      perform app.check_limit(new.institution_id, 'custom_fields', 1);
    end if;
    perform app.usage_add(new.institution_id, 'custom_fields', 1);
  elsif v_was and not v_is then
    perform app.usage_add(new.institution_id, 'custom_fields', -1);
  end if;
  return new;
end $$;
create trigger custom_field_definitions_usage before insert or update of status or delete on public.custom_field_definitions
  for each row execute function app.usage_custom_fields();

-- Reconciliation now also recounts custom fields.
create or replace function app.usage_reconcile(p_institution uuid default null) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_n integer;
begin
  with truth as (
    select i.id as institution_id, 'users'::text as metric,
           (select count(*) from public.institution_members m where m.institution_id = i.id and m.status = 'active') as value
      from public.institutions i where p_institution is null or i.id = p_institution
    union all
    select i.id, 'branches', (select count(*) from public.org_units o where o.institution_id = i.id and o.kind = 'branch' and o.archived_at is null)
      from public.institutions i where p_institution is null or i.id = p_institution
    union all
    select i.id, 'custom_fields', (select count(*) from public.custom_field_definitions d where d.institution_id = i.id and d.status = 'active')
      from public.institutions i where p_institution is null or i.id = p_institution
  ), up as (
    insert into public.usage_counters as u (institution_id, metric, period, value)
    select t.institution_id, t.metric, '', t.value from truth t
    on conflict (institution_id, metric, period) do update set value = excluded.value, updated_at = now()
     where u.value is distinct from excluded.value
    returning 1
  ) select count(*) into v_n from up;
  return v_n;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 5. Presets from the type profile (0B.06-T4): installed when the types are applied; never removed
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function app.custom_field_from_preset(p_institution uuid, p_preset jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_pack jsonb := app.current_pack((select industry from public.institutions where id = p_institution));
  v_type text;
begin
  v_type := case p_preset ->> 'type'
              when 'choice' then 'select' when 'year' then 'number' when 'phone' then 'phone' when 'date' then 'date'
              when 'decimal' then case when (p_preset ->> 'max')::numeric = 5 then 'gpa' else 'number' end
              when 'number' then 'number' else 'text' end;
  insert into public.custom_field_definitions (institution_id, entity, key, label, type, options, sort, sensitive, created_from_preset,
                                               include_in_export)
  values (p_institution, 'lead', p_preset ->> 'key', p_preset -> 'name', v_type,
          jsonb_strip_nulls(jsonb_build_object(
            'choices', case when v_type = 'select' then (select jsonb_agg(jsonb_build_object('key', o ->> 'key', 'label', o -> 'name'))
                                                            from jsonb_array_elements(p_preset -> 'options') o) end,
            'min', case when v_type = 'number' then p_preset -> 'min' end, 'max', case when v_type = 'number' then p_preset -> 'max' end,
            'max_length', p_preset -> 'max_length',
            'decimals', case when p_preset ->> 'type' = 'year' then to_jsonb(0) end)),
          (select coalesce(max(sort), 0) + 10 from public.custom_field_definitions where institution_id = p_institution and entity = 'lead'),
          exists (select 1 from jsonb_array_elements(coalesce(v_pack -> 'sensitive_fields', '[]')) s where s ->> 'field' = p_preset ->> 'key'),
          p_preset ->> 'key',
          not exists (select 1 from jsonb_array_elements(coalesce(v_pack -> 'sensitive_fields', '[]')) s where s ->> 'field' = p_preset ->> 'key'))
  on conflict (institution_id, entity, key) do nothing;
end $$;

create or replace function app.custom_fields_on_seed() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.area = 'custom_fields' then
    perform app.custom_field_from_preset(new.institution_id, new.value);
  end if;
  return null;
end $$;
create trigger seeded_items_custom_fields after insert or update of value on public.seeded_items
  for each row execute function app.custom_fields_on_seed();

-- Institutions set up before this milestone get their presets now.
select app.custom_field_from_preset(s.institution_id, s.value) from public.seeded_items s where s.area = 'custom_fields';

-- ---------------------------------------------------------------------------------------------------------------------
-- 6. Builder RPCs (settings.custom_fields)
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function public.custom_fields_list(p_entity text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_institution uuid := app.require_active_session();
begin
  if not app.settings_write_allowed(v_institution, 'settings.custom_fields') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'fields', coalesce((select jsonb_agg(to_jsonb(d) - 'institution_id' || jsonb_build_object('values',
                (select count(*) from public.custom_field_values v where v.institution_id = d.institution_id and v.field_id = d.id))
                order by d.status, d.sort, d.key)
              from public.custom_field_definitions d where d.institution_id = v_institution and d.entity = p_entity), '[]'::jsonb),
    'limit', app.check_limit(v_institution, 'custom_fields', 0, null, false));
end $$;

-- Create (p_id null) or change a field. The key and type are fixed once values exist.
create or replace function public.custom_field_save(p_entity text, p_id uuid, p_field jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.require_active_session();
  v_before      public.custom_field_definitions;
  v_errors      text[];
  v_id          uuid;
  v_type        text := p_field ->> 'type';
begin
  if not app.settings_write_allowed(v_institution, 'settings.custom_fields') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  if p_entity not in ('lead', 'client', 'network') then
    raise exception 'custom_field_invalid' using errcode = 'P0422', detail = 'entity';
  end if;
  if p_id is not null then
    select * into v_before from public.custom_field_definitions where institution_id = v_institution and id = p_id;
    if not found then
      raise exception 'record_unknown' using errcode = 'P0404', detail = p_id::text;
    end if;
    if (v_before.key <> p_field ->> 'key' or v_before.type <> v_type)
       and exists (select 1 from public.custom_field_values v where v.institution_id = v_institution and v.field_id = p_id) then
      raise exception 'custom_field_invalid' using errcode = 'P0422', detail = 'key and type cannot change once values exist';
    end if;
  end if;
  v_errors := app.custom_field_definition_errors(v_type, coalesce(p_field -> 'options', '{}'));
  if cardinality(v_errors) > 0 then
    raise exception 'custom_field_invalid' using errcode = 'P0422', detail = array_to_string(v_errors, '; ');
  end if;
  insert into public.custom_field_definitions as d (institution_id, id, entity, key, label, type, options, required, show_on_card, show_in_list,
    filterable, searchable, include_in_export, show_on_public_form, sort, group_label, sensitive, created_from_preset, updated_by)
  values (v_institution, coalesce(p_id, gen_random_uuid()), p_entity, p_field ->> 'key', p_field -> 'label', v_type,
          coalesce(p_field -> 'options', '{}'), coalesce((p_field ->> 'required')::boolean, false),
          coalesce((p_field ->> 'show_on_card')::boolean, false), coalesce((p_field ->> 'show_in_list')::boolean, false),
          coalesce((p_field ->> 'filterable')::boolean, false), coalesce((p_field ->> 'searchable')::boolean, false),
          coalesce((p_field ->> 'include_in_export')::boolean, true), coalesce((p_field ->> 'show_on_public_form')::boolean, false),
          coalesce((p_field ->> 'sort')::integer,
                   (select coalesce(max(sort), 0) + 10 from public.custom_field_definitions where institution_id = v_institution and entity = p_entity)),
          nullif(p_field -> 'group_label', 'null'::jsonb), coalesce((p_field ->> 'sensitive')::boolean, false),
          v_before.created_from_preset, auth.uid())
  on conflict (institution_id, id) do update
    set key = excluded.key, label = excluded.label, type = excluded.type, options = excluded.options, required = excluded.required,
        show_on_card = excluded.show_on_card, show_in_list = excluded.show_in_list, filterable = excluded.filterable,
        searchable = excluded.searchable, include_in_export = excluded.include_in_export, show_on_public_form = excluded.show_on_public_form,
        sort = case when p_field ? 'sort' then excluded.sort else d.sort end,
        group_label = case when p_field ? 'group_label' then excluded.group_label else d.group_label end,
        sensitive = excluded.sensitive, updated_by = excluded.updated_by, updated_at = now()
  returning d.id into v_id;
  perform app.custom_field_index_sync(v_institution, v_id);
  perform app.audit(v_institution, case when p_id is null then 'custom_field.created' else 'custom_field.changed' end, 'custom_field', v_id::text,
                    case when p_id is not null then to_jsonb(v_before) - 'institution_id' end,
                    (select to_jsonb(d) - 'institution_id' from public.custom_field_definitions d where d.institution_id = v_institution and d.id = v_id));
  return jsonb_build_object('id', v_id, 'settings_version', app.bump_settings_version(v_institution));
exception when unique_violation then
  raise exception 'custom_field_invalid' using errcode = 'P0422', detail = 'key: already used';
end $$;

-- Order and groups in one call (drag-to-order): p_order [{id, group_label}] in the new order.
create or replace function public.custom_fields_reorder(p_entity text, p_order jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.require_active_session();
begin
  if not app.settings_write_allowed(v_institution, 'settings.custom_fields') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  update public.custom_field_definitions d set sort = x.n * 10, group_label = nullif(x.e -> 'group_label', 'null'::jsonb), updated_at = now(),
         updated_by = auth.uid()
    from jsonb_array_elements(p_order) with ordinality as x (e, n)
   where d.institution_id = v_institution and d.entity = p_entity and d.id = (x.e ->> 'id')::uuid;
  perform app.audit(v_institution, 'custom_field.reordered', 'custom_field', p_entity, null, p_order);
  perform app.bump_settings_version(v_institution);
end $$;

-- Retire (values are kept, the field disappears from forms) or bring back (needs room in the plan).
create or replace function public.custom_field_retire(p_id uuid, p_retired boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.require_active_session();
begin
  if not app.settings_write_allowed(v_institution, 'settings.custom_fields') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  update public.custom_field_definitions set status = case when p_retired then 'retired' else 'active' end, updated_at = now(), updated_by = auth.uid()
   where institution_id = v_institution and id = p_id;
  if not found then
    raise exception 'record_unknown' using errcode = 'P0404', detail = p_id::text;
  end if;
  perform app.custom_field_index_sync(v_institution, p_id);
  perform app.audit(v_institution, case when p_retired then 'custom_field.retired' else 'custom_field.restored' end, 'custom_field', p_id::text, null, null);
  perform app.bump_settings_version(v_institution);
end $$;

-- Definitions as JSON for copy-from-institution (0B.06-T10, used by 0B.10).
create or replace function public.custom_fields_export(p_entity text default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_institution uuid := app.require_active_session();
begin
  if not app.settings_write_allowed(v_institution, 'settings.custom_fields') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  return coalesce((select jsonb_agg(to_jsonb(d) - 'institution_id' - 'id' - 'created_at' - 'updated_at' - 'updated_by' order by d.entity, d.sort)
    from public.custom_field_definitions d
   where d.institution_id = v_institution and d.status = 'active' and (p_entity is null or d.entity = p_entity)), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 7. Values API (0B.06-T8). Until the record screens exist (1.01 leads, 2.08 clients, 3.x network) writing values needs
--    settings.custom_fields; the record milestones call app.custom_field_values_write with their own permission check.
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function app.custom_field_values_write(p_institution uuid, p_entity text, p_record uuid, p_values jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_def  public.custom_field_definitions;
  v_cast record;
  e      record;
begin
  if jsonb_typeof(p_values) is distinct from 'object' then
    raise exception 'custom_field_invalid' using errcode = 'P0422', detail = 'values must be an object of field key → value';
  end if;
  for e in select * from jsonb_each(p_values) loop
    select * into v_def from public.custom_field_definitions
     where institution_id = p_institution and entity = p_entity and key = e.key and status = 'active';
    if not found then
      raise exception 'custom_field_invalid' using errcode = 'P0422', detail = e.key || ': unknown field';
    end if;
    if v_def.sensitive and not (auth.uid() is null or app.can('custom_field.view_sensitive')) then
      raise exception 'permission_denied' using errcode = '42501', detail = e.key;
    end if;
    select * into v_cast from app.custom_field_cast(p_institution, v_def, e.value);
    if v_cast.value_text is null and v_cast.value_num is null and v_cast.value_date is null and v_cast.value_bool is null and v_cast.value_json is null then
      delete from public.custom_field_values where institution_id = p_institution and field_id = v_def.id and record_id = p_record;
    else
      insert into public.custom_field_values as v (institution_id, field_id, entity, record_id, value_text, value_num, value_date, value_bool,
                                                   value_json, updated_by)
      values (p_institution, v_def.id, p_entity, p_record, v_cast.value_text, v_cast.value_num, v_cast.value_date, v_cast.value_bool,
              v_cast.value_json, auth.uid())
      on conflict (institution_id, field_id, record_id) do update
        set value_text = excluded.value_text, value_num = excluded.value_num, value_date = excluded.value_date, value_bool = excluded.value_bool,
            value_json = excluded.value_json, updated_by = excluded.updated_by, updated_at = now();
    end if;
  end loop;
  return app.custom_field_values_read(p_institution, p_entity, p_record);
end $$;

-- The values of one record, key → value; sensitive ones masked without the permission.
create or replace function app.custom_field_values_read(p_institution uuid, p_entity text, p_record uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_object_agg(d.key,
           case when d.sensitive and auth.uid() is not null and not app.can('custom_field.view_sensitive') then '"•••"'::jsonb
                else coalesce(to_jsonb(v.value_text), to_jsonb(v.value_num), to_jsonb(v.value_date), to_jsonb(v.value_bool), v.value_json) end),
           '{}'::jsonb)
    from public.custom_field_values v join public.custom_field_definitions d on d.institution_id = v.institution_id and d.id = v.field_id
   where v.institution_id = p_institution and v.entity = p_entity and v.record_id = p_record
$$;

create or replace function public.custom_field_values_set(p_entity text, p_record_id uuid, p_values jsonb, p_idempotency_key text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.require_active_session();
  v_done        jsonb;
  v_result      jsonb;
begin
  if not app.settings_write_allowed(v_institution, 'settings.custom_fields') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  if p_idempotency_key is not null then
    insert into public.request_keys (institution_id, key, rpc) values (v_institution, p_idempotency_key, 'custom_field_values_set')
    on conflict do nothing;
    if not found then
      select response into v_done from public.request_keys where institution_id = v_institution and key = p_idempotency_key;
      return v_done;
    end if;
  end if;
  v_result := app.custom_field_values_write(v_institution, p_entity, p_record_id, p_values);
  if p_idempotency_key is not null then
    update public.request_keys set response = v_result where institution_id = v_institution and key = p_idempotency_key;
  end if;
  return v_result;
end $$;

create or replace function public.custom_field_values_get(p_entity text, p_record_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_institution uuid := app.require_active_session();
begin
  return app.custom_field_values_read(v_institution, p_entity, p_record_id);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 8. Registry, grants
-- ---------------------------------------------------------------------------------------------------------------------
-- Sensitive custom-field values are declared in the field registry (0B.06-T6); the AI layer (phase 4) skips them.
insert into public.permissions (key, kind, module, action, scopable, sensitive, introduced_in_release)
values ('custom_field.view_sensitive', 'institution', 'core', 'view_sensitive', false, true, '0B.06') on conflict do nothing;
insert into public.field_registry (entity, field, sensitive, permission_key)
values ('custom_field', 'sensitive_value', true, 'custom_field.view_sensitive') on conflict do nothing;

revoke all on function app.custom_field_index_sync(uuid, uuid), app.usage_custom_fields(), app.custom_field_from_preset(uuid, jsonb),
  app.custom_fields_on_seed(), app.custom_field_values_write(uuid, text, uuid, jsonb), app.custom_field_values_read(uuid, text, uuid)
  from public, anon, authenticated;
revoke all on function public.custom_fields_list(text), public.custom_field_save(text, uuid, jsonb), public.custom_fields_reorder(text, jsonb),
  public.custom_field_retire(uuid, boolean), public.custom_fields_export(text), public.custom_field_values_set(text, uuid, jsonb, text),
  public.custom_field_values_get(text, uuid) from public, anon;
grant execute on function public.custom_fields_list(text), public.custom_field_save(text, uuid, jsonb), public.custom_fields_reorder(text, jsonb),
  public.custom_field_retire(uuid, boolean), public.custom_fields_export(text), public.custom_field_values_set(text, uuid, jsonb, text),
  public.custom_field_values_get(text, uuid) to authenticated;
grant execute on function app.custom_field_definition_errors(text, jsonb) to authenticated, service_role;

insert into app.definer_registry (function_name, reason, added_in, reviewer, tenant_check)
select f, r, '0B.06', 'architecture review 0B.06', t from (values
  ('app.custom_field_index_sync', 'Creates / drops the partial index of one filterable field (DDL); called by checked RPCs only.', 'service_role_only'),
  ('app.usage_custom_fields', 'Trigger: counts active custom fields of the row''s institution and checks the plan limit.', 'service_role_only'),
  ('app.custom_field_from_preset', 'Installs a type-profile preset field for one institution (seed / applier).', 'service_role_only'),
  ('app.custom_fields_on_seed', 'Trigger on seeded_items: installs preset fields of the row''s institution.', 'service_role_only'),
  ('app.custom_field_values_write', 'Validates and stores values of one record; called by checked RPCs (record milestones add their own checks).', 'service_role_only'),
  ('app.custom_field_values_read', 'Values of one record with sensitive ones masked; called by checked RPCs.', 'service_role_only'),
  ('public.custom_fields_list', 'Field definitions of the active institution for the builder; can(settings.custom_fields).', 'filters_active_institution'),
  ('public.custom_field_save', 'Creates / changes a field of the active institution; can(settings.custom_fields); plan limit; audited.', 'filters_active_institution'),
  ('public.custom_fields_reorder', 'Orders and groups fields of the active institution; can(settings.custom_fields); audited.', 'filters_active_institution'),
  ('public.custom_field_retire', 'Retires / restores a field of the active institution; can(settings.custom_fields); audited.', 'filters_active_institution'),
  ('public.custom_fields_export', 'Field definitions of the active institution as JSON (copy to another institution).', 'filters_active_institution'),
  ('public.custom_field_values_set', 'Stores values of one record of the active institution with validation and an idempotency key.', 'filters_active_institution'),
  ('public.custom_field_values_get', 'Values of one record of the active institution, sensitive ones masked without permission.', 'filters_active_institution')
) as v (f, r, t)
on conflict (function_name) do update set reason = excluded.reason, added_in = excluded.added_in, tenant_check = excluded.tenant_check;
