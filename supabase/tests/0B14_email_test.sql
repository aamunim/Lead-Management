-- 0B.14 tests: providers; one domain per institution; DNS results stored only by the service role; the sender (own
-- domain or the platform sub-domain address, never another institution's); the platform mail's daily limit; bounces
-- count for the message's own institution only and pause a bad sender (email stops, OTP still goes); resume;
-- templates in bn / en with the institution's words; invitation and approval mails queued; permissions.
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

-- 1. Providers and domains.
select pg_temp.check((select adapter_version from public.integration_providers where key = 'resend') = 'resend-1'
  and (select adapter_version from public.integration_providers where key = 'smtp') = 'smtp-1', 'SMTP and Resend adapters are ready');
select pg_temp.act_as(pg_temp.claims_for(:master, 'aal2'));
insert into out select 'a_dom', public.platform_email_domain_add(:inst_a, 'Ideal.Example.Test', 'resend');
select pg_temp.check(pg_temp.v('a_dom') -> 'domains' -> 0 ->> 'domain' = 'ideal.example.test'
  and jsonb_array_length(pg_temp.v('a_dom') -> 'domains' -> 0 -> 'expected') = 3, 'a domain with its three DNS records to add');
select pg_temp.check(pg_temp.error_of(format('select public.platform_email_domain_add(%L, ''ideal.example.test'', ''resend'')', :inst_b)) = 'domain_taken',
  'one domain belongs to one institution (no shared reputation)');
select pg_temp.check(pg_temp.error_of(format('select public.hub_email_domain_result(%L, ''ideal.example.test'', ''{"spf":{"ok":true},"dkim":{"ok":true}}'')', :inst_a))
  like 'permission denied%', 'nobody marks a domain verified from the client — only the checker (service role)');
reset role;
set local role service_role;
select pg_temp.check(public.hub_email_domain_result(:inst_a, 'ideal.example.test', '{"spf":{"ok":true},"dkim":{"ok":false,"problem":"no DKIM key"},"dmarc":{"ok":false}}') = 'failed'
  and public.hub_email_domain_result(:inst_a, 'ideal.example.test', '{"spf":{"ok":true},"dkim":{"ok":true},"dmarc":{"ok":false}}') = 'verified',
  'SPF and DKIM make a domain verified (DMARC recommended)');
reset role;

-- 2. The sender: the institution's verified domain, or its own address on the platform sub-domain.
insert into public.product_settings (key, value, schema_version) values ('platform_mail_domain', '"mail.leadora.test"', 1)
on conflict (key) do update set value = excluded.value;
select pg_temp.check(app.email_sender(:inst_a, 'platform', '{}') ->> 'from_email' = 'no-reply@ideal.example.test'
  and app.email_sender(:inst_b, 'platform', '{}') ->> 'from_email' = (select slug from public.institutions where id = :inst_b) || '@mail.leadora.test'
  and app.email_sender(:inst_b, 'platform', '{}') ->> 'from_name' = (select name from public.institutions where id = :inst_b),
  'platform mail sends as the institution (own domain or its own sub-domain address)');

-- 3. Platform default mail: routes with the sender, stops at the daily limit.
insert into public.platform_connections (id, kind, provider_key, label, mode, settings, live_test_passed_at)
values ('c5000000-0000-4000-8000-0000000000f1', 'email', 'mock_email', 'Platform mail', 'live', '{}', now());
set local role service_role;
insert into out select 'e1', app.outbox_enqueue(:inst_b, 'email', 'transactional', 'parent@example.test', '{"body":"Receipt","subject":"Receipt"}', 'email-b-00001');
create temp table c1 as select * from app.outbox_claim('t', 50);
insert into out select 'r1', app.outbox_route(:inst_b, (pg_temp.v('e1') ->> 'id')::uuid);
reset role;
select pg_temp.check(pg_temp.v('r1') -> 'connections' -> 0 ->> 'owner' = 'platform'
  and pg_temp.v('r1') -> 'connections' -> 0 -> 'sender' ->> 'from_email' like '%@mail.leadora.test', 'the platform mail carries the institution''s sender');
insert into public.usage_ledger (institution_id, day, provider, channel, category, payer, count)
values (:inst_b, app.institution_local_day(:inst_b), 'mock_email', 'email', 'notification', 'platform', 50);
set local role service_role;
insert into out select 'r2', app.outbox_route(:inst_b, (pg_temp.v('e1') ->> 'id')::uuid);
reset role;
select pg_temp.check(jsonb_array_length(pg_temp.v('r2') -> 'connections') = 0, 'after the daily platform-mail limit (Proposed 50) the platform mail is not used');
delete from public.usage_ledger where institution_id = :inst_b and provider = 'mock_email';

-- 4. Bounces count for the message's own institution only; a bad sender is paused.
insert into public.email_reputation (institution_id, day, sent) values (:inst_a, app.institution_local_day(:inst_a), 60)
on conflict (institution_id, day) do update set sent = 60;
insert into public.outbox (institution_id, id, channel, priority, lane, recipient, payload, idempotency_key, status, connection_id, connection_owner,
                           provider_message_id, sent_at)
select :inst_a, ('e5000000-0000-4000-8000-' || lpad(g::text, 12, '0'))::uuid, 'email', 'transactional', 3, 'x' || g || '@example.test',
       '{"body":"x"}', 'bounce-test-' || lpad(g::text, 4, '0'), 'sent', 'c5000000-0000-4000-8000-0000000000f1', 'platform', 'mail-' || g, now()
  from generate_series(1, 3) g;
set local role service_role;
select public.hub_webhook_record('c5000000-0000-4000-8000-0000000000f1', true, 'mail-' || g || ':bounced', '{}', 'mail-' || g, 'bounced')
  from generate_series(1, 3) g;
reset role;
select pg_temp.check((select bounced from public.email_reputation where institution_id = :inst_a and day = app.institution_local_day(:inst_a)) = 3
  and not exists (select 1 from public.email_reputation where institution_id = :inst_b and bounced > 0),
  'bounces through the shared platform mail count only for the message''s institution');
select pg_temp.check((select paused_at is not null from public.institution_service_payers where institution_id = :inst_a and kind = 'email')
  and exists (select 1 from public.platform_alerts where kind = 'email_paused' and recipient_user_id = :master),
  'a bounce rate over 5 % pauses the sender and alerts the Master Admins');
set local role service_role;
select pg_temp.check(pg_temp.error_of(format('select app.outbox_enqueue(%L, ''email'', ''transactional'', ''p@example.test'', ''{"body":"x"}'', ''paused-001'')', :inst_a))
  = 'sender_paused' and pg_temp.error_of(format('select app.outbox_enqueue(%L, ''email'', ''otp'', ''p@example.test'', ''{"body":"code"}'', ''paused-otp-01'')', :inst_a)) = '',
  'a paused sender sends no email, but sign-in codes still go');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:master, 'aal2'));
select pg_temp.check(pg_temp.error_of(format('select public.platform_email_resume(%L, '''')', :inst_a)) = 'reason_required', 'resuming needs a reason');
select pg_temp.check(public.platform_email_resume(:inst_a, 'domain fixed') -> 'paused' = 'null'::jsonb, 'the Master Admin resumes it');
reset role;

-- 5. Templates in bn / en with the institution's own words; invitations and approvals queue mails.
update public.institution_labels set en_plural = 'Enquiries', en_singular = 'Enquiry' where institution_id = :inst_a and key = 'lead';
insert into public.institution_labels (institution_id, key, en_singular, en_plural, bn_forms)
values (:inst_a, 'lead', 'Enquiry', 'Enquiries', app.bn_forms('অনুসন্ধান', true)) on conflict (institution_id, key) do nothing;
select pg_temp.check(app.render_platform_email(:inst_a, 'institution.approved', 'en', '{"trial_end":"2026-12-01"}') ->> 'body' like '%your Enquiries%'
  and app.render_platform_email(:inst_a, 'institution.approved', 'bn', '{}') ->> 'body' like '%অনুসন্ধান নিয়ে%'
  and app.render_platform_email(:inst_a, 'institution.approved', 'bn', '{}') ->> 'subject' like '%অনুমোদিত%', 'templates use the institution''s own words in both languages');
select pg_temp.act_as(pg_temp.claims_for(:master, 'aal2'));
insert into out select 'made', public.platform_institution_create(jsonb_build_object('name', 'Mail Test School', 'profiles', jsonb_build_array('school'),
  'super_admin', jsonb_build_object('email', 'head@mailtest.example.test', 'display_name', 'Head')), gen_random_uuid());
reset role;
select pg_temp.check(exists (select 1 from public.outbox where institution_id = (pg_temp.v('made') ->> 'institution_id')::uuid
  and recipient = 'head@mailtest.example.test' and payload ->> 'template_key' = 'invite.super_admin'),
  'the Super Admin invitation mail is queued');

-- 6. Isolation and permissions.
select pg_temp.act_as(pg_temp.claims_for(:owner));
select pg_temp.check(pg_temp.error_of('select count(*) from public.email_domains') like 'permission denied%'
  and pg_temp.error_of('select count(*) from public.email_reputation') like 'permission denied%'
  and pg_temp.error_of(format('select public.platform_email(%L)', :inst_a)) = 'permission_denied', 'institutions see none of this directly');
reset role;

rollback;
