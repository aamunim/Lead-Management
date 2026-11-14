-- 0B.13 tests: Custom HTTP targets must be https and public; routes (OTP / transactional vs promotional); the
-- platform gateway as last backup unless turned off; switching the primary (queued messages follow); balance and the
-- low-balance alert; "balance exhausted" for the institution; polling and contract-test plumbing; permissions.
\set ON_ERROR_STOP on
begin;
create function pg_temp.check(cond boolean, what text) returns void language plpgsql as $$
begin
  if cond is distinct from true then raise exception 'FAILED: %', what; end if;
  raise notice 'ok - %', what;
end $$;
create function pg_temp.claims_for(p_user uuid, p_aal text default 'aal1') returns jsonb language sql as $$
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
grant execute on all functions in schema pg_temp to authenticated, service_role;
create temp table out (k text primary key, v jsonb);
grant all on out to authenticated, service_role;
create function pg_temp.v(p_k text) returns jsonb language sql as $$ select v from out where k = p_k $$;
grant execute on function pg_temp.v(text) to authenticated, service_role;

\set inst_a '''a0000000-0000-4000-8000-00000000000a'''
\set owner '''77777777-7777-4777-8777-777777777777'''
\set master '''55555555-5555-4555-8555-555555555555'''

-- 1. Custom HTTP: https and public hosts only (SSRF), checked by the database as well as the adapter.
select pg_temp.act_as(pg_temp.claims_for(:master, 'aal2'));
select pg_temp.check(pg_temp.error_of(format('select public.platform_connection_save(%L, null, ''{"provider":"custom_http_sms","label":"x","settings":{"send_url":"https://10.0.0.8/send"}}'')', :inst_a))
  = 'connection_invalid', 'a private address is refused');
select pg_temp.check(pg_temp.error_of(format('select public.platform_connection_save(%L, null, ''{"provider":"custom_http_sms","label":"x","settings":{"send_url":"https://169.254.169.254/latest"}}'')', :inst_a))
  = 'connection_invalid', 'the cloud metadata address is refused');
select pg_temp.check(pg_temp.error_of(format('select public.platform_connection_save(%L, null, ''{"provider":"custom_http_sms","label":"x","settings":{"send_url":"http://sms.example.com/send"}}'')', :inst_a))
  = 'connection_invalid', 'plain http is refused');
insert into out select 'trans', public.platform_connection_save(:inst_a, null, '{"provider":"custom_http_sms","label":"Fast route","mode":"live","priority":1,
  "settings":{"send_url":"https://sms.example.com/send","sender_id":"8801700000000","route":"transactional","price_per_part":0.25,"low_balance_threshold":100,
  "masking":{"type":"non_masked"}}}');
insert into out select 'promo', public.platform_connection_save(:inst_a, null, '{"provider":"custom_http_sms","label":"Promo route","mode":"live","priority":2,
  "settings":{"send_url":"https://promo.example.com/send","sender_id":"ACME","route":"promotional","masking":{"type":"masked","status":"applied","non_masked_sender_id":"8801700000001"}}}');
select pg_temp.check((select adapter_version from public.integration_providers where key = 'custom_http_sms') = 'custom-http-1'
  and pg_temp.v('promo') -> 'masking' ->> 'status' = 'applied', 'Custom HTTP is ready; the masking status is stored and shown');
reset role;
update public.integration_connections set live_test_passed_at = now() where institution_id = :inst_a;
insert into public.platform_connections (id, kind, provider_key, label, mode, settings, live_test_passed_at)
values ('c4000000-0000-4000-8000-0000000000f1', 'sms', 'custom_http_sms', 'Platform gateway', 'live', '{"send_url":"https://gw.example.com/send"}', now());

-- 2. Routes: OTP / transactional on the fast route, bulk on the promotional route; the platform gateway last.
set local role service_role;
insert into out select 'otp', app.outbox_enqueue(:inst_a, 'sms', 'otp', '01711000001', '{"body":"Code 1234"}', 'route-otp-0001');
insert into out select 'bulk', app.outbox_enqueue(:inst_a, 'sms', 'bulk', '01711000002', '{"body":"Admission open"}', 'route-bulk-001');
create temp table claimed as select * from app.outbox_claim('t', 50);
insert into out select 'r_otp', app.outbox_route(:inst_a, (pg_temp.v('otp') ->> 'id')::uuid);
insert into out select 'r_bulk', app.outbox_route(:inst_a, (pg_temp.v('bulk') ->> 'id')::uuid);
reset role;
select pg_temp.check(pg_temp.v('r_otp') -> 'connections' -> 0 ->> 'id' = pg_temp.v('trans') ->> 'id'
  and not (pg_temp.v('r_otp') -> 'connections' @? ('$[*] ? (@.id == "' || (pg_temp.v('promo') ->> 'id') || '")')::jsonpath)
  and pg_temp.v('r_otp') -> 'connections' -> -1 ->> 'owner' = 'platform', 'OTP: the fast route first, never the promotional one, the platform gateway last');
select pg_temp.check(pg_temp.v('r_bulk') -> 'connections' -> 0 ->> 'id' = pg_temp.v('promo') ->> 'id'
  and not (pg_temp.v('r_bulk') -> 'connections' @? ('$[*] ? (@.id == "' || (pg_temp.v('trans') ->> 'id') || '")')::jsonpath),
  'bulk goes through the promotional route');

-- 3. The institution can turn the platform backup off.
select pg_temp.act_as(pg_temp.claims_for(:master, 'aal2'));
select public.institution_platform_fallback_set(:inst_a, 'sms', false);
reset role;
set local role service_role;
insert into out select 'r_otp2', app.outbox_route(:inst_a, (pg_temp.v('otp') ->> 'id')::uuid);
reset role;
select pg_temp.check(not (pg_temp.v('r_otp2') -> 'connections' @? '$[*] ? (@.owner == "platform")'), 'with the backup off, no platform gateway');

-- 4. Switch gateway (D33 / D34): make the promotional connection primary; a queued message follows at once.
select pg_temp.act_as(pg_temp.claims_for(:master, 'aal2'));
insert into out select 'switch', public.connection_make_primary(:inst_a, (pg_temp.v('promo') ->> 'id')::uuid);
reset role;
select pg_temp.check((select priority from public.integration_connections where id = (pg_temp.v('promo') ->> 'id')::uuid) = 1
  and (select priority from public.integration_connections where id = (pg_temp.v('trans') ->> 'id')::uuid) = 2
  and pg_temp.v('switch') ->> 'previous' = pg_temp.v('trans') ->> 'id'
  and exists (select 1 from public.integration_audit where action = 'connection.made_primary')
  and exists (select 1 from public.platform_audit_log where action = 'integration.primary_changed'), 'one action makes another gateway primary; audited');

-- 5. Balance: stored; below the threshold Master Admins are alerted once a day; at zero the institution sees it.
set local role service_role;
select app.health_record('institution', :inst_a, (pg_temp.v('trans') ->> 'id')::uuid, true, null, null, 40);
select app.health_record('institution', :inst_a, (pg_temp.v('trans') ->> 'id')::uuid, true, null, null, 30);
reset role;
select pg_temp.check((select last_balance = 30 from public.integration_connections where id = (pg_temp.v('trans') ->> 'id')::uuid)
  and (select count(*) from public.platform_alerts where kind = 'balance_low' and payload ->> 'connection_id' = pg_temp.v('trans') ->> 'id'
        and recipient_user_id = :master) = 1, 'low balance: stored, one alert a day');
set local role service_role;
select app.health_record('institution', :inst_a, (pg_temp.v('trans') ->> 'id')::uuid, true, null, null, 0);
reset role;
select pg_temp.act_as(pg_temp.claims_for(:owner));
select pg_temp.check((select (x ->> 'balance_exhausted')::boolean from jsonb_array_elements(public.integrations_status() -> 'connections') x
  where x ->> 'id' = pg_temp.v('trans') ->> 'id'), 'the institution sees "balance exhausted" (status only, no settings)');
select pg_temp.check(public.integrations_status()::text not like '%sms.example.com%', 'still no settings for the institution');
reset role;

-- 6. Polling and contract tests.
update public.outbox set status = 'sent', provider_message_id = 'gw-1', sent_at = now() - interval '20 minutes',
       connection_id = (pg_temp.v('trans') ->> 'id')::uuid, connection_owner = 'institution'
 where id = (pg_temp.v('otp') ->> 'id')::uuid;
update public.integration_connections set settings = settings || '{"status_url":"https://sms.example.com/status/{message_id}"}'
 where id = (pg_temp.v('trans') ->> 'id')::uuid;
set local role service_role;
select pg_temp.check(public.hub_poll_due(10) @? ('$[*] ? (@.id == "' || (pg_temp.v('otp') ->> 'id') || '")')::jsonpath,
  'a sent message without a report on a pollable gateway is due for polling');
select public.hub_contract_result('mock_sms', false, 'sandbox down');
select public.hub_contract_result('mock_sms', false, 'sandbox down again');
reset role;
select pg_temp.check((select count(*) from public.platform_alerts where kind = 'contract_failed' and recipient_user_id = :master) = 1,
  'a failed contract test alerts the platform once a day');

-- 7. People cannot switch gateways or touch the worker API.
select pg_temp.act_as(pg_temp.claims_for(:owner));
select pg_temp.check(pg_temp.error_of(format('select public.connection_make_primary(%L, %L)', :inst_a, pg_temp.v('trans') ->> 'id')) = 'permission_denied'
  and pg_temp.error_of('select public.hub_poll_due(1)') like 'permission denied%', 'only the Master Admin switches; the worker API is closed');
reset role;

rollback;
