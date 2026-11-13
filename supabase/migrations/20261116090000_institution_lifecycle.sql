-- 0B.07 Institution lifecycle, list and approval (Ch 5.4, 5.15, 5.17 rows 5 / 10; Ch 6.4, 6.7, 6.9 rows 1 / 2 / 8; Ch 4.11; D25).
--   pending → trial (approval) → active ⇄ read_only; any → suspended; any → closed (after a full export; purged after
--   the notice period). Enforced on the server:
--   * read_only / closed: a guard trigger on every tenant table refuses writes made by people (export, OTP and urgent
--     messages are exempt tables); data is never deleted for non-payment;
--   * suspended / closed: signing in to that institution is refused (other memberships of the same person work, D25).
-- See docs/dev/LIFECYCLE.md.

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Institution fields and status history (institution_code is the official code a board gives, e.g. the "College
--    Code"; the shown name comes from the labels)
-- ---------------------------------------------------------------------------------------------------------------------
alter table public.institutions
  add column institution_code  text check (institution_code is null or institution_code ~ '^[0-9A-Za-z-]{2,20}$'),
  add column eiin          text check (eiin is null or eiin ~ '^[0-9]{4,10}$'),
  add column address       text check (address is null or length(address) <= 300),
  add column contact_phone text check (app.is_ascii_phone(contact_phone)),
  add column created_by    uuid references auth.users (id) on delete set null,
  add column approved_at   timestamptz,
  add column approved_by   uuid references auth.users (id) on delete set null,
  add column closed_at     timestamptz,
  add column purge_after   timestamptz;
create index institutions_eiin_idx on public.institutions (eiin) where eiin is not null;
create index institutions_institution_code_idx on public.institutions (institution_code) where institution_code is not null;
create index institutions_purge_idx on public.institutions (purge_after) where status = 'closed';

create table public.institution_status_history (
  institution_id uuid not null references public.institutions (id) on delete cascade,
  id             uuid not null default gen_random_uuid(),
  from_status    text,
  to_status      text not null,
  reason         text check (length(reason) <= 500),
  at             timestamptz not null default now(),
  by_user        uuid references auth.users (id) on delete set null,
  primary key (institution_id, id)
);
alter table public.institution_status_history enable row level security;
revoke all on public.institution_status_history from anon, authenticated;
grant select on public.institution_status_history to authenticated;
create policy institution_status_history_read_own on public.institution_status_history for select to authenticated
  using (institution_id = (select app.auth_institution_id()) and (select app.can('audit.view')));

-- Full exports (0B.07-T7): every row of the institution's tables plus a files manifest, kept for download.
create table public.institution_exports (
  institution_id uuid not null references public.institutions (id) on delete cascade,
  id             uuid not null default gen_random_uuid(),
  kind           text not null default 'full' check (kind = 'full'),
  content        jsonb not null,
  table_counts   jsonb not null,
  size_bytes     bigint not null,
  created_at     timestamptz not null default now(),
  requested_by   uuid references auth.users (id) on delete set null,
  primary key (institution_id, id)
);
alter table public.institution_exports enable row level security;
revoke all on public.institution_exports from anon, authenticated;
create policy institution_exports_none on public.institution_exports for select to authenticated using (false);

-- Product settings (Proposed placeholders; the owner confirms them): notice before purge, trials per person.
insert into public.setting_definitions (key, scope, schema, default_value, area, description, label_key, owner_module, owner_milestone, stored_in) values
  ('purge_notice_days', 'product', '{"type":"integer","minimum":30,"maximum":3650}', '90', 'platform.product_settings',
   'Days between closing an institution and deleting its data (Ch 5.15). Proposed: 90.', 'settings:keys.purge_notice_days', 'platform', '0B.07', 'product_settings'),
  ('trial_limit_per_person', 'product', '{"type":"integer","minimum":1,"maximum":20}', '2', 'platform.product_settings',
   'Trial institutions one person or phone may open before the approval queue flags it (Ch 6.9 row 8). Proposed: 2.',
   'settings:keys.trial_limit_per_person', 'platform', '0B.07', 'product_settings')
on conflict (key) do nothing;

insert into public.event_definitions (event_key, version, entity_type, payload_schema, description) values
  ('institution.status_changed', 1, 'institution',
   '{"type":"object","required":["from","to"],"properties":{"from":{"type":["string","null"]},"to":{"type":"string"},"reason":{"type":["string","null"]}}}',
   'An institution moved to another lifecycle status (0B.07).'),
  ('institution.closed', 1, 'institution',
   '{"type":"object","required":["purge_after"],"properties":{"purge_after":{"type":"string"}}}',
   'An institution was closed; the integration hub revokes its connections, keys, webhooks and secrets (0B.11).')
on conflict do nothing;

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. Valid transitions (0B.07-T1)
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function app.status_transition_ok(p_from text, p_to text) returns boolean
language sql immutable set search_path = '' as $$
  select (p_from, p_to) in (
    ('pending', 'trial'), ('pending', 'active'), ('pending', 'suspended'), ('pending', 'closed'),
    ('trial', 'active'), ('trial', 'read_only'), ('trial', 'suspended'), ('trial', 'closed'),
    ('active', 'read_only'), ('active', 'suspended'), ('active', 'closed'),
    ('read_only', 'active'), ('read_only', 'trial'), ('read_only', 'suspended'), ('read_only', 'closed'),
    ('suspended', 'active'), ('suspended', 'trial'), ('suspended', 'read_only'), ('suspended', 'closed'))
$$;

-- An active platform user with the second step (platform staff act on any institution in any status).
create or replace function app.is_platform_staff() returns boolean
language plpgsql stable security definer set search_path = '' as $$
begin
  return app.session_aal() = 'aal2' and exists (select 1 from public.platform_members pm where pm.user_id = auth.uid() and pm.status = 'active');
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. Read-only guard on every tenant table (0B.07-T2)
-- ---------------------------------------------------------------------------------------------------------------------
-- Tables a read-only institution may still write: exports, logs and bookkeeping caused by allowed actions; the OTP /
-- urgent-message tables join this list in their milestones (with a reason).
create table app.status_guard_exempt (
  table_name text primary key,
  reason     text not null check (length(reason) > 10)
);
insert into app.status_guard_exempt values
  ('public.institution_exports', 'A full export must work in every status (Ch 9.9 row 6, before close).'),
  ('public.audit_log', 'Allowed actions (exports, sign-in) still write their audit rows.'),
  ('public.domain_events', 'Events of allowed actions and of platform changes.'),
  ('public.usage_counters', 'Counters kept by triggers of allowed changes and the nightly recount.'),
  ('public.request_keys', 'Idempotency bookkeeping of allowed calls.'),
  ('public.access_rebuild_queue', 'Access rebuilds triggered by platform changes.'),
  ('public.user_access', 'Access rebuilds triggered by platform changes.'),
  ('public.institution_settings_state', 'Settings version bumps after platform changes.'),
  ('public.institution_status_history', 'Written by the platform when the status changes.');

create or replace function app.status_guard() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid;
  v_status      text;
begin
  if auth.uid() is null or app.is_platform_staff() then
    return case tg_op when 'DELETE' then old else new end;
  end if;
  v_institution := case tg_op when 'DELETE' then old.institution_id else new.institution_id end;
  select status into v_status from public.institutions where id = v_institution;
  if v_status in ('read_only', 'closed') then
    raise exception 'institution_read_only' using errcode = 'P0423', detail = v_status;
  elsif v_status = 'suspended' then
    raise exception 'institution_suspended' using errcode = 'P0423';
  end if;
  return case tg_op when 'DELETE' then old else new end;
end $$;

-- Attaches the guard to a tenant table (later migrations call this for every new tenant table; lint rule status_guard).
create or replace function app.attach_status_guard(p_table regclass) returns void
language plpgsql set search_path = '' as $$
begin
  execute format('drop trigger if exists zz_status_guard on %s', p_table);
  execute format('create trigger zz_status_guard before insert or update or delete on %s for each row execute function app.status_guard()', p_table);
end $$;

select app.attach_status_guard((n.nspname || '.' || c.relname)::regclass)
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where c.relkind = 'r' and (n.nspname = 'public' or n.nspname like 'ext\_%')
   and exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attname = 'institution_id' and not a.attisdropped)
   and c.relname <> 'institutions'
   and (n.nspname || '.' || c.relname) not in (select table_name from app.status_guard_exempt);

-- ---------------------------------------------------------------------------------------------------------------------
-- 4. Suspended / closed: no sign-in to that institution (0B.07-T3, D25)
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function public.custom_access_token_hook(event jsonb) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_user        uuid := (event ->> 'user_id')::uuid;
  v_claims      jsonb := coalesce(event -> 'claims', '{}'::jsonb);
  v_profile     public.profiles;
  v_institution uuid;
  v_version     integer;
  v_active_cnt  integer;
begin
  select * into v_profile from public.profiles where user_id = v_user;

  -- 1. The last selection, if that membership is still active and the institution is open.
  if v_profile.last_active_institution_id is not null then
    select m.institution_id, m.access_version into v_institution, v_version
    from public.institution_members m join public.institutions i on i.id = m.institution_id
    where m.user_id = v_user and m.institution_id = v_profile.last_active_institution_id and m.status = 'active'
      and i.status not in ('suspended', 'closed');
  end if;

  -- 2. Otherwise the only active membership of an open institution, if exactly one.
  if v_institution is null then
    select count(*) into v_active_cnt from public.institution_members m join public.institutions i on i.id = m.institution_id
     where m.user_id = v_user and m.status = 'active' and i.status not in ('suspended', 'closed');
    if v_active_cnt = 1 then
      select m.institution_id, m.access_version into v_institution, v_version
      from public.institution_members m join public.institutions i on i.id = m.institution_id
      where m.user_id = v_user and m.status = 'active' and i.status not in ('suspended', 'closed');
    end if;
  end if;

  -- 3. Several and none chosen (or none at all): no active institution; the app shows the chooser (1.19).
  v_claims := v_claims
    || jsonb_build_object('user_kind', coalesce(v_profile.user_kind, 'staff'))
    || jsonb_build_object('active_institution_id', v_institution)
    || jsonb_build_object('access_version', v_version);

  return jsonb_set(event, '{claims}', v_claims);
end $$;

-- The auth service runs the hook: it now also reads each institution's status.
grant select on public.institutions to supabase_auth_admin;
create policy institutions_auth_hook_read on public.institutions as permissive
  for select to supabase_auth_admin using (true);

create or replace function app.require_active_session() returns uuid
language plpgsql stable set search_path = '' as $$
declare
  v_institution uuid := app.claim_institution_id();
  v_member      public.institution_members;
  v_status      text;
begin
  if auth.uid() is null then
    raise exception 'not_signed_in' using errcode = 'P0401', hint = 'Sign in first.';
  end if;
  if v_institution is null then
    raise exception 'no_active_institution' using errcode = 'P0402', hint = 'Choose an institution.';
  end if;
  select * into v_member from public.institution_members
   where institution_id = v_institution and user_id = auth.uid();
  if not found or v_member.status <> 'active' then
    raise exception 'membership_not_active' using errcode = 'P0403', hint = 'Your access to this institution has ended.';
  end if;
  if v_member.access_version is distinct from app.claim_access_version() then
    raise exception 'session_refresh_required' using errcode = 'P0409', hint = 'Refresh the session and retry.';
  end if;
  select status into v_status from public.institutions where id = v_institution;
  if v_status = 'suspended' then
    raise exception 'institution_suspended' using errcode = 'P0403', hint = 'This institution is suspended. Contact the platform.';
  elsif v_status = 'closed' then
    raise exception 'institution_closed' using errcode = 'P0403', hint = 'This institution is closed.';
  end if;
  return v_institution;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 5. Duplicates and trial abuse (0B.07-T5, T6; Proposed)
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function app.name_key(p_name text) returns text
language sql immutable set search_path = '' as $$
  select regexp_replace(lower(coalesce(p_name, '')), '[^a-z0-9ঀ-৿]+', '', 'g')
$$;

-- Other institutions that look like this one: the same EIIN / College Code (strong), or the same name together with
-- the same phone or address (weak, for institutions without codes).
create or replace function app.institution_duplicates(p_institution uuid) returns jsonb
language sql stable set search_path = '' as $$
  with me as (select * from public.institutions where id = p_institution)
  select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'name', o.name, 'slug', o.slug, 'status', o.status,
           'match', case when o.eiin = me.eiin then 'eiin' when o.institution_code = me.institution_code then 'institution_code'
                         when o.contact_phone = me.contact_phone then 'name_phone' else 'name_address' end) order by o.name), '[]'::jsonb)
    from public.institutions o, me
   where o.id <> me.id
     and ((me.eiin is not null and o.eiin = me.eiin) or (me.institution_code is not null and o.institution_code = me.institution_code)
          or (app.name_key(o.name) = app.name_key(me.name) and app.name_key(me.name) <> ''
              and ((me.contact_phone is not null and o.contact_phone = me.contact_phone)
                   or (me.address is not null and app.name_key(o.address) = app.name_key(me.address)))))
$$;

create or replace function app.trial_abuse(p_institution uuid) returns jsonb
language sql stable set search_path = '' as $$
  with me as (select * from public.institutions where id = p_institution)
  select jsonb_build_object(
    'by_person', (select count(*) from public.institutions o, me where me.created_by is not null and o.created_by = me.created_by
                    and o.status in ('pending', 'trial')),
    'by_phone', (select count(*) from public.institutions o, me where me.contact_phone is not null and o.contact_phone = me.contact_phone
                    and o.status in ('pending', 'trial')),
    'limit', (app.product_setting('trial_limit_per_person'))::integer,
    'flagged', greatest(
      (select count(*) from public.institutions o, me where me.created_by is not null and o.created_by = me.created_by and o.status in ('pending', 'trial')),
      (select count(*) from public.institutions o, me where me.contact_phone is not null and o.contact_phone = me.contact_phone and o.status in ('pending', 'trial')))
      > (app.product_setting('trial_limit_per_person'))::integer)
$$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 6. Status changes (platform only, audited, history, event; 0B.07-T1, T4, T8)
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function public.platform_institution_set_status(p_institution uuid, p_status text, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_from  text;
  v_plan  public.plans;
  v_purge timestamptz;
begin
  if not (case p_status when 'closed' then app.is_platform('platform.institutions_close') else app.is_platform('platform.institutions') end) then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  select status into v_from from public.institutions where id = p_institution for update;
  if not found then
    raise exception 'record_unknown' using errcode = 'P0404', detail = p_institution::text;
  end if;
  if not app.status_transition_ok(v_from, p_status) then
    raise exception 'status_transition_invalid' using errcode = 'P0409', detail = format('%s → %s', v_from, p_status);
  end if;
  if p_status in ('suspended', 'read_only', 'closed') and nullif(btrim(coalesce(p_reason, '')), '') is null then
    raise exception 'reason_required' using errcode = 'P0422';
  end if;
  -- Closing needs a full export made in the last 7 days (0B.07-T8).
  if p_status = 'closed' and not exists (select 1 from public.institution_exports e where e.institution_id = p_institution
                                             and e.created_at > now() - interval '7 days') then
    raise exception 'export_required' using errcode = 'P0409', detail = 'make a full export first';
  end if;
  if p_status = 'closed' then
    v_purge := now() + make_interval(days => (app.product_setting('purge_notice_days'))::integer);
  end if;
  update public.institutions
     set status = p_status,
         approved_at = case when v_from = 'pending' and p_status in ('trial', 'active') then now() else approved_at end,
         approved_by = case when v_from = 'pending' and p_status in ('trial', 'active') then auth.uid() else approved_by end,
         closed_at = case when p_status = 'closed' then now() end,
         purge_after = v_purge
   where id = p_institution;
  -- Approval starts the trial now (the trial days run from approval, not from sign-up).
  if v_from = 'pending' and p_status = 'trial' then
    select p.* into v_plan from public.institution_plan ip join public.plans p on p.key = ip.plan_key and p.version = ip.plan_version
     where ip.institution_id = p_institution;
    if v_plan.trial_days is not null then
      update public.institution_plan set expires_at = now() + make_interval(days => v_plan.trial_days), started_at = now()
       where institution_id = p_institution;
    end if;
  end if;
  insert into public.institution_status_history (institution_id, from_status, to_status, reason, by_user)
  values (p_institution, v_from, p_status, nullif(btrim(coalesce(p_reason, '')), ''), auth.uid());
  perform app.platform_audit('institution.status_changed', p_institution, 'institution', p_institution::text,
                             jsonb_build_object('status', v_from), jsonb_build_object('status', p_status, 'purge_after', v_purge), p_reason);
  perform app.audit(p_institution, 'institution.status_changed', 'institution', p_institution::text,
                    jsonb_build_object('status', v_from), jsonb_build_object('status', p_status), p_reason);
  perform app.emit_event(p_institution, 'institution.status_changed', 1, 'institution', p_institution::text,
                         jsonb_build_object('from', v_from, 'to', p_status, 'reason', p_reason), null, null);
  if p_status = 'closed' then
    perform app.emit_event(p_institution, 'institution.closed', 1, 'institution', p_institution::text,
                           jsonb_build_object('purge_after', v_purge), null, null);
  end if;
  perform app.bump_settings_version(p_institution);
  return jsonb_build_object('status', p_status, 'purge_after', v_purge);
end $$;

-- Purge after the notice period (0B.07-T8): deletes the closed institution and, by cascade, everything it owns.
-- Nothing of any other institution is touched; the platform audit keeps a record.
create or replace function app.institution_purge_due() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  r record;
  v_count integer := 0;
begin
  for r in select id, name from public.institutions where status = 'closed' and purge_after < now() loop
    perform app.platform_audit('institution.purged', r.id, 'institution', r.id::text, jsonb_build_object('name', r.name), null, 'notice period over');
    delete from public.institutions where id = r.id;
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;
select cron.schedule('institution-purge', '53 2 * * *', 'select app.institution_purge_due()');

-- ---------------------------------------------------------------------------------------------------------------------
-- 7. Full export (0B.07-T7): every tenant table's rows of the institution, the members' names and a files manifest
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function app.institution_export_build(p_institution uuid) returns jsonb
language plpgsql security definer set search_path = '' set jit = off as $$
-- heavy
declare
  r       record;
  v_rows  jsonb;
  v_data  jsonb := '{}';
  v_count jsonb := '{}';
begin
  for r in select n.nspname as s, c.relname as t
             from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where c.relkind = 'r' and (n.nspname = 'public' or n.nspname like 'ext\_%')
              and exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attname = 'institution_id' and not a.attisdropped)
              and c.relname not in ('institution_exports', 'request_keys')
            order by 1, 2 loop
    execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]''::jsonb) from %I.%I x where x.institution_id = $1', r.s, r.t)
      into v_rows using p_institution;
    v_data := v_data || jsonb_build_object(r.s || '.' || r.t, v_rows);
    v_count := v_count || jsonb_build_object(r.s || '.' || r.t, jsonb_array_length(v_rows));
  end loop;
  return jsonb_build_object(
    'format', 'leadora-institution-export', 'version', 1, 'made_at', now(),
    'institution', (select to_jsonb(i) from public.institutions i where i.id = p_institution),
    'people', coalesce((select jsonb_agg(jsonb_build_object('user_id', p.user_id, 'name', p.display_name, 'email', p.email))
                          from public.profiles p where p.user_id in (select m.user_id from public.institution_members m where m.institution_id = p_institution)), '[]'::jsonb),
    'files', coalesce((select jsonb_agg(jsonb_build_object('bucket', o.bucket_id, 'path', o.name, 'size', o.metadata ->> 'size'))
                         from storage.objects o where o.name like p_institution::text || '/%'), '[]'::jsonb),
    'tables', v_data,
    'counts', v_count);
end $$;

-- The institution's Super Admin or platform staff with platform.institutions.
create or replace function app.may_export(p_institution uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select app.is_platform('platform.institutions')
      or (p_institution = app.auth_institution_id() and exists (
            select 1 from public.role_assignments ra join public.roles r on r.id = ra.role_id and r.institution_id = ra.institution_id
             where ra.institution_id = p_institution and ra.user_id = auth.uid() and r.is_super_admin))
$$;

create or replace function public.institution_export_create(p_institution uuid default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := coalesce(p_institution, app.auth_institution_id());
  v_content     jsonb;
  v_id          uuid;
begin
  if v_institution is null or not app.may_export(v_institution) then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  v_content := app.institution_export_build(v_institution);
  insert into public.institution_exports (institution_id, content, table_counts, size_bytes, requested_by)
  values (v_institution, v_content, v_content -> 'counts', octet_length(v_content::text), auth.uid())
  returning id into v_id;
  perform app.audit(v_institution, 'institution.exported', 'institution_export', v_id::text, null, v_content -> 'counts');
  if app.is_platform('platform.institutions') then
    perform app.platform_audit('institution.exported', v_institution, 'institution_export', v_id::text, null, null, null);
  end if;
  return jsonb_build_object('id', v_id, 'counts', v_content -> 'counts', 'size_bytes', octet_length(v_content::text));
end $$;

create or replace function public.institution_exports_list(p_institution uuid default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_institution uuid := coalesce(p_institution, app.auth_institution_id());
begin
  if v_institution is null or not app.may_export(v_institution) then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'created_at', e.created_at, 'size_bytes', e.size_bytes,
           'counts', e.table_counts, 'by', (select email from auth.users u where u.id = e.requested_by)) order by e.created_at desc)
    from public.institution_exports e where e.institution_id = v_institution), '[]'::jsonb);
end $$;

create or replace function public.institution_export_get(p_id uuid, p_institution uuid default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_institution uuid := coalesce(p_institution, app.auth_institution_id());
begin
  if v_institution is null or not app.may_export(v_institution) then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  return (select content from public.institution_exports where institution_id = v_institution and id = p_id);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 8. Panel: list (problems first), overview, approval queue (0B.07-T9, T10)
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function app.institution_problems(p_institution uuid) returns text[]
language sql stable set search_path = '' as $$
  select array_remove(array[
    case when i.status = 'pending' then 'waiting_approval' end,
    case when i.status in ('read_only', 'suspended') then i.status end,
    case when ip.expires_at is not null and ip.expires_at < now() + interval '7 days' and i.status in ('trial', 'active') then 'ends_soon' end,
    case when exists (select 1 from public.limit_metrics lm
                       where app.limit_level(app.usage_of(i.id, lm.key), app.limit_of(i.id, lm.key)) in ('full', 'blocked')) then 'limit_reached' end
  ], null)
  from public.institutions i left join public.institution_plan ip on ip.institution_id = i.id
  where i.id = p_institution
$$;

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
             'profiles', coalesce((select jsonb_agg(jsonb_build_object('key', ip.profile_key, 'version', ip.profile_version,
                            'name', t.payload -> 'name') order by ip.position)
                          from public.institution_profiles ip join public.type_profiles t on t.key = ip.profile_key and t.version = ip.profile_version
                         where ip.institution_id = i.id), '[]'::jsonb)) as row
      from public.institutions i) x), '[]'::jsonb);
end $$;

create or replace function public.platform_institution_overview(p_institution uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not app.is_platform('platform.view') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  if not exists (select 1 from public.institutions where id = p_institution) then
    raise exception 'record_unknown' using errcode = 'P0404', detail = p_institution::text;
  end if;
  return jsonb_build_object(
    'institution', (select to_jsonb(i) - 'created_by' - 'approved_by' || jsonb_build_object(
                      'created_by', (select email from auth.users u where u.id = i.created_by),
                      'approved_by', (select email from auth.users u where u.id = i.approved_by)) from public.institutions i where i.id = p_institution),
    'problems', to_jsonb(app.institution_problems(p_institution)),
    'profiles', coalesce((select jsonb_agg(jsonb_build_object('key', ip.profile_key, 'version', ip.profile_version, 'name', t.payload -> 'name') order by ip.position)
                 from public.institution_profiles ip join public.type_profiles t on t.key = ip.profile_key and t.version = ip.profile_version
                where ip.institution_id = p_institution), '[]'::jsonb),
    'usage', (select jsonb_agg(jsonb_build_object('metric', lm.key, 'used', app.usage_of(p_institution, lm.key), 'limit', app.limit_of(p_institution, lm.key))
               order by lm.sort) from public.limit_metrics lm),
    'super_admins', coalesce((select jsonb_agg(distinct u.email) from public.role_assignments ra
                     join public.roles r on r.id = ra.role_id and r.institution_id = ra.institution_id and r.is_super_admin
                     join auth.users u on u.id = ra.user_id where ra.institution_id = p_institution), '[]'::jsonb),
    'last_login', (select max(u.last_sign_in_at) from public.institution_members m join auth.users u on u.id = m.user_id where m.institution_id = p_institution),
    'history', coalesce((select jsonb_agg(jsonb_build_object('from', h.from_status, 'to', h.to_status, 'reason', h.reason, 'at', h.at,
                 'by', (select email from auth.users u where u.id = h.by_user)) order by h.at desc)
                 from public.institution_status_history h where h.institution_id = p_institution), '[]'::jsonb),
    'duplicates', app.institution_duplicates(p_institution),
    'trial', app.trial_abuse(p_institution),
    'exports', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'created_at', e.created_at, 'size_bytes', e.size_bytes) order by e.created_at desc)
                 from public.institution_exports e where e.institution_id = p_institution), '[]'::jsonb),
    'can_close_now', exists (select 1 from public.institution_exports e where e.institution_id = p_institution and e.created_at > now() - interval '7 days'));
end $$;

create or replace function public.platform_approval_queue() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not app.is_platform('platform.view') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'name', i.name, 'slug', i.slug, 'created_at', i.created_at,
           'eiin', i.eiin, 'institution_code', i.institution_code, 'duplicates', app.institution_duplicates(i.id), 'trial', app.trial_abuse(i.id))
           order by i.created_at)
    from public.institutions i where i.status = 'pending'), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 9. The institution's own status (banners: trial days left, read only, waiting for approval)
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function public.institution_status() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_institution uuid := app.auth_institution_id();
begin
  if v_institution is null or not exists (select 1 from public.institution_members m where m.institution_id = v_institution
                                                and m.user_id = auth.uid() and m.status = 'active') then
    return null;
  end if;
  return (select jsonb_build_object('status', i.status, 'expires_at', ip.expires_at,
            'days_left', case when ip.expires_at is not null then greatest(0, ceil(extract(epoch from ip.expires_at - now()) / 86400))::integer end,
            'plan', ip.plan_key)
            from public.institutions i left join public.institution_plan ip on ip.institution_id = i.id where i.id = v_institution);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 10. Grants and registry
-- ---------------------------------------------------------------------------------------------------------------------
revoke all on function app.status_guard(), app.attach_status_guard(regclass), app.institution_purge_due(), app.institution_export_build(uuid)
  from public, anon, authenticated;
grant execute on function app.is_platform_staff(), app.status_transition_ok(text, text), app.may_export(uuid), app.name_key(text),
  app.institution_duplicates(uuid), app.trial_abuse(uuid), app.institution_problems(uuid) to authenticated, service_role;
revoke all on function public.platform_institution_set_status(uuid, text, text), public.institution_export_create(uuid),
  public.institution_exports_list(uuid), public.institution_export_get(uuid, uuid), public.platform_institution_overview(uuid),
  public.platform_approval_queue(), public.institution_status() from public, anon;
grant execute on function public.platform_institution_set_status(uuid, text, text), public.institution_export_create(uuid),
  public.institution_exports_list(uuid), public.institution_export_get(uuid, uuid), public.platform_institution_overview(uuid),
  public.platform_approval_queue(), public.institution_status() to authenticated;

insert into app.definer_registry (function_name, reason, added_in, reviewer, tenant_check)
select f, r, '0B.07', 'architecture review 0B.07', t from (values
  ('app.is_platform_staff', 'Is the caller an active platform user with the second step (own row only).', 'not_tenant_data'),
  ('app.status_guard', 'Trigger: refuses writes by people to a read-only / suspended / closed institution (row''s own institution).', 'service_role_only'),
  ('app.institution_purge_due', 'Nightly job: deletes closed institutions after the notice period; not callable by app roles.', 'service_role_only'),
  ('app.institution_export_build', 'Builds the full export of one institution; called by the checked export RPC only.', 'service_role_only'),
  ('app.may_export', 'Is the caller the institution''s Super Admin or platform staff with platform.institutions.', 'filters_active_institution'),
  ('public.platform_institution_set_status', 'Lifecycle status change; platform.institutions / platform.institutions_close + aal2; audited both sides.', 'not_tenant_data'),
  ('public.institution_export_create', 'Full export of the active institution (Super Admin) or any institution (platform staff); audited.', 'filters_active_institution'),
  ('public.institution_exports_list', 'Exports of the active institution (Super Admin) or any (platform staff).', 'filters_active_institution'),
  ('public.institution_export_get', 'One export''s content for download; same rule as creating it.', 'filters_active_institution'),
  ('public.platform_institutions_list', 'Institutions with status, plan, usage, problems for the panel; needs platform.view + aal2.', 'not_tenant_data'),
  ('public.platform_institution_overview', 'Overview tab of one institution for the panel; needs platform.view + aal2.', 'not_tenant_data'),
  ('public.platform_approval_queue', 'Pending institutions with duplicate and trial flags; needs platform.view + aal2.', 'not_tenant_data'),
  ('public.institution_status', 'Status, plan and trial days of the active institution for its banners.', 'filters_active_institution')
) as v (f, r, t)
on conflict (function_name) do update set reason = excluded.reason, added_in = excluded.added_in, tenant_check = excluded.tenant_check;
