-- 0A.20 (found by the benchmark harness, scripts/bench/run.mjs): can() was a SQL-language function with a
-- `set search_path` clause. PostgreSQL cannot inline such a function and plans its body again on every call
-- (~0.45 ms per call). The same body in PL/pgSQL keeps the fixed search path and caches its plan (~0.03 ms per call).
-- Rule for new helpers called many times per statement: PL/pgSQL, or SQL without a SET clause only if lint allows it.
create or replace function app.can(p_action text) returns boolean
language plpgsql stable set search_path = '' as $$
begin
  return app.can_check(p_action, null);
end $$;

create or replace function app.can(p_action text, p_record jsonb) returns boolean
language plpgsql stable set search_path = '' as $$
begin
  -- A record argument that is SQL NULL (e.g. a lookup that found nothing) is refused, never read as "any scope".
  return p_record is not null and app.can_check(p_action, p_record);
end $$;
