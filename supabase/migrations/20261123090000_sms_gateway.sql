-- 0B.13 SMS: Custom HTTP adapter, platform gateway, routes, masking, balance, switching the primary (Ch 42.4, 42.9 I5,
-- 42.10 rows 3–5, 8; Ch 5.6; Ch 9.7; Ch 10.5; D3, D4, D7, D15, D22, D33, D34, D35).
--   * Custom HTTP SMS is ready (adapter custom-http-1): URL, method, parameter map with {to} {message} {sender_id}
--     {api_key} {unicode}, success rule, message id path, balance URL, sender id and masking status, route, per-part
--     price, low-balance threshold. Only https and public hosts (checked here and again by the adapter, after DNS).
--   * The ready-made Bangladeshi gateway adapters wait for the owner's shortlist (0B.13-T1, open question Q3).
--   * Routes: OTP / transactional go through connections whose route is "transactional" (or "all"); bulk through
--     "promotional" (or "all").
--   * The platform gateway is used when the platform pays, when the institution has none, and — unless the institution
--     says otherwise — as the last backup (0B.13-T4; Proposed default: on).
--   * Low balance: the health round stores the balance; below the connection's threshold the Master Admins are alerted
--     once a day and the institution sees "Balance exhausted — recharge with the provider" when it pays directly.
--   * Switching the gateway (D33, D34): make another connection primary in one action; queued messages follow at once
--     (routing happens at send time); the log and the ledger keep the gateway that actually sent each message.
--   * Delivery reports by polling where a gateway has no push (status URL), and a daily contract test per adapter that
--     declares one (I5); a failure alerts the platform.

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Custom HTTP: settings schema, safety check, adapter ready
-- ---------------------------------------------------------------------------------------------------------------------
update public.integration_providers set adapter_version = 'custom-http-1', status = 'beta',
  capabilities = '{send,bulk,unicode,masking,balance,status_push,status_poll}',
  settings_schema = '{"type":"object","required":["send_url"],"additionalProperties":false,"properties":{
    "send_url":{"type":"string","pattern":"^https://","maxLength":500},
    "method":{"type":"string","enum":["GET","POST"],"default":"POST"},
    "body_format":{"type":"string","enum":["form","json"],"default":"form"},
    "params":{"type":"object","additionalProperties":{"type":"string","maxLength":500},"maxProperties":20},
    "success_match":{"type":"string","maxLength":200},
    "message_id_path":{"type":"string","maxLength":100},
    "balance_url":{"type":"string","pattern":"^https://","maxLength":500},
    "balance_path":{"type":"string","maxLength":100},
    "status_url":{"type":"string","pattern":"^https://","maxLength":500},
    "status_path":{"type":"string","maxLength":100},
    "sender_id":{"type":"string","minLength":1,"maxLength":20},
    "masking":{"type":"object","additionalProperties":false,"properties":{
       "type":{"type":"string","enum":["non_masked","masked"]},
       "status":{"type":"string","enum":["applied","approved","rejected"]},
       "non_masked_sender_id":{"type":"string","maxLength":20}}},
    "route":{"type":"string","enum":["transactional","promotional","all"],"default":"all"},
    "price_per_part":{"type":"number","minimum":0,"maximum":100},
    "rate_per_minute":{"type":"integer","minimum":1,"maximum":100000},
    "low_balance_threshold":{"type":"number","minimum":0},
    "timeout_ms":{"type":"integer","minimum":1000,"maximum":20000}}}'
 where key = 'custom_http_sms';

-- Literal addresses that must never be called (the adapter checks DNS results too): private, loopback, link-local
-- (cloud metadata), carrier-grade NAT, multicast, and host names without a dot or on internal suffixes.
create or replace function app.url_is_public(p_url text) returns boolean
language plpgsql immutable set search_path = '' as $$
declare
  v_host text := lower(substring(p_url from '^https://(?:[^@/]*@)?(\[[^\]]+\]|[^/:?#]+)'));
  v_ip   inet;
begin
  if p_url is null then return true; end if;
  if v_host is null or p_url !~ '^https://' or p_url ~ '^https://[^/]*@' then return false; end if;
  v_host := trim(both '[]' from v_host);
  begin
    v_ip := v_host::inet;
  exception when others then
    v_ip := null;
  end;
  if v_ip is not null then
    return not (v_ip << '10.0.0.0/8' or v_ip << '172.16.0.0/12' or v_ip << '192.168.0.0/16' or v_ip << '127.0.0.0/8'
             or v_ip << '169.254.0.0/16' or v_ip << '100.64.0.0/10' or v_ip << '0.0.0.0/8' or v_ip << '224.0.0.0/3'
             or v_ip << '198.18.0.0/15' or v_ip <<= '::1/128' or v_ip << 'fc00::/7' or v_ip << 'fe80::/10' or v_ip << '::ffff:0:0/96'
             or v_ip = '::'::inet);
  end if;
  return v_host like '%.%' and v_host !~ '(^localhost$|\.localhost$|\.local$|\.internal$|\.lan$)';
end $$;

create or replace function app.connection_settings_check() returns trigger
language plpgsql set search_path = '' as $$
declare
  v_url text;
begin
  if new.provider_key = 'custom_http_sms' then
    foreach v_url in array array[new.settings ->> 'send_url', new.settings ->> 'balance_url', new.settings ->> 'status_url'] loop
      if v_url is not null and not app.url_is_public(v_url) then
        raise exception 'connection_invalid' using errcode = 'P0422', detail = 'only https and public hosts may be called';
      end if;
    end loop;
  end if;
  return new;
end $$;
create trigger integration_connections_settings_check before insert or update of settings on public.integration_connections
  for each row execute function app.connection_settings_check();
create trigger platform_connections_settings_check before insert or update of settings on public.platform_connections
  for each row execute function app.connection_settings_check();

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. Balance, platform fallback, routes
-- ---------------------------------------------------------------------------------------------------------------------
alter table public.integration_connections add column last_balance numeric, add column balance_checked_at timestamptz;
alter table public.platform_connections add column last_balance numeric, add column balance_checked_at timestamptz;
alter table public.institution_service_payers add column platform_fallback boolean not null default true;

-- The 0B.11 resolver, with the platform gateway as the last backup unless the institution turned that off.
create or replace function app.resolve_connection(p_institution uuid, p_kind text, p_purpose text default 'send') returns jsonb
language sql stable security definer set search_path = '' as $$
  with pref as (select coalesce((select p.payer from public.institution_service_payers p where p.institution_id = p_institution and p.kind = p_kind),
                                'direct') as payer,
                       coalesce((select p.platform_fallback from public.institution_service_payers p
                                  where p.institution_id = p_institution and p.kind = p_kind), true) as fallback),
       own as (
         select 'institution' as owner, to_jsonb(c) as c, c.priority from public.integration_connections c, pref
          where c.institution_id = p_institution and c.kind = p_kind and c.status = 'active' and pref.payer = 'direct'
            and app.institution_can_use_connections(p_institution)
            and not (p_purpose = 'bulk' and c.mode = 'live' and c.live_test_passed_at is null)),
       plat as (
         select 'platform' as owner, to_jsonb(c) as c, c.priority from public.platform_connections c
          where c.kind = p_kind and c.status = 'active' and app.institution_can_use_connections(p_institution)
            and not (p_purpose = 'bulk' and c.mode = 'live' and c.live_test_passed_at is null)
            and ((select payer from pref) = 'platform' or not exists (select 1 from own) or (select fallback from pref)))
  select coalesce(jsonb_agg(jsonb_build_object('owner', x.owner, 'id', x.c ->> 'id', 'provider', x.c ->> 'provider_key', 'mode', x.c ->> 'mode',
                                               'settings', x.c -> 'settings', 'sandbox', x.c ->> 'mode' = 'sandbox')
                            order by x.owner = 'platform', x.priority), '[]'::jsonb)
    from (select * from own union all select * from plat) x
$$;

-- Routing for one claimed message (0B.12) learns routes: OTP / urgent / transactional on "transactional" connections,
-- bulk on "promotional" ones; "all" (or none set) carries both.
create or replace function app.outbox_route(p_institution uuid, p_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_msg   public.outbox;
  v_gate  text;
  v_all   jsonb;
  v_route text;
begin
  select * into v_msg from public.outbox where institution_id = p_institution and id = p_id;
  if not found or v_msg.status <> 'sending' then
    return jsonb_build_object('gate', 'gone', 'connections', '[]'::jsonb);
  end if;
  v_gate := app.outbox_gate(p_institution, v_msg.channel, v_msg.priority,
                            case when v_msg.channel = 'sms' then app.sms_parts(v_msg.payload ->> 'body') else 1 end);
  if v_gate is not null then
    return jsonb_build_object('gate', v_gate, 'connections', '[]'::jsonb);
  end if;
  v_route := case v_msg.priority when 'bulk' then 'promotional' else 'transactional' end;
  v_all := app.resolve_connection(p_institution, v_msg.channel, case v_msg.priority when 'bulk' then 'bulk' else 'send' end);
  return jsonb_build_object('gate', null, 'channel', v_msg.channel, 'connections', coalesce((
    select jsonb_agg(c || jsonb_build_object('secret_fields', to_jsonb(p.secret_fields)) order by ord)
      from jsonb_array_elements(v_all) with ordinality as x (c, ord)
      join public.integration_providers p on p.key = c ->> 'provider'
     where (v_msg.payload ->> 'pin_connection' is null or c ->> 'id' = v_msg.payload ->> 'pin_connection')
       and (v_msg.payload ->> 'pin_connection' is not null or coalesce(c -> 'settings' ->> 'route', 'all') in ('all', v_route))
       and not exists (select 1 from public.integration_connections ic where ic.id = (c ->> 'id')::uuid and ic.circuit_open_until > now())
       and not exists (select 1 from public.platform_connections pc where pc.id = (c ->> 'id')::uuid and pc.circuit_open_until > now())
       and (c -> 'settings' ->> 'rate_per_minute' is null
            or (select count(*) from public.delivery_log d where d.connection_id = (c ->> 'id')::uuid and d.at > now() - interval '1 minute')
               < (c -> 'settings' ->> 'rate_per_minute')::int)), '[]'::jsonb));
end $$;

-- Health with the balance (0B.13-T9): stores it and alerts Master Admins once a day below the threshold.
create or replace function app.health_record(p_owner text, p_institution uuid, p_connection uuid, p_ok boolean, p_code text, p_detail text,
                                             p_balance numeric) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_threshold numeric;
  v_label     text;
begin
  if p_owner = 'institution' then
    update public.integration_connections set last_health_at = now(),
           last_balance = coalesce(p_balance, last_balance), balance_checked_at = case when p_balance is not null then now() else balance_checked_at end
     where institution_id = p_institution and id = p_connection
    returning (settings ->> 'low_balance_threshold')::numeric, label into v_threshold, v_label;
  else
    update public.platform_connections set last_health_at = now(),
           last_balance = coalesce(p_balance, last_balance), balance_checked_at = case when p_balance is not null then now() else balance_checked_at end
     where id = p_connection
    returning (settings ->> 'low_balance_threshold')::numeric, label into v_threshold, v_label;
  end if;
  perform app.connection_outcome(p_institution, p_owner, p_connection, p_ok and coalesce(p_balance > 0, true),
                                 case when p_ok and p_balance is not null and p_balance <= 0 then 'balance_low' else p_code end, p_detail);
  if p_balance is not null and v_threshold is not null and p_balance < v_threshold
     and not exists (select 1 from public.platform_alerts a where a.kind = 'balance_low' and a.payload ->> 'connection_id' = p_connection::text
                       and a.created_at > now() - interval '1 day') then
    insert into public.platform_alerts (recipient_user_id, kind, payload)
    select pm.user_id, 'balance_low', jsonb_build_object('institution_id', p_institution, 'connection_id', p_connection, 'label', v_label,
             'balance', p_balance, 'threshold', v_threshold,
             'name', (select i.name from public.institutions i where i.id = p_institution and p_owner = 'institution'))
      from public.platform_members pm where pm.status = 'active' and pm.platform_role = 'master_admin';
  end if;
end $$;
create or replace function public.hub_health_record(p_owner text, p_institution uuid, p_connection uuid, p_ok boolean, p_code text, p_detail text,
                                                    p_balance numeric) returns void
language sql security definer set search_path = '' as $$
  select app.health_record(p_owner, p_institution, p_connection, p_ok, p_code, p_detail, p_balance) $$;
drop function public.hub_health_record(text, uuid, uuid, boolean, text, text);
drop function app.health_record(text, uuid, uuid, boolean, text, text);

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. Delivery reports by polling; contract tests
-- ---------------------------------------------------------------------------------------------------------------------
-- Sent messages without a report after 15 minutes (up to 3 days) on connections that can be polled.
create or replace function app.poll_due(p_limit integer default 50) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('institution_id', o.institution_id, 'id', o.id, 'connection_id', o.connection_id,
           'owner', o.connection_owner, 'provider_message_id', o.provider_message_id)), '[]'::jsonb)
    from (select o.* from public.outbox o
           where o.status = 'sent' and o.provider_message_id is not null and o.sent_at between now() - interval '3 days' and now() - interval '15 minutes'
             and (exists (select 1 from public.integration_connections c where c.id = o.connection_id and c.settings ? 'status_url')
                  or exists (select 1 from public.platform_connections c where c.id = o.connection_id and c.settings ? 'status_url'))
           order by o.sent_at limit p_limit) o
$$;
create or replace function public.hub_poll_due(p_limit integer) returns jsonb
language sql stable security definer set search_path = '' as $$ select app.poll_due(p_limit) $$;

-- Settings and secret field names of one connection for the polling round (never the keys themselves).
create or replace function public.hub_connection_detail(p_connection uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select jsonb_build_object('settings', c.settings, 'secret_fields', to_jsonb(p.secret_fields))
       from public.integration_connections c join public.integration_providers p on p.key = c.provider_key where c.id = p_connection),
    (select jsonb_build_object('settings', c.settings, 'secret_fields', to_jsonb(p.secret_fields))
       from public.platform_connections c join public.integration_providers p on p.key = c.provider_key where c.id = p_connection))
$$;

-- A contract test result (I5): a failure alerts every Master Admin once a day.
create or replace function public.hub_contract_result(p_provider text, p_ok boolean, p_detail text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform app.integration_audit(null, null, case when p_ok then 'contract.passed' else 'contract.failed' end,
                                jsonb_build_object('provider', p_provider, 'detail', left(p_detail, 300)));
  if not p_ok and not exists (select 1 from public.platform_alerts where kind = 'contract_failed' and payload ->> 'provider' = p_provider
                                and created_at > now() - interval '1 day') then
    insert into public.platform_alerts (recipient_user_id, kind, payload)
    select pm.user_id, 'contract_failed', jsonb_build_object('provider', p_provider, 'detail', left(p_detail, 300))
      from public.platform_members pm where pm.status = 'active' and pm.platform_role = 'master_admin';
  end if;
end $$;

create or replace function app.hub_kick_contract() returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  return app.hub_kick('contract');
end $$;
select cron.schedule('hub-contract-tests', '13 3 * * *', 'select app.hub_kick_contract()');

-- ---------------------------------------------------------------------------------------------------------------------
-- 4. Panel: make primary (switch gateway, D33 / D34), platform fallback per institution, balance in the views
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function public.connection_make_primary(p_institution uuid, p_connection uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_kind text;
  v_old  uuid;
begin
  if not app.is_platform('platform.integrations') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  if p_institution is null then
    select kind into v_kind from public.platform_connections where id = p_connection;
    select id into v_old from public.platform_connections where kind = v_kind and priority = 1 and id <> p_connection and status = 'active' limit 1;
    update public.platform_connections set priority = least(priority + 1, 9) where kind = v_kind and id <> p_connection;
    update public.platform_connections set priority = 1, status = 'active', disabled_at = null where id = p_connection;
  else
    select kind into v_kind from public.integration_connections where institution_id = p_institution and id = p_connection;
    select id into v_old from public.integration_connections
     where institution_id = p_institution and kind = v_kind and priority = 1 and id <> p_connection and status = 'active' limit 1;
    update public.integration_connections set priority = least(priority + 1, 9)
     where institution_id = p_institution and kind = v_kind and id <> p_connection;
    update public.integration_connections set priority = 1, status = 'active', disabled_at = null where institution_id = p_institution and id = p_connection;
  end if;
  if v_kind is null then
    raise exception 'record_unknown' using errcode = 'P0404';
  end if;
  perform app.integration_audit(p_institution, p_connection, 'connection.made_primary', jsonb_build_object('previous', v_old, 'kind', v_kind));
  perform app.platform_audit('integration.primary_changed', p_institution, 'integration_connection', p_connection::text,
                             jsonb_build_object('primary', v_old), jsonb_build_object('primary', p_connection), null);
  return jsonb_build_object('primary', p_connection, 'previous', v_old);
end $$;

create or replace function public.institution_platform_fallback_set(p_institution uuid, p_kind text, p_on boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not (app.is_platform('platform.integrations') or app.is_platform('platform.billing')) then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  insert into public.institution_service_payers (institution_id, kind, payer, platform_fallback, updated_by)
  values (p_institution, p_kind, 'direct', p_on, auth.uid())
  on conflict (institution_id, kind) do update set platform_fallback = excluded.platform_fallback, updated_by = excluded.updated_by, updated_at = now();
  perform app.integration_audit(p_institution, null, 'fallback.changed', jsonb_build_object('kind', p_kind, 'platform_fallback', p_on));
  return jsonb_build_object('kind', p_kind, 'platform_fallback', p_on);
end $$;

-- Connections as seen by the panel and the institution now carry the balance (and, for the institution, the plain
-- "balance exhausted" state when it pays directly).
create or replace function app.connection_json(c jsonb, p_institution uuid, p_full boolean) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', c ->> 'id', 'kind', c ->> 'kind', 'provider', c ->> 'provider_key', 'label', c ->> 'label', 'mode', c ->> 'mode',
           'status', c ->> 'status', 'priority', (c ->> 'priority')::int, 'live_test_passed_at', c -> 'live_test_passed_at',
           'last_success_at', c -> 'last_success_at', 'last_error', c -> 'last_error',
           'provider_name', p.name, 'adapter_ready', p.adapter_version is not null,
           'circuit_open', coalesce((c ->> 'circuit_open_until')::timestamptz > now(), false),
           'balance_exhausted', coalesce((c ->> 'last_balance')::numeric <= 0, false)
             or coalesce(c -> 'last_error' ->> 'code' = 'balance_low', false),
           'masking', c -> 'settings' -> 'masking', 'route', coalesce(c -> 'settings' ->> 'route', 'all'))
         || case when p_full then jsonb_build_object('settings', c -> 'settings', 'last_balance', c -> 'last_balance',
              'balance_checked_at', c -> 'balance_checked_at',
              'secrets', app.connection_secrets(p_institution, (c ->> 'id')::uuid, p.secret_fields), 'secret_fields', to_jsonb(p.secret_fields))
            else '{}'::jsonb end
    from public.integration_providers p where p.key = c ->> 'provider_key'
$$;

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
    'fallback', coalesce((select jsonb_object_agg(p.kind, p.platform_fallback) from public.institution_service_payers p
                           where p.institution_id = p_institution), '{}'::jsonb),
    'audit', coalesce((select jsonb_agg(jsonb_build_object('action', a.action, 'at', a.at, 'by', u.email, 'detail', a.detail) order by a.at desc)
                         from (select * from public.integration_audit a where a.institution_id = p_institution order by a.at desc limit 50) a
                         left join auth.users u on u.id = a.actor_user_id), '[]'::jsonb));
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 5. Grants and registry
-- ---------------------------------------------------------------------------------------------------------------------
revoke all on function app.health_record(text, uuid, uuid, boolean, text, text, numeric), app.poll_due(integer), app.hub_kick_contract()
  from public, anon, authenticated;
grant execute on function app.health_record(text, uuid, uuid, boolean, text, text, numeric) to service_role;
revoke all on function public.hub_health_record(text, uuid, uuid, boolean, text, text, numeric), public.hub_poll_due(integer),
  public.hub_contract_result(text, boolean, text), public.hub_connection_detail(uuid) from public, anon, authenticated;
grant execute on function public.hub_health_record(text, uuid, uuid, boolean, text, text, numeric), public.hub_poll_due(integer),
  public.hub_contract_result(text, boolean, text), public.hub_connection_detail(uuid) to service_role;
revoke all on function public.connection_make_primary(uuid, uuid), public.institution_platform_fallback_set(uuid, text, boolean) from public, anon;
grant execute on function public.connection_make_primary(uuid, uuid), public.institution_platform_fallback_set(uuid, text, boolean) to authenticated;

delete from app.definer_registry where function_name in ('app.health_record', 'public.hub_health_record');
insert into app.definer_registry (function_name, reason, added_in, reviewer, tenant_check)
select f, r, '0B.13', 'architecture review 0B.13', t from (values
  ('app.health_record', 'Stores a health check with the balance and alerts below the threshold; the worker (service role) only.', 'service_role_only'),
  ('public.hub_health_record', 'Service-role wrapper of app.health_record for the Edge worker.', 'service_role_only'),
  ('app.poll_due', 'Sent messages to poll for a delivery report; the worker (service role) only.', 'service_role_only'),
  ('public.hub_poll_due', 'Service-role wrapper of app.poll_due for the Edge worker.', 'service_role_only'),
  ('public.hub_connection_detail', 'Settings and secret field names of one connection for the polling round; service role only.', 'service_role_only'),
  ('public.hub_contract_result', 'Stores a daily adapter contract test result and alerts on failure; service role only.', 'service_role_only'),
  ('app.hub_kick_contract', 'Daily: wakes the worker for the adapter contract tests.', 'service_role_only'),
  ('public.connection_make_primary', 'Makes one connection the primary (switch gateway, D33 / D34); platform.integrations + aal2; audited.', 'not_tenant_data'),
  ('public.institution_platform_fallback_set', 'Platform gateway as the last backup for one institution; platform.integrations / billing + aal2.', 'not_tenant_data')
) as v (f, r, t)
on conflict (function_name) do update set reason = excluded.reason, added_in = excluded.added_in, tenant_check = excluded.tenant_check;
