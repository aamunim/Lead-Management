-- 0A.04 lint fixtures: every rule must catch a deliberately bad object, and a correct tenant table must pass.
-- Run with `npm run test:lint`. Everything is rolled back.
\set ON_ERROR_STOP on
begin;
\i supabase/lint/lint_functions.sql
\i supabase/lint/allowlist.sql

create function pg_temp.check(cond boolean, what text) returns void language plpgsql as $$
begin
  if cond is distinct from true then raise exception 'FAILED: %', what; end if;
  raise notice 'ok - %', what;
end $$;
create function pg_temp.found(p_rule text, p_object_like text) returns boolean language sql as $$
  select exists (select 1 from lint.findings() f where f.rule = p_rule and f.object like p_object_like)
$$;

select pg_temp.check(not exists (select 1 from lint.findings()), 'the committed schema has no findings');

-- ---------------------------------------------------------------------------------------------------------------------
-- A correct tenant table (the template in docs/dev/TENANCY.md) must produce no findings.
-- ---------------------------------------------------------------------------------------------------------------------
create table public.fixture_good (
  institution_id uuid not null,
  id uuid not null default gen_random_uuid(),
  title text,
  created_at timestamptz not null default now(),
  primary key (institution_id, id),
  unique (institution_id, title)
);
alter table public.fixture_good enable row level security;
create policy fixture_good_tenant on public.fixture_good to authenticated
  using (institution_id = (select app.auth_institution_id()))
  with check (institution_id = (select app.auth_institution_id()));
select app.attach_status_guard('public.fixture_good');
create function public.fixture_good_rpc() returns uuid language plpgsql set search_path = '' as $$
begin
  return app.require_active_session();
end $$;
select pg_temp.check(not exists (select 1 from lint.findings() where object like '%fixture_good%'),
                     'correct tenant table and RPC pass every rule');

-- ---------------------------------------------------------------------------------------------------------------------
-- One bad fixture per rule
-- ---------------------------------------------------------------------------------------------------------------------
create table public.fixture_no_tenant (id serial primary key, note text);
select pg_temp.check(pg_temp.found('tenant_institution_id', 'public.fixture_no_tenant'),
                     'R1 tenant_institution_id: table without institution_id is caught');
select pg_temp.check(pg_temp.found('rls_enabled', 'public.fixture_no_tenant'),
                     'R2 rls_enabled: table without RLS is caught');

create table public.fixture_rls_no_policy (institution_id uuid not null, id int, primary key (institution_id, id));
alter table public.fixture_rls_no_policy enable row level security;
select pg_temp.check(pg_temp.found('rls_enabled', 'public.fixture_rls_no_policy'),
                     'R2 rls_enabled: RLS without any policy is caught');

create table public.fixture_bad_index (institution_id uuid not null, id int, code text, primary key (institution_id, id));
create index fixture_bad_index_code on public.fixture_bad_index (code);
create unique index fixture_bad_unique on public.fixture_bad_index (code);
select pg_temp.check(pg_temp.found('index_leading_institution', '%fixture_bad_index_code'),
                     'R3 index_leading_institution: index not led by institution_id is caught');
select pg_temp.check(pg_temp.found('unique_includes_institution', '%fixture_bad_unique'),
                     'R4 unique_includes_institution: global unique on a tenant table is caught');

create table public.leads (institution_id uuid not null, id int, primary key (institution_id, id));
select pg_temp.check(pg_temp.found('branch_id', 'public.leads'),
                     'R5 branch_id: core record table without branch_id is caught');
drop table public.leads;

create table public.fixture_naive_time (institution_id uuid not null, id int, at timestamp, primary key (institution_id, id));
select pg_temp.check(pg_temp.found('timestamptz', 'public.fixture_naive_time.at'),
                     'R6 timestamptz: timestamp without time zone is caught');

create table public.fixture_student_card (institution_id uuid not null, course_id int, primary key (institution_id, course_id));
select pg_temp.check(pg_temp.found('neutral_names', 'public.fixture_student_card'),
                     'R7 neutral_names: education word in a table name is caught');
select pg_temp.check(pg_temp.found('neutral_names', 'public.fixture_student_card.course_id'),
                     'R7 neutral_names: education word in a column name is caught');

create function public.fixture_definer_unregistered() returns int language sql security definer set search_path = '' as $$
  select 1
$$;
select pg_temp.check(pg_temp.found('definer_registered', 'public.fixture_definer_unregistered'),
                     'R8 definer_registered: unregistered SECURITY DEFINER is caught');

create function public.fixture_definer_no_check() returns int language sql security definer set search_path = '' as $$
  select 1
$$;
insert into app.definer_registry (function_name, reason, added_in) values
  ('public.fixture_definer_no_check', 'fixture: registered but does not filter by institution', 'test');
select pg_temp.check(pg_temp.found('definer_tenant_check', 'public.fixture_definer_no_check'),
                     'R9 definer_tenant_check: DEFINER without an institution filter is caught');

create function public.fixture_service_reader() returns int language sql security definer set search_path = '' as $$
  select 1
$$;
insert into app.definer_registry (function_name, reason, added_in, tenant_check) values
  ('public.fixture_service_reader', 'fixture: claims to be service-only but is granted to app users', 'test', 'service_role_only');
grant execute on function public.fixture_service_reader() to authenticated;
select pg_temp.check(pg_temp.found('definer_service_only', 'public.fixture_service_reader'),
                     'R9b definer_service_only: a service-only function callable by app users is caught');

create function public.fixture_no_search_path() returns int language sql as $$ select 1 $$;
select pg_temp.check(pg_temp.found('search_path', 'public.fixture_no_search_path'),
                     'R10 search_path: function without a pinned search_path is caught');

-- R11 lesson 1: an INVOKER function the app can call, calling a helper revoked from authenticated.
create function app.fixture_locked_helper() returns int language sql set search_path = '' as $$ select 1 $$;
revoke execute on function app.fixture_locked_helper() from public, authenticated, anon;
create function public.fixture_reader() returns int language sql set search_path = '' as $$
  select app.fixture_locked_helper()
$$;
grant execute on function public.fixture_reader() to authenticated;
select pg_temp.check(pg_temp.found('invoker_sweep', 'public.fixture_reader -> app.fixture_locked_helper'),
                     'R11 invoker_sweep: invoker calling a revoked helper is caught (lesson 1)');

create function public.fixture_report() returns int language plpgsql set search_path = '' as $$
begin
  -- heavy
  return 1;
end $$;
select pg_temp.check(pg_temp.found('heavy_jit_off', 'public.fixture_report'),
                     'R12 heavy_jit_off: heavy function without "set jit = off" is caught');

create table public.fixture_bad_policy (institution_id uuid not null, id int, primary key (institution_id, id));
alter table public.fixture_bad_policy enable row level security;
create policy fixture_bad_policy_tenant on public.fixture_bad_policy to authenticated
  using (institution_id = app.auth_institution_id());
select pg_temp.check(pg_temp.found('rls_initplan', 'public.fixture_bad_policy%'),
                     'R13 rls_initplan: unwrapped session helper in a policy is caught');

create function public.fixture_type_branch() returns text language plpgsql set search_path = '' as $$
declare v text;
begin
  select institution_type into v from public.institutions limit 1;
  return v;
end $$;
select pg_temp.check(pg_temp.found('institution_type', 'public.fixture_type_branch'),
                     'R14 institution_type: behaviour depending on institution_type is caught');

-- An allow-listed exception (with a reason) silences exactly that finding.
insert into lint.allow values ('index_leading_institution', 'fixture_bad_index_code', 'fixture: allow-list works with a reason');
select pg_temp.check(not pg_temp.found('index_leading_institution', '%fixture_bad_index_code'),
                     'allow-list: a documented exception silences only that finding');
select pg_temp.check(pg_temp.found('unique_includes_institution', '%fixture_bad_unique'),
                     'allow-list: other findings on the same table remain');

-- Extension schemas (ext_*) are checked by the same rules (0A.09).
create schema ext_fixture;
create table ext_fixture.no_tenant (id uuid primary key);
create table ext_fixture.no_rls (institution_id uuid not null, id uuid not null, primary key (institution_id, id));
create function ext_fixture.no_path() returns int language sql as 'select 1';
select pg_temp.check(pg_temp.found('tenant_institution_id', 'ext_fixture.no_tenant'), 'extension table without institution_id is caught');
select pg_temp.check(pg_temp.found('rls_enabled', 'ext_fixture.no_rls'), 'extension table without RLS is caught');
select pg_temp.check(pg_temp.found('search_path', 'ext_fixture.no_path'), 'extension function without search_path is caught');

-- Phone columns must be ASCII-only (0A.11).
create table public.fixture_phone (institution_id uuid not null, id uuid not null, mobile_phone text, primary key (institution_id, id));
alter table public.fixture_phone enable row level security;
create policy fixture_phone_p on public.fixture_phone to authenticated using (institution_id = (select app.auth_institution_id()));
select pg_temp.check(pg_temp.found('phone_ascii', 'public.fixture_phone.mobile_phone'), 'phone column without the ASCII check is caught');
alter table public.fixture_phone add constraint fixture_phone_ascii check (app.is_ascii_phone(mobile_phone));
select pg_temp.check(not pg_temp.found('phone_ascii', 'public.fixture_phone.mobile_phone'), '...and passes with the check');

-- Write RPCs must check permission (0A.17).
create function public.fixture_write_rpc() returns void language plpgsql security definer set search_path = '' as $$
begin
  perform app.require_active_session();
  delete from public.fixture_good;
end $$;
grant execute on function public.fixture_write_rpc() to authenticated;
insert into app.definer_registry (function_name, reason, added_in, reviewer, tenant_check)
  values ('public.fixture_write_rpc', 'fixture for the write_needs_can rule', 'test', 'test', 'filters_active_institution');
select pg_temp.check(pg_temp.found('write_needs_can', 'public.fixture_write_rpc'), 'a write RPC without can() is caught');

-- The report fails the run when there is any finding.
-- R15: a tenant table without the lifecycle guard.
create table public.fixture_no_guard (institution_id uuid not null, id uuid not null default gen_random_uuid(), primary key (institution_id, id));
alter table public.fixture_no_guard enable row level security;
create policy fixture_no_guard_tenant on public.fixture_no_guard to authenticated using (institution_id = (select app.auth_institution_id()));
select pg_temp.check(pg_temp.found('status_guard', 'public.fixture_no_guard'), 'a tenant table without the lifecycle guard is caught');

select pg_temp.check((select count(*) from lint.findings()) > 0, 'there are findings now');
do $$
begin
  perform lint.report();
  raise exception 'FAILED: report should have failed';
exception when others then
  if sqlerrm like 'FAILED:%' then raise; end if;
  raise notice 'ok - report() fails the run when findings exist';
end $$;

rollback;
