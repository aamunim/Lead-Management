-- 0B.12 Hub runtime (Ch 42.2, 42.9 I4–I8, I12; Ch 25.5; Ch 9.5, 9.7; Ch 51 lesson 2; D7, D15).
--   * outbox: every outbound SMS / email, with a priority lane (otp → urgent → transactional → bulk), an idempotency key,
--     attempts with exponential back-off (never an immediate retry), given_up after the last attempt, and items stuck
--     in "sending" marked unknown — never claimed again and never billed twice (lesson 2).
--   * Gates before anything is queued and again before sending: institution status (no SMS / bulk before approval,
--     nothing when closed or suspended), monthly limits (bulk stops at the limit, OTP and urgent pass), modules.
--   * Claiming: OTP first, then a fair share per institution, so one institution's bulk never delays another's OTP.
--   * Routing: the institution's connections by priority (0B.11 resolver), skipping open circuits and connections over
--     their per-minute rate; a failure moves to the backup and the message records the fallback (no silent fallback).
--   * Circuit breaker: three failures in a row open a connection's circuit for five minutes and alert Master Admins.
--   * delivery_log (one row per result) and usage_ledger (per institution, local day, provider, channel, category,
--     payer): only platform-paid usage is billable (D15).
--   * webhook_events: provider callbacks verified with that connection's own secret, stored once (duplicates ignored),
--     then applied to the message (I4).
--   * The worker (Edge Function hub-worker) is woken by pg_cron only when work is due, and at once for OTP / urgent.

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Data
-- ---------------------------------------------------------------------------------------------------------------------
create table public.outbox (
  institution_id       uuid not null references public.institutions (id) on delete cascade,
  id                   uuid not null default gen_random_uuid(),
  channel              text not null check (channel in ('sms', 'email')),
  priority             text not null check (priority in ('otp', 'urgent', 'transactional', 'bulk')),
  lane                 smallint not null,                 -- 1 otp … 4 bulk (claim order)
  category             text not null default 'notification' check (category in ('otp', 'notification', 'template', 'bulk', 'test')),
  recipient            text not null check (length(recipient) between 3 and 320),
  payload              jsonb not null,                    -- {body, subject?, template_key?, pin_connection?}
  idempotency_key      text not null check (length(idempotency_key) between 8 and 200),
  status               text not null default 'queued'
                       check (status in ('queued', 'held', 'sending', 'sent', 'delivered', 'undelivered', 'failed', 'given_up', 'unknown')),
  attempts             integer not null default 0,
  max_attempts         integer not null default 5 check (max_attempts between 1 and 10),
  next_attempt_at      timestamptz not null default now(),
  send_after           timestamptz,                       -- a send time in the institution's own time zone (I12)
  claimed_at           timestamptz,
  claimed_by           text,
  connection_id        uuid,
  connection_owner     text check (connection_owner in ('institution', 'platform')),
  fallback_from        uuid,                              -- the connection that failed before this one succeeded
  sandbox              boolean not null default false,
  provider_message_id  text,
  parts                integer,
  cost                 numeric(12, 4),
  error                jsonb,
  created_by           uuid references auth.users (id) on delete set null,
  created_at           timestamptz not null default now(),
  sent_at              timestamptz,
  primary key (institution_id, id),
  unique (institution_id, idempotency_key)
);
-- The worker's queue scan (due items by lane) and the callback lookup.
create index outbox_due_idx on public.outbox (institution_id, lane, next_attempt_at) where status = 'queued';
create index outbox_sending_idx on public.outbox (institution_id, claimed_at) where status = 'sending';
create index outbox_provider_msg_idx on public.outbox (institution_id, connection_id, provider_message_id) where provider_message_id is not null;
alter table public.outbox enable row level security;
revoke all on public.outbox from anon, authenticated;
create policy outbox_none on public.outbox for select to authenticated using (false);
select app.attach_status_guard('public.outbox');

create table public.delivery_log (
  institution_id       uuid not null references public.institutions (id) on delete cascade,
  id                   uuid not null default gen_random_uuid(),
  outbox_id            uuid not null,
  recipient            text not null,
  channel              text not null,
  category             text not null,
  template_key         text,
  result               text not null check (result in ('sent', 'failed', 'given_up', 'delivered', 'undelivered', 'unknown')),
  connection_id        uuid,
  connection_owner     text,
  fallback_from        uuid,
  sandbox              boolean not null default false,
  provider_message_id  text,
  parts                integer,
  cost                 numeric(12, 4),
  error                jsonb,
  at                   timestamptz not null default now(),
  primary key (institution_id, id)
);
create index delivery_log_at_idx on public.delivery_log (institution_id, at desc);
create index delivery_log_connection_idx on public.delivery_log (institution_id, connection_id, at desc);
alter table public.delivery_log enable row level security;
revoke all on public.delivery_log from anon, authenticated;
create policy delivery_log_none on public.delivery_log for select to authenticated using (false);
select app.attach_status_guard('public.delivery_log');

create table public.usage_ledger (
  institution_id  uuid not null references public.institutions (id) on delete cascade,
  day             date not null,                         -- the institution's local day (I12)
  provider        text not null,
  channel         text not null,
  category        text not null,
  payer           text not null check (payer in ('direct', 'platform')),
  count           integer not null default 0,
  parts           integer not null default 0,
  failed_parts    integer not null default 0,
  cost            numeric(14, 4) not null default 0,
  primary key (institution_id, day, provider, channel, category, payer)
);
alter table public.usage_ledger enable row level security;
revoke all on public.usage_ledger from anon, authenticated;
create policy usage_ledger_none on public.usage_ledger for select to authenticated using (false);
select app.attach_status_guard('public.usage_ledger');

-- Provider callbacks (platform-level: a platform gateway's callback has no institution until it is matched).
create table public.webhook_events (
  id               uuid primary key default gen_random_uuid(),
  institution_id   uuid references public.institutions (id) on delete cascade,
  connection_id    uuid not null,
  connection_owner text not null check (connection_owner in ('institution', 'platform')),
  provider         text not null,
  event_key        text not null,                        -- provider message id + status: a duplicate is ignored
  signature_ok     boolean not null,
  payload          jsonb not null,
  received_at      timestamptz not null default now(),
  processed_at     timestamptz,
  result           text,
  unique (connection_id, event_key)
);
alter table public.webhook_events enable row level security;
revoke all on public.webhook_events from anon, authenticated;
create policy webhook_events_none on public.webhook_events for select to authenticated using (false);

-- Circuit breaker state on both connection tables.
alter table public.integration_connections add column consecutive_failures integer not null default 0,
  add column circuit_open_until timestamptz, add column last_health_at timestamptz;
alter table public.platform_connections add column consecutive_failures integer not null default 0,
  add column circuit_open_until timestamptz, add column last_health_at timestamptz;

-- Settings the adapters need (price and rate) join the provider schemas; a callback secret for status reports.
update public.integration_providers
   set settings_schema = jsonb_set(jsonb_set(settings_schema, '{properties,price_per_part}', '{"type":"number","minimum":0,"maximum":100}'),
                                   '{properties,rate_per_minute}', '{"type":"integer","minimum":1,"maximum":100000}'),
       secret_fields = case when key = 'custom_http_sms' then '{api_key,webhook_secret}'::text[] else secret_fields end
 where key in ('custom_http_sms', 'smtp');
insert into public.integration_error_kinds (code, responsibility, sort) values
  ('no_connection', 'platform', 5), ('limit_reached', 'institution', 45), ('not_approved', 'institution', 46),
  ('invalid_recipient', 'institution', 47), ('unknown_after_timeout', 'provider', 95)
on conflict (code) do nothing;

insert into public.limit_metrics (key, period, unit, built_in, sort) values ('email_month', 'month', 'count', '0B.12', 55)
on conflict (key) do nothing;

insert into public.setting_definitions (key, scope, schema, default_value, area, description, label_key, owner_module, owner_milestone, stored_in) values
  ('hub_claim_per_institution', 'product', '{"type":"integer","minimum":1,"maximum":1000}', '20', 'platform.product_settings',
   'Messages one institution may have in one worker round (fair share, I6). Proposed: 20.',
   'settings:keys.hub_claim_per_institution', 'platform', '0B.12', 'product_settings'),
  ('hub_circuit_failures', 'product', '{"type":"integer","minimum":1,"maximum":50}', '3', 'platform.product_settings',
   'Failures in a row that open a connection''s circuit (backup used, Master Admin alerted). Proposed: 3.',
   'settings:keys.hub_circuit_failures', 'platform', '0B.12', 'product_settings')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. Helpers
-- ---------------------------------------------------------------------------------------------------------------------
-- SMS parts: GSM-7 text 160 (153 per part when split), anything else (Bangla) 70 (67).
create or replace function app.sms_parts(p_body text) returns integer
language sql immutable set search_path = '' as $$
  select case when p_body is null or p_body = '' then 1
              when p_body ~ '^[A-Za-z0-9 @£$¥èéùìòÇØøÅå_^{}\[~\]|€ÆæßÉ!"#¤%&''()*+,\-./:;<=>?¡ÄÖÑÜ§¿äöñüà\n\r]*$'
                then case when length(p_body) <= 160 then 1 else ceil(length(p_body) / 153.0)::int end
              else case when length(p_body) <= 70 then 1 else ceil(length(p_body) / 67.0)::int end end
$$;

-- The institution's local day and a local clock time as an instant (I12): sends and the ledger follow its time zone.
create or replace function app.institution_tz(p_institution uuid) returns text
language sql stable security definer set search_path = '' as $$
  select coalesce(app.setting_value(p_institution, 'time_zone') #>> '{}', 'UTC')
$$;
create or replace function app.institution_local_day(p_institution uuid, p_at timestamptz default now()) returns date
language sql stable security definer set search_path = '' as $$
  select (p_at at time zone app.institution_tz(p_institution))::date
$$;
create or replace function app.institution_local_instant(p_institution uuid, p_day date, p_time time) returns timestamptz
language sql stable security definer set search_path = '' as $$
  select (p_day + p_time) at time zone app.institution_tz(p_institution)
$$;

-- May this message be sent now? null = yes; otherwise the reason (an error kind).
create or replace function app.outbox_gate(p_institution uuid, p_channel text, p_priority text, p_parts integer) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_status text := (select status from public.institutions where id = p_institution);
  v_limit  jsonb;
begin
  if v_status is null or v_status in ('closed', 'suspended') then
    return 'not_approved';
  end if;
  -- Before approval only sign-in codes go out (0B.09-T8).
  if p_priority <> 'otp' and not app.institution_can_message(p_institution) then
    return 'not_approved';
  end if;
  v_limit := app.check_limit(p_institution, case p_channel when 'sms' then 'sms_month' else 'email_month' end,
                             greatest(coalesce(p_parts, 1), 1), p_priority, false);
  if v_limit ->> 'level' = 'blocked' then
    return 'limit_reached';
  end if;
  return null;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. Queueing (called by product code — notify() in 1B, OTP sign-in in 0B.18 — and the panel's Test button)
-- ---------------------------------------------------------------------------------------------------------------------
-- The same idempotency key returns the first message (a retried request never sends twice).
create or replace function app.outbox_enqueue(p_institution uuid, p_channel text, p_priority text, p_recipient text, p_payload jsonb,
                                              p_idempotency_key text, p_category text default null, p_send_after timestamptz default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_row   public.outbox;
  v_parts integer := case when p_channel = 'sms' then app.sms_parts(p_payload ->> 'body') else 1 end;
  v_gate  text;
begin
  select * into v_row from public.outbox where institution_id = p_institution and idempotency_key = p_idempotency_key;
  if found then
    return jsonb_build_object('id', v_row.id, 'status', v_row.status, 'repeated', true);
  end if;
  if p_channel not in ('sms', 'email') or p_priority not in ('otp', 'urgent', 'transactional', 'bulk')
     or coalesce(btrim(p_recipient), '') = '' or coalesce(p_payload ->> 'body', '') = '' then
    raise exception 'outbox_invalid' using errcode = 'P0422';
  end if;
  v_gate := app.outbox_gate(p_institution, p_channel, p_priority, v_parts);
  if v_gate is not null then
    raise exception '%', v_gate using errcode = case v_gate when 'limit_reached' then 'P0429' else 'P0403' end;
  end if;
  insert into public.outbox (institution_id, channel, priority, lane, category, recipient, payload, idempotency_key, next_attempt_at,
                             send_after, created_by)
  values (p_institution, p_channel, p_priority, case p_priority when 'otp' then 1 when 'urgent' then 2 when 'transactional' then 3 else 4 end,
          coalesce(p_category, case p_priority when 'otp' then 'otp' when 'bulk' then 'bulk' else 'notification' end),
          btrim(p_recipient), p_payload, p_idempotency_key, greatest(now(), coalesce(p_send_after, now())), p_send_after, auth.uid())
  returning * into v_row;
  return jsonb_build_object('id', v_row.id, 'status', v_row.status, 'repeated', false);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 4. The worker side (service role only)
-- ---------------------------------------------------------------------------------------------------------------------
-- Claim due messages: items stuck in "sending" become "unknown" first (never re-claimed, never re-billed); then OTP of
-- every institution, then the rest with a fair share per institution (I6). Bulk of an institution at its monthly limit
-- is held, not sent (OTP and urgent pass).
create or replace function app.outbox_claim(p_worker text, p_limit integer default 50, p_lanes smallint[] default '{1,2,3,4}')
returns setof public.outbox language plpgsql security definer set search_path = '' as $$
declare
  v_share integer := (app.product_setting('hub_claim_per_institution'))::integer;
begin
  update public.outbox o set status = 'unknown', error = jsonb_build_object('code', 'unknown_after_timeout', 'at', now())
   where o.status = 'sending' and o.claimed_at < now() - interval '10 minutes';
  insert into public.delivery_log (institution_id, outbox_id, recipient, channel, category, template_key, result, connection_id, connection_owner, error)
  select o.institution_id, o.id, o.recipient, o.channel, o.category, o.payload ->> 'template_key', 'unknown', o.connection_id, o.connection_owner, o.error
    from public.outbox o
   where o.status = 'unknown' and o.error ->> 'code' = 'unknown_after_timeout' and (o.error ->> 'at')::timestamptz >= now()
     and not exists (select 1 from public.delivery_log d where d.institution_id = o.institution_id and d.outbox_id = o.id and d.result = 'unknown');

  return query
  with due as (
    select o.institution_id, o.id, o.lane,
           row_number() over (partition by o.institution_id order by o.lane, o.next_attempt_at) as rn
      from public.outbox o
     where o.status = 'queued' and o.next_attempt_at <= now() and o.lane = any (p_lanes)),
  picked as (
    select d.institution_id, d.id from due d
     where d.lane = 1 or d.rn <= v_share
     order by d.lane, d.rn
     limit p_limit),
  locked as (
    select o.institution_id, o.id from public.outbox o join picked p using (institution_id, id)
     where o.status = 'queued' for update of o skip locked)
  update public.outbox o set status = 'sending', claimed_at = now(), claimed_by = left(p_worker, 100), attempts = o.attempts + 1
    from locked l where o.institution_id = l.institution_id and o.id = l.id
  returning o.*;
end $$;

-- The connections to try for one claimed message: the 0B.11 resolver (institution from the message itself, I1), a
-- pinned connection for the panel's Test, without open circuits or connections over their per-minute rate.
create or replace function app.outbox_route(p_institution uuid, p_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_msg  public.outbox;
  v_gate text;
  v_all  jsonb;
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
  v_all := app.resolve_connection(p_institution, v_msg.channel, case v_msg.priority when 'bulk' then 'bulk' else 'send' end);
  return jsonb_build_object('gate', null, 'channel', v_msg.channel, 'connections', coalesce((
    select jsonb_agg(c || jsonb_build_object('secret_fields', to_jsonb(p.secret_fields)) order by ord)
      from jsonb_array_elements(v_all) with ordinality as x (c, ord)
      join public.integration_providers p on p.key = c ->> 'provider'
     where (v_msg.payload ->> 'pin_connection' is null or c ->> 'id' = v_msg.payload ->> 'pin_connection')
       and not exists (select 1 from public.integration_connections ic where ic.id = (c ->> 'id')::uuid and ic.circuit_open_until > now())
       and not exists (select 1 from public.platform_connections pc where pc.id = (c ->> 'id')::uuid and pc.circuit_open_until > now())
       and (c -> 'settings' ->> 'rate_per_minute' is null
            or (select count(*) from public.delivery_log d where d.connection_id = (c ->> 'id')::uuid and d.at > now() - interval '1 minute')
               < (c -> 'settings' ->> 'rate_per_minute')::int)), '[]'::jsonb));
end $$;

-- One connection's success or failure: last result (0B.11), failures in a row, the circuit and its alert.
create or replace function app.connection_outcome(p_institution uuid, p_owner text, p_connection uuid, p_ok boolean, p_code text, p_detail text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_fail   integer;
  v_open   boolean := false;
  v_limit  integer := (app.product_setting('hub_circuit_failures'))::integer;
  v_label  text;
begin
  perform app.connection_record_result(case p_owner when 'institution' then p_institution end, p_connection, p_ok, p_code, p_detail);
  if p_owner = 'institution' then
    update public.integration_connections set consecutive_failures = case when p_ok then 0 else consecutive_failures + 1 end,
           circuit_open_until = case when p_ok then null else circuit_open_until end
     where institution_id = p_institution and id = p_connection returning consecutive_failures, label into v_fail, v_label;
    if not p_ok and v_fail >= v_limit then
      update public.integration_connections set circuit_open_until = now() + interval '5 minutes'
       where institution_id = p_institution and id = p_connection and (circuit_open_until is null or circuit_open_until < now());
      v_open := found;
    end if;
  else
    update public.platform_connections set consecutive_failures = case when p_ok then 0 else consecutive_failures + 1 end,
           circuit_open_until = case when p_ok then null else circuit_open_until end
     where id = p_connection returning consecutive_failures, label into v_fail, v_label;
    if not p_ok and v_fail >= v_limit then
      update public.platform_connections set circuit_open_until = now() + interval '5 minutes'
       where id = p_connection and (circuit_open_until is null or circuit_open_until < now());
      v_open := found;
    end if;
  end if;
  if v_open then
    insert into public.platform_alerts (recipient_user_id, kind, payload)
    select pm.user_id, 'circuit_open', jsonb_build_object('institution_id', case p_owner when 'institution' then p_institution end,
             'connection_id', p_connection, 'label', v_label, 'code', p_code,
             'name', (select i.name from public.institutions i where i.id = p_institution and p_owner = 'institution'))
      from public.platform_members pm where pm.status = 'active' and pm.platform_role = 'master_admin';
    perform app.integration_audit(case p_owner when 'institution' then p_institution end, p_connection, 'connection.circuit_opened',
                                  jsonb_build_object('failures', v_fail, 'code', p_code));
  end if;
end $$;

-- The final result of one message (after the worker tried its connections): delivery log, ledger, usage counter.
-- Failure: back-off and retry (never at once) until the last attempt, then given_up. Called once per claimed attempt.
create or replace function app.outbox_result(p_institution uuid, p_id uuid, p_ok boolean, p_connection uuid, p_owner text, p_provider text,
                                             p_provider_message_id text default null, p_error_code text default null, p_detail text default null,
                                             p_fallback_from uuid default null, p_sandbox boolean default false) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_msg      public.outbox;
  v_parts    integer;
  v_price    numeric;
  v_cost     numeric;
  v_payer    text;
  v_status   text;
  v_error    jsonb;
  v_hold     boolean := p_error_code in ('limit_reached', 'not_approved');
begin
  select * into v_msg from public.outbox where institution_id = p_institution and id = p_id for update;
  -- Only a message this worker is sending gets a result (a late or repeated result changes nothing, is not billed).
  if not found or v_msg.status <> 'sending' then
    return 'ignored';
  end if;
  v_parts := case when v_msg.channel = 'sms' then app.sms_parts(v_msg.payload ->> 'body') else 1 end;
  v_payer := case when p_owner = 'platform' then 'platform' else 'direct' end;
  if p_ok then
    v_price := coalesce((select (settings ->> 'price_per_part')::numeric from public.integration_connections where id = p_connection),
                        (select (settings ->> 'price_per_part')::numeric from public.platform_connections where id = p_connection), 0);
    v_cost := case when p_sandbox then 0 else v_price * v_parts end;
    update public.outbox set status = 'sent', sent_at = now(), connection_id = p_connection, connection_owner = p_owner,
           provider_message_id = p_provider_message_id, parts = v_parts, cost = v_cost, fallback_from = p_fallback_from, sandbox = p_sandbox,
           error = null
     where institution_id = p_institution and id = p_id;
    v_status := 'sent';
    if not p_sandbox then
      perform app.usage_add(p_institution, case v_msg.channel when 'sms' then 'sms_month' else 'email_month' end, v_parts);
    end if;
  else
    v_error := jsonb_build_object('code', coalesce(p_error_code, 'adapter_error'), 'detail', left(p_detail, 300), 'at', now(),
      'responsibility', coalesce((select responsibility from public.integration_error_kinds where code = p_error_code), 'platform'));
    if v_hold then
      -- A gate closed after queueing: held until it opens (checked again every hour), attempts not used up.
      update public.outbox set status = 'held', attempts = attempts - 1, error = v_error, next_attempt_at = now() + interval '1 hour'
       where institution_id = p_institution and id = p_id;
      return 'held';
    elsif v_msg.attempts >= v_msg.max_attempts then
      update public.outbox set status = 'given_up', error = v_error, connection_id = p_connection, connection_owner = p_owner
       where institution_id = p_institution and id = p_id;
      v_status := 'given_up';
    else
      -- Exponential back-off: 30 s, 1, 2, 4 … minutes, at most an hour; never an immediate retry.
      update public.outbox set status = 'queued', error = v_error,
             next_attempt_at = now() + least(interval '1 hour', interval '30 seconds' * power(2, v_msg.attempts - 1))
       where institution_id = p_institution and id = p_id;
      v_status := 'failed';
    end if;
  end if;
  insert into public.delivery_log (institution_id, outbox_id, recipient, channel, category, template_key, result, connection_id, connection_owner,
                                   fallback_from, sandbox, provider_message_id, parts, cost, error)
  values (p_institution, p_id, v_msg.recipient, v_msg.channel, v_msg.category, v_msg.payload ->> 'template_key', v_status, p_connection, p_owner,
          p_fallback_from, p_sandbox, p_provider_message_id, case when p_ok then v_parts end, v_cost, v_error);
  if p_provider is not null and (p_ok or v_status = 'given_up') then
    insert into public.usage_ledger as l (institution_id, day, provider, channel, category, payer, count, parts, failed_parts, cost)
    values (p_institution, app.institution_local_day(p_institution), p_provider, v_msg.channel, v_msg.category, v_payer,
            case when p_ok then 1 else 0 end, case when p_ok then v_parts else 0 end, case when p_ok then 0 else v_parts end, coalesce(v_cost, 0))
    on conflict (institution_id, day, provider, channel, category, payer) do update
      set count = l.count + excluded.count, parts = l.parts + excluded.parts, failed_parts = l.failed_parts + excluded.failed_parts,
          cost = l.cost + excluded.cost;
  end if;
  return v_status;
end $$;

-- Held messages whose gate has opened again go back to the queue (hourly).
create or replace function app.outbox_release_held() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_count integer;
begin
  update public.outbox o set status = 'queued', next_attempt_at = now()
   where o.status = 'held' and o.next_attempt_at <= now()
     and app.outbox_gate(o.institution_id, o.channel, o.priority, case when o.channel = 'sms' then app.sms_parts(o.payload ->> 'body') else 1 end) is null;
  get diagnostics v_count = row_count;
  update public.outbox o set next_attempt_at = now() + interval '1 hour' where o.status = 'held' and o.next_attempt_at <= now();
  return v_count;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 5. Callbacks (I4): the router (Edge Function hub-webhook) finds the connection, verifies that connection's own
--    secret, then records the event once and applies it. A forged callback is stored as such and changes nothing.
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function app.webhook_connection(p_connection uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select jsonb_build_object('owner', 'institution', 'institution_id', c.institution_id, 'id', c.id, 'provider', c.provider_key, 'status', c.status)
       from public.integration_connections c where c.id = p_connection),
    (select jsonb_build_object('owner', 'platform', 'institution_id', null, 'id', c.id, 'provider', c.provider_key, 'status', c.status)
       from public.platform_connections c where c.id = p_connection))
$$;

create or replace function app.webhook_record(p_connection uuid, p_signature_ok boolean, p_event_key text, p_payload jsonb,
                                              p_provider_message_id text default null, p_status text default null) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_conn    jsonb := app.webhook_connection(p_connection);
  v_event   uuid;
  v_msg     public.outbox;
  v_result  text;
begin
  if v_conn is null then
    return 'unknown_connection';
  end if;
  insert into public.webhook_events (institution_id, connection_id, connection_owner, provider, event_key, signature_ok, payload)
  values ((v_conn ->> 'institution_id')::uuid, p_connection, v_conn ->> 'owner', v_conn ->> 'provider', left(p_event_key, 300), p_signature_ok,
          app.redact_secrets(p_payload))
  on conflict (connection_id, event_key) do nothing
  returning id into v_event;
  if v_event is null then
    return 'duplicate';
  end if;
  if not p_signature_ok then
    update public.webhook_events set processed_at = now(), result = 'rejected' where id = v_event;
    return 'rejected';
  end if;
  -- Match the message sent through this very connection (a platform gateway serves many institutions).
  select * into v_msg from public.outbox o
   where o.connection_id = p_connection and o.provider_message_id = p_provider_message_id
     and (v_conn ->> 'owner' = 'platform' or o.institution_id = (v_conn ->> 'institution_id')::uuid)
   limit 1;
  if not found then
    v_result := 'pending';                               -- the send result may still be on its way: kept for reconciliation
  elsif p_status in ('delivered', 'undelivered') then
    update public.outbox set status = p_status where institution_id = v_msg.institution_id and id = v_msg.id and status in ('sent', 'unknown');
    insert into public.delivery_log (institution_id, outbox_id, recipient, channel, category, template_key, result, connection_id, connection_owner,
                                     provider_message_id)
    values (v_msg.institution_id, v_msg.id, v_msg.recipient, v_msg.channel, v_msg.category, v_msg.payload ->> 'template_key', p_status,
            p_connection, v_conn ->> 'owner', p_provider_message_id);
    v_result := p_status;
  else
    v_result := 'ignored';
  end if;
  update public.webhook_events set processed_at = case when v_result = 'pending' then null else now() end, result = v_result,
         institution_id = coalesce(institution_id, v_msg.institution_id)
   where id = v_event;
  return v_result;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 6. Waking the worker: only when work is due (lesson 2), at once for OTP / urgent. The URL and key are stored in
--    Vault by the deploy (names hub_worker_url, hub_worker_key); without them (local, CI) nothing is called.
-- ---------------------------------------------------------------------------------------------------------------------
create extension if not exists pg_net with schema extensions;

create or replace function app.hub_kick(p_lane text default 'all') returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  v_url text := (select decrypted_secret from vault.decrypted_secrets where name = 'hub_worker_url');
  v_key text := (select decrypted_secret from vault.decrypted_secrets where name = 'hub_worker_key');
begin
  if v_url is null or v_key is null then
    return false;
  end if;
  perform net.http_post(url := v_url, body := jsonb_build_object('lane', p_lane),
                        headers := jsonb_build_object('Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json'));
  return true;
end $$;

create or replace function app.hub_kick_if_due() returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  perform app.outbox_release_held();
  if exists (select 1 from public.outbox where status = 'queued' and next_attempt_at <= now())
     or exists (select 1 from public.outbox where status = 'sending' and claimed_at < now() - interval '10 minutes') then
    return app.hub_kick('all');
  end if;
  return false;
end $$;

create or replace function app.outbox_kick_now() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform app.hub_kick('otp');
  return null;
end $$;
create trigger outbox_kick_now after insert on public.outbox
  for each row when (new.lane <= 2 and new.send_after is null) execute function app.outbox_kick_now();

select cron.schedule('hub-worker-kick', '* * * * *', 'select app.hub_kick_if_due()');

-- ---------------------------------------------------------------------------------------------------------------------
-- 7. Panel: the Test button, the delivery log and the ledger (platform staff); health of every connection
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function public.platform_connection_test(p_institution uuid, p_connection uuid, p_recipient text, p_body text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_channel text;
begin
  if not app.is_platform('platform.integrations') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  select kind into v_channel from public.integration_connections where institution_id = p_institution and id = p_connection;
  if v_channel is null or v_channel not in ('sms', 'email') then
    raise exception 'connection_invalid' using errcode = 'P0422', detail = 'only SMS and email connections can be tested here';
  end if;
  perform app.integration_audit(p_institution, p_connection, 'connection.test_sent', jsonb_build_object('recipient', p_recipient));
  -- A test is urgent (allowed before approval only for OTP; tests of a pending institution wait until approval).
  return app.outbox_enqueue(p_institution, v_channel, 'urgent', p_recipient,
           jsonb_build_object('body', coalesce(nullif(btrim(p_body), ''), 'Test message'), 'subject', 'Test', 'pin_connection', p_connection),
           'test:' || gen_random_uuid(), 'test');
end $$;

create or replace function public.platform_delivery_log(p_institution uuid default null, p_channel text default null, p_result text default null,
                                                        p_limit integer default 100) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not app.is_platform('platform.view') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'institution_id', d.institution_id, 'institution', i.name, 'recipient', d.recipient,
                     'channel', d.channel, 'category', d.category, 'template_key', d.template_key, 'result', d.result, 'at', d.at,
                     'connection', coalesce(ic.label, pc.label), 'fallback', d.fallback_from is not null, 'sandbox', d.sandbox,
                     'provider_message_id', d.provider_message_id, 'parts', d.parts, 'cost', d.cost, 'error', d.error) order by d.at desc)
    from (select * from public.delivery_log d
           where (p_institution is null or d.institution_id = p_institution) and (p_channel is null or d.channel = p_channel)
             and (p_result is null or d.result = p_result)
           order by d.at desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) d
    join public.institutions i on i.id = d.institution_id
    left join public.integration_connections ic on ic.id = d.connection_id
    left join public.platform_connections pc on pc.id = d.connection_id), '[]'::jsonb);
end $$;

create or replace function public.platform_usage_ledger(p_institution uuid default null, p_from date default null, p_to date default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not (app.is_platform('platform.view')) then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('institution_id', l.institution_id, 'institution', i.name, 'day', l.day, 'provider', l.provider,
                     'channel', l.channel, 'category', l.category, 'payer', l.payer, 'count', l.count, 'parts', l.parts,
                     'failed_parts', l.failed_parts, 'cost', l.cost, 'billable', l.payer = 'platform') order by l.day desc, i.name, l.channel)
    from public.usage_ledger l join public.institutions i on i.id = l.institution_id
   where (p_institution is null or l.institution_id = p_institution)
     and l.day between coalesce(p_from, current_date - 31) and coalesce(p_to, current_date + 1)), '[]'::jsonb);
end $$;

-- Health: connections due for a check (hourly) for the worker's health round; results go through connection_outcome.
create or replace function app.health_due(p_limit integer default 20) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(x), '[]'::jsonb) from (
    select jsonb_build_object('owner', 'institution', 'institution_id', c.institution_id, 'id', c.id, 'provider', c.provider_key,
             'settings', c.settings, 'mode', c.mode, 'secret_fields', to_jsonb(p.secret_fields)) as x
      from public.integration_connections c join public.integration_providers p on p.key = c.provider_key
     where c.status = 'active' and c.kind in ('sms', 'email') and (c.last_health_at is null or c.last_health_at < now() - interval '1 hour')
    union all
    select jsonb_build_object('owner', 'platform', 'institution_id', null, 'id', c.id, 'provider', c.provider_key,
             'settings', c.settings, 'mode', c.mode, 'secret_fields', to_jsonb(p.secret_fields))
      from public.platform_connections c join public.integration_providers p on p.key = c.provider_key
     where c.status = 'active' and c.kind in ('sms', 'email') and (c.last_health_at is null or c.last_health_at < now() - interval '1 hour')
    limit p_limit) y
$$;
create or replace function app.health_record(p_owner text, p_institution uuid, p_connection uuid, p_ok boolean, p_code text, p_detail text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if p_owner = 'institution' then
    update public.integration_connections set last_health_at = now() where institution_id = p_institution and id = p_connection;
  else
    update public.platform_connections set last_health_at = now() where id = p_connection;
  end if;
  perform app.connection_outcome(p_institution, p_owner, p_connection, p_ok, p_code, p_detail);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 8. Grants and registry
-- ---------------------------------------------------------------------------------------------------------------------
revoke all on function app.institution_tz(uuid), app.institution_local_day(uuid, timestamptz), app.institution_local_instant(uuid, date, time),
  app.outbox_gate(uuid, text, text, integer), app.outbox_enqueue(uuid, text, text, text, jsonb, text, text, timestamptz),
  app.outbox_claim(text, integer, smallint[]), app.outbox_route(uuid, uuid), app.connection_outcome(uuid, text, uuid, boolean, text, text),
  app.outbox_result(uuid, uuid, boolean, uuid, text, text, text, text, text, uuid, boolean), app.outbox_release_held(),
  app.webhook_connection(uuid), app.webhook_record(uuid, boolean, text, jsonb, text, text), app.hub_kick(text), app.hub_kick_if_due(),
  app.outbox_kick_now(), app.health_due(integer), app.health_record(text, uuid, uuid, boolean, text, text) from public, anon, authenticated;
grant execute on function app.outbox_enqueue(uuid, text, text, text, jsonb, text, text, timestamptz), app.outbox_claim(text, integer, smallint[]),
  app.outbox_route(uuid, uuid), app.connection_outcome(uuid, text, uuid, boolean, text, text),
  app.outbox_result(uuid, uuid, boolean, uuid, text, text, text, text, text, uuid, boolean),
  app.webhook_connection(uuid), app.webhook_record(uuid, boolean, text, jsonb, text, text), app.health_due(integer),
  app.health_record(text, uuid, uuid, boolean, text, text) to service_role;
revoke all on function public.platform_connection_test(uuid, uuid, text, text), public.platform_delivery_log(uuid, text, text, integer),
  public.platform_usage_ledger(uuid, date, date) from public, anon;
grant execute on function public.platform_connection_test(uuid, uuid, text, text), public.platform_delivery_log(uuid, text, text, integer),
  public.platform_usage_ledger(uuid, date, date) to authenticated;

insert into app.definer_registry (function_name, reason, added_in, reviewer, tenant_check)
select f, r, '0B.12', 'architecture review 0B.12', t from (values
  ('app.institution_tz', 'The institution''s time zone setting; called by the hub internals only.', 'service_role_only'),
  ('app.institution_local_day', 'The institution''s local date (ledger days); hub internals only.', 'service_role_only'),
  ('app.institution_local_instant', 'A local clock time of the institution as an instant (send times, I12); hub internals only.', 'service_role_only'),
  ('app.outbox_gate', 'May one institution send now (status, approval, monthly limit); hub internals only.', 'service_role_only'),
  ('app.outbox_enqueue', 'Queues one message for the institution given by the calling server code (never by a client); service role.', 'service_role_only'),
  ('app.outbox_claim', 'The worker claims due messages (OTP first, fair share); service role only.', 'service_role_only'),
  ('app.outbox_route', 'Connections for one claimed message, institution from the message (I1); service role only.', 'service_role_only'),
  ('app.connection_outcome', 'Records a connection result, failures in a row and the circuit; service role only.', 'service_role_only'),
  ('app.outbox_result', 'Final result of one claimed message: status, delivery log, ledger, usage; service role only.', 'service_role_only'),
  ('app.outbox_release_held', 'Hourly: held messages whose gate opened go back to the queue.', 'service_role_only'),
  ('app.webhook_connection', 'The connection a callback URL names; the webhook router (service role) only.', 'service_role_only'),
  ('app.webhook_record', 'Stores a provider callback once and applies it to the matching message; service role only.', 'service_role_only'),
  ('app.hub_kick', 'Wakes the worker through pg_net with the key held in Vault.', 'service_role_only'),
  ('app.hub_kick_if_due', 'Every minute: wakes the worker only when work is due (lesson 2).', 'service_role_only'),
  ('app.outbox_kick_now', 'Trigger: an OTP / urgent message wakes the worker at once.', 'service_role_only'),
  ('app.health_due', 'Connections due for a health check; the worker (service role) only.', 'service_role_only'),
  ('app.health_record', 'Stores a health check result; the worker (service role) only.', 'service_role_only'),
  ('public.platform_connection_test', 'Queues a test message through one connection; platform.integrations + aal2; audited.', 'not_tenant_data'),
  ('public.platform_delivery_log', 'Delivery log for the panel, filtered by institution / channel / result; platform.view + aal2.', 'not_tenant_data'),
  ('public.platform_usage_ledger', 'Usage ledger for the panel (billable = platform-paid, D15); platform.view + aal2.', 'not_tenant_data')
) as v (f, r, t)
on conflict (function_name) do update set reason = excluded.reason, added_in = excluded.added_in, tenant_check = excluded.tenant_check;

-- The circuit: the resolver leaves out a connection whose circuit is open (the backup is used and noted).
-- (outbox_route already filters; resolve_connection stays the 0B.11 contract.)
