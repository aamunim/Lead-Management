-- Cross-tenant leak test (0A.05). Catalog-driven: every tenant table in `public` and `ext_*` schemas and every RPC
-- that `authenticated` can execute is probed automatically — new tables and functions are covered without new tests.
-- Loaded inside a transaction by scripts/leak-test.sh (and by the self-test); everything is rolled back.
--
-- Viewers come from supabase/seeds/0A03_tenancy.sql: institution A is the "victim", the viewers are a member of B
-- and a person who belongs to A and B but has B active (D25). Every probe runs as the real `authenticated` role
-- with claims made by the real access-token hook.

create schema leak;

create table leak.ids (k text primary key, v uuid not null);
insert into leak.ids values
  ('inst_a', 'a0000000-0000-4000-8000-00000000000a'),
  ('inst_b', 'b0000000-0000-4000-8000-00000000000b'),
  ('user_a', '11111111-1111-4111-8111-111111111111'),
  ('user_b', '22222222-2222-4222-8222-222222222222'),
  ('user_both', '33333333-3333-4333-8333-333333333333');

create function leak.id(p_key text) returns uuid language sql stable as $$ select v from leak.ids where k = p_key $$;

-- Values that must never reach a viewer of B: A's id, A-only users, and the ids of A's fixture rows.
create table leak.markers (marker text primary key, source text not null);

create table leak.findings (rule text not null, object text not null, viewer text not null, message text not null);

-- Intended visibility (not a leak), each with a reason. Kept as narrow as possible: rule + object + viewer.
create table leak.allow (
  rule   text not null,
  object text not null,
  viewer text not null,
  reason text not null check (length(reason) > 10),
  primary key (rule, object, viewer)
);

create function leak.tenant_tables() returns table (oid regclass, name text) language sql stable as $$
  select c.oid::regclass, n.nspname || '.' || c.relname
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where c.relkind in ('r', 'p')
    and (n.nspname = 'public' or n.nspname like 'ext\_%')
    and exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attname = 'institution_id' and not a.attisdropped)
  order by 2
$$;

-- A literal of the right type for a NOT NULL column without default.
create function leak.sample_value(p_type regtype, p_inst uuid) returns text language sql stable as $$
  select case
    when p_type in ('uuid'::regtype) then quote_literal(gen_random_uuid()::text) || '::uuid'
    when p_type::text in ('text', 'character varying', 'citext')
      then quote_literal('leak-' || left(p_inst::text, 8) || '-' || substr(md5(random()::text), 1, 8))
    when p_type in ('integer'::regtype, 'bigint'::regtype, 'smallint'::regtype, 'numeric'::regtype) then '1'
    when p_type = 'boolean'::regtype then 'false'
    when p_type = 'timestamp with time zone'::regtype then 'now()'
    when p_type = 'date'::regtype then 'current_date'
    when p_type in ('jsonb'::regtype, 'json'::regtype) then quote_literal('{}')
    else null
  end
$$;

-- T1 Fixtures: one row per tenant table for A and for B. A table-specific fixture function
-- leak_fixtures.<schema>__<table>(institution uuid) wins; otherwise a generic insert is tried
-- (NOT NULL columns get typed sample values, foreign keys reuse a row of the same institution).
-- A table that ends up without a row for A or B is a finding: the probe would otherwise prove nothing (T5).
create function leak.build_fixtures() returns void language plpgsql as $$
declare
  t record;
  inst uuid;
  col record;
  cols text[];
  vals text[];
  v text;
  fixture_fn text;
  failed text;
begin
  perform set_config('request.jwt.claims', '', true);
  for t in select * from leak.tenant_tables() loop
    foreach inst in array array[leak.id('inst_a'), leak.id('inst_b')] loop
      execute format('select 1 from %s where institution_id = %L limit 1', t.oid, inst) into v;
      continue when v is not null;
      fixture_fn := 'leak_fixtures.' || replace(t.name, '.', '__');
      failed := null;
      begin
        if to_regprocedure(fixture_fn || '(uuid)') is not null then
          execute format('select %s(%L::uuid)', fixture_fn, inst);
        else
          cols := array['institution_id'];
          vals := array[quote_literal(inst::text) || '::uuid'];
          for col in
            select a.attname, a.atttypid::regtype as typ,
                   (select format('(select %I from %s where %s limit 1)', ra.attname, con.confrelid::regclass,
                                  case when exists (select 1 from pg_attribute x where x.attrelid = con.confrelid
                                                    and x.attname = 'institution_id')
                                       then format('institution_id = %L', inst) else 'true' end)
                    from pg_constraint con
                    join pg_attribute ra on ra.attrelid = con.confrelid and ra.attnum = con.confkey[1]
                    where con.conrelid = t.oid and con.contype = 'f' and con.conkey[1] = a.attnum
                    limit 1) as fk_value
            from pg_attribute a
            where a.attrelid = t.oid and a.attnum > 0 and not a.attisdropped and a.attnotnull
              and not a.atthasdef and a.attidentity = '' and a.attgenerated = '' and a.attname <> 'institution_id'
          loop
            v := coalesce(col.fk_value, leak.sample_value(col.typ, inst));
            if v is null then
              raise exception 'no sample value for %.% (%)', t.name, col.attname, col.typ;
            end if;
            cols := cols || quote_ident(col.attname);
            vals := vals || v;
          end loop;
          execute format('insert into %s (%s) values (%s)', t.oid, array_to_string(cols, ', '), array_to_string(vals, ', '));
        end if;
      exception when others then
        failed := sqlerrm;
      end;
      execute format('select 1 from %s where institution_id = %L limit 1', t.oid, inst) into v;
      if v is null then
        insert into leak.findings values ('no_fixture', t.name, '-',
          format('No row for institution %s; add leak_fixtures.%s(uuid). Generic insert said: %s',
                 left(inst::text, 8), replace(t.name, '.', '__'), coalesce(failed, '-')));
      end if;
    end loop;
  end loop;
end $$;

-- Markers: A's institution id, A-only users, and every `id` of A's rows in tenant tables.
create function leak.collect_markers() returns void language plpgsql as $$
declare
  t record;
begin
  insert into leak.markers values (leak.id('inst_a')::text, 'institution A'), (leak.id('user_a')::text, 'user only in A')
  on conflict do nothing;
  for t in select * from leak.tenant_tables() loop
    if exists (select 1 from pg_attribute a where a.attrelid = t.oid and a.attname = 'id' and not a.attisdropped) then
      execute format('insert into leak.markers select id::text, %L from %s where institution_id = %L on conflict do nothing',
                     'row of ' || t.name, t.oid, leak.id('inst_a'));
    end if;
  end loop;
end $$;

-- Claims exactly as Supabase Auth would issue them for this user (real hook).
create function leak.claims_for(p_user uuid) returns jsonb language sql as $$
  select (public.custom_access_token_hook(jsonb_build_object('user_id', p_user,
          'claims', jsonb_build_object('sub', p_user, 'role', 'authenticated', 'aud', 'authenticated')))) -> 'claims'
$$;

-- T2 / T4 Table probe: as the viewer, no row of institution A may be visible in any tenant table,
-- and no A row may be visible in the platform-level tables either.
create function leak.probe_tables(p_viewer text, p_claims jsonb) returns void language plpgsql as $$
declare
  t record;
  n bigint;
  probe text;
  probes text[][] := array[
    array['public.institutions', format('select count(*) from public.institutions where id = %L', leak.id('inst_a'))],
    array['public.profiles', format('select count(*) from public.profiles where user_id = %L', leak.id('user_a'))],
    array['public.institution_members', format('select count(*) from public.institution_members where institution_id = %L', leak.id('inst_a'))],
    array['public.platform_members', 'select count(*) from public.platform_members']
  ];
  i int;
begin
  for t in select * from leak.tenant_tables() loop
    -- Build the probe BEFORE switching role: the viewer has no access to the leak schema, and a permission error
    -- from the harness itself must never be mistaken for "the viewer cannot read the table" (that hid real leaks).
    probe := format('select count(*) from %s where institution_id = %L', t.oid, leak.id('inst_a'));
    begin
      perform set_config('request.jwt.claims', p_claims::text, true);
      perform set_config('role', 'authenticated', true);
      execute probe into n;
      perform set_config('role', 'postgres', true);
      if n > 0 then
        insert into leak.findings values ('table_leak', t.name, p_viewer,
          format('%s row(s) of institution A are visible.', n));
      end if;
    exception when insufficient_privilege then
      perform set_config('role', 'postgres', true); -- no privilege at all is not a leak
    end;
  end loop;
  for i in 1 .. array_length(probes, 1) loop
    perform set_config('request.jwt.claims', p_claims::text, true);
    perform set_config('role', 'authenticated', true);
    execute probes[i][2] into n;
    perform set_config('role', 'postgres', true);
    if n > 0 then
      insert into leak.findings values ('table_leak', probes[i][1], p_viewer, format('%s row(s) belonging to A are visible.', n));
    end if;
  end loop;
end $$;

-- T3 RPC probe: call every function `authenticated` can execute in public / ext_* with A's ids as arguments.
-- The call runs as the viewer inside a subtransaction that is always rolled back (side effects undone);
-- its result travels out in the exception message. An error is fine; a result containing any marker is a leak.
create function leak.probe_rpcs(p_viewer text, p_claims jsonb) returns void language plpgsql as $$
declare
  f record;
  args text[];
  typ regtype;
  call text;
  outcome text;
  m record;
begin
  for f in
    select p.oid, n.nspname || '.' || p.proname as name, p.proretset, p.proargtypes::regtype[] as argtypes,
           p.prorettype::regtype as rettype
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where (n.nspname = 'public' or n.nspname like 'ext\_%') and p.prokind = 'f'
      and p.prorettype <> 'trigger'::regtype
      and has_function_privilege('authenticated', p.oid, 'execute')
    order by 2
  loop
    args := array[]::text[];
    if f.argtypes is not null then
      foreach typ in array f.argtypes loop
        args := args || case
          when typ = 'uuid'::regtype then quote_literal(leak.id('inst_a')::text) || '::uuid'
          when typ in ('text'::regtype, 'character varying'::regtype) then quote_literal(leak.id('inst_a')::text)
          when typ in ('integer'::regtype, 'bigint'::regtype, 'smallint'::regtype, 'numeric'::regtype) then '1'
          when typ = 'boolean'::regtype then 'true'
          when typ in ('jsonb'::regtype, 'json'::regtype) then quote_literal(jsonb_build_object('institution_id', leak.id('inst_a'), 'id', leak.id('inst_a'))::text)
          else 'null::' || typ::text
        end;
      end loop;
    end if;
    call := format('select coalesce(jsonb_agg(to_jsonb(r))::text, '''') from %s(%s) as r', f.name, array_to_string(args, ', '));
    begin
      begin
        perform set_config('request.jwt.claims', p_claims::text, true);
        perform set_config('role', 'authenticated', true);
        execute call into outcome;
        raise exception using errcode = 'LK001', message = 'leak_probe_result:' || coalesce(outcome, '');
      exception when sqlstate 'LK001' then
        outcome := substr(sqlerrm, length('leak_probe_result:') + 1);
      end;
    exception when others then
      outcome := null; -- the RPC refused: not a leak
    end;
    perform set_config('role', 'postgres', true);
    if outcome is not null then
      for m in select * from leak.markers loop
        if position(m.marker in outcome) > 0 then
          insert into leak.findings values ('rpc_leak', f.name, p_viewer,
            format('Called with A''s ids, the result contains %s (%s).', left(m.marker, 8), m.source));
          exit;
        end if;
      end loop;
    end if;
  end loop;
end $$;



-- Runs a counting query as the viewer; an error (no privilege, refused by a trigger) counts as 0 rows affected.
create function leak.run_as_count(p_sql text, p_claims jsonb) returns bigint language plpgsql as $$
declare
  n bigint;
begin
  perform set_config('request.jwt.claims', p_claims::text, true);
  perform set_config('role', 'authenticated', true);
  execute p_sql into n;
  perform set_config('role', 'postgres', true);
  return coalesce(n, 0);
exception when others then
  perform set_config('role', 'postgres', true);
  return 0;
end $$;

-- 0A.06 Storage probe: in every bucket, a viewer of B may not read, list, overwrite, move or delete objects stored
-- under A's folder, nor create objects there. A public bucket serves files without RLS and is a finding unless
-- allow-listed with a reason.
create function leak.probe_storage(p_viewer text, p_claims jsonb) returns void language plpgsql as $$
declare
  b record;
  v_path text;
  v_seen bigint;
  v_changed bigint;
  v_insert_error text;
  q_select text; q_update text; q_delete text; q_insert text;
begin
  for b in select id, public from storage.buckets order by id loop
    if b.public then
      insert into leak.findings values ('storage_public_bucket', 'storage.buckets/' || b.id, p_viewer,
        'Public bucket: its files are readable by anyone with the URL, without RLS.');
    end if;
    v_path := leak.id('inst_a')::text || '/leak-probe/' || b.id || '.txt';
    perform set_config('request.jwt.claims', '', true);
    insert into storage.objects (bucket_id, name) values (b.id, v_path) on conflict do nothing;
    insert into leak.markers values (v_path, 'storage object of A') on conflict do nothing;
    q_select := format('select count(*) from storage.objects where bucket_id = %L and name like %L', b.id, leak.id('inst_a')::text || '/%');
    q_update := format('with u as (update storage.objects set name = name || %L where bucket_id = %L and name = %L returning 1) select count(*) from u',
                       '.moved', b.id, v_path);
    q_delete := format('with d as (delete from storage.objects where bucket_id = %L and name = %L returning 1) select count(*) from d', b.id, v_path);
    q_insert := format('insert into storage.objects (bucket_id, name) values (%L, %L)', b.id, leak.id('inst_a')::text || '/leak-probe/planted.txt');
    -- Each probe in its own block: an error in one (e.g. a storage trigger refusing a rename) must not hide another.
    v_seen := leak.run_as_count(q_select, p_claims);
    perform leak.run_as_count(q_update, p_claims);
    perform leak.run_as_count(q_delete, p_claims);
    if v_seen > 0 then
      insert into leak.findings values ('storage_leak', 'storage.buckets/' || b.id, p_viewer,
        format('%s object(s) under A''s folder are visible.', v_seen));
    end if;
    if not exists (select 1 from storage.objects where bucket_id = b.id and name = v_path) then
      insert into leak.findings values ('storage_leak', 'storage.buckets/' || b.id, p_viewer,
        'An object under A''s folder could be moved or deleted.');
      perform set_config('request.jwt.claims', '', true);
      insert into storage.objects (bucket_id, name) values (b.id, v_path) on conflict do nothing;
    end if;
    v_insert_error := null;
    begin
      begin
        perform set_config('request.jwt.claims', p_claims::text, true);
        perform set_config('role', 'authenticated', true);
        execute q_insert;
        raise exception using errcode = 'LK002', message = 'planted';
      exception when sqlstate 'LK002' then
        v_insert_error := null; -- the insert succeeded (then rolled back)
      end;
    exception when others then
      v_insert_error := sqlerrm;
    end;
    perform set_config('role', 'postgres', true);
    if v_insert_error is null then
      insert into leak.findings values ('storage_leak', 'storage.buckets/' || b.id, p_viewer,
        'An object can be created under A''s folder.');
    end if;
  end loop;
end $$;

-- 0A.06 Realtime probe:
--  * every table published to Realtime must be a tenant table (its postgres_changes follow the table RLS, which the
--    table probe checks), unless allow-listed;
--  * private broadcast / presence channels: a viewer of B may not receive or send on A's channel inst:<A>:<topic>.
create function leak.probe_realtime(p_viewer text, p_claims jsonb) returns void language plpgsql as $$
declare
  r record;
  v_topic text := 'inst:' || leak.id('inst_a')::text || ':leak-probe';
  v_seen bigint;
  v_send_error text;
  q_select text;
  q_insert text;
begin
  for r in select schemaname || '.' || tablename as obj from pg_publication_tables where pubname = 'supabase_realtime' loop
    if not exists (select 1 from leak.tenant_tables() t where t.name = r.obj) then
      insert into leak.findings values ('realtime_table', r.obj, p_viewer,
        'Published to Realtime but not a tenant table (no institution_id); changes could reach every subscriber.');
    end if;
  end loop;

  perform set_config('request.jwt.claims', '', true);
  insert into realtime.messages (topic, extension, payload, event, private)
  values (v_topic, 'broadcast', jsonb_build_object('marker', leak.id('inst_a')), 'probe', true);
  q_select := format('select count(*) from realtime.messages where topic = %L', v_topic);
  q_insert := format('insert into realtime.messages (topic, extension, payload, event, private) values (%L, %L, %L, %L, true)',
                     v_topic, 'broadcast', '{}', 'planted');
  begin
    perform set_config('request.jwt.claims', p_claims::text, true);
    perform set_config('realtime.topic', v_topic, true);
    perform set_config('role', 'authenticated', true);
    execute q_select into v_seen;
    perform set_config('role', 'postgres', true);
  exception when insufficient_privilege then
    perform set_config('role', 'postgres', true);
    v_seen := 0;
  end;
  if v_seen > 0 then
    insert into leak.findings values ('realtime_leak', 'channel inst:<A>:*', p_viewer,
      'A viewer of B can receive messages on A''s private channel.');
  end if;
  v_send_error := null;
  begin
    begin
      perform set_config('request.jwt.claims', p_claims::text, true);
      perform set_config('realtime.topic', v_topic, true);
      perform set_config('role', 'authenticated', true);
      execute q_insert;
      raise exception using errcode = 'LK003', message = 'sent';
    exception when sqlstate 'LK003' then
      v_send_error := null;
    end;
  exception when others then
    v_send_error := sqlerrm;
  end;
  perform set_config('role', 'postgres', true);
  perform set_config('realtime.topic', '', true);
  if v_send_error is null then
    insert into leak.findings values ('realtime_leak', 'channel inst:<A>:*', p_viewer,
      'A viewer of B can send on A''s private channel.');
  end if;
end $$;

-- T7 Placeholders that fail safe until their probes exist: Storage and Realtime (0A.06).
create function leak.probe_placeholders() returns void language plpgsql as $$
begin
  if to_regclass('storage.buckets') is not null and exists (select 1 from storage.buckets)
     and to_regprocedure('leak.probe_storage(text,jsonb)') is null then
    insert into leak.findings values ('storage_unprobed', 'storage.buckets', '-',
      'Storage buckets exist but the storage leak probe (0A.06) is not implemented yet.');
  end if;
  if exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime'
             and (schemaname = 'public' or schemaname like 'ext\_%'))
     and to_regprocedure('leak.probe_realtime(text,jsonb)') is null then
    insert into leak.findings values ('realtime_unprobed', 'supabase_realtime', '-',
      'Tables are published to Realtime but the Realtime leak probe (0A.06) is not implemented yet.');
  end if;
end $$;

create function leak.run() returns setof leak.findings language plpgsql as $$
declare
  v_b jsonb;
  v_both jsonb;
begin
  delete from leak.findings;
  perform leak.build_fixtures();
  perform leak.collect_markers();
  -- Viewer 1: a member of B only.  Viewer 2: a member of A and B with B active (D25).
  update public.profiles set last_active_institution_id = leak.id('inst_b') where user_id = leak.id('user_both');
  v_b := leak.claims_for(leak.id('user_b'));
  v_both := leak.claims_for(leak.id('user_both'));
  if (v_b ->> 'active_institution_id')::uuid is distinct from leak.id('inst_b')
     or (v_both ->> 'active_institution_id')::uuid is distinct from leak.id('inst_b') then
    raise exception 'leak test set-up: viewers must have institution B active (check the 0A.03 seed)';
  end if;
  perform leak.probe_tables('member of B', v_b);
  perform leak.probe_tables('member of A and B, B active', v_both);
  perform leak.probe_rpcs('member of B', v_b);
  perform leak.probe_rpcs('member of A and B, B active', v_both);
  perform leak.probe_storage('member of B', v_b);
  perform leak.probe_storage('member of A and B, B active', v_both);
  perform leak.probe_realtime('member of B', v_b);
  perform leak.probe_realtime('member of A and B, B active', v_both);
  perform leak.probe_placeholders();
  return query select f.* from leak.findings f
    where not exists (select 1 from leak.allow a where a.rule = f.rule and a.object = f.object and a.viewer = f.viewer)
    order by f.rule, f.object, f.viewer;
end $$;

create function leak.report() returns void language plpgsql as $$
declare
  r record;
  n int := 0;
  tables int;
  rpcs int;
begin
  for r in select * from leak.run() loop
    n := n + 1;
    raise warning 'LEAK [%] % (viewer: %): %', r.rule, r.object, r.viewer, r.message;
  end loop;
  select count(*) into tables from leak.tenant_tables();
  select count(*) into rpcs from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where (ns.nspname = 'public' or ns.nspname like 'ext\_%') and p.prokind = 'f'
     and p.prorettype <> 'trigger'::regtype and has_function_privilege('authenticated', p.oid, 'execute');
  for r in select a.* from leak.allow a
           where exists (select 1 from leak.findings f where f.rule = a.rule and f.object = a.object and f.viewer = a.viewer) loop
    raise notice 'allowed (%): % for viewer "%" — %', r.rule, r.object, r.viewer, r.reason;
  end loop;
  if n > 0 then
    raise exception 'Cross-tenant leak test failed with % finding(s).', n;
  end if;
  raise notice 'Cross-tenant leak test passed: % tenant table(s) + 4 platform tables, % RPC(s), % storage bucket(s), % Realtime table(s) + private channels, 2 viewers.',
    tables, rpcs, (select count(*) from storage.buckets),
    (select count(*) from pg_publication_tables where pubname = 'supabase_realtime');
end $$;
