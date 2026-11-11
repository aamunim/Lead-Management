-- 0B.02 tests: platform roles never mix with institution roles, every platform right needs the second step (aal2),
-- the Proposed least-privilege rights per platform role, sign-in devices and new-device alerts, invites, platform user
-- changes with guards, audited writes without secrets, isolation from institutions.
\set ON_ERROR_STOP on
begin;
create function pg_temp.check(cond boolean, what text) returns void language plpgsql as $$
begin
  if cond is distinct from true then raise exception 'FAILED: %', what; end if;
  raise notice 'ok - %', what;
end $$;
create function pg_temp.claims_for(p_user uuid, p_aal text default 'aal2') returns jsonb language sql as $$
  select (public.custom_access_token_hook(jsonb_build_object('user_id', p_user,
          'claims', jsonb_build_object('sub', p_user, 'role', 'authenticated', 'aud', 'authenticated')))) -> 'claims'
         || jsonb_build_object('aal', p_aal)
$$;
create function pg_temp.act_as(p_claims jsonb) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', p_claims::text, true);
  perform set_config('role', 'authenticated', true);
end $$;
create function pg_temp.error_of(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return ''; exception when others then return sqlerrm; end $$;
grant execute on all functions in schema pg_temp to authenticated;
create temp table out (k text primary key, v jsonb);
grant all on out to authenticated;

\set master '''55555555-5555-4555-8555-555555555555'''
\set support '''e1000000-0000-4000-8000-0000000000e1'''
\set billing '''e2000000-0000-4000-8000-0000000000e2'''
\set developer '''e3000000-0000-4000-8000-0000000000e3'''
\set owner '''77777777-7777-4777-8777-777777777777'''

-- 1. No mixing: an institution Super Admin (role *, even with the second step) has no platform right and sees nothing.
select pg_temp.act_as(pg_temp.claims_for(:owner));
select pg_temp.check(not app.is_platform('platform.view') and not app.is_platform_admin(), 'an institution Super Admin has no platform right');
select pg_temp.check(pg_temp.error_of('select public.platform_users_list()') = 'permission_denied', 'and cannot call platform RPCs');
select pg_temp.check(not exists (select 1 from public.platform_audit_log) and not exists (select 1 from public.platform_login_devices),
  'and reads no platform rows');
select pg_temp.check(pg_temp.error_of('select count(*) from public.platform_invites') like 'permission denied%',
  'platform invites are not readable by app roles at all');
reset role;
select pg_temp.check(not exists (select 1 from public.role_permissions rp join public.permissions p on p.key = rp.permission_key
  where p.kind = 'platform'), 'no institution role holds a platform permission');

-- 2. The second step is required for every platform right.
select pg_temp.act_as(pg_temp.claims_for(:master, 'aal1'));
select pg_temp.check(not app.is_platform_admin() and not app.is_platform('platform.users'), 'Master Admin without the second step: no rights');
select pg_temp.check(pg_temp.error_of('select public.platform_session_start(''device-1'')') = 'mfa_required', 'the panel refuses a one-step session');
reset role;

-- 3. Rights per platform role (Proposed least privilege).
select pg_temp.act_as(pg_temp.claims_for(:master));
select pg_temp.check(app.is_platform('platform.users') and app.is_platform('platform.billing') and app.is_platform('platform.developer'),
  'Master Admin: everything');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:support));
select pg_temp.check(app.is_platform('platform.view') and not app.is_platform('platform.users') and not app.is_platform('platform.billing')
  and not app.is_platform('platform.support_access'), 'Support: sees the panel, read only; no setup rights by default');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:billing));
select pg_temp.check(app.is_platform('platform.billing') and app.is_platform('platform.view') and not app.is_platform('platform.users'),
  'Billing: billing only');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:developer));
select pg_temp.check(app.is_platform('platform.developer') and not app.is_platform('platform.view'), 'Developer: the developer inbox only');
reset role;

-- 4. Devices and new-device alerts.
select pg_temp.act_as(pg_temp.claims_for(:master));
insert into out select 'first', public.platform_session_start('device-A');
reset role;
select pg_temp.check(not ((select v from out where k = 'first') ->> 'new_device')::boolean
  and (select v from out where k = 'first') ->> 'platform_role' = 'master_admin', 'first device: no alert');
select pg_temp.act_as(pg_temp.claims_for(:support));
select public.platform_session_start('support-phone');
insert into out select 'second', public.platform_session_start('support-laptop');
select pg_temp.check(((select v from out where k = 'second') ->> 'new_device')::boolean, 'a new device is reported');
select pg_temp.check(jsonb_array_length(public.platform_alerts_list()) = 1, 'the person sees their own new-device alert');
select pg_temp.check(((select v from out where k = 'second') -> 'permissions') = '["platform.view"]'::jsonb, 'the panel gets the person''s rights');
reset role;
select pg_temp.check((select count(*) from public.platform_alerts where kind = 'new_device' and recipient_user_id = :master) = 1,
  'every Master Admin is alerted too');
select pg_temp.act_as(pg_temp.claims_for(:support));
select public.platform_session_start('support-laptop');
reset role;
select pg_temp.check((select count(*) from public.platform_alerts where kind = 'new_device') = 2, 'a known device raises no new alert');

-- 5. Invites, role changes and guards.
select pg_temp.act_as(pg_temp.claims_for(:support));
select pg_temp.check(pg_temp.error_of('select public.platform_user_invite(''new@example.test'', ''support'')') = 'permission_denied',
  'Support cannot invite');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:master));
select public.platform_user_invite('Owner.Admin@Example.test', 'support');
select pg_temp.check(pg_temp.error_of('select public.platform_user_invite(''platform.billing@example.test'', ''support'')') = 'user_state_invalid',
  'an existing platform user cannot be invited again');
select pg_temp.check(pg_temp.error_of(format('select public.platform_user_update(%L, ''support'', ''active'')', :master)) = 'self_lockout',
  'nobody changes their own platform role');
select pg_temp.check(pg_temp.error_of(format('select public.platform_user_update(%L, ''billing'', ''active'', array[''platform.nope''])', :billing)) = 'role_invalid',
  'unknown extra permissions are refused');
select public.platform_user_update(:support, 'support', 'active', array['platform.support_access'], 'needs setup rights for onboarding');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:support));
select pg_temp.check(app.is_platform('platform.support_access'), 'a personal extra right works');
reset role;
-- The invite becomes a membership on the invited person's first two-step sign-in.
select pg_temp.act_as(pg_temp.claims_for(:owner));
insert into out select 'joined', public.platform_session_start('owner-laptop');
reset role;
select pg_temp.check((select v from out where k = 'joined') ->> 'platform_role' = 'support'
  and not exists (select 1 from public.platform_invites), 'an invite turns into a platform role at the first two-step sign-in');
-- The last Master Admin cannot be demoted (a second one can demote the first).
insert into public.platform_members (user_id, platform_role) values (:billing, 'billing') on conflict (user_id) do nothing;
select pg_temp.act_as(pg_temp.claims_for(:master));
select pg_temp.check(pg_temp.error_of(format('select public.platform_user_update(%L, ''master_admin'', ''active'')', :billing)) = '',
  'a Master Admin can make another Master Admin');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:billing));
select pg_temp.check(pg_temp.error_of(format('select public.platform_user_update(%L, ''support'', ''active'')', :master)) = '',
  'with two Master Admins one may be demoted');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:master, 'aal2'));
select pg_temp.check(not app.is_platform_admin(), 'the demoted user is no longer Master Admin');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:billing));
select pg_temp.check(pg_temp.error_of(format('select public.platform_user_update(%L, ''support'', ''active'')', :billing)) = 'self_lockout',
  'the last Master Admin cannot demote themselves');
reset role;
insert into auth.sessions (id, user_id, created_at, updated_at) values (gen_random_uuid(), :developer, now(), now());
select pg_temp.act_as(pg_temp.claims_for(:billing));
select public.platform_user_update(:developer, 'developer', 'deactivated', null, 'left');
reset role;
select pg_temp.check(not exists (select 1 from auth.sessions where user_id = :developer), 'deactivating a platform user ends their sessions');

-- 6. Audit without secrets.
select pg_temp.check(exists (select 1 from public.platform_audit_log where action = 'platform_user.changed' and reason = 'left'
  and after ->> 'status' = 'deactivated'), 'every platform write is audited with before / after and reason');
select pg_temp.check(app.redact_secrets('{"api_key":"x","nested":{"password":"y","name":"ok"},"list":[{"token":"z"}]}')
  = '{"api_key":"[redacted]","nested":{"password":"[redacted]","name":"ok"},"list":[{"token":"[redacted]"}]}'::jsonb,
  'secrets are redacted at any depth');
select pg_temp.check(not exists (select 1 from public.platform_audit_log where after::text ~* 'JBSWY3DPEHPK3PXP|password123'),
  'no secret values in the platform audit log');

-- 7. Product-level config is public and single-sourced (D37).
set local role anon;
select pg_temp.check(public.product_config() ->> 'app_name' = 'Leadora', 'the product name comes from one config value');
reset role;

rollback;
