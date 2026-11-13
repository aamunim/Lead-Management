-- 0B.05 Modules, plans and limits (Ch 9.1–9.5, 9.8, 9.9 rows 1–5; Ch 7.8; Ch 5.7, 5.10; D7, D22, D30, D31, D32).
--   * modules: the product's module list (data). A module works for an institution when it is always on, or when the
--     plan (or a Master Admin override) allows it, the institution has it on, its industry fits and the modules it
--     depends on work. Data of a module that is off is kept and returns when it is on again.
--   * plans: versioned data (prices, modules, limits, trial length); an institution keeps its plan version until it
--     changes plan. All numbers are Proposed placeholders the Master Admin edits without a release.
--   * limits: plan value, or a per-institution override; checked on the server (never only in the app): 80 % warns,
--     100 % blocks; OTP and urgent messages are never blocked. Counters are kept by triggers and reconciled nightly.
-- See docs/dev/MODULES_PLANS.md.

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Modules
-- ---------------------------------------------------------------------------------------------------------------------
create table public.modules (
  key             text primary key check (key ~ '^[a-z][a-z0-9_]*$'),
  label_key       text references public.label_keys (key),
  depends_on      text[] not null default '{}',
  always_on       boolean not null default false,
  default_enabled boolean not null default true,
  industry_scope  text[],
  built_in        text,
  sort            integer not null
);
insert into public.modules (key, label_key, depends_on, always_on, default_enabled, industry_scope, built_in, sort) values
  ('leads', 'module.leads', '{}', true, true, null, '1.01', 10),
  ('calls', null, '{}', false, true, null, '1.10', 20),
  ('call_sync', null, '{calls}', false, false, null, '3.01', 30),
  ('whatsapp_log', null, '{}', false, true, null, '1.10', 40),
  ('appointment', null, '{}', false, true, null, '1.13', 50),
  ('assessment', 'assessment', '{}', false, false, null, '2.17', 60),
  ('merit_list', 'merit_list', '{assessment}', false, false, '{education}', '2.18', 70),
  ('fees', null, '{}', false, true, null, '2.02', 80),
  ('client_number', 'client_number', '{}', false, true, null, '2.04', 90),
  ('after_steps', 'after_steps', '{}', false, false, '{education}', '2.16', 100),
  ('slot_seats', null, '{}', false, true, null, '2.01', 110),
  ('contact_persons', 'contact_person', '{}', false, true, null, '1.21', 120),
  ('hostel', null, '{fees}', false, false, null, null, 130),
  ('ai', null, '{}', false, false, null, null, 140),
  ('credits', 'module.leaderboard', '{calls}', false, false, null, null, 150),
  ('network', 'module.network', '{}', false, false, null, null, 160),
  ('files', null, '{}', false, false, null, '2.14', 170),
  ('public_forms', null, '{}', false, true, null, '1.29', 180),
  ('campaigns', null, '{}', false, false, null, '1.27', 190),
  ('branches', null, '{}', false, true, null, '0A.15', 200),
  ('automation', null, '{}', false, false, null, '1.32', 210),
  ('custom_records', null, '{}', false, false, null, '2.20', 220),
  ('api', null, '{}', false, false, null, '1.31', 230),
  ('extensions', null, '{}', false, false, null, '0A.09', 240);

-- Per-institution choices: allowed (Master Admin override of the plan; null = from the plan) and enabled (the
-- institution's own choice; null = the type default, else the module default).
create table public.institution_modules (
  institution_id uuid not null references public.institutions (id) on delete cascade,
  module_key     text not null references public.modules (key) on delete cascade,
  allowed        boolean,
  enabled        boolean,
  updated_at     timestamptz not null default now(),
  updated_by     uuid references auth.users (id) on delete set null,
  primary key (institution_id, module_key)
);

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. Plans, limits catalog, add-ons (data; Proposed placeholders, D22 / D30 / D31 / D32)
-- ---------------------------------------------------------------------------------------------------------------------
create table public.limit_metrics (
  key    text primary key check (key ~ '^[a-z][a-z0-9_]*$'),
  period text not null check (period in ('none', 'month', 'day')),
  unit   text not null check (unit in ('count', 'mb')),
  built_in text,
  sort   integer not null
);
insert into public.limit_metrics (key, period, unit, built_in, sort) values
  ('users', 'none', 'count', '0B.05', 10),
  ('active_leads', 'none', 'count', '1.01', 20),
  ('branches', 'none', 'count', '0B.05', 30),
  ('storage_mb', 'none', 'mb', '2.14', 40),
  ('sms_month', 'month', 'count', '0B.13', 50),
  ('ai_month', 'month', 'count', null, 60),
  ('automations', 'none', 'count', '1.32', 70),
  ('custom_fields', 'none', 'count', '0B.06', 80),
  ('custom_records', 'none', 'count', '2.20', 90),
  ('api_calls_month', 'month', 'count', '1.31', 100),
  ('campaign_sms_day', 'day', 'count', '1.27', 110);

create table public.plans (
  key          text not null check (key ~ '^[a-z][a-z0-9_]*$'),
  version      integer not null check (version > 0),
  name         jsonb not null check (jsonb_typeof(name -> 'en') = 'string' and jsonb_typeof(name -> 'bn') = 'string'),
  modules      text[] not null default '{}',
  -- metric → number, or null = unlimited; a metric not listed is unlimited.
  limits       jsonb not null default '{}' check (jsonb_typeof(limits) = 'object'),
  -- {currency, monthly, yearly, by_type: {<profile>: {monthly, yearly}}}; null amounts = not set yet (D30, D32).
  prices       jsonb not null default '{}' check (jsonb_typeof(prices) = 'object'),
  trial_days   integer check (trial_days between 1 and 365),
  for_new      boolean not null default false,
  sort         integer not null default 100,
  notes        text,
  created_at   timestamptz not null default now(),
  created_by   uuid references auth.users (id) on delete set null,
  primary key (key, version)
);
create unique index plans_one_for_new on public.plans ((true)) where for_new;

create table public.addons (
  key    text primary key check (key ~ '^[a-z][a-z0-9_]*$'),
  name   jsonb not null,
  unit   text not null,
  prices jsonb not null default '{}',
  active boolean not null default true,
  sort   integer not null
);
insert into public.addons (key, name, unit, sort) values
  ('sms_pack', '{"en":"SMS pack","bn":"এসএমএস প্যাক"}', 'sms', 10),
  ('ai_usage', '{"en":"AI usage","bn":"AI ব্যবহার"}', 'request', 20),
  ('extra_users', '{"en":"Extra users","bn":"বাড়তি ইউজার"}', 'user', 30),
  ('extra_branches', '{"en":"Extra branches","bn":"বাড়তি শাখা"}', 'branch', 40),
  ('extra_storage', '{"en":"Extra storage","bn":"বাড়তি স্টোরেজ"}', 'gb', 50),
  ('custom_domain', '{"en":"Own domain","bn":"নিজের ডোমেইন"}', 'month', 60),
  ('branded_app', '{"en":"Own branded app","bn":"নিজস্ব ব্র্যান্ডেড অ্যাপ"}', 'year', 70),
  ('extension', '{"en":"Extension","bn":"এক্সটেনশন"}', 'month', 80),
  ('setup_service', '{"en":"Set-up and data import","bn":"সেটআপ ও ডেটা ইমপোর্ট"}', 'once', 90);

-- Proposed plans (Ch 9.3); every number is a placeholder (Ch 53.2 rows 2–4 still open).
insert into public.plans (key, version, name, modules, limits, prices, trial_days, for_new, sort) values
  ('trial', 1, '{"en":"Free trial","bn":"ফ্রি ট্রায়াল"}',
   '{leads,calls,whatsapp_log,appointment,assessment,merit_list,fees,client_number,after_steps,slot_seats,contact_persons,hostel,public_forms,campaigns,branches,automation}',
   '{"users":5,"active_leads":500,"branches":1,"storage_mb":500,"sms_month":100,"ai_month":0,"automations":2,"custom_fields":10,"custom_records":0,"api_calls_month":0,"campaign_sms_day":100}',
   '{"currency":"BDT","monthly":0,"yearly":0}', 14, true, 10),
  ('starter', 1, '{"en":"Starter","bn":"স্টার্টার"}',
   '{leads,calls,fees,client_number,slot_seats,contact_persons,public_forms,branches}',
   '{"users":5,"active_leads":1000,"branches":1,"storage_mb":1024,"sms_month":500,"ai_month":0,"automations":0,"custom_fields":10,"custom_records":0,"api_calls_month":0,"campaign_sms_day":500}',
   '{"currency":"BDT","monthly":null,"yearly":null}', null, false, 20),
  ('standard', 1, '{"en":"Standard","bn":"স্ট্যান্ডার্ড"}',
   '{leads,calls,whatsapp_log,appointment,assessment,merit_list,fees,client_number,after_steps,slot_seats,contact_persons,hostel,public_forms,campaigns,branches,automation}',
   '{"users":25,"active_leads":10000,"branches":3,"storage_mb":10240,"sms_month":3000,"ai_month":0,"automations":20,"custom_fields":50,"custom_records":0,"api_calls_month":0,"campaign_sms_day":2000}',
   '{"currency":"BDT","monthly":null,"yearly":null}', null, false, 30),
  ('pro', 1, '{"en":"Pro","bn":"প্রো"}',
   '{leads,calls,call_sync,whatsapp_log,appointment,assessment,merit_list,fees,client_number,after_steps,slot_seats,contact_persons,hostel,ai,credits,network,files,public_forms,campaigns,branches,automation,custom_records,api}',
   '{"users":100,"active_leads":50000,"branches":null,"storage_mb":51200,"sms_month":10000,"ai_month":2000,"automations":100,"custom_fields":200,"custom_records":10,"api_calls_month":50000,"campaign_sms_day":10000}',
   '{"currency":"BDT","monthly":null,"yearly":null}', null, false, 40),
  ('enterprise', 1, '{"en":"Enterprise","bn":"এন্টারপ্রাইজ"}',
   '{leads,calls,call_sync,whatsapp_log,appointment,assessment,merit_list,fees,client_number,after_steps,slot_seats,contact_persons,hostel,ai,credits,network,files,public_forms,campaigns,branches,automation,custom_records,api,extensions}',
   '{}', '{"currency":"BDT","monthly":null,"yearly":null}', null, false, 50);

-- An institution's plan: kept at its version until it changes plan (Ch 9.9 row 8, Proposed); billing fields from day one.
create table public.institution_plan (
  institution_id   uuid primary key references public.institutions (id) on delete cascade,
  plan_key         text not null,
  plan_version     integer not null,
  started_at       timestamptz not null default now(),
  expires_at       timestamptz,
  billing_cycle    text not null default 'monthly' check (billing_cycle in ('monthly', 'yearly', 'custom')),
  price_override   numeric(12, 2) check (price_override >= 0),
  discount_percent numeric(5, 2) not null default 0 check (discount_percent between 0 and 100),
  limit_overrides  jsonb not null default '{}' check (jsonb_typeof(limit_overrides) = 'object'),
  notes            text,
  updated_at       timestamptz not null default now(),
  updated_by       uuid references auth.users (id) on delete set null,
  foreign key (plan_key, plan_version) references public.plans (key, version)
);
create index institution_plan_plan_idx on public.institution_plan (institution_id, plan_key, plan_version);

-- Usage counters (period '' for totals, 'YYYY-MM' / 'YYYY-MM-DD' for monthly / daily metrics).
create table public.usage_counters (
  institution_id uuid not null references public.institutions (id) on delete cascade,
  metric         text not null references public.limit_metrics (key),
  period         text not null default '',
  value          bigint not null default 0,
  updated_at     timestamptz not null default now(),
  primary key (institution_id, metric, period)
);

alter table public.modules enable row level security;
alter table public.institution_modules enable row level security;
alter table public.limit_metrics enable row level security;
alter table public.plans enable row level security;
alter table public.addons enable row level security;
alter table public.institution_plan enable row level security;
alter table public.usage_counters enable row level security;
revoke all on public.modules, public.institution_modules, public.limit_metrics, public.plans, public.addons,
  public.institution_plan, public.usage_counters from anon, authenticated;
grant select on public.modules, public.institution_modules, public.limit_metrics, public.plans, public.addons,
  public.institution_plan, public.usage_counters to authenticated;
create policy modules_read on public.modules for select to authenticated using (true);
create policy limit_metrics_read on public.limit_metrics for select to authenticated using (true);
create policy plans_read on public.plans for select to authenticated using (true);
create policy addons_read on public.addons for select to authenticated using (true);
create policy institution_modules_read_own on public.institution_modules for select to authenticated
  using (institution_id = (select app.auth_institution_id()));
create policy institution_plan_read_own on public.institution_plan for select to authenticated
  using (institution_id = (select app.auth_institution_id()) and (select app.can('billing.view')));
create policy usage_counters_read_own on public.usage_counters for select to authenticated
  using (institution_id = (select app.auth_institution_id()));

-- Writes for an institution by platform staff: besides the Master Admin, an active platform user with the second step
-- (e.g. Billing changing a plan) writes that institution's audit rows. Same rule as before for everyone else.
create or replace function app.assert_may_write_for(p_institution uuid) returns void
language plpgsql stable set search_path = '' as $$
begin
  if p_institution is null then
    raise exception 'institution_id_required' using errcode = 'P0402';
  end if;
  if auth.uid() is null or app.is_platform_admin() or app.is_platform('platform.billing') then
    return;
  end if;
  if p_institution is distinct from app.auth_institution_id() then
    raise exception 'institution_mismatch' using errcode = 'P0403';
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. Plan of an institution; new institutions start on the plan marked for new ones (the trial)
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function app.plan_assign_new() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_plan public.plans;
begin
  select * into v_plan from public.plans where for_new order by version desc limit 1;
  if found then
    insert into public.institution_plan (institution_id, plan_key, plan_version, expires_at)
    values (new.id, v_plan.key, v_plan.version, case when v_plan.trial_days is not null then now() + make_interval(days => v_plan.trial_days) end)
    on conflict (institution_id) do nothing;
  end if;
  return null;
end $$;
create trigger institutions_plan after insert on public.institutions for each row execute function app.plan_assign_new();

-- Institutions that existed before plans: Standard, without an end date (placeholder; the Master Admin sets real plans).
insert into public.institution_plan (institution_id, plan_key, plan_version)
select i.id, 'standard', 1 from public.institutions i on conflict (institution_id) do nothing;

create or replace function app.plan_of(p_institution uuid) returns public.plans
language sql stable set search_path = '' as $$
  select p.* from public.institution_plan ip join public.plans p on p.key = ip.plan_key and p.version = ip.plan_version
   where ip.institution_id = p_institution
$$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 4. Modules in force
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function app.module_allowed(p_institution uuid, p_key text) returns boolean
language sql stable set search_path = '' as $$
  select coalesce(
    (select m.always_on from public.modules m where m.key = p_key and m.always_on),
    (select im.allowed from public.institution_modules im where im.institution_id = p_institution and im.module_key = p_key),
    (select p_key = any (p.modules) from app.plan_of(p_institution) p),
    false)
$$;

-- The institution's own choice; else its types' default (seeded at 0B.04); else the module default.
create or replace function app.module_switched_on(p_institution uuid, p_key text) returns boolean
language sql stable set search_path = '' as $$
  select coalesce(
    (select m.always_on from public.modules m where m.key = p_key and m.always_on),
    (select im.enabled from public.institution_modules im where im.institution_id = p_institution and im.module_key = p_key),
    (select (s.value)::text::boolean from public.seeded_items s
      where s.institution_id = p_institution and s.area = 'modules' and s.item_key = p_key),
    (select m.default_enabled from public.modules m where m.key = p_key),
    false)
$$;

create or replace function app.module_enabled(p_institution uuid, p_key text, p_depth integer default 0) returns boolean
language plpgsql stable set search_path = '' as $$
declare
  v_module public.modules;
begin
  select * into v_module from public.modules where key = p_key;
  if not found or p_depth > 5 then
    return false;
  end if;
  if v_module.always_on then
    return true;
  end if;
  if v_module.industry_scope is not null
     and not ((select i.industry from public.institutions i where i.id = p_institution) = any (v_module.industry_scope)) then
    return false;
  end if;
  return app.module_allowed(p_institution, p_key) and app.module_switched_on(p_institution, p_key)
     and not exists (select 1 from unnest(v_module.depends_on) d where not app.module_enabled(p_institution, d, p_depth + 1));
end $$;

-- For RPCs and job runners of the active institution.
create or replace function app.module_enabled(p_key text) returns boolean
language sql stable set search_path = '' as $$ select app.module_enabled(app.auth_institution_id(), p_key, 0) $$;

-- Branches now also need the branches module (the branches_enabled setting stays the on / off switch inside it).
create or replace function app.branches_enabled(p_institution uuid default null) returns boolean
language sql stable set search_path = '' as $$
  select coalesce((app.setting_value(coalesce(p_institution, app.auth_institution_id()), 'branches_enabled'))::boolean, false)
     and app.module_enabled(coalesce(p_institution, app.auth_institution_id()), 'branches', 0)
$$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 5. Limits and usage
-- ---------------------------------------------------------------------------------------------------------------------
-- Monthly / daily periods follow the institution's own time zone setting.
create or replace function app.usage_period(p_institution uuid, p_metric text, p_at timestamptz default now()) returns text
language sql stable set search_path = '' as $$
  select case (select period from public.limit_metrics where key = p_metric)
           when 'month' then to_char(p_at at time zone (app.setting_value(p_institution, 'time_zone') #>> '{}'), 'YYYY-MM')
           when 'day' then to_char(p_at at time zone (app.setting_value(p_institution, 'time_zone') #>> '{}'), 'YYYY-MM-DD')
           else '' end
$$;

-- The limit in force: the institution's override, else the plan; null = unlimited.
create or replace function app.limit_of(p_institution uuid, p_metric text) returns bigint
language sql stable set search_path = '' as $$
  select case when ip.limit_overrides ? p_metric then (ip.limit_overrides ->> p_metric)::bigint
              else (p.limits ->> p_metric)::bigint end
    from public.institution_plan ip join public.plans p on p.key = ip.plan_key and p.version = ip.plan_version
   where ip.institution_id = p_institution
$$;

create or replace function app.usage_of(p_institution uuid, p_metric text) returns bigint
language sql stable set search_path = '' as $$
  select coalesce((select value from public.usage_counters
                    where institution_id = p_institution and metric = p_metric and period = app.usage_period(p_institution, p_metric)), 0)
$$;

create or replace function app.limit_level(p_used bigint, p_limit bigint) returns text
language sql immutable set search_path = '' as $$
  select case when p_limit is null or p_used <= 0 then 'ok' when p_used > p_limit then 'blocked' when p_used >= p_limit then 'full'
              when p_limit > 0 and p_used * 100 >= p_limit * 80 then 'warning' else 'ok' end
$$;

-- check_limit (0B.05-T8): would adding p_delta stay within the limit? Raises limit_reached when not (p_raise), except
-- for OTP and urgent messages which are never blocked (Ch 9.5). Locks the counter row so concurrent adds queue up.
create or replace function app.check_limit(p_institution uuid, p_metric text, p_delta bigint default 1, p_purpose text default null,
                                           p_raise boolean default true) returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_limit bigint := app.limit_of(p_institution, p_metric);
  v_used  bigint;
  v_after bigint;
  v_level text;
begin
  insert into public.usage_counters (institution_id, metric, period) values (p_institution, p_metric, app.usage_period(p_institution, p_metric))
  on conflict do nothing;
  select value into v_used from public.usage_counters
   where institution_id = p_institution and metric = p_metric and period = app.usage_period(p_institution, p_metric) for update;
  v_after := v_used + greatest(p_delta, 0);
  v_level := app.limit_level(v_after, v_limit);
  if v_level = 'blocked' and coalesce(p_purpose, '') in ('otp', 'urgent') then
    v_level := 'exempt';
  end if;
  if v_level = 'blocked' and p_raise then
    raise exception 'limit_reached' using errcode = 'P0429', detail = format('%s: %s of %s', p_metric, v_used, v_limit);
  end if;
  return jsonb_build_object('metric', p_metric, 'used', v_used, 'limit', v_limit, 'after', v_after, 'level', v_level);
end $$;

-- Counts kept by triggers (+ / − one per change) and by the code that uses a metric (sms, ai … in their milestones).
-- A decrease only updates an existing row; nothing is counted for an institution that is being deleted.
create or replace function app.usage_add(p_institution uuid, p_metric text, p_delta bigint) returns void
language plpgsql set search_path = '' as $$
begin
  -- The institution itself is being deleted (its counters go with it).
  if not exists (select 1 from public.institutions where id = p_institution) then
    return;
  end if;
  if p_delta < 0 then
    update public.usage_counters set value = greatest(value + p_delta, 0), updated_at = now()
     where institution_id = p_institution and metric = p_metric and period = app.usage_period(p_institution, p_metric);
    return;
  end if;
  insert into public.usage_counters as u (institution_id, metric, period, value)
  values (p_institution, p_metric, app.usage_period(p_institution, p_metric), p_delta)
  on conflict (institution_id, metric, period) do update set value = u.value + excluded.value, updated_at = now();
end $$;

-- Users: active members. Enforced in the database (any path that adds a member), for requests made by people; seeds
-- and platform scripts (no signed-in user) are not limited.
create or replace function app.usage_members() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_was boolean := tg_op in ('UPDATE', 'DELETE') and old.status = 'active';
  v_is  boolean := tg_op in ('INSERT', 'UPDATE') and new.status = 'active';
begin
  if tg_op = 'DELETE' then
    if v_was then perform app.usage_add(old.institution_id, 'users', -1); end if;
    return old;
  end if;
  if v_is and not v_was then
    if auth.uid() is not null then
      perform app.check_limit(new.institution_id, 'users', 1);
    end if;
    perform app.usage_add(new.institution_id, 'users', 1);
  elsif v_was and not v_is then
    perform app.usage_add(new.institution_id, 'users', -1);
  end if;
  return new;
end $$;
create trigger institution_members_usage before insert or update of status or delete on public.institution_members
  for each row execute function app.usage_members();

-- Branches: active branch units.
create or replace function app.usage_branches() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_was boolean := tg_op in ('UPDATE', 'DELETE') and old.kind = 'branch' and old.archived_at is null;
  v_is  boolean := tg_op in ('INSERT', 'UPDATE') and new.kind = 'branch' and new.archived_at is null;
begin
  if tg_op = 'DELETE' then
    if v_was then perform app.usage_add(old.institution_id, 'branches', -1); end if;
    return old;
  end if;
  if v_is and not v_was then
    if auth.uid() is not null then
      perform app.check_limit(new.institution_id, 'branches', 1);
    end if;
    perform app.usage_add(new.institution_id, 'branches', 1);
  elsif v_was and not v_is then
    perform app.usage_add(new.institution_id, 'branches', -1);
  end if;
  return new;
end $$;
create trigger org_units_usage before insert or update of kind, archived_at or delete on public.org_units
  for each row execute function app.usage_branches();

-- Reconciliation (0B.05-T7, Ch 9.9 row 4): recount from the source tables; returns how many counters were wrong.
create or replace function app.usage_reconcile(p_institution uuid default null) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_fixed integer := 0;
  v_n     integer;
begin
  with truth as (
    select i.id as institution_id, 'users'::text as metric,
           (select count(*) from public.institution_members m where m.institution_id = i.id and m.status = 'active') as value
      from public.institutions i where p_institution is null or i.id = p_institution
    union all
    select i.id, 'branches', (select count(*) from public.org_units o where o.institution_id = i.id and o.kind = 'branch' and o.archived_at is null)
      from public.institutions i where p_institution is null or i.id = p_institution
  ), up as (
    insert into public.usage_counters as u (institution_id, metric, period, value)
    select t.institution_id, t.metric, '', t.value from truth t
    on conflict (institution_id, metric, period) do update set value = excluded.value, updated_at = now()
     where u.value is distinct from excluded.value
    returning 1
  ) select count(*) into v_n from up;
  v_fixed := v_fixed + v_n;
  return v_fixed;
end $$;
select app.usage_reconcile(null);
select cron.schedule('usage-reconcile', '41 3 * * *', 'select app.usage_reconcile(null)');

-- ---------------------------------------------------------------------------------------------------------------------
-- 6. Institution RPCs: modules, limits
-- ---------------------------------------------------------------------------------------------------------------------
-- Every module with its state for the active institution (menus, Home, settings use it).
create or replace function public.modules_get() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_institution uuid := app.require_active_session();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('key', m.key, 'label_key', m.label_key, 'always_on', m.always_on,
           'depends_on', to_jsonb(m.depends_on), 'built_in', m.built_in,
           'in_industry', m.industry_scope is null or (select i.industry from public.institutions i where i.id = v_institution) = any (m.industry_scope),
           'allowed', app.module_allowed(v_institution, m.key), 'switched_on', app.module_switched_on(v_institution, m.key),
           'enabled', app.module_enabled(v_institution, m.key, 0)) order by m.sort)
    from public.modules m), '[]'::jsonb);
end $$;

-- What turning a module on or off also affects (0B.04-T3 Proposed, Ch 9.9 row 2).
create or replace function app.module_impact(p_institution uuid, p_key text, p_enabled boolean) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'needs', coalesce((select jsonb_agg(d order by d) from public.modules m, unnest(m.depends_on) d
                        where m.key = p_key and p_enabled and not app.module_enabled(p_institution, d, 0)), '[]'::jsonb),
    'stops', coalesce((select jsonb_agg(m.key order by m.sort) from public.modules m
                        where not p_enabled and p_key = any (m.depends_on) and app.module_enabled(p_institution, m.key, 0)), '[]'::jsonb))
$$;

create or replace function public.module_set(p_key text, p_enabled boolean, p_confirm boolean default false) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.require_active_session();
  v_module      public.modules;
  v_impact      jsonb;
  v_before      boolean;
begin
  if not app.settings_write_allowed(v_institution, 'settings.modules') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  select * into v_module from public.modules where key = p_key;
  if not found then
    raise exception 'module_unknown' using errcode = 'P0404', detail = p_key;
  end if;
  if v_module.always_on and not p_enabled then
    raise exception 'module_always_on' using errcode = 'P0409', detail = p_key;
  end if;
  if p_enabled and not app.module_allowed(v_institution, p_key) then
    raise exception 'module_not_in_plan' using errcode = 'P0403', detail = p_key;
  end if;
  v_impact := app.module_impact(v_institution, p_key, p_enabled);
  if p_enabled and jsonb_array_length(v_impact -> 'needs') > 0 then
    raise exception 'module_needs_other' using errcode = 'P0409', detail = (v_impact -> 'needs')::text;
  end if;
  if not coalesce(p_confirm, false) then
    return jsonb_build_object('key', p_key, 'enabled', p_enabled, 'impact', v_impact, 'applied', false);
  end if;
  v_before := app.module_switched_on(v_institution, p_key);
  insert into public.institution_modules (institution_id, module_key, enabled, updated_by) values (v_institution, p_key, p_enabled, auth.uid())
  on conflict (institution_id, module_key) do update set enabled = excluded.enabled, updated_by = excluded.updated_by, updated_at = now();
  perform app.audit(v_institution, 'module.switched', 'module', p_key, jsonb_build_object('enabled', v_before),
                    jsonb_build_object('enabled', p_enabled, 'also_stops', v_impact -> 'stops'));
  return jsonb_build_object('key', p_key, 'enabled', p_enabled, 'impact', v_impact, 'applied', true,
                            'settings_version', app.bump_settings_version(v_institution));
end $$;

-- Limits for banners (any member: levels; with billing.view also the numbers and the plan).
create or replace function public.limits_status() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_institution uuid := app.require_active_session();
  v_billing     boolean := app.can('billing.view');
begin
  return jsonb_build_object(
    'plan', case when v_billing then (select jsonb_build_object('key', p.key, 'version', p.version, 'name', p.name,
               'expires_at', ip.expires_at, 'modules', to_jsonb(p.modules))
               from public.institution_plan ip join public.plans p on p.key = ip.plan_key and p.version = ip.plan_version
              where ip.institution_id = v_institution) end,
    'metrics', coalesce((select jsonb_agg(jsonb_build_object('metric', x.key, 'level', app.limit_level(x.used, x.lim),
                 'used', case when v_billing then x.used end, 'limit', case when v_billing then x.lim end) order by x.sort)
               from (select lm.key, lm.sort, app.usage_of(v_institution, lm.key) as used, app.limit_of(v_institution, lm.key) as lim
                       from public.limit_metrics lm) x
              where v_billing or app.limit_level(x.used, x.lim) <> 'ok'), '[]'::jsonb));
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 7. Master Admin: plans catalog (platform.plans), an institution's plan, overrides and allowed modules (platform.billing)
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function public.platform_plans_list() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not (app.is_platform('platform.plans') or app.is_platform('platform.billing')) then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'plans', coalesce((select jsonb_agg(to_jsonb(p) || jsonb_build_object('institutions',
               (select count(*) from public.institution_plan ip where ip.plan_key = p.key and ip.plan_version = p.version))
               order by p.sort, p.key, p.version desc) from public.plans p), '[]'::jsonb),
    'metrics', (select jsonb_agg(to_jsonb(m) order by m.sort) from public.limit_metrics m),
    'modules', (select jsonb_agg(jsonb_build_object('key', m.key, 'always_on', m.always_on, 'built_in', m.built_in) order by m.sort) from public.modules m),
    'addons', (select jsonb_agg(to_jsonb(a) order by a.sort) from public.addons a));
end $$;

-- Saves a plan as a new version (existing customers keep theirs until they change plan).
create or replace function public.platform_plan_save(p_key text, p_name jsonb, p_modules text[], p_limits jsonb, p_prices jsonb,
                                                     p_trial_days integer default null, p_notes text default null) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_version integer;
  v_before  jsonb;
begin
  if not app.is_platform('platform.plans') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  if p_key !~ '^[a-z][a-z0-9_]*$' or jsonb_typeof(p_name -> 'en') is distinct from 'string' or jsonb_typeof(p_name -> 'bn') is distinct from 'string'
     or jsonb_typeof(p_limits) is distinct from 'object' or jsonb_typeof(p_prices) is distinct from 'object' then
    raise exception 'plan_invalid' using errcode = 'P0422';
  end if;
  if exists (select 1 from unnest(p_modules) m where not exists (select 1 from public.modules x where x.key = m))
     or exists (select 1 from jsonb_object_keys(p_limits) k where not exists (select 1 from public.limit_metrics lm where lm.key = k))
     or exists (select 1 from jsonb_each(p_limits) e where jsonb_typeof(e.value) not in ('number', 'null')
                   or (jsonb_typeof(e.value) = 'number' and (e.value)::text::numeric < 0)) then
    raise exception 'plan_invalid' using errcode = 'P0422', detail = 'unknown module or metric, or a negative limit';
  end if;
  select to_jsonb(p) into v_before from public.plans p where p.key = p_key order by p.version desc limit 1;
  v_version := coalesce((v_before ->> 'version')::integer, 0) + 1;
  insert into public.plans (key, version, name, modules, limits, prices, trial_days, for_new, sort, notes, created_by)
  values (p_key, v_version, p_name, (select array_agg(distinct m order by m) from unnest(array['leads'] || p_modules) m), p_limits, p_prices,
          p_trial_days, false, coalesce((v_before ->> 'sort')::integer, 100), p_notes, auth.uid());
  -- The plan for new institutions moves to the newest version.
  if coalesce((v_before ->> 'for_new')::boolean, false) then
    update public.plans set for_new = false where key = p_key and version < v_version;
    update public.plans set for_new = true where key = p_key and version = v_version;
  end if;
  perform app.platform_audit('plan.saved', null, 'plan', p_key || ' v' || v_version, v_before,
                             jsonb_build_object('modules', to_jsonb(p_modules), 'limits', p_limits, 'prices', p_prices, 'trial_days', p_trial_days), p_notes);
  return v_version;
end $$;

-- What must be reduced to fit another plan (0B.05-T10): counts above its limits and modules it does not include.
-- Proposed: the excess becomes read-only / archived, never deleted (the action comes with billing, 0B.16).
create or replace function app.plan_fit(p_institution uuid, p_plan text) returns jsonb
language sql stable set search_path = '' as $$
  with p as (select * from public.plans where key = p_plan order by version desc limit 1)
  select jsonb_build_object(
    'over', coalesce((select jsonb_agg(jsonb_build_object('metric', lm.key, 'used', app.usage_of(p_institution, lm.key),
               'limit', (p.limits ->> lm.key)::bigint, 'reduce_by', app.usage_of(p_institution, lm.key) - (p.limits ->> lm.key)::bigint) order by lm.sort)
               from public.limit_metrics lm, p where (p.limits ->> lm.key) is not null and lm.period = 'none'
                and app.usage_of(p_institution, lm.key) > (p.limits ->> lm.key)::bigint), '[]'::jsonb),
    'modules_lost', coalesce((select jsonb_agg(m.key order by m.sort) from public.modules m, p
               where not m.always_on and not (m.key = any (p.modules)) and app.module_enabled(p_institution, m.key, 0)), '[]'::jsonb))
$$;

create or replace function public.platform_institution_plan(p_institution uuid, p_compare_plan text default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not app.is_platform('platform.billing') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'plan', (select to_jsonb(ip) || jsonb_build_object('name', p.name, 'plan_limits', p.limits, 'plan_modules', to_jsonb(p.modules),
                                                       'latest_version', (select max(p2.version) from public.plans p2 where p2.key = p.key))
               from public.institution_plan ip join public.plans p on p.key = ip.plan_key and p.version = ip.plan_version
              where ip.institution_id = p_institution),
    'usage', (select jsonb_agg(jsonb_build_object('metric', lm.key, 'used', app.usage_of(p_institution, lm.key),
               'limit', app.limit_of(p_institution, lm.key), 'level', app.limit_level(app.usage_of(p_institution, lm.key), app.limit_of(p_institution, lm.key)))
               order by lm.sort) from public.limit_metrics lm),
    'modules', (select jsonb_agg(jsonb_build_object('key', m.key, 'always_on', m.always_on,
               'override', (select im.allowed from public.institution_modules im where im.institution_id = p_institution and im.module_key = m.key),
               'allowed', app.module_allowed(p_institution, m.key), 'enabled', app.module_enabled(p_institution, m.key, 0)) order by m.sort)
               from public.modules m),
    'fit', case when p_compare_plan is not null then app.plan_fit(p_institution, p_compare_plan) end);
end $$;

create or replace function public.platform_institution_plan_set(p_institution uuid, p_plan text, p_expires_at timestamptz,
                                                                p_billing_cycle text, p_price_override numeric, p_discount_percent numeric,
                                                                p_limit_overrides jsonb, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_before jsonb;
  v_plan   public.plans;
  v_keep   boolean;
begin
  if not app.is_platform('platform.billing') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  select to_jsonb(ip) into v_before from public.institution_plan ip where ip.institution_id = p_institution;
  if v_before is null and not exists (select 1 from public.institutions where id = p_institution) then
    raise exception 'record_unknown' using errcode = 'P0404', detail = p_institution::text;
  end if;
  if jsonb_typeof(coalesce(p_limit_overrides, '{}')) <> 'object'
     or exists (select 1 from jsonb_object_keys(coalesce(p_limit_overrides, '{}')) k where not exists (select 1 from public.limit_metrics lm where lm.key = k))
     or exists (select 1 from jsonb_each(coalesce(p_limit_overrides, '{}')) e where jsonb_typeof(e.value) not in ('number', 'null')) then
    raise exception 'plan_invalid' using errcode = 'P0422', detail = 'unknown metric in the overrides';
  end if;
  -- Same plan: keep the version (price protection); another plan: its newest version.
  v_keep := v_before ->> 'plan_key' = p_plan;
  select * into v_plan from public.plans
   where key = p_plan and (not v_keep or version = (v_before ->> 'plan_version')::integer)
   order by version desc limit 1;
  if not found then
    raise exception 'plan_invalid' using errcode = 'P0422', detail = coalesce(p_plan, '');
  end if;
  insert into public.institution_plan as ip (institution_id, plan_key, plan_version, expires_at, billing_cycle, price_override,
                                             discount_percent, limit_overrides, updated_by)
  values (p_institution, v_plan.key, v_plan.version, p_expires_at, coalesce(p_billing_cycle, 'monthly'), p_price_override,
          coalesce(p_discount_percent, 0), coalesce(p_limit_overrides, '{}'), auth.uid())
  on conflict (institution_id) do update
    set plan_key = excluded.plan_key, plan_version = excluded.plan_version,
        started_at = case when ip.plan_key = excluded.plan_key then ip.started_at else now() end,
        expires_at = excluded.expires_at, billing_cycle = excluded.billing_cycle, price_override = excluded.price_override,
        discount_percent = excluded.discount_percent, limit_overrides = excluded.limit_overrides, updated_by = excluded.updated_by, updated_at = now();
  perform app.platform_audit('institution.plan_changed', p_institution, 'institution_plan', p_institution::text, v_before,
    (select to_jsonb(ip) from public.institution_plan ip where ip.institution_id = p_institution), p_reason);
  perform app.audit(p_institution, 'institution.plan_changed', 'institution_plan', p_institution::text,
    jsonb_build_object('plan', v_before ->> 'plan_key'), jsonb_build_object('plan', v_plan.key, 'version', v_plan.version), p_reason);
  perform app.bump_settings_version(p_institution);
  return app.plan_fit(p_institution, v_plan.key);
end $$;

-- Allow / disallow one module for one institution beyond its plan (null = follow the plan).
create or replace function public.platform_module_allow(p_institution uuid, p_key text, p_allowed boolean, p_reason text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_before boolean;
begin
  if not app.is_platform('platform.billing') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  if not exists (select 1 from public.modules where key = p_key and not always_on) then
    raise exception 'module_unknown' using errcode = 'P0404', detail = p_key;
  end if;
  select allowed into v_before from public.institution_modules where institution_id = p_institution and module_key = p_key;
  insert into public.institution_modules (institution_id, module_key, allowed, updated_by) values (p_institution, p_key, p_allowed, auth.uid())
  on conflict (institution_id, module_key) do update set allowed = excluded.allowed, updated_by = excluded.updated_by, updated_at = now();
  perform app.platform_audit('institution.module_allowed', p_institution, 'module', p_key, jsonb_build_object('allowed', v_before),
                             jsonb_build_object('allowed', p_allowed), p_reason);
  perform app.bump_settings_version(p_institution);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 8. Grants and registry
-- ---------------------------------------------------------------------------------------------------------------------
revoke all on function app.plan_assign_new(), app.usage_members(), app.usage_branches(), app.usage_reconcile(uuid),
  app.check_limit(uuid, text, bigint, text, boolean), app.usage_add(uuid, text, bigint) from public, anon, authenticated;
grant execute on function app.module_enabled(text), app.module_enabled(uuid, text, integer), app.module_allowed(uuid, text),
  app.module_switched_on(uuid, text), app.limit_of(uuid, text), app.usage_of(uuid, text), app.usage_period(uuid, text, timestamptz),
  app.limit_level(bigint, bigint), app.plan_of(uuid), app.module_impact(uuid, text, boolean), app.plan_fit(uuid, text) to authenticated, service_role;
revoke all on function public.modules_get(), public.module_set(text, boolean, boolean), public.limits_status(), public.platform_plans_list(),
  public.platform_plan_save(text, jsonb, text[], jsonb, jsonb, integer, text), public.platform_institution_plan(uuid, text),
  public.platform_institution_plan_set(uuid, text, timestamptz, text, numeric, numeric, jsonb, text),
  public.platform_module_allow(uuid, text, boolean, text) from public, anon;
grant execute on function public.modules_get(), public.module_set(text, boolean, boolean), public.limits_status(), public.platform_plans_list(),
  public.platform_plan_save(text, jsonb, text[], jsonb, jsonb, integer, text), public.platform_institution_plan(uuid, text),
  public.platform_institution_plan_set(uuid, text, timestamptz, text, numeric, numeric, jsonb, text),
  public.platform_module_allow(uuid, text, boolean, text) to authenticated;

insert into app.definer_registry (function_name, reason, added_in, reviewer, tenant_check)
select f, r, '0B.05', 'architecture review 0B.05', t from (values
  ('app.plan_assign_new', 'Trigger: gives a new institution the plan marked for new ones (its own row only).', 'service_role_only'),
  ('app.usage_members', 'Trigger: counts active members of the row''s institution and checks the users limit for requests by people.', 'service_role_only'),
  ('app.usage_branches', 'Trigger: counts active branches of the row''s institution and checks the branches limit for requests by people.', 'service_role_only'),
  ('app.usage_reconcile', 'Nightly job: recounts users and branches from the source tables; not callable by app roles.', 'service_role_only'),
  ('public.modules_get', 'Modules and their state for the active institution.', 'filters_active_institution'),
  ('public.module_set', 'Turns a module of the active institution on / off with an impact preview; can(settings.modules); audited.', 'filters_active_institution'),
  ('public.limits_status', 'Limit levels of the active institution (numbers and plan only with billing.view).', 'filters_active_institution'),
  ('public.platform_plans_list', 'Plans catalog, metrics, modules, add-ons (product data); needs platform.plans or platform.billing + aal2.', 'not_tenant_data'),
  ('public.platform_plan_save', 'Saves a plan as a new version; needs platform.plans + aal2; audited.', 'not_tenant_data'),
  ('public.platform_institution_plan', 'Plan, usage, modules and fit of one institution for the panel; needs platform.billing + aal2.', 'not_tenant_data'),
  ('public.platform_institution_plan_set', 'Sets an institution''s plan, expiry, price and limit overrides; needs platform.billing + aal2; audited on both sides.', 'not_tenant_data'),
  ('public.platform_module_allow', 'Allows / disallows a module for one institution beyond its plan; needs platform.billing + aal2; audited.', 'not_tenant_data')
) as v (f, r, t)
on conflict (function_name) do update set reason = excluded.reason, added_in = excluded.added_in, tenant_check = excluded.tenant_check;
