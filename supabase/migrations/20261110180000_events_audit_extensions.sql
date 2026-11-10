-- 0A.09 Domain event log, audit log and the extension framework.
-- Plan: Ch 43 (43.2–43.5, 43.7, 43.8), Ch 3.3, Ch 11.14, principle 4. See docs/dev/EVENTS.md and docs/dev/EXTENSIONS.md.

-- ---------------------------------------------------------------------------------------------------------------------
-- Interim access helper: until can() exists (0A.17), reading events / audit and managing extensions is limited to the
-- platform Master Admin (fail-closed). 0A.17 replaces these checks with can().
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function app.is_platform_admin() returns boolean
language sql stable set search_path = '' as $$
  select exists (select 1 from public.platform_members pm where pm.user_id = auth.uid() and pm.platform_role = 'master_admin')
$$;
grant execute on function app.is_platform_admin() to authenticated, service_role;

-- Internal helpers may write for an explicit institution only when the caller is that institution's active session,
-- the platform Master Admin, or a backend call without a user (service_role / owner / jobs).
create or replace function app.assert_may_write_for(p_institution uuid) returns void
language plpgsql stable set search_path = '' as $$
begin
  if p_institution is null then
    raise exception 'institution_id_required' using errcode = 'P0402';
  end if;
  if auth.uid() is null or app.is_platform_admin() then
    return;
  end if;
  if p_institution is distinct from app.auth_institution_id() then
    raise exception 'institution_mismatch' using errcode = 'P0403';
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- Event catalogue: every event key + version has a payload JSON Schema (contract for automation, webhooks, extensions).
-- Old versions stay available after a change (Ch 43.7 #6): add a new version row, deprecate the old one later.
-- ---------------------------------------------------------------------------------------------------------------------
create table public.event_definitions (
  event_key      text not null check (event_key ~ '^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$'),
  version        integer not null check (version >= 1),
  entity_type    text not null check (entity_type ~ '^[a-z][a-z0-9_]*$'),
  payload_schema jsonb not null,
  description    text not null,
  extension_key  text,
  deprecated_at  timestamptz,
  created_at     timestamptz not null default now(),
  primary key (event_key, version)
);

create table public.domain_events (
  institution_id        uuid not null references public.institutions (id) on delete cascade,
  id                    uuid not null default gen_random_uuid(),
  event_key             text not null,
  event_version         integer not null,
  entity_type           text not null,
  entity_id             text,
  branch_id             uuid,
  actor_user_id         uuid,
  on_behalf_of_user_id  uuid,
  payload               jsonb not null default '{}'::jsonb,
  occurred_at           timestamptz not null default now(),
  processed_at          timestamptz,
  listener_errors       jsonb,
  primary key (institution_id, id),
  foreign key (event_key, event_version) references public.event_definitions (event_key, version)
);
create index domain_events_time_idx on public.domain_events (institution_id, occurred_at);
create index domain_events_key_idx on public.domain_events (institution_id, event_key, occurred_at);
create index domain_events_pending_idx on public.domain_events (institution_id, occurred_at) where processed_at is null;
comment on table public.domain_events is
  'Every important action. Written only by app.emit_event(); read by automation, webhooks and extensions. '
  'Proposed (Ch 43.7 #5): partitioning by time and expiry of processed events once volume requires it.';

-- Append-only audit log of security-relevant changes (settings, secrets, memberships, roles, extensions …).
create table public.audit_log (
  institution_id  uuid not null references public.institutions (id) on delete cascade,
  id              uuid not null default gen_random_uuid(),
  actor_user_id   uuid,
  action          text not null check (action ~ '^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$'),
  target_type     text not null,
  target_id       text,
  before          jsonb,
  after           jsonb,
  reason          text,
  at              timestamptz not null default now(),
  primary key (institution_id, id)
);
create index audit_log_time_idx on public.audit_log (institution_id, at);

-- Product-level actions (no institution): e.g. min_app_version, enabling an extension in the catalogue.
create table public.platform_audit_log (
  id             uuid primary key default gen_random_uuid(),
  actor_user_id  uuid,
  action         text not null,
  target_type    text not null,
  target_id      text,
  before         jsonb,
  after          jsonb,
  reason         text,
  at             timestamptz not null default now()
);

-- Append-only: updates are never allowed; deletes only when an institution is purged (flag set by the purge routine)
-- or through the institution delete cascade.
create or replace function app.block_audit_changes() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' and (coalesce(current_setting('app.audit_purge', true), '') = 'on' or pg_trigger_depth() > 1) then
    return old;
  end if;
  raise exception 'audit_log_is_append_only' using errcode = 'P0405';
end $$;
create trigger audit_log_append_only before update or delete on public.audit_log
  for each row execute function app.block_audit_changes();
create trigger platform_audit_log_append_only before update or delete on public.platform_audit_log
  for each row execute function app.block_audit_changes();

-- ---------------------------------------------------------------------------------------------------------------------
-- Extensions (Ch 43.4): registry of available extensions and which institution has them on.
-- ---------------------------------------------------------------------------------------------------------------------
create table public.extensions (
  key          text primary key check (key ~ '^[a-z][a-z0-9_]*$'),
  schema_name  text not null unique check (schema_name ~ '^ext_[a-z0-9_]+$'),
  version      text not null,
  status       text not null default 'available' check (status in ('available', 'retired')),
  description  text not null,
  created_at   timestamptz not null default now()
);

create table public.institution_extensions (
  institution_id  uuid not null references public.institutions (id) on delete cascade,
  extension_key   text not null references public.extensions (key) on delete cascade,
  enabled         boolean not null default false,
  changed_by      uuid,
  changed_at      timestamptz not null default now(),
  primary key (institution_id, extension_key)
);

create or replace function app.extension_enabled(p_extension_key text) returns boolean
language sql stable set search_path = '' as $$
  select exists (select 1 from public.institution_extensions ie
                 where ie.institution_id = app.auth_institution_id() and ie.extension_key = p_extension_key and ie.enabled)
$$;
grant execute on function app.extension_enabled(text) to authenticated, service_role;

-- Listeners: functions that react to events (automation 1.32, webhooks 1.31, extensions). Run by the dispatcher.
create table public.event_listeners (
  listener_key   text primary key check (listener_key ~ '^[a-z][a-z0-9_.]*$'),
  event_key      text not null,
  function_name  text not null,
  extension_key  text references public.extensions (key) on delete cascade,
  enabled        boolean not null default true
);

-- ---------------------------------------------------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------------------------------------------------
alter table public.event_definitions enable row level security;
alter table public.domain_events enable row level security;
alter table public.audit_log enable row level security;
alter table public.platform_audit_log enable row level security;
alter table public.extensions enable row level security;
alter table public.institution_extensions enable row level security;
alter table public.event_listeners enable row level security;

revoke all on public.event_definitions, public.domain_events, public.audit_log, public.platform_audit_log,
              public.extensions, public.institution_extensions, public.event_listeners from anon, authenticated;
grant select on public.event_definitions, public.extensions, public.institution_extensions to authenticated;
grant select on public.domain_events, public.audit_log, public.platform_audit_log to authenticated;

create policy event_definitions_read on public.event_definitions for select to authenticated using (true);
create policy extensions_read on public.extensions for select to authenticated using (true);
create policy institution_extensions_read_own on public.institution_extensions for select to authenticated
  using (institution_id = (select app.auth_institution_id()));
-- Events and audit: the active institution, and (until can() in 0A.17) only for the platform Master Admin.
create policy domain_events_read on public.domain_events for select to authenticated
  using (institution_id = (select app.auth_institution_id()) and (select app.is_platform_admin()));
create policy audit_log_read on public.audit_log for select to authenticated
  using (institution_id = (select app.auth_institution_id()) and (select app.is_platform_admin()));
create policy platform_audit_log_read on public.platform_audit_log for select to authenticated
  using ((select app.is_platform_admin()));
create policy event_listeners_none on public.event_listeners for select to authenticated using (false);

-- ---------------------------------------------------------------------------------------------------------------------
-- Writers (internal; not exposed through the API). DEFINER because app roles have no insert grant.
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function app.emit_event(p_institution uuid, p_event_key text, p_version integer, p_entity_type text,
                                          p_entity_id text, p_payload jsonb, p_branch_id uuid default null,
                                          p_on_behalf_of uuid default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_def    public.event_definitions;
  v_errors text[];
  v_id     uuid;
begin
  perform app.assert_may_write_for(p_institution);
  perform app.auth_institution_id(); -- marks the tenant check for the lint; the real check is above
  select * into v_def from public.event_definitions where event_key = p_event_key and version = p_version;
  if not found then
    raise exception 'event_unknown' using errcode = 'P0404', detail = format('%s v%s', p_event_key, p_version);
  end if;
  if v_def.entity_type <> p_entity_type then
    raise exception 'event_entity_mismatch' using errcode = 'P0422', detail = format('%s expects %s', p_event_key, v_def.entity_type);
  end if;
  v_errors := app.validation_errors(v_def.payload_schema, coalesce(p_payload, '{}'::jsonb));
  if array_length(v_errors, 1) > 0 then
    raise exception 'event_payload_invalid' using errcode = 'P0422', detail = array_to_string(v_errors, '; ');
  end if;
  insert into public.domain_events (institution_id, event_key, event_version, entity_type, entity_id, branch_id,
                                    actor_user_id, on_behalf_of_user_id, payload)
  values (p_institution, p_event_key, p_version, p_entity_type, p_entity_id, p_branch_id, auth.uid(), p_on_behalf_of,
          coalesce(p_payload, '{}'::jsonb))
  returning id into v_id;
  return v_id;
end $$;

create or replace function app.audit(p_institution uuid, p_action text, p_target_type text, p_target_id text,
                                     p_before jsonb, p_after jsonb, p_reason text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  perform app.assert_may_write_for(p_institution);
  perform app.auth_institution_id();
  insert into public.audit_log (institution_id, actor_user_id, action, target_type, target_id, before, after, reason)
  values (p_institution, auth.uid(), p_action, p_target_type, p_target_id, p_before, p_after, p_reason)
  returning id into v_id;
  return v_id;
end $$;

create or replace function app.platform_audit(p_action text, p_target_type text, p_target_id text,
                                              p_before jsonb, p_after jsonb, p_reason text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  if auth.uid() is not null and not app.is_platform_admin() then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  insert into public.platform_audit_log (actor_user_id, action, target_type, target_id, before, after, reason)
  values (auth.uid(), p_action, p_target_type, p_target_id, p_before, p_after, p_reason)
  returning id into v_id;
  return v_id;
end $$;

revoke all on function app.emit_event(uuid, text, integer, text, text, jsonb, uuid, uuid),
                     app.audit(uuid, text, text, text, jsonb, jsonb, text),
                     app.platform_audit(text, text, text, jsonb, jsonb, text) from public, anon;
grant execute on function app.emit_event(uuid, text, integer, text, text, jsonb, uuid, uuid),
                          app.audit(uuid, text, text, text, jsonb, jsonb, text),
                          app.platform_audit(text, text, text, jsonb, jsonb, text) to authenticated, service_role;

-- Dispatcher: runs listeners for pending events (the per-institution job scheduler, 1.16, calls it with back-off).
-- A listener of an extension runs only for institutions that have the extension enabled. Errors are recorded on the
-- event, never lost; the event is marked processed so a failing listener cannot block the queue.
create or replace function app.dispatch_events(p_limit integer default 100) returns integer
language plpgsql set search_path = '' as $$
declare
  e record;
  l record;
  v_errors jsonb;
  v_count integer := 0;
begin
  for e in
    select * from public.domain_events where processed_at is null order by occurred_at limit p_limit for update skip locked
  loop
    v_errors := '[]'::jsonb;
    for l in
      select el.* from public.event_listeners el
      where el.enabled and el.event_key = e.event_key
        and (el.extension_key is null or exists (
             select 1 from public.institution_extensions ie
             where ie.institution_id = e.institution_id and ie.extension_key = el.extension_key and ie.enabled))
      order by el.listener_key
    loop
      begin
        execute format('select %s($1)', l.function_name) using to_jsonb(e);
      exception when others then
        v_errors := v_errors || jsonb_build_object('listener', l.listener_key, 'error', sqlerrm);
      end;
    end loop;
    update public.domain_events set processed_at = now(),
           listener_errors = case when jsonb_array_length(v_errors) > 0 then v_errors end
     where institution_id = e.institution_id and id = e.id;
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;
revoke all on function app.dispatch_events(integer) from public, anon, authenticated;
grant execute on function app.dispatch_events(integer) to service_role;

-- Enabling an extension for an institution is a platform action (Master Admin panel, 0B).
create or replace function public.extension_set_enabled(p_institution_id uuid, p_extension_key text, p_enabled boolean)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_before boolean;
begin
  if not app.is_platform_admin() then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  if not exists (select 1 from public.extensions where key = p_extension_key and status = 'available') then
    raise exception 'extension_unknown' using errcode = 'P0404', detail = p_extension_key;
  end if;
  select enabled into v_before from public.institution_extensions
   where institution_id = p_institution_id and extension_key = p_extension_key;
  insert into public.institution_extensions (institution_id, extension_key, enabled, changed_by, changed_at)
  values (p_institution_id, p_extension_key, p_enabled, auth.uid(), now())
  on conflict (institution_id, extension_key) do update
    set enabled = excluded.enabled, changed_by = excluded.changed_by, changed_at = now();
  perform app.audit(p_institution_id, 'extension.toggled', 'extension', p_extension_key,
                    jsonb_build_object('enabled', v_before), jsonb_build_object('enabled', p_enabled));
  perform app.emit_event(p_institution_id, 'extension.toggled', 1, 'extension', p_extension_key,
                         jsonb_build_object('extension_key', p_extension_key, 'enabled', p_enabled));
  return p_enabled;
end $$;
revoke all on function public.extension_set_enabled(uuid, text, boolean) from public, anon;
grant execute on function public.extension_set_enabled(uuid, text, boolean) to authenticated;

insert into app.definer_registry (function_name, reason, added_in, reviewer, tenant_check) values
  ('app.emit_event', 'Inserts domain events (no app grant). app.assert_may_write_for(): only the active institution, '
   || 'the platform Master Admin or a backend call. Schema-validated payload.', '0A.09', 'architecture review 0A.09',
   'filters_active_institution'),
  ('app.audit', 'Appends audit rows; same institution guard as emit_event.', '0A.09', 'architecture review 0A.09',
   'filters_active_institution'),
  ('app.platform_audit', 'Appends product-level audit rows; platform Master Admin or backend only; no tenant data.', '0A.09',
   'architecture review 0A.09', 'not_tenant_data'),
  ('public.extension_set_enabled', 'Platform action: toggles an extension for an institution; Master Admin only; '
   || 'audited and emitted.', '0A.09', 'architecture review 0A.09', 'not_tenant_data');

-- ---------------------------------------------------------------------------------------------------------------------
-- Core event catalogue (v1). Payload schemas are the contract; see docs/dev/EVENTS.md.
-- ---------------------------------------------------------------------------------------------------------------------
insert into public.event_definitions (event_key, version, entity_type, payload_schema, description) values
  ('setting.changed', 1, 'setting',
   '{"type":"object","required":["key","value"],"properties":{"key":{"type":"string"},"value":{},"previous_value":{}}}',
   'An institution setting got a new value.'),
  ('setting.reset', 1, 'setting',
   '{"type":"object","required":["key"],"properties":{"key":{"type":"string"},"previous_value":{}}}',
   'An institution setting was reset to its default.'),
  ('secret.set', 1, 'secret',
   ('{"type":"object","required":["ref","hint","valid_from"],"properties":{"ref":{"type":"string"},"hint":{"type":"string"},'
   || '"valid_from":{"type":"string"}},"additionalProperties":false}')::jsonb,
   'A secret value was set or rotated (only the hint is carried, never the value).'),
  ('secret.revoked', 1, 'secret',
   '{"type":"object","required":["ref"],"properties":{"ref":{"type":"string"}},"additionalProperties":false}',
   'A secret was revoked.'),
  ('membership.status_changed', 1, 'membership',
   ('{"type":"object","required":["user_id","from","to"],"properties":{"user_id":{"type":"string"},'
   || '"from":{"type":"string"},"to":{"type":"string"}}}')::jsonb,
   'A person''s membership in the institution changed status (e.g. deactivated).'),
  ('extension.toggled', 1, 'extension',
   ('{"type":"object","required":["extension_key","enabled"],"properties":{"extension_key":{"type":"string"},'
   || '"enabled":{"type":"boolean"}}}')::jsonb,
   'An extension was switched on or off for the institution.');

-- ---------------------------------------------------------------------------------------------------------------------
-- 0A.09-T8: hook earlier writers into the audit log and the event log.
-- ---------------------------------------------------------------------------------------------------------------------
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
  perform app.audit(v_institution, 'setting.changed', 'setting', p_key, jsonb_build_object('value', v_previous),
                    jsonb_build_object('value', p_value));
  perform app.emit_event(v_institution, 'setting.changed', 1, 'setting', p_key,
                         jsonb_build_object('key', p_key, 'value', p_value, 'previous_value', v_previous));
  return jsonb_build_object('key', p_key, 'value', p_value, 'settings_version', app.bump_settings_version(v_institution));
end $$;

create or replace function public.setting_reset(p_key text, p_institution_id uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.secret_target_institution(p_institution_id);
  v_def         public.setting_definitions;
  v_previous    jsonb;
begin
  select * into v_def from public.setting_definitions where key = p_key and scope = 'institution';
  if not found then
    raise exception 'setting_unknown' using errcode = 'P0404', detail = p_key;
  end if;
  if not app.settings_write_allowed(v_institution, v_def.area) then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  delete from public.app_settings where institution_id = v_institution and key = p_key returning value into v_previous;
  perform app.audit(v_institution, 'setting.reset', 'setting', p_key, jsonb_build_object('value', v_previous), null);
  perform app.emit_event(v_institution, 'setting.reset', 1, 'setting', p_key,
                         jsonb_build_object('key', p_key, 'previous_value', v_previous));
  return jsonb_build_object('key', p_key, 'value', app.setting_value(v_institution, p_key),
                            'settings_version', app.bump_settings_version(v_institution));
end $$;

create or replace function public.product_setting_set(p_key text, p_value jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_def      public.setting_definitions;
  v_errors   text[];
  v_previous jsonb;
begin
  if not app.is_platform_admin() then
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
  select value into v_previous from public.product_settings where key = p_key;
  insert into public.product_settings (key, value, schema_version, updated_by) values (p_key, p_value, v_def.version, auth.uid())
  on conflict (key) do update set value = excluded.value, schema_version = excluded.schema_version,
                                  updated_by = excluded.updated_by, updated_at = now();
  perform app.platform_audit('product_setting.changed', 'product_setting', p_key, jsonb_build_object('value', v_previous),
                             jsonb_build_object('value', p_value));
  return jsonb_build_object('key', p_key, 'value', p_value);
end $$;

-- Secrets: audit + event carry the hint only.
create or replace function public.secret_set(p_ref text, p_value text, p_valid_from timestamptz default null,
                                             p_institution_id uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.secret_target_institution(p_institution_id);
  v_from        timestamptz := coalesce(p_valid_from, now());
  v_vault_id    uuid;
  v_hint        text;
begin
  if not app.secret_write_allowed(v_institution) then
    raise exception 'permission_denied' using errcode = '42501', hint = 'Only the Master Admin may set secrets (D4).';
  end if;
  if p_value is null or length(p_value) < 4 then
    raise exception 'secret_value_invalid' using errcode = 'P0422';
  end if;
  if v_from < now() - interval '1 minute' then
    raise exception 'secret_valid_from_in_past' using errcode = 'P0422';
  end if;
  v_vault_id := vault.create_secret(p_value, format('inst:%s:%s:%s', v_institution, p_ref, gen_random_uuid()),
                                    format('Institution secret %s', p_ref));
  v_hint := app.secret_hint(p_value);
  update public.institution_secrets set rotated_at = now()
   where institution_id = v_institution and secret_ref = p_ref and revoked_at is null and rotated_at is null;
  insert into public.institution_secrets (institution_id, secret_ref, vault_id, hint, valid_from, created_by)
  values (v_institution, p_ref, v_vault_id, v_hint, v_from, auth.uid());
  perform app.audit(v_institution, 'secret.set', 'secret', p_ref, null,
                    jsonb_build_object('hint', v_hint, 'valid_from', v_from));
  perform app.emit_event(v_institution, 'secret.set', 1, 'secret', p_ref,
                         jsonb_build_object('ref', p_ref, 'hint', v_hint, 'valid_from', v_from));
  return jsonb_build_object('ref', p_ref, 'hint', v_hint, 'valid_from', v_from);
end $$;

create or replace function public.secret_revoke(p_ref text, p_institution_id uuid default null)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.secret_target_institution(p_institution_id);
  v_count       integer;
begin
  if not app.secret_write_allowed(v_institution) then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  delete from vault.secrets v using public.institution_secrets s
   where s.vault_id = v.id and s.institution_id = v_institution and s.secret_ref = p_ref;
  update public.institution_secrets set revoked_at = now()
   where institution_id = v_institution and secret_ref = p_ref and revoked_at is null;
  get diagnostics v_count = row_count;
  perform app.audit(v_institution, 'secret.revoked', 'secret', p_ref, null, jsonb_build_object('versions', v_count));
  perform app.emit_event(v_institution, 'secret.revoked', 1, 'secret', p_ref, jsonb_build_object('ref', p_ref));
  return v_count;
end $$;

-- Membership status changes (deactivation etc.) are audited and emitted wherever they come from.
create or replace function app.on_membership_status_logged() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.status is distinct from old.status then
    insert into public.audit_log (institution_id, actor_user_id, action, target_type, target_id, before, after)
    values (new.institution_id, auth.uid(), 'membership.status_changed', 'membership', new.user_id::text,
            jsonb_build_object('status', old.status), jsonb_build_object('status', new.status));
    insert into public.domain_events (institution_id, event_key, event_version, entity_type, entity_id, actor_user_id, payload)
    values (new.institution_id, 'membership.status_changed', 1, 'membership', new.user_id::text, auth.uid(),
            jsonb_build_object('user_id', new.user_id, 'from', old.status, 'to', new.status));
  end if;
  return null;
end $$;
create trigger institution_members_status_logged after update on public.institution_members
  for each row execute function app.on_membership_status_logged();
insert into app.definer_registry (function_name, reason, added_in, reviewer, tenant_check) values
  ('app.on_membership_status_logged', 'Trigger: writes audit + event rows for the membership row being changed '
   || '(same institution as the row; no app insert grant).', '0A.09', 'architecture review 0A.09', 'not_tenant_data');

-- ---------------------------------------------------------------------------------------------------------------------
-- Extension migrations are applied after the core by scripts/apply-extensions.sh and tracked here (one row per file).
-- An applied file must never change: the runner compares the checksum and stops on a mismatch.
-- ---------------------------------------------------------------------------------------------------------------------
create table app.extension_migrations (
  extension_key  text not null,
  filename       text not null,
  checksum       text not null,
  applied_at     timestamptz not null default now(),
  primary key (extension_key, filename)
);
comment on table app.extension_migrations is 'Which extension migration files have been applied (scripts/apply-extensions.sh).';
