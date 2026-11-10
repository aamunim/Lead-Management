-- 0A.04 Schema guardrails (database side). The lint itself lives in supabase/lint/ and runs in CI.
-- Additive changes only (expand-then-contract, docs/dev/ARCHITECTURE_RULES.md §5).

-- D9 / Ch 12.3: core record tables carry a nullable branch_id. The FK to branches is added in 0A.15.
alter table public.institution_members add column branch_id uuid;
comment on column public.institution_members.branch_id is 'Home branch of the member (nullable; FK added in 0A.15).';

-- DEFINER registry: who reviewed it and how it respects tenancy (checked by the lint, rule definer_tenant_check).
alter table app.definer_registry
  add column reviewer     text not null default 'pending review',
  add column tenant_check text not null default 'filters_active_institution'
    check (tenant_check in ('filters_active_institution', 'not_tenant_data'));
comment on column app.definer_registry.tenant_check is
  'filters_active_institution: body must use app.auth_institution_id() / app.require_active_session(). '
  'not_tenant_data: touches no tenant rows (reason must say why).';

update app.definer_registry
   set reviewer = 'architecture review 0A.04', tenant_check = 'not_tenant_data'
 where function_name = 'app.handle_new_auth_user';

-- Guard trigger (Ch 3.3): protected columns can only change inside the RPC that owns them.
-- Usage:
--   create trigger <t>_guard before update on public.<t> for each row
--     execute function app.guard_columns('app.pipeline_action', 'stage_id', 'converted_at');
-- The owning RPC runs:  perform set_config('app.pipeline_action', 'on', true);  before its update.
create or replace function app.guard_columns() returns trigger
language plpgsql set search_path = '' as $$
declare
  v_flag   text := tg_argv[0];
  v_old    jsonb := to_jsonb(old);
  v_new    jsonb := to_jsonb(new);
  v_column text;
begin
  if coalesce(current_setting(v_flag, true), '') = 'on' then
    return new;
  end if;
  for i in 1 .. tg_nargs - 1 loop
    v_column := tg_argv[i];
    if v_old -> v_column is distinct from v_new -> v_column then
      raise exception 'protected_column' using errcode = 'P0405',
        detail = format('%s.%s can only be changed through its RPC (flag %s).', tg_table_name, v_column, v_flag);
    end if;
  end loop;
  return new;
end $$;
