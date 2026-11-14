-- 0B.11 tests: catalog; connections only by platform.integrations (Master Admin), settings checked against the provider
-- schema; secrets write-only (only hints, never values; Super Admin cannot write or read); rotation (old key until the
-- effective date); resolver (institution from the record, primary + backup, payer, live test needed for bulk); errors
-- say whose side; tenants see status only; isolation; closing an institution disables connections and destroys secrets.
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
\set user_a '''11111111-1111-4111-8111-111111111111'''
\set owner '''77777777-7777-4777-8777-777777777777'''
\set master '''55555555-5555-4555-8555-555555555555'''
\set support '''e1000000-0000-4000-8000-0000000000e1'''

-- 1. Who may manage connections (D4).
select pg_temp.act_as(pg_temp.claims_for(:owner));
select pg_temp.check(pg_temp.error_of(format('select public.platform_connection_save(%L, null, ''{"provider":"custom_http_sms","label":"x","settings":{"send_url":"https://sms.example.test/send","sender_id":"ACME"}}'')', :inst_a))
  = 'permission_denied', 'the Super Admin cannot create a connection');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:support, 'aal2'));
select pg_temp.check(pg_temp.error_of(format('select public.platform_connection_save(%L, null, ''{"provider":"custom_http_sms","label":"x","settings":{"send_url":"https://sms.example.test/send","sender_id":"ACME"}}'')', :inst_a))
  = 'permission_denied', 'Support (view only) cannot either');
reset role;

-- 2. The Master Admin creates connections; settings are checked; a secret never goes into the settings.
select pg_temp.act_as(pg_temp.claims_for(:master, 'aal2'));
select pg_temp.check(pg_temp.error_of(format('select public.platform_connection_save(%L, null, ''{"provider":"custom_http_sms","label":"x","settings":{"send_url":"http://insecure","sender_id":"ACME"}}'')', :inst_a))
  = 'connection_invalid', 'settings are checked against the provider''s schema');
select pg_temp.check(pg_temp.error_of(format('select public.platform_connection_save(%L, null, ''{"provider":"custom_http_sms","label":"x","settings":{"send_url":"https://a.test","sender_id":"A","api_key":"abc"}}'')', :inst_a))
  = 'connection_invalid', 'a secret in the settings is refused');
insert into out select 'primary', public.platform_connection_save(:inst_a, null,
  '{"provider":"custom_http_sms","label":"Main SMS","mode":"live","priority":1,"settings":{"send_url":"https://sms.example.test/send","sender_id":"ACME"}}');
insert into out select 'backup', public.platform_connection_save(:inst_a, null,
  '{"provider":"custom_http_sms","label":"Backup SMS","mode":"live","priority":2,"settings":{"send_url":"https://backup.example.test/send","sender_id":"ACME"}}');
insert into out select 'b_conn', public.platform_connection_save(:inst_b, null,
  '{"provider":"custom_http_sms","label":"B SMS","mode":"sandbox","settings":{"send_url":"https://b-sms.example.test/send","sender_id":"BBB"}}');
insert into out select 'platform', public.platform_connection_save(null, null,
  '{"provider":"custom_http_sms","label":"Platform gateway","mode":"live","settings":{"send_url":"https://gw.example.test/send","sender_id":"LEADORA"}}');

-- 3. Secrets: write-only; only hints come back; rotation keeps the old key until the effective date.
insert into out select 'secret', public.connection_secret_set(:inst_a, (pg_temp.v('primary') ->> 'id')::uuid, 'api_key', 'aaaaaaaaaaaa1111');
select pg_temp.check(pg_temp.v('secret') ->> 'hint' = 'aaaa…1111' and pg_temp.v('secret')::text not like '%aaaaaaaa%', 'setting a key returns only its hint');
select public.connection_secret_set(:inst_a, (pg_temp.v('primary') ->> 'id')::uuid, 'api_key', 'bbbbbbbbbbbb3333', now() + interval '2 days');
select public.connection_secret_set(null, (pg_temp.v('platform') ->> 'id')::uuid, 'api_key', 'cccccccccccc9999');
insert into out select 'view', public.platform_integrations(:inst_a);
select pg_temp.check(pg_temp.v('view')::text not like '%aaaaaaaa%' and pg_temp.v('view')::text not like '%bbbbbbbb%'
  and (select x -> 'secrets' -> 0 ->> 'hint' = 'aaaa…1111' and x -> 'secrets' -> 0 ->> 'next_from' is not null
         from jsonb_array_elements(pg_temp.v('view') -> 'connections') x where x ->> 'id' = pg_temp.v('primary') ->> 'id'),
  'the panel shows the hint and a waiting rotation, never a value');
select pg_temp.check(pg_temp.error_of(format('select public.connection_secret_set(%L, %L, ''password'', ''abcdef'')', :inst_a, pg_temp.v('primary') ->> 'id')) = 'connection_invalid',
  'only the provider''s secret fields');
reset role;
set local role service_role;
select pg_temp.check(public.connection_secret_for_service(:inst_a, (pg_temp.v('primary') ->> 'id')::uuid, 'api_key') = 'aaaaaaaaaaaa1111',
  'before the rotation date the old key is used');
reset role;
-- (One transaction has one now(): move the old key back and the new one to "now" to stand for the date passing.)
update public.institution_secrets set valid_from = now() - interval '2 days' where secret_ref like 'conn.%' and hint = 'aaaa…1111';
update public.institution_secrets set valid_from = now() - interval '1 minute' where secret_ref like 'conn.%' and hint = 'bbbb…3333';
set local role service_role;
select pg_temp.check(public.connection_secret_for_service(:inst_a, (pg_temp.v('primary') ->> 'id')::uuid, 'api_key') = 'bbbbbbbbbbbb3333',
  'after it the new key');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:owner));
select pg_temp.check(pg_temp.error_of(format('select public.connection_secret_for_service(%L, %L, ''api_key'')', :inst_a, pg_temp.v('primary') ->> 'id')) like 'permission denied%'
  and pg_temp.error_of(format('select public.connection_secret_set(%L, %L, ''api_key'', ''zzzzzzzz'')', :inst_a, pg_temp.v('primary') ->> 'id')) = 'permission_denied',
  'the Super Admin can neither read nor write a key');
reset role;

-- 4. The resolver: the institution from the record; primary then backup; live bulk only after a live test; payer.
set local role service_role;
insert into out select 'res_send', app.resolve_connection(:inst_a, 'sms', 'send');
insert into out select 'res_bulk', app.resolve_connection(:inst_a, 'sms', 'bulk');
reset role;
select pg_temp.check(pg_temp.v('res_send') -> 0 ->> 'id' = pg_temp.v('primary') ->> 'id' and pg_temp.v('res_send') -> 1 ->> 'id' = pg_temp.v('backup') ->> 'id'
  and (select count(*) from jsonb_array_elements(pg_temp.v('res_send')) x where x ->> 'owner' = 'institution') = 2
  and pg_temp.v('res_send') -> -1 ->> 'owner' = 'platform',
  'primary first, then the backup, then the platform gateway as the last backup (0B.13); never another institution''s');
select pg_temp.check(jsonb_array_length(pg_temp.v('res_bulk')) = 0, 'live bulk sending is blocked until a live test passes (I3)');
select pg_temp.act_as(pg_temp.claims_for(:master, 'aal2'));
select public.connection_live_test_mark(:inst_a, (pg_temp.v('primary') ->> 'id')::uuid, true, 'sent a test to the office phone');
select pg_temp.check(pg_temp.error_of(format('select public.connection_live_test_mark(%L, %L, true)', :inst_b, pg_temp.v('b_conn') ->> 'id')) = 'connection_invalid',
  'a sandbox connection is not live-tested');
select public.institution_payer_set(:inst_b, 'sms', 'platform');
reset role;
set local role service_role;
insert into out select 'res_bulk2', app.resolve_connection(:inst_a, 'sms', 'bulk');
insert into out select 'res_b', app.resolve_connection(:inst_b, 'sms', 'send');
reset role;
select pg_temp.check(jsonb_array_length(pg_temp.v('res_bulk2')) = 1 and pg_temp.v('res_bulk2') -> 0 ->> 'id' = pg_temp.v('primary') ->> 'id',
  'after the live test the primary sends bulk');
select pg_temp.check(pg_temp.v('res_b') -> 0 ->> 'owner' = 'platform' and jsonb_array_length(pg_temp.v('res_b')) = 1,
  'the platform pays for B''s SMS: the platform gateway is used (D15)');

-- 5. Errors say whose side; the institution sees status only.
set local role service_role;
select app.connection_record_result(:inst_a, (pg_temp.v('backup') ->> 'id')::uuid, false, 'balance_low', 'insufficient balance');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:owner));
insert into out select 'status', public.integrations_status();
select pg_temp.check((select x -> 'last_error' ->> 'responsibility' = 'institution' from jsonb_array_elements(pg_temp.v('status') -> 'connections') x
  where x ->> 'id' = pg_temp.v('backup') ->> 'id'), 'a low balance is the institution''s side');
select pg_temp.check(pg_temp.v('status')::text not like '%sms.example.test%' and pg_temp.v('status')::text not like '%aaaa%'
  and jsonb_array_length(pg_temp.v('status') -> 'connections') = 2, 'status only: no settings, no hints; only A''s connections');
select pg_temp.check(pg_temp.error_of('select count(*) from public.integration_connections') like 'permission denied%'
  and pg_temp.error_of('select count(*) from public.institution_secrets where secret_ref like ''conn.%''') = '', 'tables are not readable directly');
select pg_temp.check(not exists (select 1 from public.institution_secrets where institution_id = :inst_b), 'no tenant sees another''s secret metadata');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:user_a));
select pg_temp.check(pg_temp.error_of('select public.integrations_status()') = 'permission_denied', 'staff without integration.view_status see nothing');
reset role;

-- 6. Audit: every change, hints only.
select pg_temp.check((select count(*) from public.integration_audit where institution_id = :inst_a and action in
  ('connection.created', 'secret.set', 'secret.rotation_scheduled', 'connection.live_test_passed')) >= 5
  and not exists (select 1 from public.integration_audit where detail::text like '%aaaaaaaa%' or detail::text like '%bbbbbbbb%'), 'every change is audited, never with a value');

-- 7. Closing an institution disables its connections and destroys its secrets (I14).
select pg_temp.act_as(pg_temp.claims_for(:master, 'aal2'));
select public.institution_export_create(:inst_a);
select public.platform_institution_set_status(:inst_a, 'closed', 'left');
reset role;
select pg_temp.check(not exists (select 1 from public.integration_connections where institution_id = :inst_a and status = 'active')
  and not exists (select 1 from public.institution_secrets where institution_id = :inst_a)
  and not exists (select 1 from vault.secrets where name like :inst_a || ':conn.%'), 'closing leaves no active connection and no secret');
set local role service_role;
select pg_temp.check(jsonb_array_length(app.resolve_connection(:inst_a, 'sms', 'send')) = 0, 'and the resolver gives nothing for it');
reset role;

-- 8. Key age reminder (Proposed): keys older than a year.
update public.platform_secrets set valid_from = now() - interval '400 days';
insert into out select 'alerts', to_jsonb(app.integration_key_age_alerts());
select pg_temp.check((pg_temp.v('alerts'))::int >= 1 and exists (select 1 from public.platform_alerts where kind = 'key_rotation_due' and recipient_user_id = :master),
  'an old key reminds the Master Admin to rotate it');

rollback;
