-- 0B.02 Platform roles, Master Admin login and panel shell (Ch 5.1–5.3, 5.14, 5.17; Ch 11.15; Ch 10.2; D4, D21).
-- Platform roles live only in platform_members (the roadmap's platform_users) and platform permissions (kind
-- 'platform'); they never mix with institution roles. Every platform check needs a two-step (aal2) session.
-- See docs/dev/PLATFORM.md.

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Platform users
-- ---------------------------------------------------------------------------------------------------------------------
alter table public.platform_members
  add column status text not null default 'active' check (status in ('active', 'deactivated')),
  add column created_by uuid references auth.users (id) on delete set null,
  -- Optional extra rights for one person (e.g. Support with setup rights, Ch 5.17 row 1).
  add column extra_permissions text[] not null default '{}';

-- What each platform role may do (0B.02-T5, Proposed least privilege; the owner approves at the checkpoint).
create table public.platform_role_permissions (
  platform_role  text not null check (platform_role in ('master_admin', 'support', 'billing', 'developer')),
  permission_key text not null,
  permission_kind text not null default 'platform' check (permission_kind = 'platform'),
  primary key (platform_role, permission_key),
  foreign key (permission_key, permission_kind) references public.permissions (key, kind) on delete cascade
);
alter table public.platform_role_permissions enable row level security;
revoke all on public.platform_role_permissions from anon, authenticated;
grant select on public.platform_role_permissions to authenticated;
create policy platform_role_permissions_read on public.platform_role_permissions for select to authenticated using (true);

-- The new platform permission rows (the manifest sync keeps them up to date afterwards) and the Proposed rights:
-- Master Admin everything (implicit); Support sees the panel (read only); Billing sees the panel and billing;
-- Developer only the developer inbox. Support setup rights are a personal extra permission (platform.support_access).
insert into public.permissions (key, kind, module, action, scopable, sensitive, introduced_in_release)
select k, 'platform', 'core', split_part(k, '.', 2), false, true, '0B.02'
  from unnest(array['platform.view', 'platform.integrations', 'platform.profiles', 'platform.users', 'platform.developer', 'platform.billing']) k
on conflict do nothing;
insert into public.platform_role_permissions (platform_role, permission_key) values
  ('support', 'platform.view'),
  ('billing', 'platform.view'), ('billing', 'platform.billing'),
  ('developer', 'platform.developer');

-- Pending invitations by email: one person per account (no shared logins).
create table public.platform_invites (
  email          text primary key check (email = lower(email)),
  platform_role  text not null check (platform_role in ('master_admin', 'support', 'billing', 'developer')),
  invited_by     uuid references auth.users (id) on delete set null,
  invited_at     timestamptz not null default now()
);
alter table public.platform_invites enable row level security;
revoke all on public.platform_invites from anon, authenticated;
create policy platform_invites_none on public.platform_invites for select to authenticated using (false);

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. Checks: every platform right needs an active platform user AND a two-step session
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function app.session_aal() returns text
language plpgsql stable set search_path = '' as $$
begin
  return coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'aal', 'aal1');
end $$;

create or replace function app.is_platform_admin() returns boolean
language plpgsql stable security definer set search_path = '' as $$
begin
  return app.session_aal() = 'aal2' and exists (
    select 1 from public.platform_members pm
     where pm.user_id = auth.uid() and pm.platform_role = 'master_admin' and pm.status = 'active');
end $$;

-- is_platform('platform.billing'): the Master Admin always; others by role or personal extra rights.
create or replace function app.is_platform(p_permission text) returns boolean
language plpgsql stable security definer set search_path = '' as $$
begin
  if app.session_aal() <> 'aal2' then
    return false;
  end if;
  return exists (
    select 1 from public.platform_members pm
     where pm.user_id = auth.uid() and pm.status = 'active'
       and (pm.platform_role = 'master_admin' or p_permission = any (pm.extra_permissions)
            or exists (select 1 from public.platform_role_permissions rp
                        where rp.platform_role = pm.platform_role and rp.permission_key = p_permission)));
end $$;
grant execute on function app.session_aal(), app.is_platform_admin(), app.is_platform(text) to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. Audited platform writes (0B.02-T4): who, which institution, before / after, reason, IP and device; secrets never
-- ---------------------------------------------------------------------------------------------------------------------
alter table public.platform_audit_log
  add column institution_id uuid,
  add column ip text,
  add column device text;

-- Removes values whose key looks like a secret, at any depth.
create or replace function app.redact_secrets(p_value jsonb) returns jsonb
language plpgsql immutable set search_path = '' as $$
declare
  k text;
  v jsonb;
  out jsonb;
begin
  if p_value is null then
    return null;
  end if;
  if jsonb_typeof(p_value) = 'object' then
    out := '{}'::jsonb;
    for k, v in select * from jsonb_each(p_value) loop
      out := out || jsonb_build_object(k, case when k ~* '(secret|password|token|api_?key|private|credential)'
                                               then '"[redacted]"'::jsonb else app.redact_secrets(v) end);
    end loop;
    return out;
  elsif jsonb_typeof(p_value) = 'array' then
    return (select coalesce(jsonb_agg(app.redact_secrets(e)), '[]'::jsonb) from jsonb_array_elements(p_value) e);
  end if;
  return p_value;
end $$;

create or replace function app.request_header(p_name text) returns text
language plpgsql stable set search_path = '' as $$
begin
  return nullif(current_setting('request.headers', true), '')::jsonb ->> p_name;
exception when others then
  return null;
end $$;

create or replace function app.platform_audit(p_action text, p_institution uuid, p_target_type text, p_target_id text,
                                              p_before jsonb, p_after jsonb, p_reason text default null) returns void
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.platform_audit_log (actor_user_id, action, institution_id, target_type, target_id, before, after, reason, ip, device)
  values (auth.uid(), p_action, p_institution, p_target_type, p_target_id, app.redact_secrets(p_before), app.redact_secrets(p_after),
          p_reason, split_part(coalesce(app.request_header('x-forwarded-for'), ''), ',', 1),
          left(app.request_header('user-agent'), 300));
end $$;
revoke all on function app.platform_audit(text, uuid, text, text, jsonb, jsonb, text) from public, anon, authenticated;
grant execute on function app.redact_secrets(jsonb), app.request_header(text) to authenticated, service_role;

-- The platform audit log is read only on the platform side (never by an institution).
drop policy if exists platform_audit_log_read on public.platform_audit_log;
create policy platform_audit_log_read on public.platform_audit_log for select to authenticated
  using ((select app.is_platform('platform.users')) or (select app.is_platform_admin()));

-- ---------------------------------------------------------------------------------------------------------------------
-- 4. Devices and new-device alerts (0B.02-T3)
-- ---------------------------------------------------------------------------------------------------------------------
create table public.platform_login_devices (
  user_id            uuid not null references auth.users (id) on delete cascade,
  device_fingerprint text not null,
  ip                 text,
  user_agent         text,
  first_seen         timestamptz not null default now(),
  last_seen          timestamptz not null default now(),
  primary key (user_id, device_fingerprint)
);
alter table public.platform_login_devices enable row level security;
revoke all on public.platform_login_devices from anon, authenticated;
grant select on public.platform_login_devices to authenticated;
create policy platform_login_devices_read on public.platform_login_devices for select to authenticated
  using (user_id = (select auth.uid()) or (select app.is_platform_admin()));

-- Alerts for platform users (shown in the panel; email when the email adapters exist, 0B.14).
create table public.platform_alerts (
  id                uuid primary key default gen_random_uuid(),
  recipient_user_id uuid not null references auth.users (id) on delete cascade,
  kind              text not null,
  payload           jsonb not null default '{}',
  created_at        timestamptz not null default now(),
  read_at           timestamptz
);
create index platform_alerts_recipient_idx on public.platform_alerts (recipient_user_id, created_at desc);
alter table public.platform_alerts enable row level security;
revoke all on public.platform_alerts from anon, authenticated;
grant select on public.platform_alerts to authenticated;
create policy platform_alerts_read_own on public.platform_alerts for select to authenticated
  using (recipient_user_id = (select auth.uid()));

-- Called by the panel right after a two-step sign-in: accepts a pending invite, records the device and raises the
-- "new device" alert (to the person and to every Master Admin) when it is not their first device. Returns who you are.
create or replace function public.platform_session_start(p_device_fingerprint text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_user    uuid := auth.uid();
  v_email   text;
  v_member  public.platform_members;
  v_known   boolean;
  v_first   boolean;
  v_ip      text := split_part(coalesce(app.request_header('x-forwarded-for'), ''), ',', 1);
  v_agent   text := left(app.request_header('user-agent'), 300);
begin
  if v_user is null then
    raise exception 'not_signed_in' using errcode = 'P0401';
  end if;
  if app.session_aal() <> 'aal2' then
    raise exception 'mfa_required' using errcode = 'P0401';
  end if;
  select lower(email) into v_email from auth.users where id = v_user;
  -- An invitation for this email becomes a platform membership on the first two-step sign-in.
  insert into public.platform_members (user_id, platform_role, created_by)
  select v_user, i.platform_role, i.invited_by from public.platform_invites i where i.email = v_email
  on conflict (user_id) do nothing;
  if found then
    delete from public.platform_invites where email = v_email;
    perform app.platform_audit('platform_user.joined', null, 'platform_user', v_user::text, null, jsonb_build_object('email', v_email), null);
  end if;
  select * into v_member from public.platform_members where user_id = v_user;
  if not found or v_member.status <> 'active' then
    raise exception 'permission_denied' using errcode = '42501', detail = 'not a platform user';
  end if;
  if nullif(btrim(coalesce(p_device_fingerprint, '')), '') is null or length(p_device_fingerprint) > 200 then
    raise exception 'device_invalid' using errcode = 'P0422';
  end if;
  select exists (select 1 from public.platform_login_devices where user_id = v_user and device_fingerprint = p_device_fingerprint) into v_known;
  select not exists (select 1 from public.platform_login_devices where user_id = v_user) into v_first;
  insert into public.platform_login_devices (user_id, device_fingerprint, ip, user_agent)
  values (v_user, p_device_fingerprint, v_ip, v_agent)
  on conflict (user_id, device_fingerprint) do update set last_seen = now(), ip = excluded.ip, user_agent = excluded.user_agent;
  if not v_known and not v_first then
    insert into public.platform_alerts (recipient_user_id, kind, payload)
    select r, 'new_device', jsonb_build_object('user_id', v_user, 'email', v_email, 'ip', v_ip, 'user_agent', v_agent)
      from (select v_user as r union select pm.user_id from public.platform_members pm
             where pm.platform_role = 'master_admin' and pm.status = 'active') x;
    perform app.platform_audit('platform_user.new_device', null, 'platform_user', v_user::text, null,
                               jsonb_build_object('ip', v_ip, 'user_agent', v_agent), null);
  end if;
  return jsonb_build_object('user_id', v_user, 'email', v_email, 'platform_role', v_member.platform_role,
    'new_device', not v_known and not v_first,
    'permissions', (select coalesce(jsonb_agg(distinct p.key order by p.key), '[]'::jsonb) from public.permissions p
                     where p.kind = 'platform' and (v_member.platform_role = 'master_admin' or p.key = any (v_member.extra_permissions)
                       or exists (select 1 from public.platform_role_permissions rp
                                   where rp.platform_role = v_member.platform_role and rp.permission_key = p.key))));
end $$;

create or replace function public.platform_alerts_list() returns jsonb
language sql stable security invoker set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'kind', a.kind, 'payload', a.payload, 'created_at', a.created_at,
                  'read', a.read_at is not null) order by a.created_at desc), '[]'::jsonb)
    from (select * from public.platform_alerts where recipient_user_id = auth.uid() order by created_at desc limit 50) a
$$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 5. Platform users screen (0B.02-T7): list, invite by email, change role, deactivate / reactivate
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function public.platform_users_list() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not app.is_platform('platform.users') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'users', coalesce((select jsonb_agg(jsonb_build_object('user_id', pm.user_id, 'email', u.email, 'name', p.display_name,
               'platform_role', pm.platform_role, 'status', pm.status, 'extra_permissions', to_jsonb(pm.extra_permissions),
               'last_seen', (select max(d.last_seen) from public.platform_login_devices d where d.user_id = pm.user_id),
               'has_second_factor', exists (select 1 from auth.mfa_factors f where f.user_id = pm.user_id and f.status = 'verified'))
               order by pm.platform_role = 'master_admin' desc, u.email)
             from public.platform_members pm join auth.users u on u.id = pm.user_id left join public.profiles p on p.user_id = pm.user_id), '[]'::jsonb),
    'invites', coalesce((select jsonb_agg(jsonb_build_object('email', i.email, 'platform_role', i.platform_role, 'invited_at', i.invited_at)
               order by i.invited_at) from public.platform_invites i), '[]'::jsonb));
end $$;

create or replace function app.active_master_admins(p_except uuid default null) returns integer
language sql stable set search_path = '' as $$
  select count(*)::integer from public.platform_members
   where platform_role = 'master_admin' and status = 'active' and user_id is distinct from p_except
$$;

create or replace function public.platform_user_invite(p_email text, p_role text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_email text := lower(btrim(coalesce(p_email, '')));
begin
  if not app.is_platform('platform.users') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'email_invalid' using errcode = 'P0422';
  end if;
  if p_role not in ('master_admin', 'support', 'billing', 'developer') then
    raise exception 'role_invalid' using errcode = 'P0422', detail = coalesce(p_role, '');
  end if;
  if p_role = 'master_admin' and not app.is_platform_admin() then
    raise exception 'permission_escalation' using errcode = '42501';
  end if;
  if exists (select 1 from public.platform_members pm join auth.users u on u.id = pm.user_id where lower(u.email) = v_email) then
    raise exception 'user_state_invalid' using errcode = 'P0409', detail = 'already a platform user';
  end if;
  insert into public.platform_invites (email, platform_role, invited_by) values (v_email, p_role, auth.uid())
  on conflict (email) do update set platform_role = excluded.platform_role, invited_by = excluded.invited_by, invited_at = now();
  perform app.platform_audit('platform_user.invited', null, 'platform_invite', v_email, null, jsonb_build_object('platform_role', p_role), null);
end $$;

create or replace function public.platform_user_update(p_user_id uuid, p_role text, p_status text, p_extra_permissions text[] default null,
                                                       p_reason text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_before public.platform_members;
begin
  if not app.is_platform('platform.users') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  select * into v_before from public.platform_members where user_id = p_user_id;
  if not found then
    raise exception 'user_unknown' using errcode = 'P0404', detail = p_user_id::text;
  end if;
  if p_role not in ('master_admin', 'support', 'billing', 'developer') or p_status not in ('active', 'deactivated') then
    raise exception 'role_invalid' using errcode = 'P0422';
  end if;
  if exists (select 1 from unnest(coalesce(p_extra_permissions, '{}')) x
              where not exists (select 1 from public.permissions p where p.key = x and p.kind = 'platform')) then
    raise exception 'role_invalid' using errcode = 'P0422', detail = 'unknown platform permission';
  end if;
  -- Only a Master Admin creates or changes a Master Admin; nobody changes their own platform role.
  if (p_role = 'master_admin' or v_before.platform_role = 'master_admin') and not app.is_platform_admin() then
    raise exception 'permission_escalation' using errcode = '42501';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'self_lockout' using errcode = 'P0409', detail = 'ask another Master Admin';
  end if;
  if v_before.platform_role = 'master_admin' and v_before.status = 'active' and (p_role <> 'master_admin' or p_status <> 'active')
     and app.active_master_admins(p_user_id) = 0 then
    raise exception 'last_super_admin' using errcode = 'P0409', detail = 'the last Master Admin';
  end if;
  update public.platform_members set platform_role = p_role, status = p_status,
         extra_permissions = coalesce(p_extra_permissions, extra_permissions)
   where user_id = p_user_id;
  -- Deactivated: their sign-in sessions end at once.
  if p_status = 'deactivated' then
    delete from auth.sessions where user_id = p_user_id;
  end if;
  perform app.platform_audit('platform_user.changed', null, 'platform_user', p_user_id::text,
    jsonb_build_object('platform_role', v_before.platform_role, 'status', v_before.status, 'extra_permissions', to_jsonb(v_before.extra_permissions)),
    jsonb_build_object('platform_role', p_role, 'status', p_status, 'extra_permissions', to_jsonb(coalesce(p_extra_permissions, v_before.extra_permissions))),
    p_reason);
end $$;

create or replace function public.platform_invite_cancel(p_email text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not app.is_platform('platform.users') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  delete from public.platform_invites where email = lower(btrim(p_email));
  perform app.platform_audit('platform_user.invite_cancelled', null, 'platform_invite', lower(btrim(p_email)), null, null, null);
end $$;

-- Product-level values the panel and the app show (product name D37, Ch 1.7 row 3): readable without signing in.
create or replace function public.product_config() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('app_name', app.product_setting('app_name'), 'app_domain', app.product_setting('app_domain'),
                            'privacy_contact_email', app.product_setting('privacy_contact_email'))
$$;

revoke all on function public.platform_session_start(text), public.platform_alerts_list(), public.platform_users_list(),
  public.platform_user_invite(text, text), public.platform_user_update(uuid, text, text, text[], text),
  public.platform_invite_cancel(text) from public, anon;
grant execute on function public.platform_session_start(text), public.platform_alerts_list(), public.platform_users_list(),
  public.platform_user_invite(text, text), public.platform_user_update(uuid, text, text, text[], text),
  public.platform_invite_cancel(text) to authenticated;
grant execute on function public.product_config() to anon, authenticated;
revoke all on function app.active_master_admins(uuid) from public, anon, authenticated;

insert into app.definer_registry (function_name, reason, added_in, reviewer, tenant_check)
select f, r, '0B.02', 'architecture review 0B.02', t from (values
  ('app.is_platform_admin', 'Platform Master Admin check: reads the caller''s own platform_members row; needs aal2 (0B.02).', 'not_tenant_data'),
  ('app.is_platform', 'Platform permission check: reads platform_members / platform_role_permissions of the caller only; needs aal2.', 'not_tenant_data'),
  ('app.platform_audit', 'Writes platform_audit_log rows (secrets redacted); called by platform RPCs only.', 'not_tenant_data'),
  ('public.platform_session_start', 'Panel sign-in: the caller''s own invite, device and alerts; needs aal2.', 'not_tenant_data'),
  ('public.platform_users_list', 'Lists platform users (no tenant data); needs platform.users + aal2.', 'not_tenant_data'),
  ('public.platform_user_invite', 'Invites a platform user by email; needs platform.users + aal2; audited.', 'not_tenant_data'),
  ('public.platform_user_update', 'Changes a platform user''s role / status; guards; needs platform.users + aal2; audited.', 'not_tenant_data'),
  ('public.platform_invite_cancel', 'Cancels a platform invite; needs platform.users + aal2; audited.', 'not_tenant_data'),
  ('public.product_config', 'Product-level public values (app name, domain, privacy contact); no tenant data.', 'not_tenant_data')
) as v (f, r, t)
on conflict (function_name) do update set reason = excluded.reason, added_in = excluded.added_in, tenant_check = excluded.tenant_check;
