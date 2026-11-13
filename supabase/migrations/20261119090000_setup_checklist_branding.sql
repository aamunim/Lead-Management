-- 0B.10 Setup checklist, branding and copy-from-institution (Ch 6.5, 6.9 rows 4, 7; Ch 5.3, 5.8, 5.16; Ch 10.2; D12,
-- D16, D17).
--   * Checklist: product-wide items (Proposed list) with who does them, the milestone each arrives in and a rule; the
--     institution's own state for items marked by hand. Items with a rule are worked out from the data when read, so
--     they are always current (an SMS connection that turns healthy ticks its item without a separate event).
--   * Branding: name and short name (institutions), colour and logo (settings `brand_color`, `brand_logo_path`; the logo
--     lives in the institution's folder of the private bucket). Shown after sign-in only; the sign-in page stays neutral.
--   * Copy setup from another institution (platform staff): configuration areas registered as data (words, settings,
--     custom fields now; later milestones add theirs). Never records.
--   * Trial ending with setup incomplete → an alert to Support and Master Admins (Proposed).

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Checklist data
-- ---------------------------------------------------------------------------------------------------------------------
create table public.setup_checklist_items (
  key             text primary key check (key ~ '^[a-z][a-z0-9_]*$'),
  owner           text not null check (owner in ('super_admin', 'master_admin', 'both')),
  chapter         text not null,
  rule            text not null default 'manual' check (rule in ('manual', 'branding', 'branches', 'staff')),
  available       boolean not null default true,     -- false: its feature arrives later (available_from)
  available_from  text,
  optional        boolean not null default false,    -- not counted in the progress
  module          text references public.modules (key),
  video_url       text check (video_url is null or video_url ~ '^https://'),
  sort            integer not null
);
alter table public.setup_checklist_items enable row level security;
revoke all on public.setup_checklist_items from anon, authenticated;
grant select on public.setup_checklist_items to authenticated;
create policy setup_checklist_items_read on public.setup_checklist_items for select to authenticated using (true);
comment on table public.setup_checklist_items is
  'Product-wide setup checklist (0B.10, Proposed list). Later milestones set available = true when their feature ships.';

-- Ch 6.5 list (Proposed). The words are in the i18n namespace `checklist` (items.<key>.title / .help).
insert into public.setup_checklist_items (key, owner, chapter, rule, available, available_from, optional, module, sort) values
  ('branding', 'super_admin', 'Ch 5.16', 'branding', true, null, false, null, 10),
  ('branches', 'super_admin', 'Ch 12', 'branches', true, null, false, 'branches', 20),
  ('offerings', 'super_admin', 'Ch 13', 'manual', false, '1A', false, null, 30),
  ('fee_structure', 'super_admin', 'Ch 31', 'manual', false, '2', false, null, 40),
  ('pipeline_words', 'super_admin', 'Ch 8, 14', 'manual', true, null, false, null, 50),
  ('staff', 'super_admin', 'Ch 11', 'staff', true, null, false, null, 60),
  ('messaging', 'master_admin', 'Ch 26 (D4)', 'manual', false, '0B.13', false, null, 70),
  ('payment_merchant', 'both', 'Ch 31 (D17)', 'manual', true, null, false, null, 80),
  ('message_templates', 'super_admin', 'Ch 27 (D6)', 'manual', false, '1A', false, null, 90),
  ('application_form', 'super_admin', 'Ch 22', 'manual', false, '1B', false, null, 100),
  ('own_domain', 'both', 'Ch 5.16 (D16)', 'manual', false, '3', true, null, 110),
  ('ai_drive', 'super_admin', 'Ch 40', 'manual', false, '2', true, null, 120),
  ('lead_import', 'super_admin', 'Ch 23', 'manual', false, '1A', false, null, 130);

create table public.institution_checklist (
  institution_id  uuid not null references public.institutions (id) on delete cascade,
  item_key        text not null references public.setup_checklist_items (key) on delete cascade,
  status          text not null check (status in ('done', 'open')),
  note            text check (note is null or length(note) <= 300),
  completed_at    timestamptz,
  completed_by    uuid references auth.users (id) on delete set null,
  primary key (institution_id, item_key)
);
alter table public.institution_checklist enable row level security;
revoke all on public.institution_checklist from anon, authenticated;
create policy institution_checklist_none on public.institution_checklist for select to authenticated using (false);
select app.attach_status_guard('public.institution_checklist');

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. Branding settings (Appendix A branding row). Name and short name stay on institutions.
-- ---------------------------------------------------------------------------------------------------------------------
insert into public.setting_definitions (key, scope, schema, default_value, area, description, label_key, owner_module, owner_milestone, stored_in) values
  ('brand_color', 'institution', '{"type":"string","pattern":"^#[0-9A-Fa-f]{6}$"}', '"#3557D4"', 'settings.branding',
   'The institution''s colour, shown after sign-in (Ch 5.16). A colour without enough contrast is used for accents only.',
   'settings:keys.brand_color', 'core', '0B.10', 'app_settings'),
  ('brand_logo_path', 'institution', '{"type":["string","null"],"maxLength":300}', 'null', 'settings.branding',
   'Path of the logo in the institution''s folder of the private file bucket (Ch 5.16).',
   'settings:keys.brand_logo_path', 'core', '0B.10', 'app_settings'),
  ('setup_alert_days_before_trial_end', 'product', '{"type":"integer","minimum":1,"maximum":30}', '3', 'platform.product_settings',
   'Days before a trial ends when Support is told that the institution''s setup is incomplete (Ch 6.9 row 7). Proposed: 3.',
   'settings:keys.setup_alert_days_before_trial_end', 'platform', '0B.10', 'product_settings')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. Checklist state
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function app.checklist_rule_done(p_institution uuid, p_rule text) returns boolean
language sql stable security definer set search_path = '' as $$
  select case p_rule
    when 'branding' then exists (select 1 from public.app_settings s where s.institution_id = p_institution
                                   and s.key in ('brand_color', 'brand_logo_path') and s.value <> 'null'::jsonb)
    when 'branches' then exists (select 1 from public.org_units u where u.institution_id = p_institution and u.kind = 'branch' and u.archived_at is null)
    when 'staff' then (select count(*) from public.institution_members m where m.institution_id = p_institution and m.status = 'active') >= 2
    else false end
$$;

-- Every item that applies to the institution (an item tied to a module that is off is left out) with its status:
-- done (rule or marked), open, later (its feature arrives later). Progress counts available, non-optional items.
create or replace function app.checklist_state(p_institution uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  with items as (
    select i.*, c.status as marked, c.note, c.completed_at, c.completed_by,
           case when not i.available then 'later'
                when i.rule <> 'manual' and app.checklist_rule_done(p_institution, i.rule) then 'done'
                when c.status = 'done' then 'done'
                else 'open' end as state
      from public.setup_checklist_items i
      left join public.institution_checklist c on c.institution_id = p_institution and c.item_key = i.key
     where i.module is null or app.module_enabled(p_institution, i.module))
  select jsonb_build_object(
    'done', (select count(*) from items where state = 'done' and not optional),
    'total', (select count(*) from items where available and not optional),
    'percent', (select case when count(*) filter (where available and not optional) = 0 then 100
                            else round(100.0 * count(*) filter (where state = 'done' and not optional)
                                       / count(*) filter (where available and not optional)) end from items),
    'items', coalesce((select jsonb_agg(jsonb_build_object('key', key, 'owner', owner, 'chapter', chapter, 'state', state, 'auto', rule <> 'manual',
                         'available_from', available_from, 'optional', optional, 'video_url', video_url, 'note', note,
                         'completed_at', completed_at,
                         'completed_by', (select u.email from auth.users u where u.id = completed_by)) order by sort) from items), '[]'::jsonb))
$$;

-- Who in the institution sees the checklist: anyone holding a settings permission (Ch 6.5).
create or replace function app.has_settings_access() returns boolean
language plpgsql stable set search_path = '' as $$
begin
  return exists (select 1 from public.permissions p where p.kind = 'institution' and p.key like 'settings.%' and p.retired_at is null and app.can(p.key));
end $$;

create or replace function public.checklist_get() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_institution uuid := app.require_active_session();
begin
  if not app.has_settings_access() then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  return app.checklist_state(v_institution);
end $$;

-- Marks an item done (or open again) by hand: only items without a rule, available now, that the institution does.
create or replace function app.checklist_mark(p_institution uuid, p_item text, p_done boolean, p_note text, p_platform boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_item public.setup_checklist_items;
begin
  select * into v_item from public.setup_checklist_items where key = p_item;
  if not found then
    raise exception 'record_unknown' using errcode = 'P0404', detail = p_item;
  end if;
  if v_item.rule <> 'manual' or not v_item.available
     or (v_item.owner = 'master_admin' and not p_platform) or (v_item.owner = 'super_admin' and p_platform) then
    raise exception 'checklist_item_locked' using errcode = 'P0409', detail = p_item;
  end if;
  insert into public.institution_checklist as c (institution_id, item_key, status, note, completed_at, completed_by)
  values (p_institution, p_item, case when p_done then 'done' else 'open' end, nullif(btrim(coalesce(p_note, '')), ''),
          case when p_done then now() end, case when p_done then auth.uid() end)
  on conflict (institution_id, item_key) do update
    set status = excluded.status, note = coalesce(excluded.note, c.note), completed_at = excluded.completed_at, completed_by = excluded.completed_by;
  perform app.audit(p_institution, case when p_done then 'checklist.done' else 'checklist.reopened' end, 'checklist_item', p_item, null,
                    jsonb_build_object('note', p_note), null);
  return app.checklist_state(p_institution);
end $$;

create or replace function public.checklist_mark(p_item text, p_done boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.require_active_session();
begin
  if not app.has_settings_access() then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  return app.checklist_mark(v_institution, p_item, p_done, p_note, false);
end $$;

-- The same checklist for the panel (Overview tab) and marking the platform's own items (e.g. SMS / email set up).
create or replace function public.platform_checklist(p_institution uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not app.is_platform('platform.view') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  return app.checklist_state(p_institution);
end $$;

create or replace function public.platform_checklist_mark(p_institution uuid, p_item text, p_done boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not app.is_platform('platform.institutions') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  perform app.platform_audit(case when p_done then 'checklist.done' else 'checklist.reopened' end, p_institution, 'checklist_item', p_item,
                             null, jsonb_build_object('note', p_note), null);
  return app.checklist_mark(p_institution, p_item, p_done, p_note, true);
end $$;

-- The institutions list gains "what is left" (Ch 5.3).
create or replace function public.platform_institutions_list() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not app.is_platform('platform.view') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  return coalesce((select jsonb_agg(x.row order by cardinality(x.problems) = 0, x.row ->> 'name') from (
    select app.institution_problems(i.id) as problems,
           jsonb_build_object('id', i.id, 'name', i.name, 'slug', i.slug, 'status', i.status, 'industry', i.industry,
             'plan', (select jsonb_build_object('key', p.key, 'name', p.name, 'expires_at', ip.expires_at)
                        from public.institution_plan ip join public.plans p on p.key = ip.plan_key and p.version = ip.plan_version where ip.institution_id = i.id),
             'users', app.usage_of(i.id, 'users'),
             'last_login', (select max(u.last_sign_in_at) from public.institution_members m join auth.users u on u.id = m.user_id where m.institution_id = i.id),
             'problems', to_jsonb(app.institution_problems(i.id)),
             'setup', (select jsonb_build_object('done', s -> 'done', 'total', s -> 'total', 'percent', s -> 'percent')
                         from (select app.checklist_state(i.id) as s) cs),
             'profiles', coalesce((select jsonb_agg(jsonb_build_object('key', ip.profile_key, 'version', ip.profile_version,
                            'name', t.payload -> 'name') order by ip.position)
                          from public.institution_profiles ip join public.type_profiles t on t.key = ip.profile_key and t.version = ip.profile_version
                         where ip.institution_id = i.id), '[]'::jsonb)) as row
      from public.institutions i) x), '[]'::jsonb);
end $$;

-- Trial ending with setup incomplete (Proposed, 0B.10-T8): one alert per institution per trial to every active Support
-- and Master Admin user. Daily job.
create or replace function app.checklist_trial_alerts() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  r       record;
  v_count integer := 0;
  v_state jsonb;
begin
  for r in select i.id, i.name, ip.expires_at from public.institutions i join public.institution_plan ip on ip.institution_id = i.id
            where i.status = 'trial' and ip.expires_at between now()
                  and now() + make_interval(days => (app.product_setting('setup_alert_days_before_trial_end'))::integer) loop
    v_state := app.checklist_state(r.id);
    continue when (v_state ->> 'percent')::numeric >= 100;
    continue when exists (select 1 from public.platform_alerts a where a.kind = 'setup_incomplete' and a.payload ->> 'institution_id' = r.id::text
                            and a.created_at > now() - interval '30 days');
    insert into public.platform_alerts (recipient_user_id, kind, payload)
    select pm.user_id, 'setup_incomplete', jsonb_build_object('institution_id', r.id, 'name', r.name, 'done', v_state -> 'done',
             'total', v_state -> 'total', 'expires_at', r.expires_at)
      from public.platform_members pm where pm.status = 'active' and pm.platform_role in ('support', 'master_admin');
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;
select cron.schedule('setup-checklist-trial-alerts', '17 4 * * *', 'select app.checklist_trial_alerts()');

-- ---------------------------------------------------------------------------------------------------------------------
-- 4. Branding RPCs (settings.branding). Colour and logo use the settings; name and short name live on institutions.
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function public.branding_get() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_institution uuid := app.require_active_session();
begin
  return (select jsonb_build_object('name', i.name, 'short_name', i.short_name,
            'brand_color', app.setting_value(v_institution, 'brand_color'), 'logo_path', app.setting_value(v_institution, 'brand_logo_path'),
            'can_edit', app.can('settings.branding'))
            from public.institutions i where i.id = v_institution);
end $$;

create or replace function public.branding_set(p_name text, p_short_name text, p_logo_path text default null, p_clear_logo boolean default false)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.require_active_session();
  v_before      jsonb;
  v_name        text := btrim(coalesce(p_name, ''));
  v_short       text := nullif(btrim(coalesce(p_short_name, '')), '');
begin
  if not app.can('settings.branding') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  if length(v_name) not between 2 and 200 or (v_short is not null and length(v_short) > 40) then
    raise exception 'branding_invalid' using errcode = 'P0422', detail = 'name';
  end if;
  -- The logo must be a file already in this institution's own folder.
  if p_logo_path is not null and (app.storage_path_institution(p_logo_path) is distinct from v_institution
      or not exists (select 1 from storage.objects o where o.bucket_id = 'institution-files' and o.name = p_logo_path)) then
    raise exception 'branding_invalid' using errcode = 'P0422', detail = 'logo';
  end if;
  if (select status from public.institutions where id = v_institution) in ('read_only', 'closed', 'suspended') and not app.is_platform_staff() then
    raise exception 'institution_read_only' using errcode = 'P0423';
  end if;
  select jsonb_build_object('name', name, 'short_name', short_name) into v_before from public.institutions where id = v_institution;
  update public.institutions set name = v_name, short_name = v_short where id = v_institution;
  if p_logo_path is not null then
    perform public.setting_set('brand_logo_path', to_jsonb(p_logo_path));
  elsif p_clear_logo then
    perform public.setting_set('brand_logo_path', 'null'::jsonb);
  end if;
  perform app.audit(v_institution, 'branding.changed', 'institution', v_institution::text, v_before,
                    jsonb_build_object('name', v_name, 'short_name', v_short, 'logo_path', p_logo_path, 'logo_cleared', p_clear_logo), null);
  perform app.bump_settings_version(v_institution);
  return public.branding_get();
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 5. Copy setup from another institution (platform staff; configuration only, never records). Areas are data so later
--    milestones add theirs (SMS / email set-up in 0B.15, offerings in Block 2).
-- ---------------------------------------------------------------------------------------------------------------------
create table public.copy_areas (
  area        text primary key,
  table_name  text not null,                -- the configuration table copied
  match_cols  text[] not null,              -- a row already in the target with the same values is kept, not copied
  filter_sql  text not null default 'true', -- which source rows are configuration (never records)
  added_in    text not null,
  sort        integer not null
);
alter table public.copy_areas enable row level security;
revoke all on public.copy_areas from anon, authenticated;
create policy copy_areas_none on public.copy_areas for select to authenticated using (false);
insert into public.copy_areas (area, table_name, match_cols, filter_sql, added_in, sort) values
  ('labels', 'public.institution_labels', '{key}', 'not s.locked_by_platform', '0B.10', 10),
  ('settings', 'public.app_settings', '{key}',
   'exists (select 1 from public.setting_definitions d where d.key = s.key and d.scope = ''institution'' and d.stored_in = ''app_settings''
      and d.area not in (''settings.branding'', ''settings.security''))', '0B.10', 20),
  ('custom_fields', 'public.custom_field_definitions', '{entity,key}', 's.status = ''active''', '0B.10', 30);

-- Preview (p_confirm false) or copy: per area the rows that would be added and those kept because the target has its own.
create or replace function public.platform_copy_setup(p_target uuid, p_source uuid, p_areas text[], p_confirm boolean default false)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  a        public.copy_areas;
  v_match  text;
  v_add    integer;
  v_keep   integer;
  v_out    jsonb := '[]'::jsonb;
begin
  if not app.is_platform('platform.institutions') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  if p_target = p_source or not exists (select 1 from public.institutions where id = p_target and status not in ('closed', 'suspended'))
     or not exists (select 1 from public.institutions where id = p_source) then
    raise exception 'copy_source_invalid' using errcode = 'P0422';
  end if;
  if exists (select 1 from unnest(p_areas) x where not exists (select 1 from public.copy_areas c where c.area = x)) then
    raise exception 'copy_source_invalid' using errcode = 'P0422', detail = 'area';
  end if;
  for a in select * from public.copy_areas where area = any (p_areas) order by sort loop
    v_match := (select string_agg(format('t.%1$I = s.%1$I', c), ' and ') from unnest(a.match_cols) c);
    execute format('select count(*) filter (where not exists (select 1 from %1$s t where t.institution_id = $2 and %2$s)),
                           count(*) filter (where exists (select 1 from %1$s t where t.institution_id = $2 and %2$s))
                      from %1$s s where s.institution_id = $1 and (%3$s)', a.table_name, v_match, a.filter_sql)
      into v_add, v_keep using p_source, p_target;
    if p_confirm and v_add > 0 then
      -- Each row is copied with the target's institution (a new id where the table has one); the source keeps its own.
      execute format('insert into %1$s select (jsonb_populate_record(null::%1$s, to_jsonb(s) || jsonb_build_object(''institution_id'', $2)
                        || case when to_jsonb(s) ? ''id'' then jsonb_build_object(''id'', gen_random_uuid()) else ''{}''::jsonb end
                        || case when to_jsonb(s) ? ''updated_by'' then jsonb_build_object(''updated_by'', auth.uid()) else ''{}''::jsonb end
                        || case when to_jsonb(s) ? ''created_by'' then jsonb_build_object(''created_by'', auth.uid()) else ''{}''::jsonb end)).*
                        from %1$s s where s.institution_id = $1 and (%3$s)
                         and not exists (select 1 from %1$s t where t.institution_id = $2 and %2$s)', a.table_name, v_match, a.filter_sql)
        using p_source, p_target;
    end if;
    v_out := v_out || jsonb_build_array(jsonb_build_object('area', a.area, 'add', v_add, 'keep', v_keep));
  end loop;
  if p_confirm then
    perform app.bump_settings_version(p_target);
    perform app.platform_audit('setup.copied', p_target, 'institution', p_target::text, null,
                               jsonb_build_object('source', p_source, 'areas', v_out), null);
    perform app.audit(p_target, 'setup.copied', 'institution', p_target::text, null, jsonb_build_object('areas', v_out), null);
  end if;
  return jsonb_build_object('applied', p_confirm, 'areas', v_out);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 6. Grants and registry
-- ---------------------------------------------------------------------------------------------------------------------
revoke all on function app.checklist_rule_done(uuid, text), app.checklist_state(uuid), app.checklist_mark(uuid, text, boolean, text, boolean),
  app.checklist_trial_alerts() from public, anon, authenticated;
grant execute on function app.has_settings_access() to authenticated;
revoke all on function public.checklist_get(), public.checklist_mark(text, boolean, text), public.platform_checklist(uuid),
  public.platform_checklist_mark(uuid, text, boolean, text), public.branding_get(), public.branding_set(text, text, text, boolean),
  public.platform_copy_setup(uuid, uuid, text[], boolean) from public, anon;
grant execute on function public.checklist_get(), public.checklist_mark(text, boolean, text), public.platform_checklist(uuid),
  public.platform_checklist_mark(uuid, text, boolean, text), public.branding_get(), public.branding_set(text, text, text, boolean),
  public.platform_copy_setup(uuid, uuid, text[], boolean) to authenticated;

insert into app.definer_registry (function_name, reason, added_in, reviewer, tenant_check)
select f, r, '0B.10', 'architecture review 0B.10', t from (values
  ('app.checklist_rule_done', 'Is a checklist rule met for one institution (branding set, a branch, two people); called by checklist_state only.', 'service_role_only'),
  ('app.checklist_state', 'The checklist of one institution; called by the checked RPCs and the trial-alert job only.', 'service_role_only'),
  ('app.checklist_mark', 'Marks a manual item of one institution; called by the checked RPCs only.', 'service_role_only'),
  ('app.checklist_trial_alerts', 'Daily job: alerts platform staff about trials ending with setup incomplete.', 'service_role_only'),
  ('public.checklist_get', 'The active institution''s checklist for anyone with a settings permission.', 'filters_active_institution'),
  ('public.checklist_mark', 'Marks a manual checklist item of the active institution; settings permission holders.', 'filters_active_institution'),
  ('public.platform_checklist', 'One institution''s checklist for the panel; platform.view + aal2.', 'not_tenant_data'),
  ('public.platform_checklist_mark', 'Marks a platform checklist item of one institution; platform.institutions + aal2; audited.', 'not_tenant_data'),
  ('public.platform_institutions_list', 'Institutions with status, plan, usage, problems and setup progress for the panel; platform.view + aal2.', 'not_tenant_data'),
  ('public.branding_get', 'Name, short name, colour and logo path of the active institution.', 'filters_active_institution'),
  ('public.branding_set', 'Changes the active institution''s name, short name and logo; settings.branding; audited.', 'filters_active_institution'),
  ('public.platform_copy_setup', 'Copies configuration areas from one institution to another; platform.institutions + aal2; audited.', 'not_tenant_data')
) as v (f, r, t)
on conflict (function_name) do update set reason = excluded.reason, added_in = excluded.added_in, tenant_check = excluded.tenant_check;
