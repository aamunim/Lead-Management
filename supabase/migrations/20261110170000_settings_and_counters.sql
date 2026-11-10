-- 0A.08 Typed settings framework and per-institution counters.
-- Plan: Ch 4 (4.4, 4.5), Ch 2 (2.4, 2.7 #1, #3), Ch 3.4, Ch 48.7, Ch 8.10 #7. Decision: D22. See docs/dev/SETTINGS.md.
--
-- A setting is DATA: a definition row (key, JSON schema, default, version, permission area, scope). Adding a key needs
-- no code change in the settings data layer. Values are resolved in layers:
--   definition default  →  type-profile default (0B fills app.type_profile_setting_default)  →  institution value.
-- Every write is validated against the schema (pg_jsonschema), records the previous value, and bumps the institution's
-- settings_version, which PostgREST returns on every response (header x-settings-version) so clients refresh.

create extension if not exists pg_jsonschema with schema extensions;

-- ---------------------------------------------------------------------------------------------------------------------
-- Definitions (product-wide; edited only by migrations / platform roles)
-- ---------------------------------------------------------------------------------------------------------------------
create table public.setting_definitions (
  key            text primary key check (key ~ '^[a-z][a-z0-9_]*(\.[a-z0-9_]+)*$'),
  scope          text not null check (scope in ('institution', 'product')),
  schema         jsonb not null,
  default_value  jsonb not null,
  version        integer not null default 1 check (version >= 1),
  area           text not null check (area ~ '^(settings|platform)\.[a-z_]+$'),
  migrate_fn     text,
  description    text not null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint default_matches_schema check (extensions.jsonb_matches_schema(schema::json, default_value))
);
comment on column public.setting_definitions.area is
  'Permission area that guards writes (e.g. settings.terminology); checked with can() once 0A.17 exists.';
comment on column public.setting_definitions.migrate_fn is
  'Function (value jsonb, from_version int) returns jsonb that upgrades a stored value to the current version.';

-- Product-level values (scope = product), e.g. min_app_version. Platform table.
create table public.product_settings (
  key             text primary key references public.setting_definitions (key),
  value           jsonb not null,
  schema_version  integer not null,
  updated_by      uuid references auth.users (id) on delete set null,
  updated_at      timestamptz not null default now()
);

-- Institution values (overrides of the default).
create table public.app_settings (
  institution_id  uuid not null references public.institutions (id) on delete cascade,
  key             text not null references public.setting_definitions (key),
  value           jsonb not null,
  previous_value  jsonb,
  schema_version  integer not null default 1,
  updated_by      uuid references auth.users (id) on delete set null,
  updated_at      timestamptz not null default now(),
  primary key (institution_id, key)
);

-- One version number per institution, bumped by every settings change (and later labels, 0A.12).
create table public.institution_settings_state (
  institution_id    uuid primary key references public.institutions (id) on delete cascade,
  settings_version  bigint not null default 1,
  updated_at        timestamptz not null default now()
);

-- Per-institution counters (receipt no., refund no., client number …), optionally per branch (Proposed, Block 2).
create table public.institution_counters (
  institution_id  uuid not null references public.institutions (id) on delete cascade,
  counter_key     text not null check (counter_key ~ '^[a-z][a-z0-9_.-]*$'),
  branch_id       uuid,
  next_value      bigint not null default 1 check (next_value >= 1),
  updated_at      timestamptz not null default now()
);
create unique index institution_counters_key_idx on public.institution_counters
  (institution_id, counter_key, coalesce(branch_id, '00000000-0000-0000-0000-000000000000'::uuid));

alter table public.setting_definitions enable row level security;
alter table public.product_settings enable row level security;
alter table public.app_settings enable row level security;
alter table public.institution_settings_state enable row level security;
alter table public.institution_counters enable row level security;

revoke all on public.setting_definitions, public.product_settings, public.app_settings,
              public.institution_settings_state, public.institution_counters from anon, authenticated;
grant select on public.setting_definitions, public.product_settings to authenticated;
grant select on public.app_settings, public.institution_settings_state, public.institution_counters to authenticated;

create policy setting_definitions_read on public.setting_definitions for select to authenticated using (true);
create policy product_settings_read on public.product_settings for select to authenticated using (true);
create policy app_settings_read_own on public.app_settings for select to authenticated
  using (institution_id = (select app.auth_institution_id()));
create policy settings_state_read_own on public.institution_settings_state for select to authenticated
  using (institution_id = (select app.auth_institution_id()));
create policy counters_read_own on public.institution_counters for select to authenticated
  using (institution_id = (select app.auth_institution_id()));

create trigger setting_definitions_touch before update on public.setting_definitions
  for each row execute function app.touch_updated_at();

-- Every institution gets a settings-state row.
create or replace function app.on_institution_created() returns trigger
language plpgsql set search_path = '' as $$
begin
  insert into public.institution_settings_state (institution_id) values (new.id) on conflict do nothing;
  return new;
end $$;
create trigger institutions_settings_state after insert on public.institutions
  for each row execute function app.on_institution_created();
insert into public.institution_settings_state (institution_id) select id from public.institutions on conflict do nothing;

-- ---------------------------------------------------------------------------------------------------------------------
-- Resolution
-- ---------------------------------------------------------------------------------------------------------------------

-- Hook for 0B (type profiles): returns the profile's default for this institution, or NULL. Replaced in 0B.04.
create or replace function app.type_profile_setting_default(p_institution uuid, p_key text) returns jsonb
language sql stable set search_path = '' as $$ select null::jsonb $$;

create or replace function app.setting_value(p_institution uuid, p_key text) returns jsonb
language sql stable set search_path = '' as $$
  select coalesce(
    (select s.value from public.app_settings s where s.institution_id = p_institution and s.key = p_key),
    app.type_profile_setting_default(p_institution, p_key),
    (select d.default_value from public.setting_definitions d where d.key = p_key))
$$;

create or replace function app.product_setting(p_key text) returns jsonb
language sql stable set search_path = '' as $$
  select coalesce((select p.value from public.product_settings p where p.key = p_key),
                  (select d.default_value from public.setting_definitions d where d.key = p_key and d.scope = 'product'))
$$;

-- All settings of the active institution (plus product-level ones), resolved, with the version.
create or replace function public.settings_get_all() returns jsonb
language plpgsql stable security invoker set search_path = '' as $$
declare
  v_institution uuid := app.require_active_session();
begin
  return jsonb_build_object(
    'settings_version', (select s.settings_version from public.institution_settings_state s where s.institution_id = v_institution),
    'values', coalesce((
      select jsonb_object_agg(d.key, case when d.scope = 'product' then app.product_setting(d.key)
                                          else app.setting_value(v_institution, d.key) end)
      from public.setting_definitions d), '{}'::jsonb),
    'overridden', coalesce((select jsonb_agg(s.key order by s.key) from public.app_settings s
                            where s.institution_id = v_institution), '[]'::jsonb));
end $$;
revoke execute on function public.settings_get_all() from public, anon;
grant execute on function public.settings_get_all() to authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- Writes
-- ---------------------------------------------------------------------------------------------------------------------

-- Until can() exists (0A.17): only the platform Master Admin writes settings (fail-closed, same as secrets).
-- 0A.17 replaces the body with can(user, <definition area>, institution).
create or replace function app.settings_write_allowed(p_institution uuid, p_area text) returns boolean
language sql stable set search_path = '' as $$
  select exists (select 1 from public.platform_members pm where pm.user_id = auth.uid() and pm.platform_role = 'master_admin')
         and exists (select 1 from public.institutions i where i.id = p_institution)
$$;

create or replace function app.validation_errors(p_schema jsonb, p_value jsonb) returns text[]
language sql immutable set search_path = '' as $$
  select coalesce(extensions.jsonschema_validation_errors(p_schema::json, p_value::json), '{}'::text[])
$$;

create or replace function app.bump_settings_version(p_institution uuid) returns bigint
language sql set search_path = '' as $$
  insert into public.institution_settings_state as s (institution_id, settings_version) values (p_institution, 2)
  on conflict (institution_id) do update set settings_version = s.settings_version + 1, updated_at = now()
  returning settings_version
$$;

create or replace function public.setting_set(p_key text, p_value jsonb, p_institution_id uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.secret_target_institution(p_institution_id);
  v_def         public.setting_definitions;
  v_errors      text[];
  v_previous    jsonb;
begin
  select * into v_def from public.setting_definitions where key = p_key;
  if not found or v_def.scope <> 'institution' then
    raise exception 'setting_unknown' using errcode = 'P0404', detail = p_key;
  end if;
  if not app.settings_write_allowed(v_institution, v_def.area) then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  v_errors := app.validation_errors(v_def.schema, p_value);
  if array_length(v_errors, 1) > 0 then
    raise exception 'setting_invalid' using errcode = 'P0422', detail = array_to_string(v_errors, '; ');
  end if;
  select value into v_previous from public.app_settings where institution_id = v_institution and key = p_key;
  insert into public.app_settings (institution_id, key, value, previous_value, schema_version, updated_by, updated_at)
  values (v_institution, p_key, p_value, v_previous, v_def.version, auth.uid(), now())
  on conflict (institution_id, key) do update
    set value = excluded.value, previous_value = public.app_settings.value, schema_version = excluded.schema_version,
        updated_by = excluded.updated_by, updated_at = now();
  return jsonb_build_object('key', p_key, 'value', p_value, 'settings_version', app.bump_settings_version(v_institution));
end $$;

-- Reset to default: removes the institution's override (the type-profile / definition default applies again).
create or replace function public.setting_reset(p_key text, p_institution_id uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.secret_target_institution(p_institution_id);
  v_def         public.setting_definitions;
begin
  select * into v_def from public.setting_definitions where key = p_key and scope = 'institution';
  if not found then
    raise exception 'setting_unknown' using errcode = 'P0404', detail = p_key;
  end if;
  if not app.settings_write_allowed(v_institution, v_def.area) then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  delete from public.app_settings where institution_id = v_institution and key = p_key;
  return jsonb_build_object('key', p_key, 'value', app.setting_value(v_institution, p_key),
                            'settings_version', app.bump_settings_version(v_institution));
end $$;

-- Product-level settings: platform Master Admin only.
create or replace function public.product_setting_set(p_key text, p_value jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_def    public.setting_definitions;
  v_errors text[];
begin
  if not exists (select 1 from public.platform_members pm where pm.user_id = auth.uid() and pm.platform_role = 'master_admin') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  select * into v_def from public.setting_definitions where key = p_key and scope = 'product';
  if not found then
    raise exception 'setting_unknown' using errcode = 'P0404', detail = p_key;
  end if;
  v_errors := app.validation_errors(v_def.schema, p_value);
  if array_length(v_errors, 1) > 0 then
    raise exception 'setting_invalid' using errcode = 'P0422', detail = array_to_string(v_errors, '; ');
  end if;
  insert into public.product_settings (key, value, schema_version, updated_by) values (p_key, p_value, v_def.version, auth.uid())
  on conflict (key) do update set value = excluded.value, schema_version = excluded.schema_version,
                                  updated_by = excluded.updated_by, updated_at = now();
  return jsonb_build_object('key', p_key, 'value', p_value);
end $$;

revoke execute on function public.setting_set(text, jsonb, uuid), public.setting_reset(text, uuid),
  public.product_setting_set(text, jsonb) from public, anon;
grant execute on function public.setting_set(text, jsonb, uuid), public.setting_reset(text, uuid),
  public.product_setting_set(text, jsonb) to authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- Settings migrations: upgrade stored values when a definition's version rises (CI runs this on seed data).
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function app.run_setting_migrations() returns integer
language plpgsql set search_path = '' as $$
declare
  r record;
  v_new jsonb;
  v_count integer := 0;
  v_errors text[];
begin
  for r in
    select s.institution_id, s.key, s.value, s.schema_version, d.version, d.migrate_fn, d.schema
    from public.app_settings s join public.setting_definitions d on d.key = s.key
    where s.schema_version < d.version
  loop
    if r.migrate_fn is null then
      raise exception 'setting_migration_missing' using detail = format('%s v%s -> v%s', r.key, r.schema_version, r.version);
    end if;
    execute format('select %s($1, $2)', r.migrate_fn) into v_new using r.value, r.schema_version;
    v_errors := app.validation_errors(r.schema, v_new);
    if array_length(v_errors, 1) > 0 then
      raise exception 'setting_migration_invalid' using detail = format('%s: %s', r.key, array_to_string(v_errors, '; '));
    end if;
    update public.app_settings set value = v_new, previous_value = r.value, schema_version = r.version, updated_at = now()
     where institution_id = r.institution_id and key = r.key;
    perform app.bump_settings_version(r.institution_id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- Counters: atomic and gap-free per institution (and optional branch). The row lock is held until the caller's
-- transaction ends, so a rolled-back receipt does not burn a number. Not exposed through the API (schema app);
-- RPCs that issue numbers (receipts 2.06, refunds, client numbers 2.04) call it.
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function app.counter_next(p_counter_key text, p_branch_id uuid default null) returns bigint
language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.require_active_session();
  v_value       bigint;
begin
  insert into public.institution_counters as c (institution_id, counter_key, branch_id, next_value)
  values (v_institution, p_counter_key, p_branch_id, 2)
  on conflict (institution_id, counter_key, coalesce(branch_id, '00000000-0000-0000-0000-000000000000'::uuid))
  do update set next_value = c.next_value + 1, updated_at = now()
  returning next_value - 1 into v_value;
  return v_value;
end $$;
revoke execute on function app.counter_next(text, uuid) from public, anon;
grant execute on function app.counter_next(text, uuid) to authenticated;

insert into app.definer_registry (function_name, reason, added_in, reviewer, tenant_check) values
  ('public.setting_set', 'Writes app_settings (no direct write grant). Target = active institution, or explicit for the platform '
   || 'Master Admin; schema-validated; bumps settings_version.', '0A.08', 'architecture review 0A.08', 'filters_active_institution'),
  ('public.setting_reset', 'Removes an institution override (same target rule as setting_set).', '0A.08',
   'architecture review 0A.08', 'filters_active_institution'),
  ('public.product_setting_set', 'Product-level settings; platform Master Admin only; no tenant data.', '0A.08',
   'architecture review 0A.08', 'not_tenant_data'),
  ('app.counter_next', 'Increments the active institution''s counter (no direct write grant); not exposed via the API.', '0A.08',
   'architecture review 0A.08', 'filters_active_institution');

-- ---------------------------------------------------------------------------------------------------------------------
-- Minimum app version (product-level, Ch 46) and the per-request hook.
-- PostgREST runs app.pre_request() before every API request:
--   * an app older than min_app_version gets "upgrade_required" (header x-app-version sent by the app);
--   * the response carries x-settings-version for the active institution, so clients refresh stale settings.
-- ---------------------------------------------------------------------------------------------------------------------
insert into public.setting_definitions (key, scope, schema, default_value, area, description) values
  ('min_app_version', 'product', '{"type":"string","pattern":"^[0-9]+\\.[0-9]+\\.[0-9]+$"}', '"0.0.0"',
   'platform.releases', 'Apps older than this version must update (typed error upgrade_required).');

create or replace function app.version_lt(p_a text, p_b text) returns boolean
language sql immutable set search_path = '' as $$
  select string_to_array(p_a, '.')::int[] < string_to_array(p_b, '.')::int[]
$$;

create or replace function app.pre_request() returns void
language plpgsql stable set search_path = '' as $$
declare
  v_headers  jsonb := coalesce(nullif(current_setting('request.headers', true), '')::jsonb, '{}'::jsonb);
  v_app      text := v_headers ->> 'x-app-version';
  v_min      text := app.product_setting('min_app_version') #>> '{}';
  v_version  bigint;
begin
  if v_app ~ '^[0-9]+\.[0-9]+\.[0-9]+$' and app.version_lt(v_app, v_min) then
    raise exception 'upgrade_required' using errcode = 'P0426', detail = format('app %s < minimum %s', v_app, v_min);
  end if;
  select s.settings_version into v_version from public.institution_settings_state s
   where s.institution_id = app.auth_institution_id();
  if v_version is not null then
    perform set_config('response.headers', jsonb_build_array(jsonb_build_object('x-settings-version', v_version::text))::text, true);
  end if;
end $$;
grant execute on function app.pre_request() to anon, authenticated, service_role;

alter role authenticator set pgrst.db_pre_request to 'app.pre_request';
notify pgrst, 'reload config';
