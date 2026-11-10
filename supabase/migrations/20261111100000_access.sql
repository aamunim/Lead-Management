-- 0A.17 Role assignments, can(), user_access and the access version (D9, D23, D25). See docs/dev/ACCESS.md.
-- One check function, can(), for every write RPC; RLS reads the same precomputed `user_access` rows. Each row belongs
-- to ONE role assignment, so the assignment's branch / unit / offering limits stay bound to that role's permissions:
-- an `all` scope from one assignment never widens another assignment's branch limit (Ch 11.16 #2).

create extension if not exists pg_cron;

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------------------------------------------------------
create table public.role_assignments (
  institution_id  uuid not null,
  id              uuid not null default gen_random_uuid(),
  user_id         uuid not null,
  role_id         uuid not null,
  org_unit_id     uuid,              -- optional: limits the assignment to this unit (and below)
  branch_id       uuid,              -- optional: limits the assignment to this branch
  offering_limit  uuid[],            -- optional: only these offerings (filled by 1A when offerings exist)
  valid_from      timestamptz not null default now(),
  valid_to        timestamptz,       -- temporary roles (season staff, auditors); expiry job cleans up
  created_by      uuid references auth.users (id) on delete set null,
  created_at      timestamptz not null default now(),
  primary key (institution_id, id),
  foreign key (institution_id, user_id) references public.institution_members (institution_id, user_id) on delete cascade,
  -- A role with people in it cannot be deleted; they are moved to another role first (role_delete).
  foreign key (institution_id, role_id) references public.roles (institution_id, id) on delete restrict,
  foreign key (institution_id, org_unit_id) references public.org_units (institution_id, id) on delete restrict,
  foreign key (institution_id, branch_id) references public.branches (institution_id, org_unit_id) on delete restrict,
  check (valid_to is null or valid_to > valid_from)
);
create index role_assignments_user_idx on public.role_assignments (institution_id, user_id);
create index role_assignments_role_idx on public.role_assignments (institution_id, role_id);
create unique index role_assignments_unique_idx on public.role_assignments
  (institution_id, user_id, role_id, coalesce(org_unit_id, '00000000-0000-0000-0000-000000000000'::uuid),
   coalesce(branch_id, '00000000-0000-0000-0000-000000000000'::uuid));

-- Precomputed access (R14): one row per (user, permission, assignment).
--   branch_ids   null = no branch limit; otherwise only records of these branches (null-branch records: creator only)
--   user_ids     null = any owner; otherwise records owned by these users (own / team / org_unit scopes)
--   offering_ids null = any offering; otherwise only these (records without an offering: creator only)
create table public.user_access (
  institution_id  uuid not null,
  user_id         uuid not null,
  assignment_id   uuid not null,
  permission_key  text not null,
  scope           text,
  branch_ids      uuid[],
  user_ids        uuid[],
  offering_ids    uuid[],
  valid_to        timestamptz,
  primary key (institution_id, user_id, permission_key, assignment_id),
  foreign key (institution_id, assignment_id) references public.role_assignments (institution_id, id) on delete cascade
);
create index user_access_perm_idx on public.user_access (institution_id, permission_key, user_id);

-- Fingerprint of a member's last built access; a rebuild that ends with another fingerprint bumps access_version.
-- (Comparing with the stored fingerprint, not the current rows: deleting an assignment removes its rows by cascade
-- before the rebuild runs.)
alter table public.institution_members add column access_fingerprint text;

-- Rebuild queue: changes enqueue the affected users; RPCs flush their institution before returning, the cron job
-- drains the rest (imports, reorganisations) fairly per institution.
create table public.access_rebuild_queue (
  institution_id  uuid not null references public.institutions (id) on delete cascade,
  user_id         uuid not null,
  queued_at       timestamptz not null default now(),
  primary key (institution_id, user_id)
);

alter table public.role_assignments enable row level security;
alter table public.user_access enable row level security;
alter table public.access_rebuild_queue enable row level security;
revoke all on public.role_assignments, public.user_access, public.access_rebuild_queue from anon, authenticated;
grant select on public.role_assignments, public.user_access to authenticated;
create policy role_assignments_read on public.role_assignments for select to authenticated
  using (institution_id = (select app.auth_institution_id()));
-- A person reads only their own access rows (the role editor reads others' through RPCs).
create policy user_access_read_own on public.user_access for select to authenticated
  using (institution_id = (select app.auth_institution_id()) and user_id = (select auth.uid()));
create policy access_rebuild_queue_none on public.access_rebuild_queue for select to authenticated using (false);

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. Building user_access
-- ---------------------------------------------------------------------------------------------------------------------
-- Users of a set of units and everything below them.
create or replace function app.users_in_units(p_institution uuid, p_units uuid[]) returns uuid[]
language sql stable set search_path = '' as $$
  select coalesce(array_agg(distinct m.user_id), '{}')
    from public.org_unit_closure c
    join public.org_unit_members m on m.institution_id = c.institution_id and m.org_unit_id = c.descendant_id
   where c.institution_id = p_institution and c.ancestor_id = any (p_units)
$$;

-- Rebuild one user's rows; bump their access version when anything changed (R15: effective on the next request).
create or replace function app.rebuild_user_access(p_institution uuid, p_user uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  v_before   text;
  v_after    text;
  v_home     uuid;
  v_managed  uuid[];
  v_units    uuid[];
  a          record;
begin
  select m.access_fingerprint into v_before from public.institution_members m
   where m.institution_id = p_institution and m.user_id = p_user;
  delete from public.user_access where institution_id = p_institution and user_id = p_user;

  select m.branch_id into v_home from public.institution_members m
   where m.institution_id = p_institution and m.user_id = p_user and m.status = 'active';
  if found then
    select coalesce(array_agg(org_unit_id), '{}') into v_managed from public.org_unit_managers
     where institution_id = p_institution and user_id = p_user;
    select coalesce(array_agg(org_unit_id), '{}') into v_units from public.org_unit_members
     where institution_id = p_institution and user_id = p_user;
    for a in
      select ra.*, r.is_super_admin from public.role_assignments ra
        join public.roles r on r.institution_id = ra.institution_id and r.id = ra.role_id and r.archived_at is null
       where ra.institution_id = p_institution and ra.user_id = p_user
         and ra.valid_from <= now() and (ra.valid_to is null or ra.valid_to > now())
    loop
      insert into public.user_access (institution_id, user_id, assignment_id, permission_key, scope, branch_ids, user_ids, offering_ids, valid_to)
      select p_institution, p_user, a.id, rp.permission_key, coalesce(rp.scope, 'all'),
             -- branch limit: the assignment's branch, else for scope `branch` the person's home branch
             case when a.branch_id is not null then array[a.branch_id]
                  when rp.scope = 'branch' then case when v_home is null then '{}'::uuid[] else array[v_home] end
                  else null end,
             -- owner limit by scope
             case coalesce(rp.scope, 'all')
               when 'own' then array[p_user]
               when 'team' then array(select distinct u from unnest(app.users_in_units(p_institution,
                                      case when a.org_unit_id is not null then array[a.org_unit_id] else v_managed end) || p_user) u)
               when 'org_unit' then array(select distinct u from unnest(app.users_in_units(p_institution,
                                      case when a.org_unit_id is not null then array[a.org_unit_id] else v_units end) || p_user) u)
               else case when a.org_unit_id is not null
                         then array(select distinct u from unnest(app.users_in_units(p_institution, array[a.org_unit_id]) || p_user) u) end
             end,
             a.offering_limit, a.valid_to
        from public.role_permissions rp
       where rp.institution_id = p_institution and rp.role_id = a.role_id
      on conflict do nothing;
    end loop;
  end if;

  select md5(coalesce(string_agg(ua::text, '|' order by ua.permission_key, ua.assignment_id), '')) into v_after
    from public.user_access ua where ua.institution_id = p_institution and ua.user_id = p_user;
  if coalesce(v_before, md5('')) is distinct from v_after then
    update public.institution_members set access_version = access_version + 1, access_fingerprint = v_after
     where institution_id = p_institution and user_id = p_user;
    return true;
  end if;
  return false;
end $$;

create or replace function app.queue_access_rebuild(p_institution uuid, p_users uuid[]) returns void
language sql security definer set search_path = '' as $$
  insert into public.access_rebuild_queue (institution_id, user_id)
  select p_institution, u from unnest(p_users) u where u is not null
  on conflict do nothing
$$;

-- Process the queue: one institution (RPCs, right away) or up to p_limit users spread over institutions (job).
create or replace function app.flush_access_queue(p_institution uuid default null, p_limit integer default 500) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  q record;
  n integer := 0;
begin
  for q in
    select institution_id, user_id from (
      select institution_id, user_id, row_number() over (partition by institution_id order by queued_at) as rn
        from public.access_rebuild_queue where p_institution is null or institution_id = p_institution) x
     order by rn, institution_id   -- fair: the first user of every institution, then the second …
     limit p_limit
  loop
    -- Claim by deleting: if another worker took this user meanwhile, the delete finds nothing and we skip it.
    delete from public.access_rebuild_queue where institution_id = q.institution_id and user_id = q.user_id;
    if found then
      perform app.rebuild_user_access(q.institution_id, q.user_id);
      n := n + 1;
    end if;
  end loop;
  return n;
end $$;

-- Triggers: what changed → which users need a rebuild.
create or replace function app.access_changed() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_inst  uuid := coalesce((to_jsonb(new) ->> 'institution_id')::uuid, (to_jsonb(old) ->> 'institution_id')::uuid);
  v_users uuid[];
begin
  case tg_table_name
    when 'role_assignments' then
      v_users := array[coalesce((to_jsonb(new) ->> 'user_id')::uuid, (to_jsonb(old) ->> 'user_id')::uuid)];
    when 'role_permissions', 'roles' then
      select array_agg(distinct ra.user_id) into v_users from public.role_assignments ra
       where ra.institution_id = v_inst and ra.role_id = coalesce((to_jsonb(new) ->> 'role_id')::uuid, (to_jsonb(old) ->> 'role_id')::uuid,
                                                                   (to_jsonb(new) ->> 'id')::uuid, (to_jsonb(old) ->> 'id')::uuid);
    when 'institution_members' then
      v_users := array[coalesce((to_jsonb(new) ->> 'user_id')::uuid, (to_jsonb(old) ->> 'user_id')::uuid)];
    else
      -- Org structure changed (units, members, managers): everyone with an assignment in the institution.
      select array_agg(distinct ra.user_id) into v_users from public.role_assignments ra where ra.institution_id = v_inst;
  end case;
  if v_users is not null then
    perform app.queue_access_rebuild(v_inst, v_users);
  end if;
  return null;
end $$;
create trigger role_assignments_access after insert or update or delete on public.role_assignments
  for each row execute function app.access_changed();
create trigger role_permissions_access after insert or update or delete on public.role_permissions
  for each row execute function app.access_changed();
create trigger roles_access after update of archived_at on public.roles
  for each row execute function app.access_changed();
create trigger institution_members_access_rebuild after update of status, branch_id on public.institution_members
  for each row execute function app.access_changed();
create trigger org_unit_members_access after insert or delete on public.org_unit_members
  for each row execute function app.access_changed();
create trigger org_unit_managers_access after insert or delete on public.org_unit_managers
  for each row execute function app.access_changed();
create trigger org_units_access after update of parent_id, archived_at on public.org_units
  for each row execute function app.access_changed();

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. can() and the RLS helpers
-- ---------------------------------------------------------------------------------------------------------------------
-- Support access with a time limit and a reason is built in 0B (Ch 11.15); until then: never.
create or replace function app.is_platform_admin_for_support() returns boolean
language sql stable set search_path = '' as $$ select false $$;

-- can(action [, record]): does the signed-in person (active institution) have the permission?
--   can('settings.users')                      → at any scope (screens, settings, "may create")
--   can('lead.edit', jsonb_build_object(…))    → for this record {"owner_id", "branch_id", "offering_id", "created_by"}
-- A record argument that is SQL NULL (e.g. a lookup that found nothing) is refused, never read as "any scope".
create or replace function app.can_check(p_action text, p_record jsonb) returns boolean
language sql stable security definer set search_path = '' as $$
  select app.is_platform_admin_for_support() or exists (
    select 1 from public.user_access ua
     where ua.institution_id = app.auth_institution_id() and ua.user_id = auth.uid()
       and ua.permission_key in (p_action, '*')
       and (ua.valid_to is null or ua.valid_to > now())
       and (p_record is null or (
             (ua.branch_ids is null or (p_record ->> 'branch_id')::uuid = any (ua.branch_ids)
              or (p_record ->> 'created_by')::uuid = auth.uid())
         and (ua.user_ids is null or (p_record ->> 'owner_id')::uuid = any (ua.user_ids)
              or (p_record ->> 'created_by')::uuid = auth.uid())
         and (ua.offering_ids is null or (p_record ->> 'offering_id')::uuid = any (ua.offering_ids)
              or ((p_record ->> 'offering_id') is null and (p_record ->> 'created_by')::uuid = auth.uid()))))
       -- `*` (Super Admin) never extends to platform permissions
       and (ua.permission_key <> '*' or exists (select 1 from public.permissions p where p.key = p_action and p.kind = 'institution')))
$$;
create or replace function app.can(p_action text) returns boolean
language sql stable set search_path = '' as $$
  select app.can_check(p_action, null)
$$;
create or replace function app.can(p_action text, p_record jsonb) returns boolean
language sql stable set search_path = '' as $$
  select p_record is not null and app.can_check(p_action, p_record)
$$;

grant execute on function app.can(text), app.can(text, jsonb), app.can_check(text, jsonb), app.is_platform_admin_for_support() to authenticated, service_role;

-- RLS for 1A tables (R14). The person's access rows for a permission are loaded ONCE per query (init-plan) and each
-- record is checked against that small array — no table lookup per row (3,000 rows: +2–3 ms, tested). Same rule as
-- can(), per assignment, so limits never mix. Create policies with app.create_visibility_policy():
--   select app.create_visibility_policy('public.leads', 'lead.view');
create or replace function app.my_access_rows(p_permission text) returns public.user_access[]
language sql stable set search_path = '' as $$
  select coalesce(array_agg(ua), '{}') from public.user_access ua
   where ua.institution_id = app.auth_institution_id() and ua.user_id = auth.uid()
     and ua.permission_key in (p_permission, '*') and (ua.valid_to is null or ua.valid_to > now())
$$;
grant execute on function app.my_access_rows(text) to authenticated;

create or replace function app.visibility_expression(p_table text, p_permission text, p_owner text, p_branch text,
                                                     p_offering text, p_created_by text) returns text
language sql immutable set search_path = '' as $$
  select format($f$exists (select 1 from unnest((select app.my_access_rows(%1$L))) ua
     where (ua.branch_ids is null or %2$s.%3$I = any (ua.branch_ids) or %2$s.%6$I = (select auth.uid()))
       and (ua.user_ids is null or %2$s.%4$I = any (ua.user_ids) or %2$s.%6$I = (select auth.uid()))
       and (ua.offering_ids is null or %2$s.%5$I = any (ua.offering_ids) or (%2$s.%5$I is null and %2$s.%6$I = (select auth.uid()))))$f$,
    p_permission, p_table, p_branch, p_owner, p_offering, p_created_by)
$$;

-- Creates the SELECT policy "<table>_visible" for a tenant table with owner / branch / offering / creator columns.
create or replace function app.create_visibility_policy(p_table regclass, p_permission text, p_owner text default 'owner_id',
    p_branch text default 'branch_id', p_offering text default 'offering_id', p_created_by text default 'created_by') returns void
language plpgsql set search_path = '' as $$
declare
  v_name text := (select c.relname from pg_catalog.pg_class c where c.oid = p_table);
begin
  execute format('create policy %I on %s for select to authenticated using (institution_id = (select app.auth_institution_id()) and %s)',
                 v_name || '_visible', p_table, app.visibility_expression(v_name, p_permission, p_owner, p_branch, p_offering, p_created_by));
end $$;
revoke all on function app.create_visibility_policy(regclass, text, text, text, text, text) from public, anon, authenticated;

-- One record (outside RLS): the same rule as a function.
create or replace function app.row_visible(p_permission text, p_owner uuid, p_branch uuid, p_offering uuid, p_created_by uuid)
returns boolean language sql stable set search_path = '' as $$
  select exists (select 1 from unnest(app.my_access_rows(p_permission)) ua
     where (ua.branch_ids is null or p_branch = any (ua.branch_ids) or p_created_by = auth.uid())
       and (ua.user_ids is null or p_owner = any (ua.user_ids) or p_created_by = auth.uid())
       and (ua.offering_ids is null or p_offering = any (ua.offering_ids) or (p_offering is null and p_created_by = auth.uid())))
$$;
grant execute on function app.row_visible(text, uuid, uuid, uuid, uuid) to authenticated;

-- Union helpers for filters and counts (NOT for RLS decisions on their own — they merge assignments):
create or replace function app.visible_branch_ids(p_permission text) returns uuid[]
language sql stable set search_path = '' as $$
  select case when bool_or(ua.branch_ids is null) then null else array(select distinct b from unnest(array_agg(ua.branch_ids)) b) end
    from public.user_access ua
   where ua.institution_id = app.auth_institution_id() and ua.user_id = auth.uid() and ua.permission_key in (p_permission, '*')
     and (ua.valid_to is null or ua.valid_to > now())
$$;
create or replace function app.visible_owner_ids(p_permission text) returns uuid[]
language sql stable set search_path = '' as $$
  select case when bool_or(ua.user_ids is null) then null else array(select distinct u from unnest(array_agg(ua.user_ids)) u) end
    from public.user_access ua
   where ua.institution_id = app.auth_institution_id() and ua.user_id = auth.uid() and ua.permission_key in (p_permission, '*')
     and (ua.valid_to is null or ua.valid_to > now())
$$;
create or replace function app.visible_offering_ids(p_permission text) returns uuid[]
language sql stable set search_path = '' as $$
  select case when bool_or(ua.offering_ids is null) then null else array(select distinct o from unnest(array_agg(ua.offering_ids)) o) end
    from public.user_access ua
   where ua.institution_id = app.auth_institution_id() and ua.user_id = auth.uid() and ua.permission_key in (p_permission, '*')
     and (ua.valid_to is null or ua.valid_to > now())
$$;
grant execute on function app.visible_branch_ids(text), app.visible_owner_ids(text), app.visible_offering_ids(text) to authenticated;

-- Behaviour flags of a person: on if any active role has it (Ch 11.9).
create or replace function app.user_flags(p_institution uuid, p_user uuid) returns text[]
language sql stable set search_path = '' as $$
  select coalesce(array_agg(distinct f order by f), '{}')
    from public.role_assignments ra
    join public.roles r on r.institution_id = ra.institution_id and r.id = ra.role_id and r.archived_at is null
    cross join unnest(r.flags) f
   where ra.institution_id = p_institution and ra.user_id = p_user and ra.valid_from <= now() and (ra.valid_to is null or ra.valid_to > now())
$$;
grant execute on function app.user_flags(uuid, uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------------------------------
-- 4. Earlier "Master Admin until can()" checks now use can() (0A.07 / 0A.08 / 0A.09 / 0A.15 / 0A.16)
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function app.settings_write_allowed(p_institution uuid, p_area text) returns boolean
language sql stable set search_path = '' as $$
  select exists (select 1 from public.institutions i where i.id = p_institution)
     and (app.is_platform_admin() or (p_institution = app.auth_institution_id() and app.can(p_area)))
$$;
create or replace function app.secret_write_allowed(p_institution uuid) returns boolean
language sql stable set search_path = '' as $$
  select app.settings_write_allowed(p_institution, 'integration.manage')
$$;
drop policy domain_events_read on public.domain_events;
create policy domain_events_read on public.domain_events for select to authenticated
  using (institution_id = (select app.auth_institution_id()) and ((select app.is_platform_admin()) or (select app.can('audit.view'))));
drop policy audit_log_read on public.audit_log;
create policy audit_log_read on public.audit_log for select to authenticated
  using (institution_id = (select app.auth_institution_id()) and ((select app.is_platform_admin()) or (select app.can('audit.view'))));

-- ---------------------------------------------------------------------------------------------------------------------
-- 5. Safeguards (Ch 11.3, 11.16 #10, R8)
-- ---------------------------------------------------------------------------------------------------------------------
-- Does the caller hold every permission of a role, at an equal or wider scope (no escalation, R8)?
create or replace function app.holds_all_of_role(p_institution uuid, p_role uuid) returns boolean
language sql stable set search_path = '' as $$
  select app.is_platform_admin() or not exists (
    select 1 from public.role_permissions rp
     where rp.institution_id = p_institution and rp.role_id = p_role
       and not exists (select 1 from public.user_access ua
                        where ua.institution_id = p_institution and ua.user_id = auth.uid()
                          and (ua.permission_key = '*' or (ua.permission_key = rp.permission_key and ua.branch_ids is null
                               and (rp.scope is null or ua.scope = 'all' or ua.scope = rp.scope)))
                          and (ua.valid_to is null or ua.valid_to > now())))
$$;

-- Does the caller hold every permission of a grant map ({key: scope|true})?
create or replace function app.holds_all_of_grants(p_institution uuid, p_grants jsonb) returns boolean
language sql stable set search_path = '' as $$
  select app.is_platform_admin() or not exists (
    select 1 from jsonb_each(coalesce(p_grants, '{}'::jsonb)) g
     where not exists (select 1 from public.user_access ua
                        where ua.institution_id = p_institution and ua.user_id = auth.uid()
                          and (ua.permission_key = '*' or (ua.permission_key = g.key and ua.branch_ids is null
                               and (ua.scope = 'all' or ua.scope = nullif(g.value #>> '{}', 'true') or g.value #>> '{}' = 'true')))
                          and (ua.valid_to is null or ua.valid_to > now())))
$$;

-- Is the target person more powerful than the caller (holds something the caller does not)? Then hands off (R8).
create or replace function app.outranks_caller(p_institution uuid, p_user uuid) returns boolean
language sql stable set search_path = '' as $$
  select not app.is_platform_admin() and p_user is distinct from auth.uid() and exists (
    select 1 from public.user_access t
     where t.institution_id = p_institution and t.user_id = p_user
       and not exists (select 1 from public.user_access me
                        where me.institution_id = p_institution and me.user_id = auth.uid()
                          and (me.permission_key = '*' or (me.permission_key = t.permission_key and me.branch_ids is null and me.scope = 'all'))))
$$;

create or replace function app.active_super_admins(p_institution uuid, p_except_assignment uuid default null) returns integer
language sql stable set search_path = '' as $$
  select count(distinct ra.user_id)::integer
    from public.role_assignments ra
    join public.roles r on r.institution_id = ra.institution_id and r.id = ra.role_id and r.is_super_admin and r.archived_at is null
    join public.institution_members m on m.institution_id = ra.institution_id and m.user_id = ra.user_id and m.status = 'active'
   where ra.institution_id = p_institution and ra.id is distinct from p_except_assignment
     and ra.valid_from <= now() and (ra.valid_to is null or ra.valid_to > now())
$$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 6. RPCs
-- ---------------------------------------------------------------------------------------------------------------------
-- What a person would be able to do with one more assignment, before saving (Ch 11.16 #2).
create or replace function public.role_assignment_preview(p_user_id uuid, p_role_id uuid, p_branch_id uuid default null,
                                                          p_org_unit_id uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.require_active_session();
begin
  if not app.can('settings.users') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'current', (select coalesce(jsonb_agg(distinct jsonb_build_object('permission', ua.permission_key, 'scope', ua.scope,
                  'branch_ids', ua.branch_ids)), '[]'::jsonb) from public.user_access ua
                where ua.institution_id = v_institution and ua.user_id = p_user_id),
    'adds', (select coalesce(jsonb_agg(jsonb_build_object('permission', rp.permission_key, 'scope', coalesce(rp.scope, 'all'),
                  'branch_ids', case when p_branch_id is not null then jsonb_build_array(p_branch_id) end,
                  'org_unit_id', p_org_unit_id, 'sensitive', p.sensitive) order by rp.permission_key), '[]'::jsonb)
             from public.role_permissions rp join public.permissions p on p.key = rp.permission_key
             where rp.institution_id = v_institution and rp.role_id = p_role_id));
end $$;

create or replace function public.role_assign(p_user_id uuid, p_role_id uuid, p_org_unit_id uuid default null, p_branch_id uuid default null,
                                              p_valid_from timestamptz default null, p_valid_to timestamptz default null,
                                              p_offering_limit uuid[] default null, p_institution_id uuid default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.secret_target_institution(p_institution_id);
  v_role        public.roles;
  v_id          uuid;
begin
  if not app.settings_write_allowed(v_institution, 'settings.users') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  v_role := app.role_or_fail(v_institution, p_role_id);
  if v_role.archived_at is not null then
    raise exception 'role_invalid' using errcode = 'P0422', detail = 'archived role';
  end if;
  if not app.holds_all_of_role(v_institution, p_role_id) then
    raise exception 'permission_escalation' using errcode = '42501', detail = 'you cannot give a role with permissions you do not have';
  end if;
  if app.outranks_caller(v_institution, p_user_id) then
    raise exception 'permission_escalation' using errcode = '42501', detail = 'this person has more access than you';
  end if;
  if not exists (select 1 from public.institution_members m where m.institution_id = v_institution and m.user_id = p_user_id
                 and m.status = 'active') then
    raise exception 'not_a_member' using errcode = 'P0403';
  end if;
  insert into public.role_assignments (institution_id, user_id, role_id, org_unit_id, branch_id, offering_limit, valid_from, valid_to, created_by)
  values (v_institution, p_user_id, p_role_id, p_org_unit_id, p_branch_id, p_offering_limit, coalesce(p_valid_from, now()), p_valid_to, auth.uid())
  returning id into v_id;
  perform app.flush_access_queue(v_institution);
  perform app.audit(v_institution, 'role.assigned', 'role_assignment', v_id::text, null,
                    jsonb_build_object('user_id', p_user_id, 'role_id', p_role_id, 'branch_id', p_branch_id, 'org_unit_id', p_org_unit_id,
                                       'valid_to', p_valid_to));
  perform app.emit_event(v_institution, 'role.assigned', 1, 'role_assignment', v_id::text,
                         jsonb_build_object('user_id', p_user_id, 'role_id', p_role_id));
  return v_id;
end $$;

create or replace function public.role_unassign(p_assignment_id uuid, p_institution_id uuid default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.secret_target_institution(p_institution_id);
  v_a           public.role_assignments;
  v_role        public.roles;
begin
  if not app.settings_write_allowed(v_institution, 'settings.users') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  select * into v_a from public.role_assignments where institution_id = v_institution and id = p_assignment_id;
  if not found then
    raise exception 'role_unknown' using errcode = 'P0404', detail = p_assignment_id::text;
  end if;
  v_role := app.role_or_fail(v_institution, v_a.role_id);
  if app.outranks_caller(v_institution, v_a.user_id) or not app.holds_all_of_role(v_institution, v_a.role_id) then
    raise exception 'permission_escalation' using errcode = '42501', detail = 'this person has more access than you';
  end if;
  if v_role.is_super_admin and app.active_super_admins(v_institution, p_assignment_id) = 0 then
    raise exception 'last_super_admin' using errcode = 'P0409', detail = 'give the Super Admin role to someone else first';
  end if;
  -- Self-lockout: removing the caller's own last way to manage users / roles.
  if v_a.user_id = auth.uid() and not app.is_platform_admin() and not exists (
       select 1 from public.user_access ua where ua.institution_id = v_institution and ua.user_id = auth.uid()
          and ua.assignment_id <> p_assignment_id and ua.permission_key in ('*', 'settings.users')) then
    raise exception 'self_lockout' using errcode = 'P0409', detail = 'you would lose your own access to manage users';
  end if;
  delete from public.role_assignments where institution_id = v_institution and id = p_assignment_id;
  perform app.flush_access_queue(v_institution);
  perform app.audit(v_institution, 'role.unassigned', 'role_assignment', p_assignment_id::text,
                    jsonb_build_object('user_id', v_a.user_id, 'role_id', v_a.role_id), null);
  perform app.emit_event(v_institution, 'role.unassigned', 1, 'role_assignment', p_assignment_id::text,
                         jsonb_build_object('user_id', v_a.user_id, 'role_id', v_a.role_id));
end $$;

-- Copy a role (custom, non-sensitive grants only unless the caller has two-step sign-in and holds them).
create or replace function public.role_copy(p_role_id uuid, p_name text, p_institution_id uuid default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.secret_target_institution(p_institution_id);
  v_role        public.roles;
  v_id          uuid;
begin
  if not app.settings_write_allowed(v_institution, 'settings.roles') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  v_role := app.role_or_fail(v_institution, p_role_id);
  insert into public.roles (institution_id, name, flags, rank_for_sorting)
  values (v_institution, btrim(p_name), v_role.flags, v_role.rank_for_sorting) returning id into v_id;
  insert into public.role_permissions (institution_id, role_id, permission_key, scope)
  select v_institution, v_id, rp.permission_key, rp.scope
    from public.role_permissions rp join public.permissions p on p.key = rp.permission_key
   where rp.institution_id = v_institution and rp.role_id = p_role_id and not p.sensitive and rp.permission_key <> '*'
     and app.holds_all_of_grants(v_institution, jsonb_build_object(rp.permission_key, coalesce(to_jsonb(rp.scope), 'true'::jsonb)));
  perform app.audit(v_institution, 'role.created', 'role', v_id::text, null, jsonb_build_object('copied_from', p_role_id, 'name', btrim(p_name)));
  perform app.emit_event(v_institution, 'role.changed', 1, 'role', v_id::text, jsonb_build_object('role_id', v_id, 'change', 'created'));
  return v_id;
end $$;

-- Delete (archive) a custom role; its people move to p_move_to_role_id first (never left without a role silently).
create or replace function public.role_delete(p_role_id uuid, p_move_to_role_id uuid default null, p_institution_id uuid default null)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.secret_target_institution(p_institution_id);
  v_role        public.roles;
  v_moved       integer := 0;
begin
  if not app.settings_write_allowed(v_institution, 'settings.roles') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  v_role := app.role_or_fail(v_institution, p_role_id);
  if v_role.is_system then
    raise exception 'role_invalid' using errcode = 'P0422', detail = 'system roles cannot be deleted';
  end if;
  if exists (select 1 from public.role_assignments where institution_id = v_institution and role_id = p_role_id) then
    if p_move_to_role_id is null then
      raise exception 'role_has_members' using errcode = 'P0409', detail = 'choose a role to move its people to';
    end if;
    perform app.role_or_fail(v_institution, p_move_to_role_id);
    if not app.holds_all_of_role(v_institution, p_move_to_role_id) then
      raise exception 'permission_escalation' using errcode = '42501';
    end if;
    update public.role_assignments set role_id = p_move_to_role_id where institution_id = v_institution and role_id = p_role_id;
    get diagnostics v_moved = row_count;
  end if;
  update public.roles set archived_at = now() where institution_id = v_institution and id = p_role_id;
  perform app.flush_access_queue(v_institution);
  perform app.audit(v_institution, 'role.deleted', 'role', p_role_id::text, jsonb_build_object('name', v_role.name),
                    jsonb_build_object('moved_to', p_move_to_role_id, 'moved', v_moved));
  perform app.emit_event(v_institution, 'role.changed', 1, 'role', p_role_id::text, jsonb_build_object('role_id', p_role_id, 'change', 'updated'));
  return v_moved;
end $$;

-- 0A.16 role RPCs gain the escalation rule: nobody creates or grants permissions they do not hold themselves.
create or replace function app.assert_no_escalation(p_institution uuid, p_grants jsonb) returns void
language plpgsql stable set search_path = '' as $$
begin
  if not app.holds_all_of_grants(p_institution, p_grants) then
    raise exception 'permission_escalation' using errcode = '42501', detail = 'you cannot give permissions you do not have';
  end if;
end $$;

create or replace function app.before_grant_check() returns trigger
language plpgsql set search_path = '' as $$
begin
  -- Only for writes made by signed-in people (RPCs); seeds, templates and the registry sync run without a user.
  if auth.uid() is not null and not app.is_platform_admin() then
    perform app.assert_no_escalation(new.institution_id, jsonb_build_object(new.permission_key, coalesce(to_jsonb(new.scope), 'true'::jsonb)));
  end if;
  return new;
end $$;
create trigger role_permissions_no_escalation before insert or update on public.role_permissions
  for each row execute function app.before_grant_check();

-- Mine: what the signed-in person may do (the app hides what it cannot do, Ch 11.13).
create or replace function public.my_access() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'permissions', coalesce((select jsonb_object_agg(k, s) from (
        select ua.permission_key as k, jsonb_agg(distinct coalesce(ua.scope, 'all')) as s from public.user_access ua
         where ua.institution_id = app.auth_institution_id() and ua.user_id = auth.uid() and (ua.valid_to is null or ua.valid_to > now())
         group by ua.permission_key) x), '{}'::jsonb),
    'flags', to_jsonb(app.user_flags(app.auth_institution_id(), auth.uid())))
$$;

revoke all on function public.role_assignment_preview(uuid, uuid, uuid, uuid), public.role_assign(uuid, uuid, uuid, uuid, timestamptz, timestamptz, uuid[], uuid),
  public.role_unassign(uuid, uuid), public.role_copy(uuid, text, uuid), public.role_delete(uuid, uuid, uuid), public.my_access() from public, anon;
grant execute on function public.role_assignment_preview(uuid, uuid, uuid, uuid), public.role_assign(uuid, uuid, uuid, uuid, timestamptz, timestamptz, uuid[], uuid),
  public.role_unassign(uuid, uuid), public.role_copy(uuid, text, uuid), public.role_delete(uuid, uuid, uuid), public.my_access() to authenticated;
revoke all on function app.rebuild_user_access(uuid, uuid), app.flush_access_queue(uuid, integer), app.queue_access_rebuild(uuid, uuid[])
  from public, anon, authenticated;
grant execute on function app.rebuild_user_access(uuid, uuid), app.flush_access_queue(uuid, integer), app.queue_access_rebuild(uuid, uuid[]) to service_role;
grant execute on function app.holds_all_of_role(uuid, uuid), app.holds_all_of_grants(uuid, jsonb), app.outranks_caller(uuid, uuid),
  app.active_super_admins(uuid, uuid), app.assert_no_escalation(uuid, jsonb), app.users_in_units(uuid, uuid[]) to authenticated, service_role;

-- 0A.16 role_create / role_update / role_set_grants used settings_write_allowed (now can()); add the escalation rule to
-- role_set_grants through the role_permissions trigger above (same check, every path).

-- ---------------------------------------------------------------------------------------------------------------------
-- 7. "Who" selector evaluator for non-access settings (0A.16-T8 / 0A.17-T10)
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function app.who_matches(p_institution uuid, p_who jsonb, p_user uuid) returns boolean
language sql stable set search_path = '' as $$
  select case p_who ->> 'mode'
    when 'all' then exists (select 1 from public.institution_members m where m.institution_id = p_institution and m.user_id = p_user and m.status = 'active')
    when 'users' then p_who -> 'user_ids' ? p_user::text
    when 'roles' then exists (select 1 from public.role_assignments ra
                              where ra.institution_id = p_institution and ra.user_id = p_user and p_who -> 'roles' ? ra.role_id::text
                                and ra.valid_from <= now() and (ra.valid_to is null or ra.valid_to > now()))
    else false end
$$;
grant execute on function app.who_matches(uuid, jsonb, uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------------------------------
-- 8. Jobs: drain the rebuild queue every minute; expire temporary roles nightly (moves to the 1B scheduler later)
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function app.expire_temporary_roles() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  n integer := 0;
  r record;
begin
  -- Rows already ignore expired assignments (can() checks valid_to); this removes them and bumps access versions.
  for r in select distinct ua.institution_id, ua.user_id from public.user_access ua where ua.valid_to is not null and ua.valid_to <= now()
           union select ra.institution_id, ra.user_id from public.role_assignments ra
                  where ra.valid_from <= now() and ra.valid_from > now() - interval '1 day'
                    and not exists (select 1 from public.user_access ua where ua.assignment_id = ra.id) loop
    perform app.queue_access_rebuild(r.institution_id, array[r.user_id]);
    n := n + 1;
  end loop;
  perform app.flush_access_queue(null, 5000);
  return n;
end $$;
revoke all on function app.expire_temporary_roles() from public, anon, authenticated;
grant execute on function app.expire_temporary_roles() to service_role;

select cron.schedule('access-rebuild-queue', '* * * * *', 'select app.flush_access_queue(null, 500)');
select cron.schedule('expire-temporary-roles', '17 2 * * *', 'select app.expire_temporary_roles()');

-- ---------------------------------------------------------------------------------------------------------------------
-- 9. Registry entries and events
-- ---------------------------------------------------------------------------------------------------------------------
insert into app.definer_registry (function_name, reason, added_in, reviewer, tenant_check)
select f, r, '0A.17', 'architecture review 0A.17', t from (values
  ('app.rebuild_user_access', 'Rebuilds one user''s access rows from assignments; service_role / internal only.', 'service_role_only'),
  ('app.flush_access_queue', 'Processes the access rebuild queue; service_role / internal only.', 'service_role_only'),
  ('app.queue_access_rebuild', 'Queues users for an access rebuild; service_role / internal only.', 'service_role_only'),
  ('app.expire_temporary_roles', 'Nightly job: expires temporary roles; service_role only.', 'service_role_only'),
  ('app.access_changed', 'Trigger: queues the users whose access changed (same institution as the row).', 'not_tenant_data'),
  ('app.can_check', 'The permission check behind can(): reads only the caller''s own user_access rows in the active institution.', 'filters_active_institution'),
  ('public.role_assignment_preview', 'Shows a person''s current and resulting access in the active institution; needs settings.users.', 'filters_active_institution'),
  ('public.role_assign', 'Assigns a role in the target institution; can() + escalation rules; audited.', 'filters_active_institution'),
  ('public.role_unassign', 'Removes an assignment; last Super Admin / self-lockout / escalation rules; audited.', 'filters_active_institution'),
  ('public.role_copy', 'Copies a role (non-sensitive grants the caller holds); audited.', 'filters_active_institution'),
  ('public.role_delete', 'Archives a custom role after moving its people; audited.', 'filters_active_institution'),
  ('public.my_access', 'The caller''s own permissions and flags in the active institution.', 'filters_active_institution')
) as v (f, r, t);

insert into public.event_definitions (event_key, version, entity_type, payload_schema, description) values
  ('role.assigned', 1, 'role_assignment', '{"type":"object","required":["user_id","role_id"],"properties":{"user_id":{"type":"string"},"role_id":{"type":"string"}}}', 'A role was given to a person.'),
  ('role.unassigned', 1, 'role_assignment', '{"type":"object","required":["user_id","role_id"],"properties":{"user_id":{"type":"string"},"role_id":{"type":"string"}}}', 'A role was taken from a person.');
