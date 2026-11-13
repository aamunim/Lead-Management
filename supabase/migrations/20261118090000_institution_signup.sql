-- 0B.09 Institution setup wizard and self sign-up (Ch 6.1–6.4, 6.8, 6.9 rows 1, 3, 6; Ch 10.6; D8, D19, D20, D25).
--   * Public, before sign-in: the open industries and types (list_open_packs, 0B.03) and a preview of what the chosen
--     types set up (signup_preview). No institution is ever listed publicly (Ch 10.10 row 5).
--   * The person creates (or signs in to) their login with Supabase Auth, then institution_signup creates the
--     institution in `pending` (waiting for approval), applies the types (0B.04), makes them its Super Admin and records
--     the sign-up with its IP for the rate limits. An existing login simply gets a new membership (D25).
--   * Master Admin "Create institution" (platform.institutions_create) runs the same steps, starts the trial and invites
--     the Super Admin by email: an existing login is attached at once, otherwise when that email first signs in.
--   * app.institution_can_message(): no SMS or bulk sending before approval; the hub outbox gate (0B.12) must call it.
-- Proposed placeholders (owner approves): self sign-up open, the rate limits, CAPTCHA (Supabase Auth captcha on the
-- sign-up call, switched on per environment), Master Admin creation starting the trial at once.

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Data
-- ---------------------------------------------------------------------------------------------------------------------
create table public.institution_signups (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid references auth.users (id) on delete set null,
  created_institution uuid references public.institutions (id) on delete set null,
  request_key     uuid not null,
  source          text not null check (source in ('self', 'platform')),
  payload         jsonb not null,
  ip              text,
  email           text,
  phone           text check (app.is_ascii_phone(phone)),
  captcha_score   numeric,
  created_at      timestamptz not null default now(),
  unique (user_id, request_key)
);
create index institution_signups_ip_idx on public.institution_signups (ip, created_at) where ip is not null;
create index institution_signups_user_idx on public.institution_signups (user_id, created_at);
create index institution_signups_phone_idx on public.institution_signups (phone, created_at) where phone is not null;
create trigger institution_signups_phone before insert or update on public.institution_signups
  for each row execute function app.normalize_phone_columns('phone');
alter table public.institution_signups enable row level security;
revoke all on public.institution_signups from anon, authenticated;
create policy institution_signups_none on public.institution_signups for select to authenticated using (false);
comment on table public.institution_signups is
  'Platform-level record of every institution sign-up (self or by the platform) for rate limits and review; no tenant reads it.';

-- Super Admin invitations made by the platform (0B.09-T9). Accepted when that email signs in for the first time.
create table public.institution_invites (
  institution_id  uuid not null references public.institutions (id) on delete cascade,
  id              uuid not null default gen_random_uuid(),
  email           text not null check (email = lower(btrim(email)) and email like '%_@_%'),
  role_id         uuid not null,
  display_name    text check (display_name is null or length(btrim(display_name)) between 1 and 120),
  phone           text check (app.is_ascii_phone(phone)),
  invited_by      uuid references auth.users (id) on delete set null,
  invited_at      timestamptz not null default now(),
  accepted_at     timestamptz,
  accepted_by     uuid references auth.users (id) on delete set null,
  primary key (institution_id, id),
  foreign key (institution_id, role_id) references public.roles (institution_id, id) on delete cascade
);
create unique index institution_invites_open_idx on public.institution_invites (institution_id, email) where accepted_at is null;
-- Documented exception to "indexes start with institution_id": an invitation is found by email when a login is made.
create index institution_invites_email_idx on public.institution_invites (email) where accepted_at is null;
alter table public.institution_invites enable row level security;
revoke all on public.institution_invites from anon, authenticated;
create policy institution_invites_none on public.institution_invites for select to authenticated using (false);
create trigger institution_invites_phone before insert or update on public.institution_invites
  for each row execute function app.normalize_phone_columns('phone');
select app.attach_status_guard('public.institution_invites');

-- Product settings (Proposed placeholders; the owner confirms them).
insert into public.setting_definitions (key, scope, schema, default_value, area, description, label_key, owner_module, owner_milestone, stored_in) values
  ('self_signup_open', 'product', '{"type":"boolean"}', 'true', 'platform.product_settings',
   'Institutions may sign up by themselves and wait for approval (Ch 6.2). Proposed: on.', 'settings:keys.self_signup_open', 'platform', '0B.09', 'product_settings'),
  ('signup_limit_per_ip_hour', 'product', '{"type":"integer","minimum":1,"maximum":100}', '5', 'platform.product_settings',
   'Institution sign-ups allowed from one network address per hour (Ch 6.9 row 1). Proposed: 5.',
   'settings:keys.signup_limit_per_ip_hour', 'platform', '0B.09', 'product_settings'),
  ('signup_limit_per_person_day', 'product', '{"type":"integer","minimum":1,"maximum":20}', '3', 'platform.product_settings',
   'Institution sign-ups one login or one phone number may make per day (Ch 6.9 row 1). Proposed: 3.',
   'settings:keys.signup_limit_per_person_day', 'platform', '0B.09', 'product_settings')
on conflict (key) do nothing;

insert into public.event_definitions (event_key, version, entity_type, payload_schema, description) values
  ('institution.signed_up', 1, 'institution',
   '{"type":"object","required":["source","profiles"],"properties":{"source":{"type":"string"},"profiles":{"type":"array"}}}',
   'A new institution was created by the setup wizard (self sign-up or by the platform) (0B.09).')
on conflict do nothing;

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. Helpers
-- ---------------------------------------------------------------------------------------------------------------------
-- SMS and bulk sending only after approval (0B.09-T8): the hub outbox gate (0B.12) calls this for every send.
create or replace function app.institution_can_message(p_institution uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select i.status in ('trial', 'active') from public.institutions i where i.id = p_institution), false)
$$;

-- Validates the wizard's answers and returns them cleaned. Only the essentials (Ch 6.9 row 3): everything else is in
-- the setup checklist after sign-up.
create or replace function app.signup_clean(p_payload jsonb) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_name     text := btrim(coalesce(p_payload ->> 'name', ''));
  v_short    text := nullif(btrim(coalesce(p_payload ->> 'short_name', '')), '');
  v_eiin     text := nullif(btrim(coalesce(p_payload ->> 'eiin', '')), '');
  v_code     text := nullif(btrim(coalesce(p_payload ->> 'institution_code', '')), '');
  v_address  text := nullif(btrim(coalesce(p_payload ->> 'address', '')), '');
  v_phone    text := app.normalize_phone(nullif(btrim(coalesce(p_payload ->> 'contact_phone', '')), ''));
  v_profiles text[];
  v_exclude  text[];
begin
  if jsonb_typeof(p_payload -> 'profiles') is distinct from 'array' then
    raise exception 'signup_invalid' using errcode = 'P0422', detail = 'profiles';
  end if;
  v_profiles := array(select distinct x from jsonb_array_elements_text(p_payload -> 'profiles') x);
  v_exclude := array(select distinct x from jsonb_array_elements_text(coalesce(p_payload -> 'exclude', '[]')) x);
  if cardinality(v_profiles) = 0 or cardinality(v_profiles) > 9 then
    raise exception 'signup_invalid' using errcode = 'P0422', detail = 'profiles';
  end if;
  if length(v_name) not between 2 and 200 then
    raise exception 'signup_invalid' using errcode = 'P0422', detail = 'name';
  end if;
  if v_short is not null and length(v_short) > 40 then
    raise exception 'signup_invalid' using errcode = 'P0422', detail = 'short_name';
  end if;
  if v_eiin is not null and v_eiin !~ '^[0-9]{4,10}$' then
    raise exception 'signup_invalid' using errcode = 'P0422', detail = 'eiin';
  end if;
  if v_code is not null and v_code !~ '^[0-9A-Za-z-]{2,20}$' then
    raise exception 'signup_invalid' using errcode = 'P0422', detail = 'institution_code';
  end if;
  if v_address is not null and length(v_address) > 300 then
    raise exception 'signup_invalid' using errcode = 'P0422', detail = 'address';
  end if;
  if v_phone is not null and not app.is_ascii_phone(v_phone) then
    raise exception 'signup_invalid' using errcode = 'P0422', detail = 'contact_phone';
  end if;
  -- The roles area makes the Super Admin role: it cannot be left out.
  if 'roles' = any (v_exclude) or exists (select 1 from unnest(v_exclude) x where not exists (select 1 from public.profile_areas a where a.area = x)) then
    raise exception 'signup_invalid' using errcode = 'P0422', detail = 'exclude';
  end if;
  return jsonb_build_object('name', v_name, 'short_name', v_short, 'eiin', v_eiin, 'institution_code', v_code, 'address', v_address,
                            'contact_phone', v_phone, 'profiles', to_jsonb(v_profiles), 'exclude', to_jsonb(v_exclude),
                            'label_choices', coalesce(nullif(p_payload -> 'label_choices', 'null'::jsonb), '{}'::jsonb));
end $$;

-- A unique address for the institution, from its name (any script falls back to "inst").
create or replace function app.institution_slug(p_name text) returns text
language plpgsql volatile set search_path = '' as $$
declare
  v_base text := left(btrim(regexp_replace(lower(p_name), '[^a-z0-9]+', '-', 'g'), '-'), 36);
  v_slug text;
begin
  if length(v_base) < 2 then v_base := 'inst'; end if;
  loop
    v_slug := v_base || '-' || substr(md5(gen_random_uuid()::text), 1, 6);
    exit when not exists (select 1 from public.institutions where slug = v_slug);
  end loop;
  return v_slug;
end $$;

-- Makes the person the institution's Super Admin (active member + the Super Admin role); their next token opens it.
create or replace function app.make_super_admin(p_institution uuid, p_user uuid, p_by uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_role uuid := (select r.id from public.roles r where r.institution_id = p_institution and r.is_super_admin);
begin
  if v_role is null then
    raise exception 'super_admin_role_missing' using errcode = 'P0500';
  end if;
  insert into public.institution_members (institution_id, user_id, status) values (p_institution, p_user, 'active')
  on conflict (institution_id, user_id) do update set status = 'active' where institution_members.status <> 'active';
  if not exists (select 1 from public.role_assignments a where a.institution_id = p_institution and a.user_id = p_user and a.role_id = v_role) then
    insert into public.role_assignments (institution_id, user_id, role_id, created_by) values (p_institution, p_user, v_role, p_by);
  end if;
  update public.profiles set last_active_institution_id = p_institution where user_id = p_user;
  perform app.flush_access_queue(p_institution);
end $$;

-- The role templates of a just-created institution are seeded on behalf of its first Super Admin, who holds nothing yet:
-- the escalation guard (0A.17) lets exactly that institution's seeding through, marked by app.institution_create in
-- this transaction only (a transaction-local setting no API caller can set; it stays for the rest of the transaction,
-- which ends with the sign-up).
create or replace function app.before_grant_check() returns trigger
language plpgsql set search_path = '' as $$
begin
  -- Only for writes made by signed-in people (RPCs); seeds, templates and the registry sync run without a user.
  if auth.uid() is not null and not app.is_platform_admin()
     and coalesce(current_setting('app.seeding_institution', true), '') is distinct from new.institution_id::text then
    perform app.assert_no_escalation(new.institution_id, jsonb_build_object(new.permission_key, coalesce(to_jsonb(new.scope), 'true'::jsonb)));
  end if;
  return new;
end $$;

-- Audit and event rows of the institution being created in this transaction are written for it (its first Super Admin
-- has no token for it yet).
create or replace function app.assert_may_write_for(p_institution uuid) returns void
language plpgsql stable set search_path = '' as $$
begin
  if p_institution is null then
    raise exception 'institution_id_required' using errcode = 'P0402';
  end if;
  if auth.uid() is null or app.is_platform_admin() or app.is_platform('platform.billing') or app.is_platform('platform.support_access')
     or p_institution::text = coalesce(current_setting('app.seeding_institution', true), '') then
    return;
  end if;
  if p_institution is distinct from app.auth_institution_id() then
    raise exception 'institution_mismatch' using errcode = 'P0403';
  end if;
end $$;

-- A login made in the wizard keeps the language chosen on the device before sign-up (sent with the sign-up as
-- user metadata; only 'bn' / 'en' are taken). Without it a Bangla sign-up continued in English.
create or replace function app.handle_new_auth_user() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_language text := new.raw_user_meta_data ->> 'preferred_language';
begin
  insert into public.profiles (user_id, email, phone, preferred_language)
  values (new.id, new.email, new.phone, case when v_language in ('bn', 'en') then v_language end)
  on conflict (user_id) do nothing;
  return new;
end $$;

-- Creates the institution with its types and records the sign-up; shared by self sign-up and the platform.
create or replace function app.institution_create(p_clean jsonb, p_source text, p_request_key uuid, p_email text, p_phone text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  insert into public.institutions (slug, name, short_name, eiin, institution_code, address, contact_phone, created_by, status)
  values (app.institution_slug(p_clean ->> 'name'), p_clean ->> 'name', p_clean ->> 'short_name', p_clean ->> 'eiin',
          p_clean ->> 'institution_code', p_clean ->> 'address', p_clean ->> 'contact_phone', auth.uid(), 'pending')
  returning id into v_id;
  insert into public.institution_status_history (institution_id, from_status, to_status, by_user, reason)
  values (v_id, null, 'pending', auth.uid(), case p_source when 'self' then 'self sign-up' else 'created by the platform' end);
  perform set_config('app.seeding_institution', v_id::text, true);
  perform app.apply_profiles(v_id, array(select jsonb_array_elements_text(p_clean -> 'profiles')),
                             array(select jsonb_array_elements_text(p_clean -> 'exclude')), p_clean -> 'label_choices', 'setup wizard (0B.09)');
  insert into public.institution_signups (user_id, created_institution, request_key, source, payload, ip, email, phone)
  values (auth.uid(), v_id, p_request_key, p_source, p_clean,
          nullif(split_part(coalesce(app.request_header('x-forwarded-for'), ''), ',', 1), ''), p_email, p_phone);
  perform app.emit_event(v_id, 'institution.signed_up', 1, 'institution', v_id::text,
                         jsonb_build_object('source', p_source, 'profiles', p_clean -> 'profiles'));
  return v_id;
end $$;

-- Deleting an institution (the purge job, 0B.07) cascades to its role assignments, whose access trigger queued a rebuild
-- for the institution being deleted and failed. Found by 0B.09 (the first purged institution with role assignments).
create or replace function app.queue_access_rebuild(p_institution uuid, p_users uuid[]) returns void
language sql security definer set search_path = '' as $$
  insert into public.access_rebuild_queue (institution_id, user_id)
  select p_institution, u from unnest(p_users) u
   where u is not null and exists (select 1 from public.institutions i where i.id = p_institution)
  on conflict do nothing
$$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. Public, before sign-in: what the chosen types would set up (Ch 6.3 step 5). Nothing about any institution.
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function public.signup_preview(p_profiles text[], p_exclude text[] default '{}', p_label_choices jsonb default '{}')
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if coalesce(cardinality(p_profiles), 0) = 0 or cardinality(p_profiles) > 9 then
    raise exception 'signup_invalid' using errcode = 'P0422', detail = 'profiles';
  end if;
  return app.profile_preview(null, p_profiles, coalesce(p_exclude, '{}'), coalesce(p_label_choices, '{}'));
end $$;

-- Is self sign-up open (the wizard shows "closed" otherwise).
create or replace function public.signup_status() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('open', coalesce((app.product_setting('self_signup_open'))::boolean, false))
$$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 4. Self sign-up (0B.09-T1, T5, T7): the signed-in person creates an institution and becomes its Super Admin.
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function public.institution_signup(p_payload jsonb, p_request_key uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_user   uuid := auth.uid();
  v_clean  jsonb;
  v_ip     text := nullif(split_part(coalesce(app.request_header('x-forwarded-for'), ''), ',', 1), '');
  v_email  text;
  v_phone  text;
  v_done   uuid;
  v_id     uuid;
  v_person integer := (app.product_setting('signup_limit_per_person_day'))::integer;
begin
  if v_user is null then
    raise exception 'not_signed_in' using errcode = 'P0401';
  end if;
  if p_request_key is null then
    raise exception 'request_key_required' using errcode = 'P0422';
  end if;
  -- The same tap twice gives the same institution.
  select created_institution into v_done from public.institution_signups where user_id = v_user and request_key = p_request_key;
  if found then
    return jsonb_build_object('institution_id', v_done, 'status', (select status from public.institutions where id = v_done), 'repeated', true);
  end if;
  if not coalesce((app.product_setting('self_signup_open'))::boolean, false) then
    raise exception 'signup_closed' using errcode = 'P0403';
  end if;
  v_clean := app.signup_clean(p_payload);
  select lower(u.email) into v_email from auth.users u where u.id = v_user;
  v_phone := app.normalize_phone(nullif(btrim(coalesce(p_payload #>> '{super_admin,phone}', '')), ''));
  if v_phone is not null and not app.is_ascii_phone(v_phone) then
    raise exception 'signup_invalid' using errcode = 'P0422', detail = 'phone';
  end if;
  -- Rate limits (Proposed, Ch 6.9 row 1): per network address per hour; per login and per phone per day.
  if v_ip is not null and (select count(*) from public.institution_signups s where s.ip = v_ip and s.created_at > now() - interval '1 hour')
       >= (app.product_setting('signup_limit_per_ip_hour'))::integer
     or (select count(*) from public.institution_signups s where s.user_id = v_user and s.created_at > now() - interval '1 day') >= v_person
     or (select count(*) from public.institution_signups s
          where s.phone is not null and s.phone in (v_phone, v_clean ->> 'contact_phone') and s.created_at > now() - interval '1 day') >= v_person then
    raise exception 'signup_rate_limited' using errcode = 'P0429';
  end if;

  v_id := app.institution_create(v_clean, 'self', p_request_key, v_email, coalesce(v_phone, v_clean ->> 'contact_phone'));
  update public.profiles
     set display_name = coalesce(nullif(btrim(coalesce(p_payload #>> '{super_admin,display_name}', '')), ''), display_name),
         phone = coalesce(v_phone, phone)
   where user_id = v_user;
  perform app.make_super_admin(v_id, v_user, v_user);
  perform app.audit(v_id, 'institution.signed_up', 'institution', v_id::text, null,
                    jsonb_build_object('name', v_clean ->> 'name', 'profiles', v_clean -> 'profiles', 'excluded', v_clean -> 'exclude'), null);
  return jsonb_build_object('institution_id', v_id, 'status', 'pending', 'repeated', false);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 5. Master Admin "Create institution" (0B.09-T9, Proposed): the same steps, the trial starts at once, the Super Admin
--    is invited by email (an existing login is attached now, D25).
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function app.attach_invites(p_user uuid, p_email text) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_inv   record;
  v_count integer := 0;
begin
  for v_inv in select * from public.institution_invites i where i.email = lower(p_email) and i.accepted_at is null
                  and exists (select 1 from public.institutions x where x.id = i.institution_id and x.status not in ('suspended', 'closed')) loop
    update public.profiles set display_name = coalesce(display_name, v_inv.display_name), phone = coalesce(phone, v_inv.phone)
     where user_id = p_user;
    perform app.make_super_admin(v_inv.institution_id, p_user, v_inv.invited_by);
    update public.institution_invites set accepted_at = now(), accepted_by = p_user
     where institution_id = v_inv.institution_id and id = v_inv.id;
    perform app.audit(v_inv.institution_id, 'invite.accepted', 'institution_invite', v_inv.id::text, null,
                      jsonb_build_object('email', v_inv.email), null);
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;

-- A confirmed email signs in for the first time (or confirms later): its invitations become memberships.
create or replace function app.on_auth_user_confirmed() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.email is not null and new.email_confirmed_at is not null
     and (tg_op = 'INSERT' or old.email_confirmed_at is null) then
    perform app.attach_invites(new.id, new.email);
  end if;
  return new;
end $$;
create trigger on_auth_user_confirmed after insert or update of email_confirmed_at on auth.users
  for each row execute function app.on_auth_user_confirmed();

create or replace function public.platform_institution_create(p_payload jsonb, p_request_key uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_clean  jsonb;
  v_email  text := lower(btrim(coalesce(p_payload #>> '{super_admin,email}', '')));
  v_name   text := nullif(btrim(coalesce(p_payload #>> '{super_admin,display_name}', '')), '');
  v_phone  text := app.normalize_phone(nullif(btrim(coalesce(p_payload #>> '{super_admin,phone}', '')), ''));
  v_done   uuid;
  v_id     uuid;
  v_user   uuid;
  v_inv    uuid;
begin
  if not app.is_platform('platform.institutions_create') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  if p_request_key is null then
    raise exception 'request_key_required' using errcode = 'P0422';
  end if;
  select created_institution into v_done from public.institution_signups where user_id = auth.uid() and request_key = p_request_key;
  if found then
    return jsonb_build_object('institution_id', v_done, 'repeated', true);
  end if;
  v_clean := app.signup_clean(p_payload);
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'signup_invalid' using errcode = 'P0422', detail = 'email';
  end if;
  if v_phone is not null and not app.is_ascii_phone(v_phone) then
    raise exception 'signup_invalid' using errcode = 'P0422', detail = 'phone';
  end if;

  v_id := app.institution_create(v_clean, 'platform', p_request_key, v_email, v_phone);
  perform public.platform_institution_set_status(v_id, 'trial', 'created by the platform');
  insert into public.institution_invites (institution_id, email, role_id, display_name, phone, invited_by)
  values (v_id, v_email, (select r.id from public.roles r where r.institution_id = v_id and r.is_super_admin), v_name, v_phone, auth.uid())
  returning id into v_inv;
  select u.id into v_user from auth.users u where lower(u.email) = v_email and u.email_confirmed_at is not null;
  if v_user is not null then
    perform app.attach_invites(v_user, v_email);
  end if;
  perform app.platform_audit('institution.created', v_id, 'institution', v_id::text, null,
                             jsonb_build_object('name', v_clean ->> 'name', 'profiles', v_clean -> 'profiles', 'super_admin', v_email), null);
  return jsonb_build_object('institution_id', v_id, 'invite_id', v_inv, 'attached', v_user is not null, 'repeated', false);
end $$;

-- Open invitations of one institution for the panel (who still has to sign in).
create or replace function public.platform_institution_invites(p_institution uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not app.is_platform('platform.view') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'email', i.email, 'invited_at', i.invited_at, 'accepted_at', i.accepted_at)
                                    order by i.invited_at desc)
                     from public.institution_invites i where i.institution_id = p_institution), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 6. The institution's own status now says whether it may send messages (banner: "waiting for approval").
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function public.institution_status() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_institution uuid := app.auth_institution_id();
begin
  if v_institution is null or not exists (select 1 from public.institution_members m where m.institution_id = v_institution
                                                and m.user_id = auth.uid() and m.status = 'active') then
    return null;
  end if;
  return (select jsonb_build_object('status', i.status, 'expires_at', ip.expires_at,
            'days_left', case when ip.expires_at is not null then greatest(0, ceil(extract(epoch from ip.expires_at - now()) / 86400))::integer end,
            'plan', ip.plan_key, 'can_message', app.institution_can_message(i.id))
            from public.institutions i left join public.institution_plan ip on ip.institution_id = i.id where i.id = v_institution);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 7. Permissions, grants, registry
-- ---------------------------------------------------------------------------------------------------------------------
-- platform.institutions_create is declared in config/modules/core.json (synced like every permission).
revoke all on function app.signup_clean(jsonb), app.institution_slug(text), app.make_super_admin(uuid, uuid, uuid),
  app.institution_create(jsonb, text, uuid, text, text), app.attach_invites(uuid, text), app.on_auth_user_confirmed()
  from public, anon, authenticated;
grant execute on function app.institution_can_message(uuid) to authenticated, service_role;
revoke all on function public.signup_preview(text[], text[], jsonb), public.signup_status(), public.institution_signup(jsonb, uuid),
  public.platform_institution_create(jsonb, uuid), public.platform_institution_invites(uuid) from public;
grant execute on function public.signup_preview(text[], text[], jsonb), public.signup_status() to anon, authenticated;
revoke all on function public.institution_signup(jsonb, uuid), public.platform_institution_create(jsonb, uuid),
  public.platform_institution_invites(uuid) from anon;
grant execute on function public.institution_signup(jsonb, uuid), public.platform_institution_create(jsonb, uuid),
  public.platform_institution_invites(uuid) to authenticated;

insert into app.definer_registry (function_name, reason, added_in, reviewer, tenant_check)
select f, r, '0B.09', 'architecture review 0B.09', t from (values
  ('app.institution_can_message', 'May the institution send SMS / bulk messages (trial or active only); the outbox gate calls it.', 'not_tenant_data'),
  ('app.make_super_admin', 'Adds one person as Super Admin of a just-created institution; called only by the sign-up / invite code.', 'service_role_only'),
  ('app.institution_create', 'Creates an institution, applies its types and records the sign-up; called only by the checked RPCs.', 'service_role_only'),
  ('app.attach_invites', 'Turns the open invitations of one confirmed email into memberships; called by the auth trigger and the panel.', 'service_role_only'),
  ('app.on_auth_user_confirmed', 'Trigger on auth.users: a confirmed email''s invitations become memberships (own user only).', 'service_role_only'),
  ('public.signup_preview', 'Public preview of what the chosen types set up; product data only, no institution.', 'not_tenant_data'),
  ('public.signup_status', 'Public: is self sign-up open (a product setting).', 'not_tenant_data'),
  ('public.institution_signup', 'Self sign-up: the caller creates a pending institution and becomes its Super Admin; rate limited.', 'not_tenant_data'),
  ('public.platform_institution_create', 'Master Admin creates an institution and invites its Super Admin; platform.institutions_create + aal2.', 'not_tenant_data'),
  ('public.platform_institution_invites', 'Open Super Admin invitations of one institution for the panel; platform.view + aal2.', 'not_tenant_data')
) as v (f, r, t)
on conflict (function_name) do update set reason = excluded.reason, added_in = excluded.added_in, tenant_check = excluded.tenant_check;
