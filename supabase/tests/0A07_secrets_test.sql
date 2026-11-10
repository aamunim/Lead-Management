-- 0A.07 tests: per-institution secrets. Values only in Vault; app users write but never read; Edge (service_role) reads.
\set ON_ERROR_STOP on
begin;
create function pg_temp.check(cond boolean, what text) returns void language plpgsql as $$
begin
  if cond is distinct from true then raise exception 'FAILED: %', what; end if;
  raise notice 'ok - %', what;
end $$;
create function pg_temp.claims_for(p_user uuid) returns jsonb language sql as $$
  select (public.custom_access_token_hook(jsonb_build_object('user_id', p_user,
          'claims', jsonb_build_object('sub', p_user, 'role', 'authenticated', 'aud', 'authenticated')))) -> 'claims'
$$;
create function pg_temp.act_as(p_claims jsonb) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', p_claims::text, true);
  perform set_config('role', 'authenticated', true);
end $$;
create function pg_temp.as_service() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('role', 'service_role', true);
end $$;
create function pg_temp.error_of(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return ''; exception when others then return sqlerrm; end $$;
grant execute on all functions in schema pg_temp to authenticated, service_role;
create temp table out (k text primary key, v text);
grant all on out to authenticated, service_role;

\set inst_a '''a0000000-0000-4000-8000-00000000000a'''
\set user_a '''11111111-1111-4111-8111-111111111111'''
\set user_b '''22222222-2222-4222-8222-222222222222'''
\set user_platform '''55555555-5555-4555-8555-555555555555'''
\set key1 '''sk-live-AAAA-first-value-ZZ9911'''
\set key2 '''sk-live-BBBB-second-value-QQ7722'''

-- 1. Institution staff cannot write secrets yet (fail-closed until `integration.manage`, 0A.16/0A.17).
select pg_temp.act_as(pg_temp.claims_for(:user_a));
select pg_temp.check(pg_temp.error_of(format('select public.secret_set(%L, %L)', 'sms.primary.api_key', :key1)) = 'permission_denied',
                     'staff of A cannot set a secret before permissions exist');
reset role;

-- 2. The Master Admin sets A's SMS key; only a hint comes back.
select pg_temp.act_as(pg_temp.claims_for(:user_platform));
insert into out select 'set1', public.secret_set('sms.primary.api_key', :key1, null, :inst_a)::text;
reset role;
select pg_temp.check((select v::jsonb ->> 'hint' from out where k = 'set1') = 'sk-l…9911', 'set returns only the hint key…xxxx');
select pg_temp.check(position(:key1 in (select v from out where k = 'set1')) = 0, 'set never returns the value');
select pg_temp.check((select count(*) from vault.secrets s join public.institution_secrets m on m.vault_id = s.id
                      where m.institution_id = :inst_a and s.secret = :key1) = 0,
                     'the value is stored encrypted in Vault (not as plain text)');

-- 3. App users see metadata of their own institution only, and never the value.
select pg_temp.act_as(pg_temp.claims_for(:user_a));
select pg_temp.check((select hint from public.institution_secrets where secret_ref = 'sms.primary.api_key') = 'sk-l…9911',
                     'staff of A see the hint of A''s key');
select pg_temp.check(pg_temp.error_of('select vault_id from public.institution_secrets') like 'permission denied%',
                     'staff cannot even read the vault reference');
select pg_temp.check(pg_temp.error_of('select decrypted_secret from vault.decrypted_secrets') like 'permission denied%',
                     'staff cannot read Vault');
select pg_temp.check(pg_temp.error_of(format('select public.secret_read_for_service(%L, %L)', :inst_a, 'sms.primary.api_key'))
                     like 'permission denied%', 'staff cannot call the Edge-only reader');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:user_b));
select pg_temp.check((select count(*) from public.institution_secrets) = 0, 'staff of B see none of A''s secret metadata');
select pg_temp.check(pg_temp.error_of(format('select public.secret_revoke(%L, %L)', 'sms.primary.api_key', :inst_a)) = 'permission_denied',
                     'staff of B cannot revoke A''s secret');
reset role;

-- 4. Edge Functions (service_role) read the value in force.
select pg_temp.as_service();
insert into out select 'read1', public.secret_read_for_service(:inst_a, 'sms.primary.api_key');
reset role;
select pg_temp.check((select v from out where k = 'read1') = :key1, 'service_role reads the current value');

-- 5. Rotation: a new value with a future start date; the old one keeps working until then.
select pg_temp.act_as(pg_temp.claims_for(:user_platform));
select public.secret_set('sms.primary.api_key', :key2, now() + interval '1 day', :inst_a);
reset role;
select pg_temp.as_service();
insert into out select 'read2', public.secret_read_for_service(:inst_a, 'sms.primary.api_key');
reset role;
select pg_temp.check((select v from out where k = 'read2') = :key1, 'rotation: old value stays in force before valid_from');
-- Time passes (inside one transaction now() is fixed, so move both start dates back instead):
update public.institution_secrets set valid_from = now() - interval '2 days'
 where institution_id = :inst_a and hint = app.secret_hint(:key1);
update public.institution_secrets set valid_from = now() - interval '1 day'
 where institution_id = :inst_a and hint = app.secret_hint(:key2);
select pg_temp.as_service();
insert into out select 'read3', public.secret_read_for_service(:inst_a, 'sms.primary.api_key');
reset role;
select pg_temp.check((select v from out where k = 'read3') = :key2, 'rotation: new value in force after valid_from');
select pg_temp.check((select count(*) from public.institution_secrets where institution_id = :inst_a and rotated_at is not null) = 1,
                     'rotation: the previous version is marked rotated');
select pg_temp.act_as(pg_temp.claims_for(:user_platform));
select pg_temp.check(pg_temp.error_of(format('select public.secret_set(%L, %L, now() - interval ''1 day'', %L)',
                     'sms.primary.api_key', :key2, :inst_a)) = 'secret_valid_from_in_past', 'rotation into the past is refused');
reset role;

-- 6. Short values get a hint without characters.
select pg_temp.check(app.secret_hint('1234pass') = '••••', 'short secrets get a hint without characters');

-- 7. Revoke destroys the values but keeps who/when for the audit trail.
select pg_temp.act_as(pg_temp.claims_for(:user_platform));
select pg_temp.check(public.secret_revoke('sms.primary.api_key', :inst_a) = 2, 'revoke marks every version revoked');
reset role;
select pg_temp.as_service();
insert into out select 'read4', coalesce(public.secret_read_for_service(:inst_a, 'sms.primary.api_key'), '<none>');
reset role;
select pg_temp.check((select v from out where k = 'read4') = '<none>', 'after revoke nothing can be read');
select pg_temp.check((select count(*) from vault.secrets s join public.institution_secrets m on m.vault_id = s.id
                      where m.institution_id = :inst_a and m.secret_ref = 'sms.primary.api_key') = 0,
                     'after revoke the Vault values are gone');
select pg_temp.check((select count(*) from public.institution_secrets
                      where institution_id = :inst_a and secret_ref = 'sms.primary.api_key') = 2,
                     'after revoke the metadata (who, when) remains');

-- 8. Purge on institution closure (service_role only).
select pg_temp.act_as(pg_temp.claims_for(:user_platform));
select public.secret_set('email.smtp.password', 'a-long-smtp-password-1234', null, :inst_a);
reset role;
select pg_temp.act_as(pg_temp.claims_for(:user_a));
select pg_temp.check(pg_temp.error_of(format('select public.purge_institution_secrets(%L)', :inst_a)) like 'permission denied%',
                     'app users cannot purge');
reset role;
select pg_temp.as_service();
select public.purge_institution_secrets(:inst_a);
reset role;
select pg_temp.check((select count(*) from public.institution_secrets where institution_id = :inst_a) = 0,
                     'purge removes all of the institution''s secrets');
rollback;
