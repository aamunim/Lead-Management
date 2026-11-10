-- Schema lint (0A.04). Reads the real catalog of a migrated database and reports rule violations.
-- Loaded inside a transaction by scripts/schema-lint.sh and by the fixture tests; everything is rolled back.
-- Rules and their plan references are listed in docs/dev/SCHEMA_LINT.md.

create schema lint;

-- Exceptions. Every exception needs a reason (supabase/lint/allowlist.sql).
create table lint.allow (
  rule   text not null,
  object text not null,
  reason text not null check (length(reason) > 10),
  primary key (rule, object)
);

-- Tables that must carry a nullable branch_id once they exist (D9, Ch 12.3).
create table lint.branch_tables (table_name text primary key);
insert into lint.branch_tables values
  ('public.institution_members'), ('public.leads'), ('public.clients'), ('public.offerings'),
  ('public.cohorts'), ('public.payments');

-- Education words that must not appear in internal names (neutral keys, Ch 8.3).
create table lint.forbidden_words (word text primary key, use_instead text not null);
insert into lint.forbidden_words values
  ('student', 'client'), ('students', 'clients'), ('course', 'offering'), ('courses', 'offerings'),
  ('batch', 'cohort'), ('batches', 'cohorts'), ('admission', 'conversion'), ('admissions', 'conversions'),
  ('guardian', 'contact_person'), ('guardians', 'contact_persons'), ('alumni', 'network'), ('alumnus', 'network'),
  ('college', 'institution'), ('school', 'institution'), ('papers', 'documents');

create function lint.is_allowed(p_rule text, p_object text) returns boolean language sql stable as $$
  select exists (select 1 from lint.allow a where a.rule = p_rule and a.object = p_object)
$$;

-- Schemas we own and check.
create function lint.our_schemas() returns text[] language sql immutable as $$ select array['public', 'app'] $$;

create function lint.findings() returns table (rule text, object text, message text)
language plpgsql as $$
declare
  r record;
  v_callee text;
  v_schema text;
  v_name text;
  v_exec boolean;
  v_rest text;
begin
  -- R1 tenant tables need institution_id NOT NULL ------------------------------------------------------------------
  for r in
    select c.oid, n.nspname || '.' || c.relname as obj
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where c.relkind in ('r', 'p') and n.nspname = any (lint.our_schemas())
  loop
    if lint.is_allowed('platform_table', r.obj) then continue; end if;
    if not exists (select 1 from pg_attribute a where a.attrelid = r.oid and a.attname = 'institution_id'
                   and not a.attisdropped and a.attnotnull) then
      rule := 'tenant_institution_id'; object := r.obj;
      message := 'Tenant table must have "institution_id uuid not null" (or be allow-listed as a platform table).';
      return next;
    end if;
  end loop;

  -- R2 RLS enabled with at least one policy (public = exposed through the API) ------------------------------------
  for r in
    select c.oid, c.relrowsecurity, n.nspname || '.' || c.relname as obj
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where c.relkind in ('r', 'p') and n.nspname = 'public'
  loop
    if not r.relrowsecurity then
      rule := 'rls_enabled'; object := r.obj; message := 'Row level security is not enabled.'; return next;
    elsif not exists (select 1 from pg_policy p where p.polrelid = r.oid) and not lint.is_allowed('rls_enabled', r.obj) then
      rule := 'rls_enabled'; object := r.obj; message := 'RLS is enabled but the table has no policy.'; return next;
    end if;
  end loop;

  -- R3 every index on a tenant table starts with institution_id ----------------------------------------------------
  -- R4 unique indexes on tenant tables include institution_id ----------------------------------------------------
  for r in
    select i.indexrelid, i.indisunique, ic.relname as index_name, n.nspname || '.' || t.relname as tbl,
           (select a.attname from pg_attribute a where a.attrelid = t.oid and a.attnum = i.indkey[0]) as first_col,
           exists (select 1 from unnest(i.indkey) k join pg_attribute a on a.attrelid = t.oid and a.attnum = k
                   where a.attname = 'institution_id') as has_inst
    from pg_index i
    join pg_class t on t.oid = i.indrelid
    join pg_class ic on ic.oid = i.indexrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = any (lint.our_schemas())
      and exists (select 1 from pg_attribute a where a.attrelid = t.oid and a.attname = 'institution_id' and not a.attisdropped)
  loop
    if coalesce(r.first_col, '') <> 'institution_id' and not lint.is_allowed('index_leading_institution', r.index_name) then
      rule := 'index_leading_institution'; object := r.tbl || ' / ' || r.index_name;
      message := 'Index must start with institution_id (or be allow-listed with a reason).'; return next;
    end if;
    if r.indisunique and not r.has_inst and not lint.is_allowed('unique_includes_institution', r.index_name) then
      rule := 'unique_includes_institution'; object := r.tbl || ' / ' || r.index_name;
      message := 'Unique constraint on a tenant table must include institution_id (uniqueness is per institution).';
      return next;
    end if;
  end loop;

  -- R5 branch_id on core record tables ------------------------------------------------------------------------------
  for r in
    select bt.table_name, c.oid
    from lint.branch_tables bt
    join pg_class c on c.oid = to_regclass(bt.table_name)
  loop
    if not exists (select 1 from pg_attribute a where a.attrelid = r.oid and a.attname = 'branch_id'
                   and not a.attisdropped and not a.attnotnull) then
      rule := 'branch_id'; object := r.table_name; message := 'Core record table must have a nullable branch_id (D9).';
      return next;
    end if;
  end loop;

  -- R6 timestamps with time zone ------------------------------------------------------------------------------------
  for r in
    select n.nspname || '.' || c.relname || '.' || a.attname as obj
    from pg_attribute a
    join pg_class c on c.oid = a.attrelid
    join pg_namespace n on n.oid = c.relnamespace
    where c.relkind in ('r', 'p', 'v', 'm') and n.nspname = any (lint.our_schemas())
      and a.attnum > 0 and not a.attisdropped and a.atttypid = 'timestamp'::regtype
  loop
    rule := 'timestamptz'; object := r.obj; message := 'Use timestamptz (or date for date-only values).'; return next;
  end loop;

  -- R7 neutral names: no education words in tables, columns, functions ---------------------------------------------
  for r in
    with names as (
      select 'table' as kind, n.nspname || '.' || c.relname as obj, c.relname as name
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where c.relkind in ('r', 'p', 'v', 'm') and n.nspname = any (lint.our_schemas())
      union all
      select 'column', n.nspname || '.' || c.relname || '.' || a.attname, a.attname
      from pg_attribute a join pg_class c on c.oid = a.attrelid join pg_namespace n on n.oid = c.relnamespace
      where c.relkind in ('r', 'p', 'v', 'm') and n.nspname = any (lint.our_schemas()) and a.attnum > 0 and not a.attisdropped
      union all
      select 'function', n.nspname || '.' || p.proname, p.proname
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = any (lint.our_schemas())
    )
    select names.kind, names.obj, w.word, w.use_instead
    from names join lint.forbidden_words w
      on ('_' || names.name || '_') like ('%\_' || w.word || '\_%')
  loop
    if lint.is_allowed('neutral_names', r.obj) then continue; end if;
    rule := 'neutral_names'; object := r.obj;
    message := format('%s name uses "%s"; use the neutral key "%s" (labels change the shown word).', r.kind, r.word, r.use_instead);
    return next;
  end loop;

  -- R8 / R9 / R10 / R12 / R14 functions ----------------------------------------------------------------------------
  for r in
    select p.oid, p.prosecdef, p.prosrc, p.proconfig, p.prorettype = 'trigger'::regtype as is_trigger,
           n.nspname || '.' || p.proname as obj
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = any (lint.our_schemas()) and p.prokind = 'f'
  loop
    -- R10 search_path pinned (prevents search-path hijacking; forces schema-qualified calls the sweep can see)
    if not exists (select 1 from unnest(coalesce(r.proconfig, '{}')) cfg where cfg like 'search_path=%') then
      rule := 'search_path'; object := r.obj; message := 'Function must declare "set search_path = ''''".'; return next;
    end if;

    if r.prosecdef then
      -- R8 registered
      if not exists (select 1 from app.definer_registry d where d.function_name = r.obj) then
        rule := 'definer_registered'; object := r.obj;
        message := 'SECURITY DEFINER function is not in app.definer_registry (add it with a reason, or make it INVOKER).';
        return next;
      -- R9 tenant check present
      elsif exists (select 1 from app.definer_registry d where d.function_name = r.obj
                    and d.tenant_check = 'filters_active_institution')
        and r.prosrc !~ '(auth_institution_id|require_active_session|secret_target_institution)\(' then
        rule := 'definer_tenant_check'; object := r.obj;
        message := 'DEFINER function must filter by app.auth_institution_id() / app.require_active_session().';
        return next;
      end if;
    end if;

    -- R9b service_role_only DEFINER functions: never executable by app roles
    if r.prosecdef and exists (select 1 from app.definer_registry d where d.function_name = r.obj
                               and d.tenant_check = 'service_role_only')
       and (has_function_privilege('authenticated', r.oid, 'execute') or has_function_privilege('anon', r.oid, 'execute')) then
      rule := 'definer_service_only'; object := r.obj;
      message := 'Registered as service_role_only but authenticated or anon can execute it.';
      return next;
    end if;

    -- R12 heavy functions disable JIT (lesson 4)
    if r.prosrc ~* '--\s*heavy' and not exists (select 1 from unnest(coalesce(r.proconfig, '{}')) cfg where cfg = 'jit=off') then
      rule := 'heavy_jit_off'; object := r.obj; message := 'Function marked "-- heavy" must declare "set jit = off".';
      return next;
    end if;

    -- R14 institution_type only in seeding code (Ch 2.7 #5)
    if r.prosrc ~* 'institution_type' and not lint.is_allowed('institution_type', r.obj) then
      rule := 'institution_type'; object := r.obj;
      message := 'Only seeding code may read institution_type; behaviour must depend on settings and modules.';
      return next;
    end if;

    -- R11 invoker sweep (lesson 1): an INVOKER function the app can run, or any trigger function, must not call a
    -- function that `authenticated` cannot execute (it would fail with "permission denied" for every user).
    if not r.prosecdef and (r.is_trigger or has_function_privilege('authenticated', r.oid, 'execute')) then
      for v_callee in
        select distinct m[1] || '.' || m[2]
        from regexp_matches(r.prosrc, '\m(app|public|auth|extensions)\.([a-z_][a-z0-9_]*)\s*\(', 'g') as m
      loop
        v_schema := split_part(v_callee, '.', 1);
        v_name := split_part(v_callee, '.', 2);
        if not exists (select 1 from pg_proc p2 join pg_namespace n2 on n2.oid = p2.pronamespace
                       where n2.nspname = v_schema and p2.proname = v_name) then
          continue; -- not a function (e.g. a table followed by a column list)
        end if;
        select bool_or(has_function_privilege('authenticated', p2.oid, 'execute')) into v_exec
        from pg_proc p2 join pg_namespace n2 on n2.oid = p2.pronamespace
        where n2.nspname = v_schema and p2.proname = v_name;
        if not v_exec and not lint.is_allowed('invoker_sweep', r.obj || ' -> ' || v_callee) then
          rule := 'invoker_sweep'; object := r.obj || ' -> ' || v_callee;
          message := 'Runs as the caller but calls a function the authenticated role cannot execute.';
          return next;
        end if;
      end loop;
    end if;
  end loop;

  -- R13 RLS init-plan: session helpers in policies must be wrapped in (select ...) (Ch 47.9) -----------------------
  for r in
    select schemaname || '.' || tablename || ' / ' || policyname as obj,
           coalesce(qual, '') || ' ' || coalesce(with_check, '') as expr
    from pg_policies where schemaname = any (lint.our_schemas())
  loop
    v_rest := regexp_replace(r.expr, '\(\s*SELECT\s+(auth|app)\.[a-z_]+\(\)\s+AS\s+[a-z_]+\s*\)', '', 'gi');
    if v_rest ~* '(auth\.(uid|jwt|role)|app\.(auth_[a-z_]+|claim_[a-z_]+))\(\)' then
      rule := 'rls_initplan'; object := r.obj;
      message := 'Wrap session helpers in (select ...) so they run once per query, not once per row.';
      return next;
    end if;
  end loop;
end $$;

-- Prints every finding and fails when there is at least one.
create function lint.report() returns void language plpgsql as $$
declare
  r record;
  n integer := 0;
begin
  for r in select * from lint.findings() order by rule, object loop
    n := n + 1;
    raise warning 'LINT [%] %: %', r.rule, r.object, r.message;
  end loop;
  if n > 0 then
    raise exception 'Schema lint failed with % finding(s). See docs/dev/SCHEMA_LINT.md.', n;
  end if;
  raise notice 'Schema lint passed.';
end $$;
