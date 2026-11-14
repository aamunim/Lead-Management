-- 0B.14 Transactional email (Ch 42.5, 42.10 row 6; Ch 5.6; Ch 25.4; D1, D3, D4, D47).
--   * Adapters: SMTP (implicit TLS on port 465 — Gmail app password, cPanel mail) and Resend (owner's choice, D47);
--     others follow the same interface.
--   * Sender identity: from name / address / reply-to per connection; the institution's own verified domain, or — for the
--     platform default mail — a per-institution address on the platform's mail sub-domain (never another institution's).
--   * Domain check: SPF / DKIM / DMARC records expected for the domain, checked by the email-domain-check Edge Function
--     (DNS) and stored here; status pending → verified / failed.
--   * Reputation: delivered / bounced / complained per institution and day from provider callbacks (through the 0B.12
--     router); a bad sender is paused (email stops for that institution only) and the Master Admins are alerted.
--   * Platform default mail: a low daily limit per institution (Proposed 50).
--   * Platform mail templates (approval, suspension, Super Admin invite, sign-in code) in Bangla and English, with the
--     institution's own words from the label system.

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Providers
-- ---------------------------------------------------------------------------------------------------------------------
update public.integration_providers set adapter_version = 'smtp-1', status = 'beta', capabilities = '{send}',
  secret_fields = '{password}',
  settings_schema = '{"type":"object","required":["host","from_email"],"additionalProperties":false,"properties":{
    "host":{"type":"string","maxLength":200},"port":{"type":"integer","enum":[465],"default":465},
    "username":{"type":"string","maxLength":200},
    "from_name":{"type":"string","maxLength":100},"from_email":{"type":"string","maxLength":200},"reply_to":{"type":"string","maxLength":200},
    "price_per_part":{"type":"number","minimum":0},"rate_per_minute":{"type":"integer","minimum":1,"maximum":100000}}}'
 where key = 'smtp';
insert into public.integration_providers (key, kind, name, settings_schema, secret_fields, docs_url, capabilities, adapter_version, status, sort) values
  ('resend', 'email', '{"en":"Resend","bn":"Resend"}',
   '{"type":"object","required":["from_email"],"additionalProperties":false,"properties":{
      "from_name":{"type":"string","maxLength":100},"from_email":{"type":"string","maxLength":200},"reply_to":{"type":"string","maxLength":200},
      "price_per_part":{"type":"number","minimum":0},"rate_per_minute":{"type":"integer","minimum":1,"maximum":100000}}}',
   '{api_key,webhook_secret}', 'https://resend.com/docs', '{send,status_push,bounces}', 'resend-1', 'beta', 25)
on conflict (key) do nothing;

insert into public.integration_error_kinds (code, responsibility, sort) values
  ('sender_paused', 'institution', 48), ('domain_not_verified', 'institution', 49)
on conflict (code) do nothing;

insert into public.setting_definitions (key, scope, schema, default_value, area, description, label_key, owner_module, owner_milestone, stored_in) values
  ('platform_mail_domain', 'product', '{"type":["string","null"],"maxLength":200}', 'null', 'platform.product_settings',
   'Sub-domain of the platform default mail; each institution sends as <slug>@<this domain> (Ch 42.5). Set when the platform domain is verified.',
   'settings:keys.platform_mail_domain', 'platform', '0B.14', 'product_settings'),
  ('platform_mail_daily_limit', 'product', '{"type":"integer","minimum":0,"maximum":10000}', '50', 'platform.product_settings',
   'Emails per institution per day through the platform default mail (Ch 42.5). Proposed: 50.',
   'settings:keys.platform_mail_daily_limit', 'platform', '0B.14', 'product_settings'),
  ('email_bounce_pause_percent', 'product', '{"type":"number","minimum":1,"maximum":50}', '5', 'platform.product_settings',
   'Bounce rate over 7 days (at least 50 emails) that pauses an institution''s email (Ch 42.10 row 6). Proposed: 5 %.',
   'settings:keys.email_bounce_pause_percent', 'platform', '0B.14', 'product_settings'),
  ('email_complaint_pause_percent', 'product', '{"type":"number","minimum":0.01,"maximum":10}', '0.3', 'platform.product_settings',
   'Spam-complaint rate over 7 days that pauses an institution''s email. Proposed: 0.3 %.',
   'settings:keys.email_complaint_pause_percent', 'platform', '0B.14', 'product_settings')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. Domains and reputation
-- ---------------------------------------------------------------------------------------------------------------------
create table public.email_domains (
  institution_id  uuid not null references public.institutions (id) on delete cascade,
  domain          text not null check (domain ~ '^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$'),
  provider        text,                                  -- resend / smtp: which records are expected
  dkim_selector   text not null default 'resend' check (dkim_selector ~ '^[a-z0-9_-]{1,63}$'),
  status          text not null default 'pending' check (status in ('pending', 'verified', 'failed')),
  last_check      jsonb,                                 -- {spf:{ok,found,problem}, dkim:{…}, dmarc:{…}}
  checked_at      timestamptz,
  verified_at     timestamptz,
  created_at      timestamptz not null default now(),
  primary key (institution_id, domain)
);
alter table public.email_domains enable row level security;
revoke all on public.email_domains from anon, authenticated;
create policy email_domains_none on public.email_domains for select to authenticated using (false);
select app.attach_status_guard('public.email_domains');

create table public.email_reputation (
  institution_id  uuid not null references public.institutions (id) on delete cascade,
  day             date not null,
  sent            integer not null default 0,
  delivered       integer not null default 0,
  bounced         integer not null default 0,
  complained      integer not null default 0,
  primary key (institution_id, day)
);
alter table public.email_reputation enable row level security;
revoke all on public.email_reputation from anon, authenticated;
create policy email_reputation_none on public.email_reputation for select to authenticated using (false);
select app.attach_status_guard('public.email_reputation');

-- Email paused for one institution (bad sender); the Master Admin resumes it.
alter table public.institution_service_payers add column paused_at timestamptz, add column paused_reason text;

alter table public.delivery_log drop constraint delivery_log_result_check;
alter table public.delivery_log add constraint delivery_log_result_check
  check (result in ('sent', 'failed', 'given_up', 'delivered', 'undelivered', 'unknown', 'bounced', 'complained'));
alter table public.outbox drop constraint outbox_status_check;
alter table public.outbox add constraint outbox_status_check
  check (status in ('queued', 'held', 'sending', 'sent', 'delivered', 'undelivered', 'failed', 'given_up', 'unknown', 'bounced', 'complained'));

-- The records an institution's domain needs (instructions shown in the panel, step by step).
create or replace function app.email_domain_expected(p_domain text, p_provider text, p_selector text) returns jsonb
language sql immutable set search_path = '' as $$
  select jsonb_build_array(
    jsonb_build_object('type', 'TXT', 'name', p_domain, 'check', 'spf',
      'value', case p_provider when 'resend' then 'v=spf1 include:amazonses.com ~all' else 'v=spf1 include:<your mail server> ~all' end,
      'note', 'one SPF record only; add the include to an existing one'),
    jsonb_build_object('type', 'TXT', 'name', p_selector || '._domainkey.' || p_domain, 'check', 'dkim',
      'value', 'p=<public key from the provider>', 'note', 'copy the DKIM key the provider shows'),
    jsonb_build_object('type', 'TXT', 'name', '_dmarc.' || p_domain, 'check', 'dmarc',
      'value', 'v=DMARC1; p=none; rua=mailto:<reports address>', 'note', 'recommended; start with p=none'))
$$;

-- The sender for one message: the connection's own settings for the institution's connection; on the platform mail,
-- the institution's verified domain or its own address on the platform sub-domain, with its name and reply-to.
create or replace function app.email_sender(p_institution uuid, p_owner text, p_settings jsonb) returns jsonb
language sql stable security definer set search_path = '' as $$
  select case when p_owner = 'institution' then jsonb_build_object('from_name', coalesce(p_settings ->> 'from_name', i.name),
                  'from_email', p_settings ->> 'from_email', 'reply_to', p_settings ->> 'reply_to')
         else jsonb_build_object('from_name', i.name,
                  'from_email', coalesce((select 'no-reply@' || d.domain from public.email_domains d
                                           where d.institution_id = p_institution and d.status = 'verified' order by d.verified_at limit 1),
                                         case when app.product_setting('platform_mail_domain') #>> '{}' is not null
                                              then i.slug || '@' || (app.product_setting('platform_mail_domain') #>> '{}') end),
                  'reply_to', coalesce(p_settings ->> 'reply_to', (select u.email from public.role_assignments a
                                         join public.roles r on r.institution_id = a.institution_id and r.id = a.role_id and r.is_super_admin
                                         join auth.users u on u.id = a.user_id where a.institution_id = p_institution limit 1)))
         end
    from public.institutions i where i.id = p_institution
$$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. Gates and routing for email
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function app.outbox_gate(p_institution uuid, p_channel text, p_priority text, p_parts integer) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_status text := (select status from public.institutions where id = p_institution);
  v_limit  jsonb;
begin
  if v_status is null or v_status in ('closed', 'suspended') then
    return 'not_approved';
  end if;
  if p_priority <> 'otp' and not app.institution_can_message(p_institution) then
    return 'not_approved';
  end if;
  -- A paused sender (bad reputation) sends no email until the Master Admin resumes it (OTP still goes).
  if p_channel = 'email' and p_priority <> 'otp' and exists (select 1 from public.institution_service_payers p
       where p.institution_id = p_institution and p.kind = 'email' and p.paused_at is not null) then
    return 'sender_paused';
  end if;
  v_limit := app.check_limit(p_institution, case p_channel when 'sms' then 'sms_month' else 'email_month' end,
                             greatest(coalesce(p_parts, 1), 1), p_priority, false);
  if v_limit ->> 'level' = 'blocked' then
    return 'limit_reached';
  end if;
  return null;
end $$;

-- Routing for email also leaves out the platform mail once the institution reached its daily platform-mail limit, and
-- carries the sender for each connection.
create or replace function app.outbox_route(p_institution uuid, p_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_msg   public.outbox;
  v_gate  text;
  v_all   jsonb;
  v_route text;
  v_platform_today integer;
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
  v_platform_today := coalesce((select sum(l.count + (l.failed_parts)) from public.usage_ledger l
                                 where l.institution_id = p_institution and l.channel = 'email' and l.payer = 'platform'
                                   and l.day = app.institution_local_day(p_institution)), 0);
  v_all := app.resolve_connection(p_institution, v_msg.channel, case v_msg.priority when 'bulk' then 'bulk' else 'send' end);
  return jsonb_build_object('gate', null, 'channel', v_msg.channel, 'connections', coalesce((
    select jsonb_agg(c || jsonb_build_object('secret_fields', to_jsonb(p.secret_fields))
                      || case when v_msg.channel = 'email' then jsonb_build_object('sender', app.email_sender(p_institution, c ->> 'owner', c -> 'settings'))
                              else '{}'::jsonb end order by ord)
      from jsonb_array_elements(v_all) with ordinality as x (c, ord)
      join public.integration_providers p on p.key = c ->> 'provider'
     where (v_msg.payload ->> 'pin_connection' is null or c ->> 'id' = v_msg.payload ->> 'pin_connection')
       and (v_msg.payload ->> 'pin_connection' is not null or coalesce(c -> 'settings' ->> 'route', 'all') in ('all', v_route))
       and not (v_msg.channel = 'email' and c ->> 'owner' = 'platform'
                and v_platform_today >= (app.product_setting('platform_mail_daily_limit'))::integer)
       and not (v_msg.channel = 'email' and c ->> 'owner' = 'platform'
                and app.email_sender(p_institution, 'platform', c -> 'settings') ->> 'from_email' is null)
       and not exists (select 1 from public.integration_connections ic where ic.id = (c ->> 'id')::uuid and ic.circuit_open_until > now())
       and not exists (select 1 from public.platform_connections pc where pc.id = (c ->> 'id')::uuid and pc.circuit_open_until > now())
       and (c -> 'settings' ->> 'rate_per_minute' is null
            or (select count(*) from public.delivery_log d where d.connection_id = (c ->> 'id')::uuid and d.at > now() - interval '1 minute')
               < (c -> 'settings' ->> 'rate_per_minute')::int)), '[]'::jsonb));
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 4. Callbacks: delivered / bounced / complained count against the message's own institution only; a bad sender is
--    paused. (Extends the 0B.12 router function.)
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function app.email_reputation_add(p_institution uuid, p_kind text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_sent       integer;
  v_bounced    integer;
  v_complained integer;
begin
  insert into public.email_reputation as r (institution_id, day, sent, delivered, bounced, complained)
  values (p_institution, app.institution_local_day(p_institution), case p_kind when 'sent' then 1 else 0 end,
          case p_kind when 'delivered' then 1 else 0 end, case p_kind when 'bounced' then 1 else 0 end, case p_kind when 'complained' then 1 else 0 end)
  on conflict (institution_id, day) do update
    set sent = r.sent + excluded.sent, delivered = r.delivered + excluded.delivered, bounced = r.bounced + excluded.bounced,
        complained = r.complained + excluded.complained;
  if p_kind not in ('bounced', 'complained') then
    return;
  end if;
  select sum(sent), sum(bounced), sum(complained) into v_sent, v_bounced, v_complained
    from public.email_reputation where institution_id = p_institution and day > app.institution_local_day(p_institution) - 7;
  if v_sent >= 50 and (100.0 * v_bounced / v_sent >= (app.product_setting('email_bounce_pause_percent'))::numeric
                       or 100.0 * v_complained / v_sent >= (app.product_setting('email_complaint_pause_percent'))::numeric) then
    insert into public.institution_service_payers as p (institution_id, kind, payer, paused_at, paused_reason)
    values (p_institution, 'email', 'direct', now(), format('bounces %s, complaints %s of %s in 7 days', v_bounced, v_complained, v_sent))
    on conflict (institution_id, kind) do update set paused_at = coalesce(p.paused_at, now()), paused_reason = excluded.paused_reason
    where p.paused_at is null;
    if found then
      insert into public.platform_alerts (recipient_user_id, kind, payload)
      select pm.user_id, 'email_paused', jsonb_build_object('institution_id', p_institution, 'name', (select name from public.institutions where id = p_institution),
               'sent', v_sent, 'bounced', v_bounced, 'complained', v_complained)
        from public.platform_members pm where pm.status = 'active' and pm.platform_role = 'master_admin';
      perform app.integration_audit(p_institution, null, 'email.paused', jsonb_build_object('sent', v_sent, 'bounced', v_bounced, 'complained', v_complained));
    end if;
  end if;
end $$;

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
  select * into v_msg from public.outbox o
   where o.connection_id = p_connection and o.provider_message_id = p_provider_message_id
     and (v_conn ->> 'owner' = 'platform' or o.institution_id = (v_conn ->> 'institution_id')::uuid)
   limit 1;
  if not found then
    v_result := 'pending';
  elsif p_status in ('delivered', 'undelivered', 'bounced', 'complained') then
    update public.outbox set status = p_status where institution_id = v_msg.institution_id and id = v_msg.id
       and status in ('sent', 'unknown', 'delivered');
    insert into public.delivery_log (institution_id, outbox_id, recipient, channel, category, template_key, result, connection_id, connection_owner,
                                     provider_message_id)
    values (v_msg.institution_id, v_msg.id, v_msg.recipient, v_msg.channel, v_msg.category, v_msg.payload ->> 'template_key', p_status,
            p_connection, v_conn ->> 'owner', p_provider_message_id);
    if v_msg.channel = 'email' and p_status in ('delivered', 'bounced', 'complained') then
      perform app.email_reputation_add(v_msg.institution_id, p_status);
    end if;
    v_result := p_status;
  else
    v_result := 'ignored';
  end if;
  update public.webhook_events set processed_at = case when v_result = 'pending' then null else now() end, result = v_result,
         institution_id = coalesce(institution_id, v_msg.institution_id)
   where id = v_event;
  return v_result;
end $$;

-- Every email that goes out counts as sent for the reputation (the result function of 0B.12 calls this).
create or replace function app.email_sent_count() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.channel = 'email' and new.status = 'sent' and old.status is distinct from 'sent' and not new.sandbox then
    perform app.email_reputation_add(new.institution_id, 'sent');
  end if;
  return new;
end $$;
create trigger outbox_email_sent after update of status on public.outbox
  for each row when (new.channel = 'email' and new.status = 'sent') execute function app.email_sent_count();

-- ---------------------------------------------------------------------------------------------------------------------
-- 5. Panel: domains, verification result, pause / resume, reputation
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function public.platform_email(p_institution uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not app.is_platform('platform.view') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'domains', coalesce((select jsonb_agg(jsonb_build_object('domain', d.domain, 'provider', d.provider, 'status', d.status, 'last_check', d.last_check,
                 'checked_at', d.checked_at, 'verified_at', d.verified_at, 'dkim_selector', d.dkim_selector,
                 'expected', app.email_domain_expected(d.domain, d.provider, d.dkim_selector)) order by d.created_at)
               from public.email_domains d where d.institution_id = p_institution), '[]'::jsonb),
    'paused', (select jsonb_build_object('at', p.paused_at, 'reason', p.paused_reason) from public.institution_service_payers p
                where p.institution_id = p_institution and p.kind = 'email' and p.paused_at is not null),
    'reputation', (select jsonb_build_object('sent', coalesce(sum(r.sent), 0), 'delivered', coalesce(sum(r.delivered), 0),
                     'bounced', coalesce(sum(r.bounced), 0), 'complained', coalesce(sum(r.complained), 0))
                     from public.email_reputation r where r.institution_id = p_institution and r.day > current_date - 7),
    'platform_sender', app.email_sender(p_institution, 'platform', '{}'::jsonb));
end $$;

create or replace function public.platform_email_domain_add(p_institution uuid, p_domain text, p_provider text, p_selector text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_domain text := lower(btrim(p_domain));
begin
  if not app.is_platform('platform.integrations') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  if v_domain !~ '^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$' or p_provider not in ('resend', 'smtp') then
    raise exception 'connection_invalid' using errcode = 'P0422', detail = 'domain';
  end if;
  -- One domain belongs to one institution (a shared domain would share reputation, Ch 42.10 row 6).
  if exists (select 1 from public.email_domains where domain = v_domain and institution_id <> p_institution) then
    raise exception 'domain_taken' using errcode = 'P0409';
  end if;
  insert into public.email_domains (institution_id, domain, provider, dkim_selector)
  values (p_institution, v_domain, p_provider, coalesce(nullif(btrim(p_selector), ''), case p_provider when 'resend' then 'resend' else 'default' end))
  on conflict (institution_id, domain) do update set provider = excluded.provider, dkim_selector = excluded.dkim_selector, status = 'pending';
  perform app.integration_audit(p_institution, null, 'email.domain_added', jsonb_build_object('domain', v_domain, 'provider', p_provider));
  return public.platform_email(p_institution);
end $$;

-- The checker (Edge Function email-domain-check, service role) stores what DNS showed.
create or replace function public.hub_email_domain_result(p_institution uuid, p_domain text, p_result jsonb) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_status text := case when (p_result -> 'spf' ->> 'ok')::boolean and (p_result -> 'dkim' ->> 'ok')::boolean then 'verified' else 'failed' end;
begin
  update public.email_domains set last_check = p_result, checked_at = now(), status = v_status,
         verified_at = case when v_status = 'verified' then coalesce(verified_at, now()) else null end
   where institution_id = p_institution and domain = p_domain;
  if not found then
    return 'unknown_domain';
  end if;
  perform app.integration_audit(p_institution, null, 'email.domain_checked', jsonb_build_object('domain', p_domain, 'status', v_status));
  return v_status;
end $$;

-- The Verify button: may this caller check this institution's domain (the Edge Function asks before resolving DNS).
create or replace function public.platform_email_domain_check_allowed(p_institution uuid, p_domain text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not app.is_platform('platform.integrations') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  return (select jsonb_build_object('domain', d.domain, 'provider', d.provider, 'dkim_selector', d.dkim_selector)
            from public.email_domains d where d.institution_id = p_institution and d.domain = lower(p_domain));
end $$;

create or replace function public.platform_email_resume(p_institution uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not app.is_platform('platform.integrations') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  if length(btrim(coalesce(p_reason, ''))) < 3 then
    raise exception 'reason_required' using errcode = 'P0422';
  end if;
  update public.institution_service_payers set paused_at = null, paused_reason = null where institution_id = p_institution and kind = 'email';
  perform app.integration_audit(p_institution, null, 'email.resumed', jsonb_build_object('reason', p_reason));
  perform app.platform_audit('email.resumed', p_institution, 'institution', p_institution::text, null, null, p_reason);
  return public.platform_email(p_institution);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 6. Platform mail templates (bn / en) with the institution's own words, and sending them
-- ---------------------------------------------------------------------------------------------------------------------
create table public.platform_email_templates (
  key       text not null check (key ~ '^[a-z][a-z0-9_.]*$'),
  language  text not null check (language in ('bn', 'en')),
  subject   text not null,
  body      text not null,                      -- {{var}} and {{label:key}} / {{label:key:plural}}
  updated_at timestamptz not null default now(),
  primary key (key, language)
);
alter table public.platform_email_templates enable row level security;
revoke all on public.platform_email_templates from anon, authenticated;
create policy platform_email_templates_none on public.platform_email_templates for select to authenticated using (false);
insert into public.platform_email_templates (key, language, subject, body) values
  ('institution.approved', 'en', '{{institution}} is approved',
   'Hello,\n\n{{institution}} is approved. Your trial runs until {{trial_end}}. Sign in to add your team and start with your {{label:lead:plural}}.\n\n{{product}}'),
  ('institution.approved', 'bn', '{{institution}} অনুমোদিত হয়েছে',
   'আসসালামু আলাইকুম,\n\n{{institution}} অনুমোদিত হয়েছে। ট্রায়াল চলবে {{trial_end}} পর্যন্ত। সাইন-ইন করে আপনার টিম যোগ করুন এবং {{label:lead}} নিয়ে কাজ শুরু করুন।\n\n{{product}}'),
  ('institution.suspended', 'en', '{{institution}} is suspended',
   'Hello,\n\n{{institution}} is suspended: {{reason}}. Please contact us.\n\n{{product}}'),
  ('institution.suspended', 'bn', '{{institution}} স্থগিত করা হয়েছে',
   'আসসালামু আলাইকুম,\n\n{{institution}} স্থগিত করা হয়েছে: {{reason}}। অনুগ্রহ করে আমাদের সাথে যোগাযোগ করুন।\n\n{{product}}'),
  ('invite.super_admin', 'en', 'You are invited to run {{institution}}',
   'Hello {{name}},\n\nYou are the Super Admin of {{institution}} on {{product}}. Sign up or sign in with this email address ({{email}}) to start.\n\n{{product}}'),
  ('invite.super_admin', 'bn', '{{institution}} পরিচালনার আমন্ত্রণ',
   'আসসালামু আলাইকুম {{name}},\n\n{{product}}-এ আপনি {{institution}}-এর সুপার অ্যাডমিন। শুরু করতে এই ইমেইল ({{email}}) দিয়ে সাইন-আপ বা সাইন-ইন করুন।\n\n{{product}}'),
  ('otp.code', 'en', 'Your sign-in code', 'Your sign-in code is {{code}}. It expires in {{minutes}} minutes. Do not share it with anyone.'),
  ('otp.code', 'bn', 'আপনার সাইন-ইন কোড', 'আপনার সাইন-ইন কোড {{code}}। {{minutes}} মিনিটে মেয়াদ শেষ হবে। কাউকে জানাবেন না।');

create or replace function app.render_platform_email(p_institution uuid, p_key text, p_language text, p_vars jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_t       public.platform_email_templates;
  v_subject text;
  v_body    text;
  v_m       text[];
  v_vars    jsonb := coalesce(p_vars, '{}'::jsonb) || jsonb_build_object('product', coalesce(app.product_setting('app_name') #>> '{}', 'Leadora'),
                       'institution', (select name from public.institutions where id = p_institution));
begin
  select * into v_t from public.platform_email_templates where key = p_key and language = coalesce(p_language, 'en');
  if not found then
    select * into v_t from public.platform_email_templates where key = p_key and language = 'en';
  end if;
  if not found then
    raise exception 'template_unknown' using errcode = 'P0404', detail = p_key;
  end if;
  v_subject := v_t.subject;
  v_body := v_t.body;
  -- The institution's own words (renamed "Lead", "Student"…) come from the label system.
  for v_m in select regexp_matches(v_subject || v_body, '\{\{label:([a-z_]+)(?::([a-z_]+))?\}\}', 'g') loop
    v_subject := replace(v_subject, '{{label:' || v_m[1] || coalesce(':' || v_m[2], '') || '}}',
                         coalesce(app.label(p_institution, v_m[1], coalesce(p_language, 'en'), coalesce(v_m[2], 'singular')), v_m[1]));
    v_body := replace(v_body, '{{label:' || v_m[1] || coalesce(':' || v_m[2], '') || '}}',
                      coalesce(app.label(p_institution, v_m[1], coalesce(p_language, 'en'), coalesce(v_m[2], 'singular')), v_m[1]));
  end loop;
  for v_m in select regexp_matches(v_subject || v_body, '\{\{([a-z_]+)\}\}', 'g') loop
    v_subject := replace(v_subject, '{{' || v_m[1] || '}}', coalesce(v_vars ->> v_m[1], ''));
    v_body := replace(v_body, '{{' || v_m[1] || '}}', coalesce(v_vars ->> v_m[1], ''));
  end loop;
  return jsonb_build_object('subject', v_subject, 'body', replace(v_body, '\n', E'\n'), 'template_key', p_key);
end $$;

-- Queues a platform mail to one address (transactional lane; the platform mail or the institution's own email route).
create or replace function app.platform_mail(p_institution uuid, p_to text, p_key text, p_language text, p_vars jsonb, p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_mail jsonb := app.render_platform_email(p_institution, p_key, p_language, p_vars);
begin
  return app.outbox_enqueue(p_institution, 'email', case when p_key like 'otp.%' then 'otp' else 'transactional' end, p_to,
                            v_mail, p_idempotency_key, 'notification');
exception when others then
  -- A mail that cannot be queued (paused sender, limit) never blocks the action that caused it; it is recorded.
  perform app.integration_audit(p_institution, null, 'email.not_queued', jsonb_build_object('template', p_key, 'reason', sqlerrm));
  return jsonb_build_object('queued', false, 'reason', sqlerrm);
end $$;

-- Wiring: the Super Admin invitation (0B.09) and approval / suspension (0B.07) send their mails.
create or replace function app.on_invite_mail() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform app.platform_mail(new.institution_id, new.email, 'invite.super_admin', 'bn',
                            jsonb_build_object('name', coalesce(new.display_name, ''), 'email', new.email), 'invite:' || new.id);
  return new;
end $$;
create trigger institution_invites_mail after insert on public.institution_invites
  for each row execute function app.on_invite_mail();

create or replace function app.on_status_mail() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  r record;
begin
  if new.to_status not in ('trial', 'active', 'suspended') or (new.to_status = 'active' and new.from_status <> 'pending')
     or new.from_status is null then
    return new;
  end if;
  for r in select u.email, coalesce(p.preferred_language, 'bn') as lang from public.role_assignments a
             join public.roles ro on ro.institution_id = a.institution_id and ro.id = a.role_id and ro.is_super_admin
             join auth.users u on u.id = a.user_id left join public.profiles p on p.user_id = a.user_id
            where a.institution_id = new.institution_id loop
    perform app.platform_mail(new.institution_id, r.email, case new.to_status when 'suspended' then 'institution.suspended' else 'institution.approved' end,
      r.lang, jsonb_build_object('reason', coalesce(new.reason, ''), 'trial_end',
        coalesce((select to_char(ip.expires_at at time zone app.institution_tz(new.institution_id), 'YYYY-MM-DD')
                    from public.institution_plan ip where ip.institution_id = new.institution_id), '')),
      'status:' || new.id || ':' || r.email);
  end loop;
  return new;
end $$;
create trigger institution_status_history_mail after insert on public.institution_status_history
  for each row execute function app.on_status_mail();

-- ---------------------------------------------------------------------------------------------------------------------
-- 7. Grants and registry
-- ---------------------------------------------------------------------------------------------------------------------
revoke all on function app.email_sender(uuid, text, jsonb), app.email_reputation_add(uuid, text), app.email_sent_count(),
  app.render_platform_email(uuid, text, text, jsonb), app.platform_mail(uuid, text, text, text, jsonb, text), app.on_invite_mail(), app.on_status_mail()
  from public, anon, authenticated;
grant execute on function app.email_domain_expected(text, text, text) to authenticated, service_role;
grant execute on function app.render_platform_email(uuid, text, text, jsonb), app.platform_mail(uuid, text, text, text, jsonb, text) to service_role;
revoke all on function public.platform_email(uuid), public.platform_email_domain_add(uuid, text, text, text), public.hub_email_domain_result(uuid, text, jsonb),
  public.platform_email_domain_check_allowed(uuid, text), public.platform_email_resume(uuid, text) from public, anon;
grant execute on function public.platform_email(uuid), public.platform_email_domain_add(uuid, text, text, text),
  public.platform_email_domain_check_allowed(uuid, text), public.platform_email_resume(uuid, text) to authenticated;
revoke all on function public.hub_email_domain_result(uuid, text, jsonb) from authenticated;
grant execute on function public.hub_email_domain_result(uuid, text, jsonb) to service_role;

insert into app.definer_registry (function_name, reason, added_in, reviewer, tenant_check)
select f, r, '0B.14', 'architecture review 0B.14', t from (values
  ('app.email_sender', 'The sender of one email (institution''s own or its address on the platform mail); hub internals only.', 'service_role_only'),
  ('app.email_reputation_add', 'Counts sent / delivered / bounced / complained for the message''s own institution; pauses a bad sender.', 'service_role_only'),
  ('app.email_sent_count', 'Trigger: a sent email counts for its institution''s reputation.', 'service_role_only'),
  ('app.render_platform_email', 'Renders a platform mail template with the institution''s own words; hub internals only.', 'service_role_only'),
  ('app.platform_mail', 'Queues a platform mail for one institution (invites, approval, codes); server code only.', 'service_role_only'),
  ('app.on_invite_mail', 'Trigger: a Super Admin invitation sends its mail.', 'service_role_only'),
  ('app.on_status_mail', 'Trigger: approval / suspension sends a mail to the institution''s Super Admins.', 'service_role_only'),
  ('public.platform_email', 'Email domains, pause state and reputation of one institution; platform.view + aal2.', 'not_tenant_data'),
  ('public.platform_email_domain_add', 'Adds a sending domain for an institution (one institution per domain); platform.integrations + aal2.', 'not_tenant_data'),
  ('public.hub_email_domain_result', 'Stores a DNS check result; the email-domain-check Edge Function (service role) only.', 'service_role_only'),
  ('public.platform_email_domain_check_allowed', 'May the caller verify this domain (asked by the Edge Function first); platform.integrations + aal2.', 'not_tenant_data'),
  ('public.platform_email_resume', 'Resumes a paused sender with a reason; platform.integrations + aal2; audited.', 'not_tenant_data'),
  ('app.outbox_gate', 'May one institution send now (status, approval, paused sender, monthly limit); hub internals only.', 'service_role_only'),
  ('app.outbox_route', 'Connections for one claimed message, with sender and platform-mail limit (I1); service role only.', 'service_role_only')
) as v (f, r, t)
on conflict (function_name) do update set reason = excluded.reason, added_in = excluded.added_in, tenant_check = excluded.tenant_check;
