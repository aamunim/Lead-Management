-- 0B.09 tests: the public wizard data shows no institution; self sign-up creates a pending institution with the types
-- applied and the person as its Super Admin (a second login of the same person joins with the same login, D25);
-- the same tap twice gives one institution; rate limits; duplicate EIIN flagged; no messaging before approval; the
-- pending institution's Super Admin sees only their institution; Master Admin creation with an invitation.
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
create function pg_temp.new_user(p_id uuid, p_email text, p_confirmed boolean default true) returns void language sql as $$
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                          created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change)
  values ('00000000-0000-0000-0000-000000000000', p_id, 'authenticated', 'authenticated', p_email, '', case when p_confirmed then now() end,
          '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '')
$$;
grant execute on all functions in schema pg_temp to authenticated, anon;
create temp table out (k text primary key, v jsonb);
grant all on out to authenticated, anon;
create function pg_temp.v(p_k text) returns jsonb language sql as $$ select v from out where k = p_k $$;
grant execute on function pg_temp.v(text) to authenticated, anon;

\set inst_a '''a0000000-0000-4000-8000-00000000000a'''
\set owner '''77777777-7777-4777-8777-777777777777'''
\set master '''55555555-5555-4555-8555-555555555555'''
\set support '''e1000000-0000-4000-8000-0000000000e1'''
\set newbie '''c9000000-0000-4000-8000-0000000000c1'''
\set invitee '''c9000000-0000-4000-8000-0000000000c2'''
select pg_temp.new_user(:newbie, 'new.principal@example.test');
-- The network address of the "request" (PostgREST passes the headers).
select set_config('request.headers', '{"x-forwarded-for": "203.0.113.7"}', true);

-- 1. Before sign-in: open types and a preview; nothing about any institution.
insert into out select 'a_name', to_jsonb((select name from public.institutions where id = :inst_a));
set local role anon;
select pg_temp.check((public.signup_status() ->> 'open')::boolean, 'self sign-up is open');
select pg_temp.check(jsonb_array_length(public.list_open_packs()) = 1, 'one industry is open: the wizard skips step 1 (D20)');
insert into out select 'preview', public.signup_preview(array['college'], array['modules']);
select pg_temp.check(pg_temp.v('preview') -> 'areas' @? '$[*] ? (@.area == "roles" && @.add > 0)'
  and not (pg_temp.v('preview') -> 'areas' @? '$[*] ? (@.area == "modules")'), 'the preview lists what the type sets up, without the excluded part');
select pg_temp.check(pg_temp.v('preview')::text not like '%' || (pg_temp.v('a_name') #>> '{}') || '%',
  'the preview names no institution');
select pg_temp.check(pg_temp.error_of('select public.institution_signup(''{}'', gen_random_uuid())') like '%permission denied%',
  'nobody signs up an institution without a login');
reset role;

-- 2. Self sign-up: pending, types applied, the person is the Super Admin and their next token opens it.
select pg_temp.act_as(pg_temp.claims_for(:newbie));
select pg_temp.check(pg_temp.error_of('select public.institution_signup(''{"name":"X","profiles":["college"]}'', gen_random_uuid())') = 'signup_invalid',
  'a too-short name is refused');
select pg_temp.check(pg_temp.error_of('select public.institution_signup(''{"name":"Good College","profiles":["college"],"exclude":["roles"]}'', gen_random_uuid())')
  = 'signup_invalid', 'the Super Admin role cannot be left out');
insert into out select 'signup', public.institution_signup(jsonb_build_object('name', 'Dhaka Model College', 'eiin', '108888',
  'contact_phone', '01711000123', 'profiles', jsonb_build_array('college'), 'exclude', jsonb_build_array('modules'),
  'super_admin', jsonb_build_object('display_name', 'Rahim Uddin', 'phone', '01711000124')), 'c9000000-0000-4000-8000-0000000000f1');
insert into out select 'again', public.institution_signup('{"name":"Dhaka Model College","profiles":["college"]}', 'c9000000-0000-4000-8000-0000000000f1');
reset role;
insert into out select 'id', pg_temp.v('signup') -> 'institution_id';
select pg_temp.check(pg_temp.v('again') -> 'institution_id' = pg_temp.v('id') and (pg_temp.v('again') ->> 'repeated')::boolean
  and (select count(*) from public.institutions where created_by = :newbie) = 1, 'the same tap twice gives one institution');
select pg_temp.check((select status = 'pending' and industry = 'education' and eiin = '108888' from public.institutions where id = (pg_temp.v('id') #>> '{}')::uuid),
  'the institution waits for approval (pending, education)');
select pg_temp.check(exists (select 1 from public.institution_profiles where institution_id = (pg_temp.v('id') #>> '{}')::uuid and profile_key = 'college')
  and exists (select 1 from public.seeded_items where institution_id = (pg_temp.v('id') #>> '{}')::uuid and area = 'labels')
  and not exists (select 1 from public.seeded_items where institution_id = (pg_temp.v('id') #>> '{}')::uuid and area = 'modules'),
  'the type is applied, the excluded part is not');
select pg_temp.check(exists (select 1 from public.role_assignments a join public.roles r on r.institution_id = a.institution_id and r.id = a.role_id
  where a.institution_id = (pg_temp.v('id') #>> '{}')::uuid and a.user_id = :newbie and r.is_super_admin)
  and (select display_name = 'Rahim Uddin' and phone = '01711000124' from public.profiles where user_id = :newbie), 'the person is its Super Admin');
select pg_temp.check(exists (select 1 from public.domain_events where event_key = 'institution.signed_up' and institution_id = (pg_temp.v('id') #>> '{}')::uuid)
  and exists (select 1 from public.institution_signups where user_id = :newbie and ip = '203.0.113.7'), 'the sign-up is recorded with its address and an event');
insert into out select 'claims', pg_temp.claims_for(:newbie);
select pg_temp.check(pg_temp.v('claims') ->> 'active_institution_id' = pg_temp.v('id') #>> '{}', 'the next sign-in opens the new institution');

-- 3. The pending institution: setup continues, no messaging, sees only itself.
select pg_temp.act_as(pg_temp.v('claims'));
insert into out select 'set_err', to_jsonb(pg_temp.error_of('select public.setting_set(''fees'', ''{"enabled": true}'')'));
select pg_temp.check(pg_temp.v('set_err') #>> '{}' = '', 'the Super Admin can continue setup while pending: ' || (pg_temp.v('set_err') #>> '{}'));
select pg_temp.check(not (public.institution_status() ->> 'can_message')::boolean and public.institution_status() ->> 'status' = 'pending',
  'no SMS or bulk sending before approval');
select pg_temp.check((select count(*) from public.institutions) = 1 and not exists (select 1 from public.app_settings where institution_id = :inst_a),
  'a pending institution''s Super Admin sees only their institution');
reset role;
select pg_temp.check(not app.institution_can_message((pg_temp.v('id') #>> '{}')::uuid) and app.institution_can_message(:inst_a),
  'the outbox gate: pending no, active yes');

-- 4. Duplicate EIIN is flagged to the Master Admin; approval opens messaging.
update public.institutions set eiin = '108888' where id = :inst_a;
select pg_temp.act_as(pg_temp.claims_for(:master, 'aal2'));
select pg_temp.check(exists (select 1 from jsonb_array_elements(public.platform_approval_queue()) q
  where q ->> 'id' = pg_temp.v('id') #>> '{}' and q -> 'duplicates' @? '$[*] ? (@.match == "eiin")'), 'the approval queue flags the duplicate EIIN');
select public.platform_institution_set_status((pg_temp.v('id') #>> '{}')::uuid, 'trial', 'checked');
reset role;
select pg_temp.check(app.institution_can_message((pg_temp.v('id') #>> '{}')::uuid), 'after approval (trial) messaging is allowed');

-- 5. D25: the same login signs up a second institution and keeps the first.
select pg_temp.act_as(pg_temp.claims_for(:owner));
insert into out select 'second', public.institution_signup('{"name":"Owner Second School","profiles":["school"]}', gen_random_uuid());
reset role;
select pg_temp.check((select count(*) from public.institution_members where user_id = :owner and status = 'active') >= 2
  and exists (select 1 from public.institution_members where user_id = :owner and institution_id = :inst_a and status = 'active'),
  'an existing login gets a new membership and keeps the old one');

-- 6. Rate limits: per login per day (3, Proposed), per network address per hour.
select pg_temp.act_as(pg_temp.claims_for(:owner));
select public.institution_signup('{"name":"Owner Third School","profiles":["school"]}', gen_random_uuid());
select public.institution_signup('{"name":"Owner Fourth School","profiles":["school"]}', gen_random_uuid());
select pg_temp.check(pg_temp.error_of('select public.institution_signup(''{"name":"Owner Fifth School","profiles":["school"]}'', gen_random_uuid())')
  = 'signup_rate_limited', 'a fourth sign-up by one login in a day is refused (limit 3)');
reset role;
insert into public.product_settings (key, value, schema_version) values ('signup_limit_per_ip_hour', '4', 1) on conflict (key) do update set value = excluded.value;
select pg_temp.act_as(pg_temp.claims_for(:master, 'aal2'));
select pg_temp.check(pg_temp.error_of('select public.institution_signup(''{"name":"Fifth From One Address","profiles":["school"]}'', gen_random_uuid())')
  = 'signup_rate_limited', 'a fifth sign-up from one address in an hour is refused (limit set to 4)');
reset role;
insert into public.product_settings (key, value, schema_version) values ('self_signup_open', 'false', 1) on conflict (key) do update set value = excluded.value;
select set_config('request.headers', '{"x-forwarded-for": "198.51.100.9"}', true);
select pg_temp.act_as(pg_temp.claims_for(:support));
select pg_temp.check(pg_temp.error_of('select public.institution_signup(''{"name":"Closed Door School","profiles":["school"]}'', gen_random_uuid())')
  = 'signup_closed', 'self sign-up can be closed by the platform');
reset role;
delete from public.product_settings where key = 'self_signup_open';

-- 7. Master Admin creates an institution; the Super Admin is invited and joins when that email signs in.
select pg_temp.act_as(pg_temp.claims_for(:support, 'aal2'));
select pg_temp.check(pg_temp.error_of('select public.platform_institution_create(''{"name":"Support Made","profiles":["school"],"super_admin":{"email":"a@b.test"}}'', gen_random_uuid())')
  = 'permission_denied', 'Support cannot create institutions');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:master, 'aal2'));
insert into out select 'made', public.platform_institution_create(jsonb_build_object('name', 'Panel Made Polytechnic', 'profiles', jsonb_build_array('polytechnic'),
  'super_admin', jsonb_build_object('email', 'Invited.Head@Example.test', 'display_name', 'Invited Head')), gen_random_uuid());
reset role;
select pg_temp.check((select status = 'trial' from public.institutions where id = (pg_temp.v('made') ->> 'institution_id')::uuid)
  and not (pg_temp.v('made') ->> 'attached')::boolean, 'created by the platform: the trial starts at once; the invitee has no login yet');
select pg_temp.new_user(:invitee, 'invited.head@example.test', false);
select pg_temp.check(not exists (select 1 from public.institution_members where user_id = :invitee), 'an unconfirmed email does not join');
update auth.users set email_confirmed_at = now() where id = :invitee;
select pg_temp.check(exists (select 1 from public.institution_members m join public.role_assignments a using (institution_id, user_id)
  join public.roles r on r.institution_id = a.institution_id and r.id = a.role_id
  where m.user_id = :invitee and m.institution_id = (pg_temp.v('made') ->> 'institution_id')::uuid and m.status = 'active' and r.is_super_admin)
  and (select display_name from public.profiles where user_id = :invitee) = 'Invited Head', 'the confirmed invitee joins as Super Admin');
select pg_temp.check(exists (select 1 from public.platform_audit_log where action = 'institution.created'
  and institution_id = (pg_temp.v('made') ->> 'institution_id')::uuid), 'the creation is in the platform audit');
-- An existing login is attached at once (D25).
select pg_temp.act_as(pg_temp.claims_for(:master, 'aal2'));
insert into out select 'made2', public.platform_institution_create(jsonb_build_object('name', 'Panel Made Coaching', 'profiles', jsonb_build_array('coaching'),
  'super_admin', jsonb_build_object('email', 'new.principal@example.test')), gen_random_uuid());
select pg_temp.check(jsonb_array_length(public.platform_institution_invites((pg_temp.v('made2') ->> 'institution_id')::uuid)) = 1, 'the panel lists the invitation');
reset role;
select pg_temp.check((pg_temp.v('made2') ->> 'attached')::boolean and exists (select 1 from public.institution_members
  where user_id = :newbie and institution_id = (pg_temp.v('made2') ->> 'institution_id')::uuid), 'an existing login is attached at once');

-- 8. A login made in the wizard keeps the language chosen on the device.
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                        created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change)
values ('00000000-0000-0000-0000-000000000000', 'c9000000-0000-4000-8000-0000000000c3', 'authenticated', 'authenticated', 'bangla.signup@example.test', '',
        now(), '{"provider":"email","providers":["email"]}', '{"preferred_language":"bn"}', now(), now(), '', '', '', '');
select pg_temp.check((select preferred_language from public.profiles where user_id = 'c9000000-0000-4000-8000-0000000000c3') = 'bn',
  'a new login keeps the language chosen before sign-up');

-- 8. Deleting (purging) an institution with people and roles works (the access trigger skips a deleted institution).
delete from public.institutions where id = (pg_temp.v('made') ->> 'institution_id')::uuid;
select pg_temp.check(not exists (select 1 from public.institutions where id = (pg_temp.v('made') ->> 'institution_id')::uuid)
  and not exists (select 1 from public.role_assignments where institution_id = (pg_temp.v('made') ->> 'institution_id')::uuid),
  'an institution with people and roles can be purged');

rollback;
