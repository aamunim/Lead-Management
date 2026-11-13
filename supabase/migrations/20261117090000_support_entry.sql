-- 0B.08 Support entry ("Enter institution"; Ch 5.5, 5.3 Audit tab, 5.17 row 3, Ch 11.15).
-- A platform user with platform.support_access (Master Admin, or Support with the personal setup right) enters one
-- institution with a reason and a time limit. The token then carries that institution and the support session id;
-- every check (auth_institution_id, require_active_session, can) honours the session while it is open and not expired.
--   * Read only by default: the lifecycle guard refuses every write. Edit mode is requested with a reason and approved
--     by another Master Admin (Proposed).
--   * Sensitive permissions are never granted to a support session (sensitive data stays masked).
--   * Every start, end, edit request / approval and every write in edit mode is in both audit logs with the session
--     id; the institution's Super Admin sees the support access log.
-- See docs/dev/SUPPORT.md.

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Sessions and audit links
-- ---------------------------------------------------------------------------------------------------------------------
create table public.support_sessions (
  institution_id   uuid not null references public.institutions (id) on delete cascade,
  id               uuid not null default gen_random_uuid(),
  platform_user_id uuid not null references auth.users (id) on delete cascade,
  reason           text not null check (length(btrim(reason)) between 5 and 500),
  mode             text not null default 'read_only' check (mode in ('read_only', 'edit')),
  edit_reason      text check (length(edit_reason) <= 500),
  edit_requested_at timestamptz,
  edit_approved_by uuid references auth.users (id) on delete set null,
  edit_approved_at timestamptz,
  started_at       timestamptz not null default now(),
  expires_at       timestamptz not null,
  ended_at         timestamptz,
  primary key (institution_id, id),
  unique (id),
  check (expires_at > started_at and expires_at <= started_at + interval '4 hours')
);
create index support_sessions_user_idx on public.support_sessions (institution_id, platform_user_id, ended_at);
create index support_sessions_open_idx on public.support_sessions (platform_user_id, expires_at) where ended_at is null;
alter table public.support_sessions enable row level security;
revoke all on public.support_sessions from anon, authenticated;
grant select on public.support_sessions to authenticated, supabase_auth_admin;
-- The platform user reads their own sessions (the token checks); the auth service reads them for the sign-in hook.
create policy support_sessions_read_own on public.support_sessions for select to authenticated
  using (platform_user_id = (select auth.uid()));
create policy support_sessions_auth_hook_read on public.support_sessions for select to supabase_auth_admin using (true);
-- Ending / starting sessions is done by the RPCs below; written by the platform, so no lifecycle guard needed.
insert into app.status_guard_exempt values
  ('public.support_sessions', 'Support sessions are written by the platform RPCs, also for read-only / suspended institutions.'),
  ('public.platform_audit_log', 'Platform audit: written for every platform action and support session, in any institution status.');
drop trigger if exists zz_status_guard on public.platform_audit_log;

alter table public.audit_log add column support_session_id uuid;
alter table public.platform_audit_log add column support_session_id uuid;

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. The session in force for this request (from the token, checked against the table every time)
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function app.claim_support_session_id() returns uuid
language sql stable set search_path = '' as $$
  select nullif(auth.jwt() ->> 'support_session_id', '')::uuid
$$;

-- 'read_only' | 'edit' while the session is open, not expired, belongs to the caller, matches the token's
-- institution and the caller still has the second step; else null.
create or replace function app.support_mode() returns text
language sql stable security definer set search_path = '' as $$
  select s.mode from public.support_sessions s
   where app.claim_support_session_id() is not null
     and s.id = app.claim_support_session_id() and s.platform_user_id = auth.uid()
     and s.institution_id = app.claim_institution_id() and s.ended_at is null and s.expires_at > now()
     and app.session_aal() = 'aal2'
$$;

-- The active institution: a membership as before, or an open support session.
create or replace function app.auth_institution_id() returns uuid
language sql stable set search_path = '' as $$
  select coalesce(
    (select m.institution_id
       from public.institution_members m
      where m.institution_id = app.claim_institution_id()
        and m.user_id = auth.uid()
        and m.status = 'active'
        and m.access_version = app.claim_access_version()),
    (select app.claim_institution_id() where app.claim_support_session_id() is not null and app.support_mode() is not null))
$$;

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
  -- An open support session stands in for the membership (0B.08).
  if app.claim_support_session_id() is not null then
    if app.support_mode() is null then
      raise exception 'support_session_ended' using errcode = 'P0401', hint = 'The support session has ended.';
    end if;
    return v_institution;
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

-- can(): a support session holds every non-sensitive permission of the institution (to see what the people see);
-- sensitive ones never. Writes are still refused by the guard unless the session is in approved edit mode.
create or replace function app.is_platform_admin_for_support() returns boolean
language sql stable set search_path = '' as $$ select app.support_mode() is not null $$;

create or replace function app.can_check(p_action text, p_record jsonb) returns boolean
language plpgsql stable security definer set search_path = '' as $$
-- PL/pgSQL so the plan is cached (a SQL function with a SET clause is planned again on every call; lesson 13).
begin
  if app.claim_support_session_id() is not null then
    return app.support_mode() is not null
       and exists (select 1 from public.permissions p where p.key = p_action and p.kind = 'institution' and not p.sensitive);
  end if;
  return exists (
    select 1 from public.user_access ua
     where ua.institution_id = app.auth_institution_id() and ua.user_id = auth.uid()
       and ua.permission_key in (p_action, '*')
       and (ua.valid_to is null or ua.valid_to > now())
       and (p_record is null or (
             (ua.branch_ids is null or (p_record ->> 'branch_id')::uuid = any (ua.branch_ids)
              or (p_record ->> 'created_by')::uuid = auth.uid())
         and (ua.user_ids is null or (p_record ->> 'owner_id')::uuid = any (ua.user_ids)
              or (p_record ->> 'created_by')::uuid = auth.uid())
         and (ua.offering_ids is null or (p_record ->> 'offering_id')::uuid = any (ua.offering_ids)
              or ((p_record ->> 'offering_id') is null and (p_record ->> 'created_by')::uuid = auth.uid()))))
       -- `*` (Super Admin) never extends to platform permissions
       and (ua.permission_key <> '*' or exists (select 1 from public.permissions p where p.key = p_action and p.kind = 'institution')));
end $$;

-- The lifecycle guard also enforces read-only support sessions; writes in edit mode are logged with the session.
create or replace function app.status_guard() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid;
  v_status      text;
  v_mode        text;
begin
  if auth.uid() is null then
    return case tg_op when 'DELETE' then old else new end;
  end if;
  v_institution := case tg_op when 'DELETE' then old.institution_id else new.institution_id end;
  if app.claim_support_session_id() is not null then
    v_mode := app.support_mode();
    if v_mode is null then
      raise exception 'support_session_ended' using errcode = 'P0401';
    elsif v_mode = 'read_only' or v_institution is distinct from app.claim_institution_id() then
      raise exception 'support_read_only' using errcode = 'P0423';
    end if;
    insert into public.platform_audit_log (actor_user_id, action, institution_id, target_type, target_id, support_session_id)
    values (auth.uid(), 'support.write', v_institution, tg_table_schema || '.' || tg_table_name, lower(tg_op), app.claim_support_session_id());
    return case tg_op when 'DELETE' then old else new end;
  end if;
  if app.is_platform_staff() then
    return case tg_op when 'DELETE' then old else new end;
  end if;
  select status into v_status from public.institutions where id = v_institution;
  if v_status in ('read_only', 'closed') then
    raise exception 'institution_read_only' using errcode = 'P0423', detail = v_status;
  elsif v_status = 'suspended' then
    raise exception 'institution_suspended' using errcode = 'P0423';
  end if;
  return case tg_op when 'DELETE' then old else new end;
end $$;

-- Both audit logs record the support session the action happened in.
create or replace function app.audit(p_institution uuid, p_action text, p_target_type text, p_target_id text,
                                     p_before jsonb, p_after jsonb, p_reason text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  perform app.assert_may_write_for(p_institution);
  perform app.auth_institution_id();
  insert into public.audit_log (institution_id, actor_user_id, action, target_type, target_id, before, after, reason, support_session_id)
  values (p_institution, auth.uid(), p_action, p_target_type, p_target_id, p_before, p_after, p_reason,
          case when app.support_mode() is not null then app.claim_support_session_id() end)
  returning id into v_id;
  return v_id;
end $$;

create or replace function app.platform_audit(p_action text, p_institution uuid, p_target_type text, p_target_id text,
                                              p_before jsonb, p_after jsonb, p_reason text default null) returns void
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.platform_audit_log (actor_user_id, action, institution_id, target_type, target_id, before, after, reason, ip, device,
                                         support_session_id)
  values (auth.uid(), p_action, p_institution, p_target_type, p_target_id, app.redact_secrets(p_before), app.redact_secrets(p_after),
          p_reason, split_part(coalesce(app.request_header('x-forwarded-for'), ''), ',', 1),
          left(app.request_header('user-agent'), 300), app.claim_support_session_id());
end $$;

-- A support session writes the institution's audit rows (support entry is visible to the institution).
create or replace function app.assert_may_write_for(p_institution uuid) returns void
language plpgsql stable set search_path = '' as $$
begin
  if p_institution is null then
    raise exception 'institution_id_required' using errcode = 'P0402';
  end if;
  if auth.uid() is null or app.is_platform_admin() or app.is_platform('platform.billing') or app.is_platform('platform.support_access') then
    return;
  end if;
  if p_institution is distinct from app.auth_institution_id() then
    raise exception 'institution_mismatch' using errcode = 'P0403';
  end if;
end $$;

-- The institution itself (name in the header) is readable during an open support session.
create policy institutions_select_support on public.institutions for select to authenticated
  using (id = (select app.claim_institution_id()) and (select app.support_mode()) is not null);

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. The sign-in hook: an open support session opens its institution
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
  v_support     public.support_sessions;
begin
  select * into v_profile from public.profiles where user_id = v_user;

  -- 0. An open support session (0B.08) wins while it lasts.
  select * into v_support from public.support_sessions s
   where s.platform_user_id = v_user and s.ended_at is null and s.expires_at > now()
   order by s.started_at desc limit 1;
  if found then
    v_claims := v_claims
      || jsonb_build_object('user_kind', coalesce(v_profile.user_kind, 'staff'))
      || jsonb_build_object('active_institution_id', v_support.institution_id)
      || jsonb_build_object('access_version', null)
      || jsonb_build_object('support_session_id', v_support.id);
    return jsonb_set(event, '{claims}', v_claims);
  end if;

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
  v_claims := (v_claims - 'support_session_id')
    || jsonb_build_object('user_kind', coalesce(v_profile.user_kind, 'staff'))
    || jsonb_build_object('active_institution_id', v_institution)
    || jsonb_build_object('access_version', v_version);

  return jsonb_set(event, '{claims}', v_claims);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 4. RPCs: start, end, request and approve edit (platform side); the support log (institution side)
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function public.support_session_start(p_institution uuid, p_reason text, p_minutes integer) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
  v_ends timestamptz;
begin
  if not app.is_platform('platform.support_access') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  if length(btrim(coalesce(p_reason, ''))) < 5 then
    raise exception 'reason_required' using errcode = 'P0422';
  end if;
  if p_minutes is null or p_minutes < 5 or p_minutes > 240 then
    raise exception 'support_minutes_invalid' using errcode = 'P0422', detail = '5 to 240 minutes';
  end if;
  if not exists (select 1 from public.institutions where id = p_institution and status <> 'closed') then
    raise exception 'record_unknown' using errcode = 'P0404', detail = p_institution::text;
  end if;
  -- One open session per person.
  update public.support_sessions set ended_at = now() where platform_user_id = auth.uid() and ended_at is null;
  v_ends := now() + make_interval(mins => p_minutes);
  insert into public.support_sessions (institution_id, platform_user_id, reason, expires_at)
  values (p_institution, auth.uid(), btrim(p_reason), v_ends) returning id into v_id;
  perform app.platform_audit('support.started', p_institution, 'support_session', v_id::text, null,
                             jsonb_build_object('minutes', p_minutes, 'mode', 'read_only'), btrim(p_reason));
  insert into public.audit_log (institution_id, actor_user_id, action, target_type, target_id, after, reason, support_session_id)
  values (p_institution, auth.uid(), 'support.started', 'support_session', v_id::text,
          jsonb_build_object('minutes', p_minutes, 'mode', 'read_only'), btrim(p_reason), v_id);
  return jsonb_build_object('id', v_id, 'expires_at', v_ends, 'mode', 'read_only');
end $$;

create or replace function public.support_session_end() returns void
language plpgsql security definer set search_path = '' as $$
declare
  r public.support_sessions;
begin
  for r in update public.support_sessions set ended_at = now()
            where platform_user_id = auth.uid() and ended_at is null returning * loop
    perform app.platform_audit('support.ended', r.institution_id, 'support_session', r.id::text, null, null, null);
    insert into public.audit_log (institution_id, actor_user_id, action, target_type, target_id, support_session_id)
    values (r.institution_id, auth.uid(), 'support.ended', 'support_session', r.id::text, r.id);
  end loop;
end $$;

-- The current session for the banner (null when none).
create or replace function public.support_session_current() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', s.id, 'institution_id', s.institution_id, 'institution_name', i.name, 'mode', s.mode,
                            'expires_at', s.expires_at, 'edit_requested', s.edit_requested_at is not null and s.mode = 'read_only')
    from public.support_sessions s join public.institutions i on i.id = s.institution_id
   where s.id = app.claim_support_session_id() and s.platform_user_id = auth.uid() and s.ended_at is null and s.expires_at > now()
$$;

create or replace function public.support_edit_request(p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_session public.support_sessions;
begin
  select * into v_session from public.support_sessions
   where id = app.claim_support_session_id() and platform_user_id = auth.uid() and ended_at is null and expires_at > now();
  if not found or not app.is_platform('platform.support_access') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  if length(btrim(coalesce(p_reason, ''))) < 5 then
    raise exception 'reason_required' using errcode = 'P0422';
  end if;
  update public.support_sessions set edit_reason = btrim(p_reason), edit_requested_at = now() where id = v_session.id;
  perform app.platform_audit('support.edit_requested', v_session.institution_id, 'support_session', v_session.id::text, null, null, btrim(p_reason));
  insert into public.audit_log (institution_id, actor_user_id, action, target_type, target_id, reason, support_session_id)
  values (v_session.institution_id, auth.uid(), 'support.edit_requested', 'support_session', v_session.id::text, btrim(p_reason), v_session.id);
end $$;

-- Edit mode needs another Master Admin's approval (Proposed: four eyes).
create or replace function public.support_edit_approve(p_session uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_session public.support_sessions;
begin
  if not app.is_platform_admin() then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  select * into v_session from public.support_sessions where id = p_session and ended_at is null and expires_at > now()
                                                      and edit_requested_at is not null and mode = 'read_only';
  if not found then
    raise exception 'record_unknown' using errcode = 'P0404', detail = p_session::text;
  end if;
  if v_session.platform_user_id = auth.uid() then
    raise exception 'self_approval' using errcode = 'P0409', detail = 'another Master Admin approves';
  end if;
  update public.support_sessions set mode = 'edit', edit_approved_by = auth.uid(), edit_approved_at = now() where id = p_session;
  perform app.platform_audit('support.edit_approved', v_session.institution_id, 'support_session', p_session::text, null, null, v_session.edit_reason);
  insert into public.audit_log (institution_id, actor_user_id, action, target_type, target_id, reason, support_session_id)
  values (v_session.institution_id, auth.uid(), 'support.edit_approved', 'support_session', p_session::text, v_session.edit_reason, p_session);
end $$;

-- Pending edit requests for the panel (Master Admin).
create or replace function public.support_edit_requests() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not app.is_platform_admin() then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'institution', i.name, 'by', u.email, 'reason', s.reason,
           'edit_reason', s.edit_reason, 'requested_at', s.edit_requested_at, 'expires_at', s.expires_at) order by s.edit_requested_at)
    from public.support_sessions s join public.institutions i on i.id = s.institution_id join auth.users u on u.id = s.platform_user_id
   where s.edit_requested_at is not null and s.mode = 'read_only' and s.ended_at is null and s.expires_at > now()), '[]'::jsonb);
end $$;

-- The institution's support access log (settings.security): who entered, when, why, how long, what they changed.
create or replace function public.support_access_log() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_institution uuid := app.require_active_session();
begin
  if not app.can('settings.security') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'by', u.email, 'reason', s.reason, 'mode', s.mode,
           'edit_reason', s.edit_reason, 'started_at', s.started_at, 'expires_at', s.expires_at, 'ended_at', s.ended_at,
           'writes', (select count(*) from public.platform_audit_log p where p.support_session_id = s.id and p.action = 'support.write'),
           'actions', coalesce((select jsonb_agg(jsonb_build_object('action', a.action, 'target', a.target_type, 'at', a.at) order by a.at)
                       from public.audit_log a where a.institution_id = s.institution_id and a.support_session_id = s.id), '[]'::jsonb))
           order by s.started_at desc)
    from public.support_sessions s join auth.users u on u.id = s.platform_user_id
   where s.institution_id = v_institution), '[]'::jsonb);
end $$;

-- Panel → Institution → Audit tab (0B.08-T6): platform changes and support entries for one institution.
create or replace function public.platform_institution_audit(p_institution uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not app.is_platform('platform.view') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('action', p.action, 'at', p.at, 'by', (select email from auth.users u where u.id = p.actor_user_id),
           'target', p.target_type, 'target_id', p.target_id, 'reason', p.reason, 'support_session_id', p.support_session_id) order by p.at desc)
    from (select * from public.platform_audit_log where institution_id = p_institution order by at desc limit 300) p), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 5. Grants and registry
-- ---------------------------------------------------------------------------------------------------------------------
grant execute on function app.claim_support_session_id(), app.support_mode() to authenticated, service_role;
revoke all on function public.support_session_start(uuid, text, integer), public.support_session_end(), public.support_session_current(),
  public.support_edit_request(text), public.support_edit_approve(uuid), public.support_edit_requests(), public.support_access_log(),
  public.platform_institution_audit(uuid) from public, anon;
grant execute on function public.support_session_start(uuid, text, integer), public.support_session_end(), public.support_session_current(),
  public.support_edit_request(text), public.support_edit_approve(uuid), public.support_edit_requests(), public.support_access_log(),
  public.platform_institution_audit(uuid) to authenticated;

insert into app.definer_registry (function_name, reason, added_in, reviewer, tenant_check)
select f, r, '0B.08', 'architecture review 0B.08', t from (values
  ('app.support_mode', 'The caller''s own open support session for the token''s institution (support_sessions of the caller only).', 'not_tenant_data'),
  ('public.support_session_start', 'Starts a support session with reason and time limit; needs platform.support_access + aal2; audited both sides.', 'not_tenant_data'),
  ('public.support_session_end', 'Ends the caller''s own support sessions; audited both sides.', 'not_tenant_data'),
  ('public.support_session_current', 'The caller''s own open support session for the banner.', 'not_tenant_data'),
  ('public.support_edit_request', 'Asks for edit mode in the caller''s own session with a reason; audited both sides.', 'not_tenant_data'),
  ('public.support_edit_approve', 'Another Master Admin approves edit mode; audited both sides.', 'not_tenant_data'),
  ('public.support_edit_requests', 'Open edit requests for Master Admins (no tenant data).', 'not_tenant_data'),
  ('public.support_access_log', 'Support sessions and their actions for the active institution; can(settings.security).', 'filters_active_institution'),
  ('public.platform_institution_audit', 'Platform audit rows of one institution for the panel Audit tab; needs platform.view + aal2.', 'not_tenant_data')
) as v (f, r, t)
on conflict (function_name) do update set reason = excluded.reason, added_in = excluded.added_in, tenant_check = excluded.tenant_check;
