-- 0B.11 Integration hub core (Ch 42.1, 42.2, 42.8, 42.9 I1–I3, I9–I11, I14, 42.10 rows 1, 9; Ch 5.3, 5.6; Ch 9.7;
-- D3, D4, D15, D22).
--   * Provider catalog (product data): what each provider needs (settings schema, secret fields), its capabilities and
--     adapter version. Adapters themselves arrive with 0B.13 (SMS), 0B.14 (email), Block 2 (payments) …
--   * Connections per institution (and the platform's own default gateways): mode sandbox / live, status, settings,
--     priority (primary + backups), who pays (D15), live-test mark, last success / error with whose side it is (I10).
--   * Secrets: write-only, held in Vault (0A.07 store); only a hint and the key's age are ever shown; rotation with an
--     effective-from date (the old key works until then); a yearly rotation reminder (Proposed).
--   * Resolver: the institution comes from the record being processed, never from client input (I1).
--   * Closing an institution disables its connections and destroys its secrets (I14).
-- Master Admin only (D4): platform.integrations + aal2. The institution sees status only (integration.view_status).

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Catalog
-- ---------------------------------------------------------------------------------------------------------------------
create table public.integration_providers (
  key              text primary key check (key ~ '^[a-z][a-z0-9_]*$'),
  kind             text not null check (kind in ('sms', 'email', 'payment', 'ai', 'storage', 'push', 'pdf_image', 'domain', 'app')),
  name             jsonb not null check (jsonb_typeof(name -> 'en') = 'string' and jsonb_typeof(name -> 'bn') = 'string'),
  settings_schema  jsonb not null default '{"type":"object","properties":{},"additionalProperties":false}',
  secret_fields    text[] not null default '{}',     -- e.g. {api_key}; values only ever go to Vault
  docs_url         text check (docs_url is null or docs_url ~ '^https://'),
  capabilities     text[] not null default '{}',
  adapter_version  text,                             -- null: no adapter yet (the provider can be configured, not used)
  status           text not null default 'planned' check (status in ('active', 'beta', 'planned', 'retired')),
  sort             integer not null default 0
);
alter table public.integration_providers enable row level security;
revoke all on public.integration_providers from anon, authenticated;
grant select on public.integration_providers to authenticated;
create policy integration_providers_read on public.integration_providers for select to authenticated using (true);
comment on table public.integration_providers is 'Product-wide provider catalog (0B.11). Adapters set adapter_version when they ship.';

-- Generic entries now; the ready-made SMS adapters follow when the pilot gateways are known (Q3).
insert into public.integration_providers (key, kind, name, settings_schema, secret_fields, docs_url, capabilities, adapter_version, status, sort) values
  ('custom_http_sms', 'sms', '{"en":"Custom HTTP SMS gateway","bn":"কাস্টম HTTP SMS গেটওয়ে"}',
   '{"type":"object","required":["send_url","sender_id"],"additionalProperties":false,"properties":{
      "send_url":{"type":"string","pattern":"^https://","maxLength":500},
      "method":{"type":"string","enum":["GET","POST"],"default":"POST"},
      "sender_id":{"type":"string","minLength":1,"maxLength":20},
      "body_template":{"type":"string","maxLength":2000},
      "success_match":{"type":"string","maxLength":200}}}',
   '{api_key}', null, '{send,bulk,unicode}', null, 'planned', 10),
  ('smtp', 'email', '{"en":"SMTP mail server","bn":"SMTP মেইল সার্ভার"}',
   '{"type":"object","required":["host","port","from_email"],"additionalProperties":false,"properties":{
      "host":{"type":"string","maxLength":200},"port":{"type":"integer","minimum":1,"maximum":65535},
      "username":{"type":"string","maxLength":200},"from_email":{"type":"string","maxLength":200},
      "from_name":{"type":"string","maxLength":100},"tls":{"type":"boolean","default":true}}}',
   '{password}', null, '{send}', null, 'planned', 20),
  ('sslcommerz', 'payment', '{"en":"SSLCommerz","bn":"SSLCommerz"}',
   '{"type":"object","required":["store_id"],"additionalProperties":false,"properties":{"store_id":{"type":"string","maxLength":100}}}',
   '{store_password}', 'https://developer.sslcommerz.com/', '{checkout,refund,ipn}', null, 'planned', 30),
  ('google_drive', 'storage', '{"en":"Google Drive","bn":"Google Drive"}',
   '{"type":"object","additionalProperties":false,"properties":{"folder_id":{"type":"string","maxLength":200}}}',
   '{refresh_token}', null, '{backup,files}', null, 'planned', 40),
  ('fcm', 'push', '{"en":"Firebase Cloud Messaging","bn":"Firebase Cloud Messaging"}',
   '{"type":"object","additionalProperties":false,"properties":{"project_id":{"type":"string","maxLength":100}}}',
   '{service_account}', null, '{push}', null, 'planned', 50),
  ('ai_api', 'ai', '{"en":"AI provider (own key)","bn":"AI প্রোভাইডার (নিজের কী)"}',
   '{"type":"object","additionalProperties":false,"properties":{"vendor":{"type":"string","maxLength":50},"model":{"type":"string","maxLength":100}}}',
   '{api_key}', null, '{text}', null, 'planned', 60);

-- Whose side a failure is on (I10): the message says so.
create table public.integration_error_kinds (
  code            text primary key check (code ~ '^[a-z][a-z0-9_]*$'),
  responsibility  text not null check (responsibility in ('platform', 'institution', 'provider')),
  sort            integer not null default 0
);
alter table public.integration_error_kinds enable row level security;
revoke all on public.integration_error_kinds from anon, authenticated;
grant select on public.integration_error_kinds to authenticated;
create policy integration_error_kinds_read on public.integration_error_kinds for select to authenticated using (true);
insert into public.integration_error_kinds (code, responsibility, sort) values
  ('adapter_error', 'platform', 10), ('config_invalid', 'platform', 20),
  ('auth_failed', 'institution', 30), ('balance_low', 'institution', 40), ('account_blocked', 'institution', 50),
  ('merchant_inactive', 'institution', 60), ('sender_not_approved', 'institution', 70),
  ('provider_down', 'provider', 80), ('timeout', 'provider', 90), ('rate_limited', 'provider', 100);

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. Connections (per institution) and the platform's own (default gateways)
-- ---------------------------------------------------------------------------------------------------------------------
create table public.integration_connections (
  institution_id       uuid not null references public.institutions (id) on delete cascade,
  id                   uuid not null default gen_random_uuid(),
  kind                 text not null,
  provider_key         text not null references public.integration_providers (key),
  label                text not null check (length(btrim(label)) between 1 and 80),
  mode                 text not null default 'sandbox' check (mode in ('sandbox', 'live')),
  status               text not null default 'active' check (status in ('active', 'disabled')),
  settings             jsonb not null default '{}' check (jsonb_typeof(settings) = 'object'),
  priority             integer not null default 1 check (priority between 1 and 9),
  live_test_passed_at  timestamptz,
  last_success_at      timestamptz,
  last_error           jsonb,                       -- {code, responsibility, at, detail}
  created_by           uuid references auth.users (id) on delete set null,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  disabled_at          timestamptz,
  primary key (institution_id, id)
);
create index integration_connections_kind_idx on public.integration_connections (institution_id, kind, status, priority);
alter table public.integration_connections enable row level security;
revoke all on public.integration_connections from anon, authenticated;
create policy integration_connections_none on public.integration_connections for select to authenticated using (false);
select app.attach_status_guard('public.integration_connections');
create trigger integration_connections_touch before update on public.integration_connections
  for each row execute function app.touch_updated_at();

create table public.platform_connections (
  id                   uuid primary key default gen_random_uuid(),
  kind                 text not null,
  provider_key         text not null references public.integration_providers (key),
  label                text not null check (length(btrim(label)) between 1 and 80),
  mode                 text not null default 'sandbox' check (mode in ('sandbox', 'live')),
  status               text not null default 'active' check (status in ('active', 'disabled')),
  settings             jsonb not null default '{}' check (jsonb_typeof(settings) = 'object'),
  priority             integer not null default 1 check (priority between 1 and 9),
  live_test_passed_at  timestamptz,
  last_success_at      timestamptz,
  last_error           jsonb,
  created_by           uuid references auth.users (id) on delete set null,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  disabled_at          timestamptz
);
alter table public.platform_connections enable row level security;
revoke all on public.platform_connections from anon, authenticated;
create policy platform_connections_none on public.platform_connections for select to authenticated using (false);
create trigger platform_connections_touch before update on public.platform_connections
  for each row execute function app.touch_updated_at();

-- Platform secrets (the default gateways' keys): same rules as institution secrets, no institution.
create table public.platform_secrets (
  id          uuid primary key default gen_random_uuid(),
  secret_ref  text not null check (secret_ref ~ '^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$'),
  vault_id    uuid not null,
  hint        text not null,
  valid_from  timestamptz not null default now(),
  created_at  timestamptz not null default now(),
  created_by  uuid references auth.users (id) on delete set null,
  rotated_at  timestamptz,
  revoked_at  timestamptz,
  unique (secret_ref, valid_from)
);
alter table public.platform_secrets enable row level security;
revoke all on public.platform_secrets from anon, authenticated;
create policy platform_secrets_none on public.platform_secrets for select to authenticated using (false);

-- Who pays per institution and service (D15): direct (the institution's own account) or the platform's account.
create table public.institution_service_payers (
  institution_id  uuid not null references public.institutions (id) on delete cascade,
  kind            text not null,
  payer           text not null check (payer in ('direct', 'platform')),
  updated_by      uuid references auth.users (id) on delete set null,
  updated_at      timestamptz not null default now(),
  primary key (institution_id, kind)
);
alter table public.institution_service_payers enable row level security;
revoke all on public.institution_service_payers from anon, authenticated;
create policy institution_service_payers_none on public.institution_service_payers for select to authenticated using (false);
select app.attach_status_guard('public.institution_service_payers');

-- Integration audit: every connection and secret change (never a value; hints only).
create table public.integration_audit (
  id              uuid primary key default gen_random_uuid(),
  institution_id  uuid references public.institutions (id) on delete set null,
  connection_id   uuid,
  actor_user_id   uuid references auth.users (id) on delete set null,
  action          text not null,
  detail          jsonb not null default '{}',
  at              timestamptz not null default now()
);
create index integration_audit_institution_idx on public.integration_audit (institution_id, at desc);
alter table public.integration_audit enable row level security;
revoke all on public.integration_audit from anon, authenticated;
create policy integration_audit_none on public.integration_audit for select to authenticated using (false);

-- Proposed placeholder: a reminder to rotate keys after a year (Ch 42.10 row 9).
insert into public.setting_definitions (key, scope, schema, default_value, area, description, label_key, owner_module, owner_milestone, stored_in) values
  ('key_rotation_reminder_days', 'product', '{"type":"integer","minimum":30,"maximum":1825}', '365', 'platform.product_settings',
   'Remind the Master Admin to rotate a provider key after this many days (Ch 42.10 row 9). Proposed: 365.',
   'settings:keys.key_rotation_reminder_days', 'platform', '0B.11', 'product_settings')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. Helpers
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function app.integration_audit(p_institution uuid, p_connection uuid, p_action text, p_detail jsonb) returns void
language sql security definer set search_path = '' as $$
  insert into public.integration_audit (institution_id, connection_id, actor_user_id, action, detail)
  values (p_institution, p_connection, auth.uid(), p_action, app.redact_secrets(coalesce(p_detail, '{}'::jsonb)))
$$;

create or replace function app.secret_ref_for(p_connection uuid, p_field text) returns text
language sql immutable set search_path = '' as $$
  select 'conn.' || replace(p_connection::text, '-', '') || '.' || p_field
$$;

-- A connection's secrets as the panel may see them: field, hint, age, a rotation waiting, never the value.
create or replace function app.connection_secrets(p_institution uuid, p_connection uuid, p_fields text[]) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('field', f,
           'hint', cur.hint, 'since', cur.valid_from, 'age_days', case when cur.valid_from is not null then (now()::date - cur.valid_from::date) end,
           'next_from', nxt.valid_from) order by f), '[]'::jsonb)
    from unnest(p_fields) f
    left join lateral (
      select s.hint, s.valid_from from public.institution_secrets s
       where p_institution is not null and s.institution_id = p_institution and s.secret_ref = app.secret_ref_for(p_connection, f)
         and s.revoked_at is null and s.valid_from <= now()
      union all
      select s.hint, s.valid_from from public.platform_secrets s
       where p_institution is null and s.secret_ref = app.secret_ref_for(p_connection, f) and s.revoked_at is null and s.valid_from <= now()
      order by 2 desc limit 1) cur on true
    left join lateral (
      select s.valid_from from public.institution_secrets s
       where p_institution is not null and s.institution_id = p_institution and s.secret_ref = app.secret_ref_for(p_connection, f)
         and s.revoked_at is null and s.valid_from > now()
      union all
      select s.valid_from from public.platform_secrets s
       where p_institution is null and s.secret_ref = app.secret_ref_for(p_connection, f) and s.revoked_at is null and s.valid_from > now()
      order by 1 limit 1) nxt on true
$$;

create or replace function app.connection_json(c jsonb, p_institution uuid, p_full boolean) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', c ->> 'id', 'kind', c ->> 'kind', 'provider', c ->> 'provider_key', 'label', c ->> 'label', 'mode', c ->> 'mode',
           'status', c ->> 'status', 'priority', (c ->> 'priority')::int, 'live_test_passed_at', c -> 'live_test_passed_at',
           'last_success_at', c -> 'last_success_at', 'last_error', c -> 'last_error',
           'provider_name', p.name, 'adapter_ready', p.adapter_version is not null)
         || case when p_full then jsonb_build_object('settings', c -> 'settings',
              'secrets', app.connection_secrets(p_institution, (c ->> 'id')::uuid, p.secret_fields), 'secret_fields', to_jsonb(p.secret_fields))
            else '{}'::jsonb end
    from public.integration_providers p where p.key = c ->> 'provider_key'
$$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 4. Panel RPCs (platform.integrations + aal2; D4)
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function public.platform_providers() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not app.is_platform('platform.view') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'providers', coalesce((select jsonb_agg(to_jsonb(p) order by p.kind, p.sort) from public.integration_providers p), '[]'::jsonb),
    'platform_connections', coalesce((select jsonb_agg(app.connection_json(to_jsonb(c), null, app.is_platform('platform.integrations'))
                                         order by c.kind, c.priority) from public.platform_connections c), '[]'::jsonb),
    'error_kinds', coalesce((select jsonb_object_agg(e.code, e.responsibility) from public.integration_error_kinds e), '{}'::jsonb));
end $$;

create or replace function public.platform_integrations(p_institution uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not app.is_platform('platform.view') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'connections', coalesce((select jsonb_agg(app.connection_json(to_jsonb(c), p_institution, app.is_platform('platform.integrations'))
                               order by c.kind, c.priority) from public.integration_connections c where c.institution_id = p_institution), '[]'::jsonb),
    'payers', coalesce((select jsonb_object_agg(p.kind, p.payer) from public.institution_service_payers p where p.institution_id = p_institution), '{}'::jsonb),
    'audit', coalesce((select jsonb_agg(jsonb_build_object('action', a.action, 'at', a.at, 'by', u.email, 'detail', a.detail) order by a.at desc)
                         from (select * from public.integration_audit a where a.institution_id = p_institution order by a.at desc limit 50) a
                         left join auth.users u on u.id = a.actor_user_id), '[]'::jsonb));
end $$;

-- Create or change a connection (p_institution null = the platform's own). Settings are checked against the provider's
-- schema; a secret field name in the settings is refused (secrets only through connection_secret_set).
create or replace function public.platform_connection_save(p_institution uuid, p_id uuid, p_data jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_provider public.integration_providers;
  v_id       uuid := p_id;
  v_settings jsonb := coalesce(p_data -> 'settings', '{}'::jsonb);
  v_errors   text[];
  v_row      jsonb;
begin
  if not app.is_platform('platform.integrations') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  select * into v_provider from public.integration_providers where key = p_data ->> 'provider';
  if not found or v_provider.status = 'retired' then
    raise exception 'connection_invalid' using errcode = 'P0422', detail = 'provider';
  end if;
  if exists (select 1 from jsonb_object_keys(v_settings) k where k = any (v_provider.secret_fields)) then
    raise exception 'connection_invalid' using errcode = 'P0422', detail = 'a secret belongs in the secret field, not the settings';
  end if;
  v_errors := app.validation_errors(v_provider.settings_schema, v_settings);
  if cardinality(v_errors) > 0 then
    raise exception 'connection_invalid' using errcode = 'P0422', detail = array_to_string(v_errors, '; ');
  end if;
  if coalesce(p_data ->> 'mode', 'sandbox') not in ('sandbox', 'live') or length(btrim(coalesce(p_data ->> 'label', ''))) not between 1 and 80
     or coalesce((p_data ->> 'priority')::int, 1) not between 1 and 9 then
    raise exception 'connection_invalid' using errcode = 'P0422', detail = 'label / mode / priority';
  end if;
  if p_institution is not null and not exists (select 1 from public.institutions where id = p_institution and status <> 'closed') then
    raise exception 'record_unknown' using errcode = 'P0404';
  end if;

  if p_institution is null then
    if v_id is null then
      insert into public.platform_connections (kind, provider_key, label, mode, settings, priority, created_by)
      values (v_provider.kind, v_provider.key, btrim(p_data ->> 'label'), coalesce(p_data ->> 'mode', 'sandbox'), v_settings,
              coalesce((p_data ->> 'priority')::int, 1), auth.uid()) returning id into v_id;
    else
      update public.platform_connections set label = btrim(p_data ->> 'label'), settings = v_settings, priority = coalesce((p_data ->> 'priority')::int, priority),
             -- Switching to live needs a new live test (I3).
             live_test_passed_at = case when mode <> coalesce(p_data ->> 'mode', mode) then null else live_test_passed_at end,
             mode = coalesce(p_data ->> 'mode', mode)
       where id = v_id and provider_key = v_provider.key;
      if not found then raise exception 'record_unknown' using errcode = 'P0404'; end if;
    end if;
    select to_jsonb(c) into v_row from public.platform_connections c where c.id = v_id;
  else
    if v_id is null then
      insert into public.integration_connections (institution_id, kind, provider_key, label, mode, settings, priority, created_by)
      values (p_institution, v_provider.kind, v_provider.key, btrim(p_data ->> 'label'), coalesce(p_data ->> 'mode', 'sandbox'), v_settings,
              coalesce((p_data ->> 'priority')::int, 1), auth.uid()) returning id into v_id;
    else
      update public.integration_connections set label = btrim(p_data ->> 'label'), settings = v_settings,
             priority = coalesce((p_data ->> 'priority')::int, priority),
             live_test_passed_at = case when mode <> coalesce(p_data ->> 'mode', mode) then null else live_test_passed_at end,
             mode = coalesce(p_data ->> 'mode', mode)
       where institution_id = p_institution and id = v_id and provider_key = v_provider.key;
      if not found then raise exception 'record_unknown' using errcode = 'P0404'; end if;
    end if;
    select to_jsonb(c) into v_row from public.integration_connections c where c.institution_id = p_institution and c.id = v_id;
  end if;
  perform app.integration_audit(p_institution, v_id, case when p_id is null then 'connection.created' else 'connection.changed' end,
                                jsonb_build_object('provider', v_provider.key, 'label', v_row ->> 'label', 'mode', v_row ->> 'mode',
                                                   'priority', v_row -> 'priority', 'settings', v_settings));
  perform app.platform_audit(case when p_id is null then 'integration.connection_created' else 'integration.connection_changed' end,
                             p_institution, 'integration_connection', v_id::text, null, jsonb_build_object('provider', v_provider.key), null);
  return app.connection_json(v_row, p_institution, true);
end $$;

-- Write-only secret of a connection (D4). p_valid_from in the future = rotation: the current key works until then.
create or replace function public.connection_secret_set(p_institution uuid, p_connection uuid, p_field text, p_value text,
                                                        p_valid_from timestamptz default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_fields  text[];
  v_from    timestamptz := coalesce(p_valid_from, now());
  v_ref     text := app.secret_ref_for(p_connection, p_field);
  v_vault   uuid;
  v_hint    text;
begin
  if not app.is_platform('platform.integrations') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  if p_institution is null then
    select p.secret_fields into v_fields from public.platform_connections c join public.integration_providers p on p.key = c.provider_key where c.id = p_connection;
  else
    select p.secret_fields into v_fields from public.integration_connections c join public.integration_providers p on p.key = c.provider_key
     where c.institution_id = p_institution and c.id = p_connection;
  end if;
  if v_fields is null then
    raise exception 'record_unknown' using errcode = 'P0404';
  end if;
  if not (p_field = any (v_fields)) then
    raise exception 'connection_invalid' using errcode = 'P0422', detail = 'secret field';
  end if;
  if p_value is null or length(p_value) < 4 or length(p_value) > 8000 then
    raise exception 'secret_value_invalid' using errcode = 'P0422';
  end if;
  if v_from < now() - interval '1 minute' then
    raise exception 'secret_valid_from_in_past' using errcode = 'P0422';
  end if;
  v_vault := vault.create_secret(p_value, format('%s:%s:%s', coalesce(p_institution::text, 'platform'), v_ref, gen_random_uuid()),
                                 format('Connection secret %s', v_ref));
  v_hint := app.secret_hint(p_value);
  if p_institution is null then
    update public.platform_secrets set rotated_at = now() where secret_ref = v_ref and revoked_at is null and rotated_at is null;
    insert into public.platform_secrets (secret_ref, vault_id, hint, valid_from, created_by) values (v_ref, v_vault, v_hint, v_from, auth.uid());
  else
    update public.institution_secrets set rotated_at = now()
     where institution_id = p_institution and secret_ref = v_ref and revoked_at is null and rotated_at is null;
    insert into public.institution_secrets (institution_id, secret_ref, vault_id, hint, valid_from, created_by)
    values (p_institution, v_ref, v_vault, v_hint, v_from, auth.uid());
  end if;
  perform app.integration_audit(p_institution, p_connection, case when v_from > now() then 'secret.rotation_scheduled' else 'secret.set' end,
                                jsonb_build_object('field', p_field, 'hint', v_hint, 'valid_from', v_from));
  perform app.platform_audit('integration.secret_set', p_institution, 'integration_connection', p_connection::text, null,
                             jsonb_build_object('field', p_field, 'hint', v_hint, 'valid_from', v_from), null);
  return jsonb_build_object('field', p_field, 'hint', v_hint, 'valid_from', v_from);
end $$;

-- Marks the live test (I3): live bulk sending stays blocked until one live test passed. The adapters (0B.13) run the
-- real test and call this; until then the Master Admin marks it after testing by hand.
create or replace function public.connection_live_test_mark(p_institution uuid, p_connection uuid, p_passed boolean, p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_row jsonb;
begin
  if not app.is_platform('platform.integrations') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  if p_institution is null then
    update public.platform_connections set live_test_passed_at = case when p_passed then now() end where id = p_connection and mode = 'live'
    returning to_jsonb(platform_connections.*) into v_row;
  else
    update public.integration_connections set live_test_passed_at = case when p_passed then now() end
     where institution_id = p_institution and id = p_connection and mode = 'live'
    returning to_jsonb(integration_connections.*) into v_row;
  end if;
  if v_row is null then
    raise exception 'connection_invalid' using errcode = 'P0422', detail = 'only a live connection is live-tested';
  end if;
  perform app.integration_audit(p_institution, p_connection, case when p_passed then 'connection.live_test_passed' else 'connection.live_test_cleared' end,
                                jsonb_build_object('note', p_note));
  return app.connection_json(v_row, p_institution, true);
end $$;

create or replace function public.connection_set_status(p_institution uuid, p_connection uuid, p_active boolean, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_row jsonb;
begin
  if not app.is_platform('platform.integrations') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  if p_institution is null then
    update public.platform_connections set status = case when p_active then 'active' else 'disabled' end,
           disabled_at = case when p_active then null else now() end where id = p_connection
    returning to_jsonb(platform_connections.*) into v_row;
  else
    update public.integration_connections set status = case when p_active then 'active' else 'disabled' end,
           disabled_at = case when p_active then null else now() end where institution_id = p_institution and id = p_connection
    returning to_jsonb(integration_connections.*) into v_row;
  end if;
  if v_row is null then
    raise exception 'record_unknown' using errcode = 'P0404';
  end if;
  perform app.integration_audit(p_institution, p_connection, case when p_active then 'connection.enabled' else 'connection.disabled' end,
                                jsonb_build_object('reason', p_reason));
  return app.connection_json(v_row, p_institution, true);
end $$;

create or replace function public.institution_payer_set(p_institution uuid, p_kind text, p_payer text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not (app.is_platform('platform.integrations') or app.is_platform('platform.billing')) then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  if p_payer not in ('direct', 'platform') or p_kind not in (select distinct kind from public.integration_providers) then
    raise exception 'connection_invalid' using errcode = 'P0422', detail = 'payer';
  end if;
  insert into public.institution_service_payers (institution_id, kind, payer, updated_by) values (p_institution, p_kind, p_payer, auth.uid())
  on conflict (institution_id, kind) do update set payer = excluded.payer, updated_by = excluded.updated_by, updated_at = now();
  perform app.integration_audit(p_institution, null, 'payer.changed', jsonb_build_object('kind', p_kind, 'payer', p_payer));
  return jsonb_build_object('kind', p_kind, 'payer', p_payer);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 5. Runtime side (service role only: the hub worker of 0B.12 and the adapters)
-- ---------------------------------------------------------------------------------------------------------------------
-- A closed or suspended institution uses nothing.
create or replace function app.institution_can_use_connections(p_institution uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.institutions i where i.id = p_institution and i.status not in ('closed', 'suspended'))
$$;

-- The connections to try for one institution and kind, primary first. p_institution is the institution of the record
-- being processed (a lead, a payment, an outbox row) — never a value the client sent (I1). The platform's connections
-- are used when the platform pays for that service (D15) or the institution has none. Live connections without a
-- passed live test are left out for bulk sending (I3).
create or replace function app.resolve_connection(p_institution uuid, p_kind text, p_purpose text default 'send') returns jsonb
language sql stable security definer set search_path = '' as $$
  with payer as (select coalesce((select p.payer from public.institution_service_payers p where p.institution_id = p_institution and p.kind = p_kind),
                                 'direct') as payer),
       own as (
         select 'institution' as owner, to_jsonb(c) as c, c.priority from public.integration_connections c, payer
          where c.institution_id = p_institution and c.kind = p_kind and c.status = 'active' and payer.payer = 'direct'
            and app.institution_can_use_connections(p_institution)
            and not (p_purpose = 'bulk' and c.mode = 'live' and c.live_test_passed_at is null)),
       plat as (
         select 'platform' as owner, to_jsonb(c) as c, c.priority from public.platform_connections c
          where c.kind = p_kind and c.status = 'active' and app.institution_can_use_connections(p_institution)
            and not (p_purpose = 'bulk' and c.mode = 'live' and c.live_test_passed_at is null)
            and ((select payer from payer) = 'platform' or not exists (select 1 from own)))
  select coalesce(jsonb_agg(jsonb_build_object('owner', x.owner, 'id', x.c ->> 'id', 'provider', x.c ->> 'provider_key', 'mode', x.c ->> 'mode',
                                               'settings', x.c -> 'settings', 'sandbox', x.c ->> 'mode' = 'sandbox')
                            order by x.owner = 'platform', x.priority), '[]'::jsonb)
    from (select * from own union all select * from plat) x
$$;

-- The runtime records each result; an error carries whose side it is on (I10).
create or replace function app.connection_record_result(p_institution uuid, p_connection uuid, p_ok boolean, p_error_code text default null,
                                                        p_detail text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_error jsonb;
begin
  if not p_ok then
    v_error := jsonb_build_object('code', coalesce(p_error_code, 'adapter_error'), 'at', now(), 'detail', left(p_detail, 300),
      'responsibility', coalesce((select e.responsibility from public.integration_error_kinds e where e.code = p_error_code), 'platform'));
  end if;
  if p_institution is null then
    update public.platform_connections set last_success_at = case when p_ok then now() else last_success_at end,
           last_error = case when p_ok then last_error else v_error end where id = p_connection;
  else
    update public.integration_connections set last_success_at = case when p_ok then now() else last_success_at end,
           last_error = case when p_ok then last_error else v_error end where institution_id = p_institution and id = p_connection;
  end if;
end $$;

-- Edge-only: the secret of a connection in force now (the rotation's new key only from its effective date).
create or replace function public.connection_secret_for_service(p_institution uuid, p_connection uuid, p_field text) returns text
language sql stable security definer set search_path = '' as $$
  select d.decrypted_secret
    from (select s.vault_id, s.valid_from from public.institution_secrets s
           where p_institution is not null and s.institution_id = p_institution and s.secret_ref = app.secret_ref_for(p_connection, p_field)
             and s.revoked_at is null and s.valid_from <= now()
          union all
          select s.vault_id, s.valid_from from public.platform_secrets s
           where p_institution is null and s.secret_ref = app.secret_ref_for(p_connection, p_field) and s.revoked_at is null and s.valid_from <= now()) s
    join vault.decrypted_secrets d on d.id = s.vault_id
   order by s.valid_from desc limit 1
$$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 6. Closing an institution (I14): disable its connections, destroy its secrets; later milestones add API keys and
--    webhooks to this hook.
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function app.integration_close(p_institution uuid) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_disabled integer;
  v_secrets  integer;
begin
  update public.integration_connections set status = 'disabled', disabled_at = now()
   where institution_id = p_institution and status <> 'disabled';
  get diagnostics v_disabled = row_count;
  v_secrets := public.purge_institution_secrets(p_institution);
  perform app.integration_audit(p_institution, null, 'institution.closed_cleanup', jsonb_build_object('disabled', v_disabled, 'secrets', v_secrets));
  return v_disabled;
end $$;

create or replace function app.on_institution_closed() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform app.integration_close(new.id);
  return new;
end $$;
create trigger institutions_integration_close after update of status on public.institutions
  for each row when (new.status = 'closed' and old.status is distinct from 'closed') execute function app.on_institution_closed();

-- Yearly key rotation reminder (Proposed): one alert per key and month to every active Master Admin.
create or replace function app.integration_key_age_alerts() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_days  integer := (app.product_setting('key_rotation_reminder_days'))::integer;
  v_count integer := 0;
  r       record;
begin
  for r in select s.institution_id, s.secret_ref, s.hint, s.valid_from from public.institution_secrets s
            where s.secret_ref like 'conn.%' and s.revoked_at is null and s.rotated_at is null and s.valid_from < now() - make_interval(days => v_days)
           union all
           select null, s.secret_ref, s.hint, s.valid_from from public.platform_secrets s
            where s.revoked_at is null and s.rotated_at is null and s.valid_from < now() - make_interval(days => v_days) loop
    continue when exists (select 1 from public.platform_alerts a where a.kind = 'key_rotation_due' and a.payload ->> 'ref' = r.secret_ref
                            and a.created_at > now() - interval '30 days');
    insert into public.platform_alerts (recipient_user_id, kind, payload)
    select pm.user_id, 'key_rotation_due', jsonb_build_object('institution_id', r.institution_id, 'ref', r.secret_ref, 'hint', r.hint,
             'since', r.valid_from, 'name', (select i.name from public.institutions i where i.id = r.institution_id))
      from public.platform_members pm where pm.status = 'active' and pm.platform_role = 'master_admin';
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;
select cron.schedule('integration-key-age', '29 5 * * *', 'select app.integration_key_age_alerts()');

-- ---------------------------------------------------------------------------------------------------------------------
-- 7. The institution's own view: status only, never settings or keys (integration.view_status)
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function public.integrations_status() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_institution uuid := app.require_active_session();
begin
  if not app.can('integration.view_status') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'connections', coalesce((select jsonb_agg(app.connection_json(to_jsonb(c), v_institution, false) order by c.kind, c.priority)
                               from public.integration_connections c where c.institution_id = v_institution), '[]'::jsonb),
    'payers', coalesce((select jsonb_object_agg(p.kind, p.payer) from public.institution_service_payers p where p.institution_id = v_institution), '{}'::jsonb));
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 8. Grants and registry
-- ---------------------------------------------------------------------------------------------------------------------
revoke all on function app.integration_audit(uuid, uuid, text, jsonb), app.connection_secrets(uuid, uuid, text[]),
  app.connection_json(jsonb, uuid, boolean), app.resolve_connection(uuid, text, text), app.institution_can_use_connections(uuid),
  app.connection_record_result(uuid, uuid, boolean, text, text), app.integration_close(uuid), app.on_institution_closed(),
  app.integration_key_age_alerts() from public, anon, authenticated;
grant execute on function app.resolve_connection(uuid, text, text), app.connection_record_result(uuid, uuid, boolean, text, text) to service_role;
revoke all on function public.connection_secret_for_service(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.connection_secret_for_service(uuid, uuid, text) to service_role;
revoke all on function public.platform_providers(), public.platform_integrations(uuid), public.platform_connection_save(uuid, uuid, jsonb),
  public.connection_secret_set(uuid, uuid, text, text, timestamptz), public.connection_live_test_mark(uuid, uuid, boolean, text),
  public.connection_set_status(uuid, uuid, boolean, text), public.institution_payer_set(uuid, text, text), public.integrations_status() from public, anon;
grant execute on function public.platform_providers(), public.platform_integrations(uuid), public.platform_connection_save(uuid, uuid, jsonb),
  public.connection_secret_set(uuid, uuid, text, text, timestamptz), public.connection_live_test_mark(uuid, uuid, boolean, text),
  public.connection_set_status(uuid, uuid, boolean, text), public.institution_payer_set(uuid, text, text), public.integrations_status() to authenticated;

insert into app.definer_registry (function_name, reason, added_in, reviewer, tenant_check)
select f, r, '0B.11', 'architecture review 0B.11', t from (values
  ('app.integration_audit', 'Writes one integration audit row (values redacted); called by the checked RPCs only.', 'service_role_only'),
  ('app.connection_secrets', 'Hints and ages of a connection''s secrets (never values); called by the checked RPCs only.', 'service_role_only'),
  ('app.connection_json', 'A connection as the panel / institution may see it; called by the checked RPCs only.', 'service_role_only'),
  ('app.resolve_connection', 'Connections to use for one institution and kind; the institution comes from the record (I1); service role only.', 'service_role_only'),
  ('app.institution_can_use_connections', 'Is the institution open (not closed / suspended); called by the resolver only.', 'service_role_only'),
  ('app.connection_record_result', 'Records a send result on a connection; the hub worker (service role) only.', 'service_role_only'),
  ('app.integration_close', 'Disables an institution''s connections and destroys its secrets when it closes (I14).', 'service_role_only'),
  ('app.on_institution_closed', 'Trigger: runs the integration close hook when an institution is closed.', 'service_role_only'),
  ('app.integration_key_age_alerts', 'Daily job: reminds Master Admins to rotate keys older than the reminder age.', 'service_role_only'),
  ('public.connection_secret_for_service', 'Edge-only read of a connection secret in force; service role only.', 'service_role_only'),
  ('public.platform_providers', 'Provider catalog and the platform''s own connections; platform.view + aal2 (settings only with platform.integrations).', 'not_tenant_data'),
  ('public.platform_integrations', 'One institution''s connections, payers and integration audit; platform.view + aal2.', 'not_tenant_data'),
  ('public.platform_connection_save', 'Creates / changes a connection; platform.integrations + aal2 (D4); audited.', 'not_tenant_data'),
  ('public.connection_secret_set', 'Write-only connection secret into Vault with rotation date; platform.integrations + aal2; audited (hint only).', 'not_tenant_data'),
  ('public.connection_live_test_mark', 'Marks a live connection as live-tested (I3); platform.integrations + aal2; audited.', 'not_tenant_data'),
  ('public.connection_set_status', 'Enables / disables a connection; platform.integrations + aal2; audited.', 'not_tenant_data'),
  ('public.institution_payer_set', 'Who pays for a service of an institution (D15); platform.integrations or billing + aal2; audited.', 'not_tenant_data'),
  ('public.integrations_status', 'Status of the active institution''s connections (no settings or keys); integration.view_status.', 'filters_active_institution')
) as v (f, r, t)
on conflict (function_name) do update set reason = excluded.reason, added_in = excluded.added_in, tenant_check = excluded.tenant_check;
