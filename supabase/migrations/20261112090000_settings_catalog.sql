-- 0B.01 Per-institution settings registry and Appendix A keys (D13, D22, D42). See docs/dev/SETTINGS.md.
-- Builds on the 0A.08 framework (definitions, JSON-schema validation, versions + migrate_fn, app_settings, settings
-- version, product settings): this adds who owns each key and its label, a change history with rollback, every
-- Appendix A key (neutral names, D42), product-level keys (T9), the catalog of other per-institution configuration
-- (T3), and read RPCs for one or several keys. Area permissions are in config/modules/core.json.

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Definitions: label, owner, where the value is stored
-- ---------------------------------------------------------------------------------------------------------------------
alter table public.setting_definitions
  add column label_key text,
  add column owner_module text,
  add column owner_milestone text,
  add column stored_in text not null default 'app_settings';
comment on column public.setting_definitions.label_key is 'Translation key of the label / help (settings namespace).';
comment on column public.setting_definitions.owner_module is 'Module that owns the key and extends its schema later.';
comment on column public.setting_definitions.stored_in is
  'Where the value lives: app_settings (normal), product_settings, or another table (registered for the catalog only).';

update public.setting_definitions set label_key = 'settings:keys.' || key,
  owner_module = case key
    when 'branches_enabled' then 'organisation' when 'idle_signout_minutes' then 'security' when 'min_app_version' then 'platform'
    when 'working_days' then 'office' when 'working_hours' then 'office' when 'quiet_hours' then 'office' when 'scorecard_day' then 'office'
    else 'locale' end,
  owner_milestone = case key
    when 'branches_enabled' then '0A.15' when 'idle_signout_minutes' then '0A.14' when 'min_app_version' then '0A.08' else '0A.11' end,
  stored_in = case scope when 'product' then 'product_settings' else 'app_settings' end;

-- A value for a key stored elsewhere (e.g. institution_name lives in institutions.name) is refused.
create or replace function app.app_settings_stored_here() returns trigger
language plpgsql set search_path = '' as $$
begin
  if exists (select 1 from public.setting_definitions d where d.key = new.key and d.stored_in <> 'app_settings') then
    raise exception 'setting_unknown' using errcode = 'P0404', detail = new.key || ' is not stored in app_settings';
  end if;
  return new;
end $$;
create trigger app_settings_stored_here before insert or update on public.app_settings
  for each row execute function app.app_settings_stored_here();

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. Change history and rollback (0B.01-T1, T5)
-- ---------------------------------------------------------------------------------------------------------------------
create table public.app_settings_history (
  institution_id  uuid not null references public.institutions (id) on delete cascade,
  id              uuid not null default gen_random_uuid(),
  key             text not null,
  old_value       jsonb,               -- null = the default applied before
  new_value       jsonb,               -- null = reset to the default
  schema_version  integer,
  actor_user_id   uuid,
  reason          text,
  at              timestamptz not null default now(),
  primary key (institution_id, id)
);
create index app_settings_history_key_idx on public.app_settings_history (institution_id, key, at desc);
alter table public.app_settings_history enable row level security;
revoke all on public.app_settings_history from anon, authenticated;
grant select on public.app_settings_history to authenticated;
-- Readable by people who may change that area, and by auditors.
create policy app_settings_history_read on public.app_settings_history for select to authenticated
  using (institution_id = (select app.auth_institution_id())
         and ((select app.can('audit.view'))
              or exists (select 1 from public.setting_definitions d where d.key = app_settings_history.key and app.can(d.area))));

create or replace function app.app_settings_log() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    insert into public.app_settings_history (institution_id, key, old_value, new_value, schema_version, actor_user_id, reason)
    values (old.institution_id, old.key, old.value, null, old.schema_version, auth.uid(), nullif(current_setting('app.audit_reason', true), ''));
    return old;
  end if;
  if tg_op = 'UPDATE' and new.value is not distinct from old.value then
    return new;
  end if;
  insert into public.app_settings_history (institution_id, key, old_value, new_value, schema_version, actor_user_id, reason)
  values (new.institution_id, new.key, case when tg_op = 'UPDATE' then old.value end, new.value, new.schema_version, auth.uid(),
          nullif(current_setting('app.audit_reason', true), ''));
  return new;
end $$;
create trigger app_settings_log after insert or update or delete on public.app_settings
  for each row execute function app.app_settings_log();

-- Put a setting back to the value it had before one change (validated and permission-checked like any change).
create or replace function public.setting_rollback(p_history_id uuid, p_institution_id uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.secret_target_institution(p_institution_id);
  v_row         public.app_settings_history;
  v_area        text;
begin
  select * into v_row from public.app_settings_history where institution_id = v_institution and id = p_history_id;
  if not found then
    raise exception 'setting_unknown' using errcode = 'P0404', detail = p_history_id::text;
  end if;
  select area into v_area from public.setting_definitions where key = v_row.key;
  if not app.settings_write_allowed(v_institution, v_area) then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  perform set_config('app.audit_reason', 'rollback of ' || p_history_id::text, true);
  if v_row.old_value is null then
    return public.setting_reset(v_row.key, v_institution);
  end if;
  return public.setting_set(v_row.key, v_row.old_value, v_institution);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. Read one or several keys (0B.01-T5): INVOKER, active institution from the session only, with the source
--    of the value: institution → type profile (0B.03) → product default.
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function public.get_setting(p_key text) returns jsonb
language plpgsql stable security invoker set search_path = '' as $$
declare
  v_institution uuid := app.require_active_session();
  v_def         public.setting_definitions;
  v_value       jsonb;
begin
  select * into v_def from public.setting_definitions where key = p_key and scope = 'institution';
  if not found then
    raise exception 'setting_unknown' using errcode = 'P0404', detail = p_key;
  end if;
  if v_def.stored_in = 'institutions.name' then
    select to_jsonb(i.name) into v_value from public.institutions i where i.id = v_institution;
    return jsonb_build_object('key', p_key, 'value', v_value, 'source', 'institution');
  end if;
  select s.value into v_value from public.app_settings s where s.institution_id = v_institution and s.key = p_key;
  if v_value is not null then
    return jsonb_build_object('key', p_key, 'value', v_value, 'source', 'institution');
  end if;
  v_value := app.type_profile_setting_default(v_institution, p_key);
  if v_value is not null then
    return jsonb_build_object('key', p_key, 'value', v_value, 'source', 'type_profile');
  end if;
  return jsonb_build_object('key', p_key, 'value', v_def.default_value, 'source', 'default');
end $$;

create or replace function public.get_settings(p_keys text[]) returns jsonb
language sql stable security invoker set search_path = '' as $$
  select coalesce(jsonb_object_agg(k, public.get_setting(k) - 'key'), '{}'::jsonb) from unnest(p_keys) k
$$;

revoke all on function public.get_setting(text), public.get_settings(text[]), public.setting_rollback(uuid, uuid) from public, anon;
grant execute on function public.get_setting(text), public.get_settings(text[]), public.setting_rollback(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- 4. Catalog of other per-institution configuration (0B.01-T3): product-level, read-only to institutions.
-- ---------------------------------------------------------------------------------------------------------------------
create table public.config_groups (
  group_key       text primary key,
  owner_tables    text not null,
  owner_milestone text not null,
  description     text not null,
  label_key       text not null
);
alter table public.config_groups enable row level security;
revoke all on public.config_groups from anon, authenticated;
grant select on public.config_groups to authenticated;
create policy config_groups_read on public.config_groups for select to authenticated using (true);

-- ---------------------------------------------------------------------------------------------------------------------
-- 5. Appendix A keys, product keys and configuration groups (generated by scripts/settings/gen_catalog_0B01.py)
-- ---------------------------------------------------------------------------------------------------------------------
insert into public.setting_definitions (key, scope, schema, default_value, area, description, label_key, owner_module, owner_milestone, stored_in)
select key, scope, schema::jsonb, default_value::jsonb, area, description, label_key, owner_module, owner_milestone, stored_in from (values
  ('activity', 'institution', '{"type": "object", "required": ["enabled"], "properties": {"enabled": {"type": "boolean"}}, "additionalProperties": false}', '{"enabled": false}', 'settings.team', 'Team activity tracking (Ch 38).', 'settings:keys.activity', 'team', 'phase 4', 'app_settings'),
  ('reports', 'institution', '{"type": "object", "required": ["enabled"], "properties": {"enabled": {"type": "boolean"}}, "additionalProperties": false}', '{"enabled": true}', 'settings.team', 'Report settings (Ch 38).', 'settings:keys.reports', 'reports', 'phase 4', 'app_settings'),
  ('scorecard', 'institution', '{"type": "object", "required": ["enabled"], "properties": {"enabled": {"type": "boolean"}}, "additionalProperties": false}', '{"enabled": false}', 'settings.team', 'Weekly scorecard (Ch 39).', 'settings:keys.scorecard', 'team', 'phase 4', 'app_settings'),
  ('credits', 'institution', '{"type": "object", "required": ["enabled"], "properties": {"enabled": {"type": "boolean"}}, "additionalProperties": false}', '{"enabled": false}', 'settings.team', 'Credits and leaderboard (Ch 39).', 'settings:keys.credits', 'team', 'phase 4', 'app_settings'),
  ('credit_extras', 'institution', '{"type": "object", "required": ["enabled"], "properties": {"enabled": {"type": "boolean"}}, "additionalProperties": false}', '{"enabled": false}', 'settings.team', 'Extra credits (Ch 39).', 'settings:keys.credit_extras', 'team', 'phase 4', 'app_settings'),
  ('notifications', 'institution', '{"type": "object", "required": ["enabled"], "properties": {"enabled": {"type": "boolean"}}, "additionalProperties": false}', '{"enabled": true}', 'settings.team', 'Who receives which notification ("who" selector, Ch 25).', 'settings:keys.notifications', 'notifications', '1.22', 'app_settings'),
  ('web', 'institution', '{"type": "object", "required": ["mode"], "additionalProperties": false, "properties": {"mode": {"enum": ["all", "roles", "users"]}, "roles": {"type": "array", "items": {"type": "string"}}, "user_ids": {"type": "array", "items": {"type": "string"}}}}', '{"mode": "roles", "roles": []}', 'settings.team', 'Who may use the website besides admins, who always can (Ch 45).', 'settings:keys.web', 'web', '1.35', 'app_settings'),
  ('conversion', 'institution', '{"type": "object", "required": ["enabled"], "properties": {"enabled": {"type": "boolean"}}, "additionalProperties": false}', '{"enabled": false}', 'settings.conversion', 'Conversion flow (Ch 17, 36).', 'settings:keys.conversion', 'conversion', '2.05', 'app_settings'),
  ('conversion_approval', 'institution', '{"type": "object", "required": ["enabled"], "properties": {"enabled": {"type": "boolean"}}, "additionalProperties": false}', '{"enabled": false}', 'settings.conversion', 'Approval during conversion (Ch 17, 34).', 'settings:keys.conversion_approval', 'conversion', '2.05', 'app_settings'),
  ('clients', 'institution', '{"type": "object", "required": ["enabled"], "properties": {"enabled": {"type": "boolean"}}, "additionalProperties": false}', '{"enabled": false}', 'settings.conversion', 'Clients tab (Ch 36).', 'settings:keys.clients', 'clients', '2.08', 'app_settings'),
  ('files', 'institution', '{"type": "object", "required": ["enabled"], "properties": {"enabled": {"type": "boolean"}}, "additionalProperties": false}', '{"enabled": false}', 'settings.conversion', 'Files on or off and who sees everyone''s files (Ch 32).', 'settings:keys.files', 'files', '2.14', 'app_settings'),
  ('upload_rules', 'institution', '{"type": "object", "required": ["enabled"], "properties": {"enabled": {"type": "boolean"}}, "additionalProperties": false}', '{"enabled": false}', 'settings.conversion', 'Upload rules, edited on the web (Ch 31).', 'settings:keys.upload_rules', 'files', '2.13', 'app_settings'),
  ('photo_presets', 'institution', '{"type": "object", "required": ["enabled"], "properties": {"enabled": {"type": "boolean"}}, "additionalProperties": false}', '{"enabled": false}', 'settings.conversion', 'Photo studio presets (Ch 31).', 'settings:keys.photo_presets', 'files', '2.15', 'app_settings'),
  ('fees', 'institution', '{"type": "object", "required": ["enabled"], "properties": {"enabled": {"type": "boolean"}}, "additionalProperties": false}', '{"enabled": false}', 'settings.fees', 'Fees, payments, methods, receipt design, reminders (Ch 34, 35).', 'settings:keys.fees', 'fees', '2.02', 'app_settings'),
  ('receipt_prefix', 'institution', '{"type": "string", "pattern": "^[A-Za-z0-9-]{0,12}$"}', '"R-"', 'settings.fees', 'Prefix of receipt numbers (Ch 35).', 'settings:keys.receipt_prefix', 'fees', '2.07', 'app_settings'),
  ('assignment', 'institution', '{"type": "object", "required": ["enabled"], "properties": {"enabled": {"type": "boolean"}}, "additionalProperties": false}', '{"enabled": true}', 'settings.leads', 'Lead assignment, round robin (Ch 14).', 'settings:keys.assignment', 'leads', '1.03', 'app_settings'),
  ('board', 'institution', '{"type": "object", "required": ["enabled"], "properties": {"enabled": {"type": "boolean"}}, "additionalProperties": false}', '{"enabled": true}', 'settings.pipeline', 'Pipeline board (Ch 15).', 'settings:keys.board', 'leads', '1.12', 'app_settings'),
  ('lead_cards', 'institution', '{"type": "object", "required": ["enabled"], "properties": {"enabled": {"type": "boolean"}}, "additionalProperties": false}', '{"enabled": true}', 'settings.leads', 'What a lead card shows (Ch 15).', 'settings:keys.lead_cards', 'leads', '1.04', 'app_settings'),
  ('lead_filters', 'institution', '{"type": "object", "required": ["enabled"], "properties": {"enabled": {"type": "boolean"}}, "additionalProperties": false}', '{"enabled": true}', 'settings.leads', 'Lead filters (Ch 15).', 'settings:keys.lead_filters', 'leads', '1.12', 'app_settings'),
  ('lead_score', 'institution', '{"type": "object", "required": ["enabled"], "properties": {"enabled": {"type": "boolean"}}, "additionalProperties": false}', '{"enabled": false}', 'settings.leads', 'Lead score rules, referring to stage kinds or ids, never hard-coded stage keys (Ch 22).', 'settings:keys.lead_score', 'leads', '1.13', 'app_settings'),
  ('appointment', 'institution', '{"type": "object", "required": ["enabled"], "properties": {"enabled": {"type": "boolean"}}, "additionalProperties": false}', '{"enabled": false}', 'settings.leads', 'Appointments, e.g. campus visits (Ch 22).', 'settings:keys.appointment', 'leads', '1.13', 'app_settings'),
  ('message_templates', 'institution', '{"type": "object", "required": ["enabled"], "properties": {"enabled": {"type": "boolean"}}, "additionalProperties": false}', '{"enabled": true}', 'settings.leads', 'Message templates (Ch 24).', 'settings:keys.message_templates', 'messaging', '1.20', 'app_settings'),
  ('speed_to_lead_minutes', 'institution', '{"type": "integer", "minimum": 1, "maximum": 1440}', '5', 'settings.leads', 'A new lead not called within this many minutes is escalated to its owner (Ch 18). Default Proposed.', 'settings:keys.speed_to_lead_minutes', 'leads', '1.11', 'app_settings'),
  ('early_reminder_minutes', 'institution', '{"type": "integer", "minimum": 0, "maximum": 1440}', '15', 'settings.leads', 'Early reminder before a follow-up (Ch 18). Default Proposed.', 'settings:keys.early_reminder_minutes', 'leads', '1.11', 'app_settings'),
  ('repeat_reminder_minutes', 'institution', '{"type": "integer", "minimum": 5, "maximum": 1440}', '30', 'settings.leads', 'Repeat reminder interval (Ch 18). Default Proposed.', 'settings:keys.repeat_reminder_minutes', 'leads', '1.11', 'app_settings'),
  ('escalate_team_lead_hours', 'institution', '{"type": "integer", "minimum": 1, "maximum": 168}', '2', 'settings.leads', 'Escalate to the team lead after this many hours (Ch 18). Default Proposed.', 'settings:keys.escalate_team_lead_hours', 'leads', '1.11', 'app_settings'),
  ('escalate_admin_hours', 'institution', '{"type": "integer", "minimum": 1, "maximum": 336}', '24', 'settings.leads', 'Escalate to an admin after this many hours (Ch 18). Default Proposed.', 'settings:keys.escalate_admin_hours', 'leads', '1.11', 'app_settings'),
  ('call_sync', 'institution', '{"type": "object", "required": ["enabled"], "properties": {"enabled": {"type": "boolean"}}, "additionalProperties": false}', '{"enabled": false}', 'settings.calls', 'Call-log sync (Ch 41).', 'settings:keys.call_sync', 'calls', 'phase 3', 'app_settings'),
  ('call_lock', 'institution', '{"type": "object", "required": ["enabled"], "properties": {"enabled": {"type": "boolean"}}, "additionalProperties": false}', '{"enabled": false}', 'settings.calls', 'Call lock (Ch 19).', 'settings:keys.call_lock', 'calls', '1.10', 'app_settings'),
  ('double_call', 'institution', '{"type": "object", "required": ["enabled"], "properties": {"enabled": {"type": "boolean"}}, "additionalProperties": false}', '{"enabled": true}', 'settings.calls', 'Double-call warning (Ch 19).', 'settings:keys.double_call', 'calls', '1.10', 'app_settings'),
  ('contacts_import', 'institution', '{"type": "object", "required": ["mode"], "additionalProperties": false, "properties": {"mode": {"enum": ["all", "roles", "users"]}, "roles": {"type": "array", "items": {"type": "string"}}, "user_ids": {"type": "array", "items": {"type": "string"}}}}', '{"mode": "roles", "roles": []}', 'settings.calls', 'Who may use the phone''s contacts (Ch 23).', 'settings:keys.contacts_import', 'calls', '1.14', 'app_settings'),
  ('ai_chance', 'institution', '{"type": "object", "required": ["enabled"], "properties": {"enabled": {"type": "boolean"}}, "additionalProperties": false}', '{"enabled": false}', 'settings.ai', 'Chance of conversion (Ch 40).', 'settings:keys.ai_chance', 'ai', 'phase 4', 'app_settings'),
  ('ai_credit', 'institution', '{"type": "object", "required": ["enabled"], "properties": {"enabled": {"type": "boolean"}}, "additionalProperties": false}', '{"enabled": false}', 'settings.ai', 'AI conversion credit (Ch 40).', 'settings:keys.ai_credit', 'ai', 'phase 4', 'app_settings'),
  ('ai_providers', 'institution', '{"type": "object", "required": ["enabled", "monthly_budget"], "additionalProperties": false, "properties": {"enabled": {"type": "boolean"}, "monthly_budget": {"type": "number", "minimum": 0}}}', '{"enabled": false, "monthly_budget": 0}', 'settings.ai', 'AI provider, model and budget; keys only in the Vault (Ch 40, 42).', 'settings:keys.ai_providers', 'ai', 'phase 4', 'app_settings'),
  ('network', 'institution', '{"type": "object", "required": ["enabled"], "properties": {"enabled": {"type": "boolean"}}, "additionalProperties": false}', '{"enabled": false}', 'settings.forms', 'Network (alumni) and referrals (Ch 37).', 'settings:keys.network', 'network', 'phase 5', 'app_settings'),
  ('public_forms', 'institution', '{"type": "object", "required": ["enabled"], "properties": {"enabled": {"type": "boolean"}}, "additionalProperties": false}', '{"enabled": false}', 'settings.forms', 'Public forms (Ch 27).', 'settings:keys.public_forms', 'forms', '1.29', 'app_settings'),
  ('institution_name', 'institution', '{"type": "string", "maxLength": 120}', '""', 'settings.general', 'Institution name (Ch 6); stored in institutions.name.', 'settings:keys.institution_name', 'core', '0A.03', 'institutions.name'),
  ('app_name', 'product', '{"type": "string", "minLength": 1, "maxLength": 60}', '"Leadora"', 'platform.product_settings', 'App name (D37).', 'settings:keys.app_name', 'platform', '0B.01', 'product_settings'),
  ('app_domain', 'product', '{"type": "string", "maxLength": 253}', '""', 'platform.product_settings', 'Product domain.', 'settings:keys.app_domain', 'platform', '0B.01', 'product_settings'),
  ('privacy_contact_email', 'product', '{"type": "string", "maxLength": 254}', '""', 'platform.product_settings', 'Contact on the privacy page (Ch 5).', 'settings:keys.privacy_contact_email', 'platform', '0B.01', 'product_settings'),
  ('developer_email', 'product', '{"type": "string", "maxLength": 254}', '""', 'platform.product_settings', 'Owner of the developer / feedback inbox (Ch 46).', 'settings:keys.developer_email', 'platform', '0B.01', 'product_settings')
) as v (key, scope, schema, default_value, area, description, label_key, owner_module, owner_milestone, stored_in);

insert into public.config_groups (group_key, owner_tables, owner_milestone, description, label_key) values
  ('branding', 'institutions, branding settings', '0B.10', 'Name, short name, logo, colour (Ch 6).', 'settings:groups.branding'),
  ('external_board_flow', 'external board flow settings', '2.16', 'Steps, board id label, fee default, on/off (Ch 36).', 'settings:groups.external_board_flow'),
  ('reset_password_format', 'login settings', '0B.19', 'Plain or short-name based reset passwords (Ch 10).', 'settings:groups.reset_password_format'),
  ('locale', 'app_settings (locale keys)', '0A.11', 'Time zone, currency, phone rules, week, payment methods, language (Ch 13).', 'settings:groups.locale'),
  ('lead_score_rules', 'lead score rules', '1.13', 'Rules refer to stage kinds or ids (Ch 22).', 'settings:groups.lead_score_rules'),
  ('counters', 'counters', '0A.08', 'Receipt, refund and client id counters (Ch 33, 35).', 'settings:groups.counters'),
  ('external_accounts', 'integration hub connections, Vault', '0B.11', 'Drive, PDF / photo services, AI, SMS, email, payments (Ch 42).', 'settings:groups.external_accounts'),
  ('types_and_packs', 'type profiles, packs, labels, modules', '0B.03', 'Type profile / industry, labels, modules on or off (Ch 7, 8, 9).', 'settings:groups.types_and_packs'),
  ('plan_and_billing', 'plans, subscriptions', '0B.16', 'Plan, period, limits, prices, who pays gateway / SMS charges (Ch 9, D15).', 'settings:groups.plan_and_billing'),
  ('login', 'login settings', '0B.17', 'Google mode, domain auto-approval and default role, OTP channel (Ch 10).', 'settings:groups.login'),
  ('roles_and_access', 'roles, role_assignments, field rules', '0A.16', 'Roles, templates, field masking, export limits, approval policies (Ch 11).', 'settings:groups.roles_and_access'),
  ('branches', 'org_units, branches', '0A.15', 'Branch name, address, phone, head (Ch 12).', 'settings:groups.branches'),
  ('notification_matrix', 'notification matrix, templates, consent', '1.21', 'Kind x recipient x channel, template texts, opt-out (Ch 24, 25).', 'settings:groups.notification_matrix'),
  ('campaigns', 'campaign settings', '1.27', 'Daily limit, approval limit, send speed (Ch 26).', 'settings:groups.campaigns'),
  ('public_pages', 'public pages, custom domains', '1.29', 'Slug, own domain, application form, deadlines (Ch 27).', 'settings:groups.public_pages'),
  ('custom_parts', 'custom fields, custom records, automations, webhooks, API keys', '0B.06', 'Per-institution custom parts and limits (Ch 14, 43).', 'settings:groups.custom_parts');

-- Every key must have an owner and a label key: checked by CI (npm run check:settings) and the 0B.01 SQL test, not
-- by a NOT NULL constraint, so tests can still register short-lived test keys.

insert into app.definer_registry (function_name, reason, added_in, reviewer, tenant_check)
select f, r, '0B.01', 'architecture review 0B.01', t from (values
  ('app.app_settings_log', 'Trigger: writes the history row of the app_settings row being changed (same institution, never reads other rows).', 'not_tenant_data'),
  ('public.setting_rollback', 'Restores an earlier value of a setting of the target institution through setting_set / setting_reset (validated, can(area)).', 'filters_active_institution')
) as v (f, r, t);
