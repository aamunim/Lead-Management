-- 0B.12 tests: idempotent queueing; gates (approval, closed, monthly limit — bulk stops, OTP passes); claim order (OTP
-- first, fair share) with 20,000 queued bulk messages; routing from the message's own institution (I1), backup on
-- failure noted (no silent fallback), circuit breaker with an alert; back-off (never immediate), given_up, stuck items
-- unknown and never re-billed; ledger by payer in the local day; callbacks verified, stored once, applied; isolation.
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
\set inst_b '''b0000000-0000-4000-8000-00000000000b'''
\set owner '''77777777-7777-4777-8777-777777777777'''
\set master '''55555555-5555-4555-8555-555555555555'''

-- Connections: A has a primary and a backup mock gateway (price 0.25 per part); B has one; the platform has one.
insert into public.integration_connections (institution_id, id, kind, provider_key, label, mode, settings, priority) values
  (:inst_a, 'c1000000-0000-4000-8000-0000000000a1', 'sms', 'mock_sms', 'A main', 'live', '{"price_per_part":0.25}', 1),
  (:inst_a, 'c1000000-0000-4000-8000-0000000000a2', 'sms', 'mock_sms', 'A backup', 'live', '{"price_per_part":0.30}', 2),
  (:inst_b, 'c1000000-0000-4000-8000-0000000000b1', 'sms', 'mock_sms', 'B main', 'live', '{"price_per_part":0.20,"rate_per_minute":1}', 1);
update public.integration_connections set live_test_passed_at = now() where provider_key = 'mock_sms';
insert into public.platform_connections (id, kind, provider_key, label, mode, settings) values
  ('c1000000-0000-4000-8000-0000000000f1', 'email', 'mock_email', 'Platform mail', 'live', '{"price_per_part":0.01}');
update public.platform_connections set live_test_passed_at = now();

set local role service_role;
-- 1. Queueing is idempotent; a pending institution sends only OTP; the payload is checked.
insert into out select 'm1', app.outbox_enqueue(:inst_a, 'sms', 'transactional', '01711000001', '{"body":"Your fee is received"}', 'idem-key-0001');
insert into out select 'm1b', app.outbox_enqueue(:inst_a, 'sms', 'transactional', '01711000001', '{"body":"Your fee is received"}', 'idem-key-0001');
reset role;
select pg_temp.check(pg_temp.v('m1') ->> 'id' = pg_temp.v('m1b') ->> 'id' and (pg_temp.v('m1b') ->> 'repeated')::boolean
  and (select count(*) from public.outbox where idempotency_key = 'idem-key-0001') = 1, 'the same idempotency key queues once');
update public.institutions set status = 'pending' where id = :inst_b;
set local role service_role;
select pg_temp.check(pg_temp.error_of(format('select app.outbox_enqueue(%L, ''sms'', ''bulk'', ''01711000002'', ''{"body":"Offer"}'', ''pend-bulk-001'')', :inst_b))
  = 'not_approved', 'no bulk before approval');
select pg_temp.check(pg_temp.error_of(format('select app.outbox_enqueue(%L, ''sms'', ''otp'', ''01711000002'', ''{"body":"Code 1234"}'', ''pend-otp-0001'')', :inst_b))
  = '', 'a sign-in code goes out before approval');
reset role;
update public.institutions set status = 'active' where id = :inst_b;
select pg_temp.check(app.sms_parts('Hello') = 1 and app.sms_parts(repeat('a', 161)) = 2 and app.sms_parts('আপনার ফি জমা হয়েছে') = 1
  and app.sms_parts(repeat('ক', 71)) = 2, 'SMS parts: 160 / 153 for plain text, 70 / 67 for Bangla');

-- 2. Monthly limit: bulk stops, OTP and urgent pass (Proposed placeholders of the plan; limit set to 2 here).
update public.institution_plan set limit_overrides = limit_overrides || '{"sms_month": 2}' where institution_id = :inst_b;
insert into public.usage_counters (institution_id, metric, period, value) values (:inst_b, 'sms_month', app.usage_period(:inst_b, 'sms_month'), 2)
on conflict (institution_id, metric, period) do update set value = 2;
set local role service_role;
select pg_temp.check(pg_temp.error_of(format('select app.outbox_enqueue(%L, ''sms'', ''bulk'', ''01711000003'', ''{"body":"Offer"}'', ''limit-bulk-01'')', :inst_b))
  = 'limit_reached' and pg_temp.error_of(format('select app.outbox_enqueue(%L, ''sms'', ''urgent'', ''01711000003'', ''{"body":"Office closed"}'', ''limit-urg-001'')', :inst_b)) = '',
  'at the monthly limit bulk stops, urgent still goes');
reset role;
update public.institution_plan set limit_overrides = limit_overrides - 'sms_month' where institution_id = :inst_b;

-- 3. 20,000 bulk messages of A are queued; B's OTP is in the very first worker round (I6, lane 1 first).
insert into public.outbox (institution_id, channel, priority, lane, category, recipient, payload, idempotency_key, next_attempt_at)
select :inst_a, 'sms', 'bulk', 4, 'bulk', '0171' || lpad(g::text, 7, '0'), '{"body":"Admission open"}', 'bulk-key-' || g, now() - interval '1 minute'
  from generate_series(1, 20000) g;
set local role service_role;
select app.outbox_enqueue(:inst_b, 'sms', 'otp', '01711000009', '{"body":"Code 5678"}', 'otp-b-000001');
create temp table round1 as select * from app.outbox_claim('test-worker', 50);
reset role;
select pg_temp.check(exists (select 1 from round1 where institution_id = :inst_b and priority = 'otp')
  and (select count(*) from round1 where institution_id = :inst_a) <= (app.product_setting('hub_claim_per_institution'))::int,
  'OTP of another institution is in the first round; one institution gets only its fair share');
update public.outbox set status = 'queued', claimed_at = null, attempts = 0 where id in (select id from round1 where priority = 'bulk');
delete from public.outbox where idempotency_key like 'bulk-key-%';

-- 4. Routing (I1): each message uses its own institution's connections, primary first; a pinned test connection.
set local role service_role;
create temp table round2 as select * from app.outbox_claim('test-worker', 50);
reset role;
insert into out select 'a_msg', to_jsonb((select id from public.outbox where institution_id = :inst_a and idempotency_key = 'idem-key-0001' and status = 'sending'));
insert into out select 'b_msg', to_jsonb((select id from public.outbox where institution_id = :inst_b and idempotency_key = 'otp-b-000001' and status = 'sending'));
set local role service_role;
insert into out select 'route_a2', app.outbox_route(:inst_a, (pg_temp.v('a_msg') #>> '{}')::uuid);
insert into out select 'route_b', app.outbox_route(:inst_b, (pg_temp.v('b_msg') #>> '{}')::uuid);
reset role;
select pg_temp.check(pg_temp.v('route_a2') -> 'connections' -> 0 ->> 'id' = 'c1000000-0000-4000-8000-0000000000a1'
  and pg_temp.v('route_a2') -> 'connections' -> 1 ->> 'id' = 'c1000000-0000-4000-8000-0000000000a2'
  and pg_temp.v('route_b') -> 'connections' -> 0 ->> 'id' = 'c1000000-0000-4000-8000-0000000000b1'
  and jsonb_array_length(pg_temp.v('route_b') -> 'connections') = 1, 'each message routes through its own institution''s connections (I1)');

-- 5. Primary fails, backup succeeds: the message records the fallback; delivery log, ledger and usage follow.
set local role service_role;
select app.connection_outcome(:inst_a, 'institution', 'c1000000-0000-4000-8000-0000000000a1', false, 'provider_down', 'HTTP 503');
insert into out select 'res_a', to_jsonb(app.outbox_result(:inst_a, (pg_temp.v('a_msg') #>> '{}')::uuid, true, 'c1000000-0000-4000-8000-0000000000a2',
  'institution', 'mock_sms', 'mock-msg-0001', null, null, 'c1000000-0000-4000-8000-0000000000a1'));
select app.connection_outcome(:inst_a, 'institution', 'c1000000-0000-4000-8000-0000000000a2', true, null, null);
reset role;
select pg_temp.check((select status = 'sent' and fallback_from = 'c1000000-0000-4000-8000-0000000000a1' and cost = 0.30 and parts = 1
  from public.outbox where id = (pg_temp.v('a_msg') #>> '{}')::uuid)
  and exists (select 1 from public.delivery_log where outbox_id = (pg_temp.v('a_msg') #>> '{}')::uuid and result = 'sent' and fallback_from is not null),
  'the backup sent it and the fallback is on the message and in the log (no silent fallback)');
select pg_temp.check((select count = 1 and parts = 1 and cost = 0.30 and payer = 'direct' and day = app.institution_local_day(:inst_a)
  from public.usage_ledger where institution_id = :inst_a and channel = 'sms' and category = 'notification'),
  'the ledger counts it on the institution''s local day, paid directly');
set local role service_role;
select pg_temp.check(app.outbox_result(:inst_a, (pg_temp.v('a_msg') #>> '{}')::uuid, true, 'c1000000-0000-4000-8000-0000000000a2', 'institution', 'mock_sms') = 'ignored',
  'a repeated result changes nothing and is not billed again');
reset role;
select pg_temp.check((select count from public.usage_ledger where institution_id = :inst_a and channel = 'sms' and category = 'notification') = 1,
  'still billed once');

-- 6. Circuit breaker: three failures in a row open the circuit; the route skips it; Master Admins are alerted.
set local role service_role;
select app.connection_outcome(:inst_b, 'institution', 'c1000000-0000-4000-8000-0000000000b1', false, 'timeout', null) from generate_series(1, 3);
insert into out select 'route_b2', app.outbox_route(:inst_b, (pg_temp.v('b_msg') #>> '{}')::uuid);
reset role;
select pg_temp.check((select circuit_open_until > now() from public.integration_connections where id = 'c1000000-0000-4000-8000-0000000000b1')
  and jsonb_array_length(pg_temp.v('route_b2') -> 'connections') = 0
  and exists (select 1 from public.platform_alerts where kind = 'circuit_open' and recipient_user_id = :master), 'an open circuit is skipped and alerted');

-- 7. Failure: back-off (never immediate), then given_up after the last attempt.
set local role service_role;
insert into out select 'fail1', to_jsonb(app.outbox_result(:inst_b, (pg_temp.v('b_msg') #>> '{}')::uuid, false, 'c1000000-0000-4000-8000-0000000000b1',
  'institution', 'mock_sms', null, 'balance_low', 'not enough balance'));
reset role;
select pg_temp.check(pg_temp.v('fail1') #>> '{}' = 'failed' and (select status = 'queued' and next_attempt_at >= now() + interval '29 seconds'
  and error ->> 'responsibility' = 'institution' from public.outbox where id = (pg_temp.v('b_msg') #>> '{}')::uuid),
  'a failure waits before the next try and says whose side it is');
update public.outbox set status = 'sending', attempts = max_attempts where id = (pg_temp.v('b_msg') #>> '{}')::uuid;
set local role service_role;
insert into out select 'fail2', to_jsonb(app.outbox_result(:inst_b, (pg_temp.v('b_msg') #>> '{}')::uuid, false, 'c1000000-0000-4000-8000-0000000000b1',
  'institution', 'mock_sms', null, 'timeout', null));
reset role;
select pg_temp.check(pg_temp.v('fail2') #>> '{}' = 'given_up' and exists (select 1 from public.delivery_log where outbox_id = (pg_temp.v('b_msg') #>> '{}')::uuid
  and result = 'given_up') and (select failed_parts from public.usage_ledger where institution_id = :inst_b and category = 'otp') = 1,
  'after the last attempt: given_up, logged, failed parts in the ledger');

-- 8. A message stuck in "sending" becomes unknown, is never claimed again and never billed.
insert into public.outbox (institution_id, id, channel, priority, lane, recipient, payload, idempotency_key, status, claimed_at, attempts)
values (:inst_a, 'd1000000-0000-4000-8000-0000000000d1', 'sms', 'transactional', 3, '01711000077', '{"body":"x"}', 'stuck-000001', 'sending',
        now() - interval '20 minutes', 1);
set local role service_role;
create temp table round3 as select * from app.outbox_claim('test-worker', 50);
reset role;
select pg_temp.check((select status from public.outbox where id = 'd1000000-0000-4000-8000-0000000000d1') = 'unknown'
  and not exists (select 1 from round3 where id = 'd1000000-0000-4000-8000-0000000000d1')
  and exists (select 1 from public.delivery_log where outbox_id = 'd1000000-0000-4000-8000-0000000000d1' and result = 'unknown'),
  'a stuck item is marked unknown, not re-claimed (lesson 2)');

-- 9. Platform-paid email: billable in the ledger (D15).
insert into public.institution_service_payers (institution_id, kind, payer) values (:inst_a, 'email', 'platform');
set local role service_role;
insert into out select 'e1', app.outbox_enqueue(:inst_a, 'email', 'transactional', 'parent@example.test', '{"body":"Receipt","subject":"Receipt"}', 'email-key-0001');
create temp table round4 as select * from app.outbox_claim('test-worker', 50) where channel = 'email';
insert into out select 'route_e', app.outbox_route(:inst_a, (pg_temp.v('e1') ->> 'id')::uuid);
select app.outbox_result(:inst_a, (pg_temp.v('e1') ->> 'id')::uuid, true, 'c1000000-0000-4000-8000-0000000000f1', 'platform', 'mock_email', 'mail-1');
reset role;
select pg_temp.check(pg_temp.v('route_e') -> 'connections' -> 0 ->> 'owner' = 'platform'
  and (select payer = 'platform' and count = 1 from public.usage_ledger where institution_id = :inst_a and channel = 'email'),
  'platform-paid email: the platform gateway is used and the ledger row is billable');

-- 10. Callbacks: a forged one is stored and ignored; a real one applies once; a duplicate is ignored.
set local role service_role;
insert into out select 'w_bad', to_jsonb(app.webhook_record('c1000000-0000-4000-8000-0000000000a2', false, 'mock-msg-0001:delivered',
  '{"status":"delivered"}', 'mock-msg-0001', 'delivered'));
insert into out select 'w_ok', to_jsonb(app.webhook_record('c1000000-0000-4000-8000-0000000000a2', true, 'mock-msg-0001:delivered:2',
  '{"status":"delivered"}', 'mock-msg-0001', 'delivered'));
insert into out select 'w_dup', to_jsonb(app.webhook_record('c1000000-0000-4000-8000-0000000000a2', true, 'mock-msg-0001:delivered:2',
  '{"status":"delivered"}', 'mock-msg-0001', 'delivered'));
insert into out select 'w_other', to_jsonb(app.webhook_record('c1000000-0000-4000-8000-0000000000b1', true, 'mock-msg-0001:undelivered',
  '{"status":"undelivered"}', 'mock-msg-0001', 'undelivered'));
reset role;
select pg_temp.check(pg_temp.v('w_bad') #>> '{}' = 'rejected' and pg_temp.v('w_ok') #>> '{}' = 'delivered' and pg_temp.v('w_dup') #>> '{}' = 'duplicate'
  and (select status from public.outbox where id = (pg_temp.v('a_msg') #>> '{}')::uuid) = 'delivered'
  and (select count(*) from public.delivery_log where outbox_id = (pg_temp.v('a_msg') #>> '{}')::uuid and result = 'delivered') = 1,
  'bad signature rejected; a duplicate callback is processed once');
select pg_temp.check(pg_temp.v('w_other') #>> '{}' = 'pending', 'B''s connection cannot change A''s message (callbacks match their own connection)');

-- 11. Time zone: the ledger day and a local send time follow the institution (I12).
select pg_temp.check(app.institution_local_instant(:inst_a, '2026-11-20', '09:00') = '2026-11-20 09:00'::timestamp at time zone app.institution_tz(:inst_a),
  'a local 9 am is 9 am in the institution''s zone');

-- 12. Isolation and the panel.
select pg_temp.act_as(pg_temp.claims_for(:owner));
select pg_temp.check(pg_temp.error_of('select count(*) from public.outbox') like 'permission denied%'
  and pg_temp.error_of('select count(*) from public.delivery_log') like 'permission denied%'
  and pg_temp.error_of('select count(*) from public.usage_ledger') like 'permission denied%'
  and pg_temp.error_of(format('select app.outbox_enqueue(%L, ''sms'', ''bulk'', ''x'', ''{"body":"x"}'', ''client-key-01'')', :inst_a)) like 'permission denied%',
  'tables are not readable and the queue is not callable by people');
select pg_temp.check(pg_temp.error_of('select public.platform_delivery_log()') = 'permission_denied', 'only platform staff see the delivery log');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:master, 'aal2'));
select pg_temp.check(jsonb_array_length(public.platform_delivery_log(:inst_a)) >= 2
  and exists (select 1 from jsonb_array_elements(public.platform_usage_ledger()) x where (x ->> 'billable')::boolean),
  'the panel shows the delivery log and the billable ledger');
select pg_temp.check(pg_temp.error_of(format('select public.platform_connection_test(%L, %L, ''01711000055'')', :inst_a, 'c1000000-0000-4000-8000-0000000000a1')) = '',
  'the Test button queues a message pinned to that connection');
reset role;

rollback;
