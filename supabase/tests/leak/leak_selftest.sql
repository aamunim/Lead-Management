-- 0A.05 self-test: the leak test must catch a missing / wrong policy, a leaking RPC, a table it cannot fill,
-- and unprobed Realtime; a correct tenant table (with a foreign key) must pass. Everything is rolled back.
\set ON_ERROR_STOP on
begin;
\i supabase/tests/leak/leak_functions.sql
create schema leak_fixtures;
\i supabase/tests/leak/fixtures/all.sql
\i supabase/tests/leak/allowlist.sql

create function pg_temp.check(cond boolean, what text) returns void language plpgsql as $$
begin
  if cond is distinct from true then raise exception 'FAILED: %', what; end if;
  raise notice 'ok - %', what;
end $$;

-- A correct tenant table and a child table with a foreign key (generic fixtures must fill both).
create table public.selftest_good (
  institution_id uuid not null, id uuid not null default gen_random_uuid(), title text not null,
  primary key (institution_id, id), unique (id));
alter table public.selftest_good enable row level security;
create policy selftest_good_tenant on public.selftest_good to authenticated
  using (institution_id = (select app.auth_institution_id())) with check (institution_id = (select app.auth_institution_id()));
grant select on public.selftest_good to authenticated;
create table public.selftest_good_child (
  institution_id uuid not null, id uuid not null default gen_random_uuid(),
  parent_id uuid not null references public.selftest_good (id), amount integer not null,
  primary key (institution_id, id));
alter table public.selftest_good_child enable row level security;
create policy selftest_child_tenant on public.selftest_good_child to authenticated
  using (institution_id = (select app.auth_institution_id()));
grant select on public.selftest_good_child to authenticated;

-- A table whose policy was "forgotten": readable by everyone signed in.
create table public.selftest_leaky (institution_id uuid not null, id uuid not null default gen_random_uuid(), note text,
  primary key (institution_id, id));
alter table public.selftest_leaky enable row level security;
create policy selftest_leaky_all on public.selftest_leaky to authenticated using (true);
grant select on public.selftest_leaky to authenticated;

-- An RPC that bypasses RLS and returns rows of any institution.
create function public.selftest_leaky_rpc(p_institution uuid) returns setof public.selftest_good
language sql security definer set search_path = '' as $$
  select * from public.selftest_good where institution_id = p_institution $$;
grant execute on function public.selftest_leaky_rpc(uuid) to authenticated;

-- A table the generic fixture builder cannot fill (custom type, no fixture function).
create type public.selftest_mood as enum ('calm', 'busy');
create table public.selftest_unfillable (institution_id uuid not null, mood public.selftest_mood not null,
  primary key (institution_id, mood));
alter table public.selftest_unfillable enable row level security;
create policy selftest_unfillable_tenant on public.selftest_unfillable to authenticated
  using (institution_id = (select app.auth_institution_id()));

-- Storage: a bucket whose policy forgot the institution folder, and a public bucket.
insert into storage.buckets (id, name, public) values ('selftest-open', 'selftest-open', false),
                                                      ('selftest-public', 'selftest-public', true);
create policy selftest_open_all on storage.objects for all to authenticated
  using (bucket_id = 'selftest-open') with check (bucket_id = 'selftest-open');

-- Realtime: a tenant table (fine), a non-tenant table (finding), and a channel policy that forgot the institution.
alter publication supabase_realtime add table public.selftest_good;
create table public.selftest_global (id int primary key);
alter table public.selftest_global enable row level security;
create policy selftest_global_read on public.selftest_global to authenticated using (true);
alter publication supabase_realtime add table public.selftest_global;
create policy selftest_channels_open on realtime.messages for select to authenticated
  using ((select realtime.topic()) like 'inst:%');

create temp table result as select * from leak.run();

select pg_temp.check(exists (select 1 from result where rule = 'table_leak' and object = 'public.selftest_leaky'
                             and viewer = 'member of B'), 'a forgotten / permissive policy is caught (viewer: member of B)');
select pg_temp.check(exists (select 1 from result where rule = 'table_leak' and object = 'public.selftest_leaky'
                             and viewer = 'member of A and B, B active'), 'the same leak is caught for the dual member (D25)');
select pg_temp.check(exists (select 1 from result where rule = 'rpc_leak' and object = 'public.selftest_leaky_rpc'),
                     'an RPC returning another institution''s rows is caught');
select pg_temp.check(exists (select 1 from result where rule = 'no_fixture' and object = 'public.selftest_unfillable'),
                     'a table without fixtures fails the run');
select pg_temp.check(exists (select 1 from result where rule = 'storage_leak' and object = 'storage.buckets/selftest-open'
                             and message like '%visible%'), 'storage: a policy without the institution folder lets B read A''s files');
select pg_temp.check(exists (select 1 from result where rule = 'storage_leak' and object = 'storage.buckets/selftest-open'
                             and message like '%moved or deleted%'), 'storage: ...and move or delete them');
select pg_temp.check(exists (select 1 from result where rule = 'storage_leak' and object = 'storage.buckets/selftest-open'
                             and message like '%created%'), 'storage: ...and plant files in A''s folder');
select pg_temp.check(exists (select 1 from result where rule = 'storage_public_bucket' and object = 'storage.buckets/selftest-public'),
                     'storage: a public bucket is reported');
select pg_temp.check(not exists (select 1 from result where object = 'storage.buckets/institution-files'),
                     'storage: the real institution-files bucket passes every storage probe');
select pg_temp.check(exists (select 1 from result where rule = 'realtime_table' and object = 'public.selftest_global'),
                     'realtime: a published table without institution_id is reported');
select pg_temp.check(not exists (select 1 from result where rule = 'realtime_table' and object = 'public.selftest_good'),
                     'realtime: a published tenant table is fine (its RLS is probed as a table)');
select pg_temp.check(exists (select 1 from result where rule = 'realtime_leak' and message like '%receive%'),
                     'realtime: a channel policy without the institution lets B receive A''s messages');
select pg_temp.check(not exists (select 1 from result where object like 'public.selftest_good%'),
                     'a correct tenant table and its child (foreign key) pass, with generic fixtures');
select pg_temp.check((select count(*) from public.selftest_good_child) = 2,
                     'generic fixtures filled the child table for A and B through the foreign key');
select pg_temp.check(not exists (select 1 from result where object in ('public.institutions', 'public.institution_members',
                     'public.set_active_institution')), 'allow-listed own-membership visibility is not reported');
select pg_temp.check(not exists (select 1 from result where viewer = 'member of B'
                     and object in ('public.institutions', 'public.institution_members', 'public.profiles', 'public.platform_members')),
                     'a member of B only sees nothing of A in the platform tables');
rollback;
