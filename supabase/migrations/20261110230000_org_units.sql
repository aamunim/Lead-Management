-- 0A.15 Branches and the organisational unit tree (D9, D25). See docs/dev/ORG_UNITS.md.
-- The organisation is a tree of any depth: institution (implicit root) → branch → department → team → …
-- A branch is an org unit of kind 'branch' directly under the institution; its details live in `branches`.
-- Subtree lookups use a closure table (every ancestor–descendant pair), so "this unit and everything below" is one
-- indexed query. Units are never deleted: they are archived, and only once nothing is left in them (Ch 12.7 #7).

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------------------------------------------------------
create table public.org_units (
  institution_id  uuid not null references public.institutions (id) on delete cascade,
  id              uuid not null default gen_random_uuid(),
  parent_id       uuid,                    -- null = directly under the institution
  kind            text not null check (kind in ('branch', 'department', 'team', 'other')),
  name            text not null check (length(btrim(name)) between 1 and 120),
  branch_id       uuid,                    -- the branch this unit belongs to (itself for a branch); kept by trigger
  archived_at     timestamptz,
  created_at      timestamptz not null default now(),
  created_by      uuid references auth.users (id) on delete set null,
  primary key (institution_id, id),
  foreign key (institution_id, parent_id) references public.org_units (institution_id, id) on delete restrict,
  -- Ch 12.4: a branch sits directly under the institution.
  constraint org_units_branch_at_top check (kind <> 'branch' or parent_id is null)
);
create index org_units_parent_idx on public.org_units (institution_id, parent_id);
create index org_units_branch_idx on public.org_units (institution_id, branch_id);
create unique index org_units_sibling_name_idx on public.org_units
  (institution_id, coalesce(parent_id, '00000000-0000-0000-0000-000000000000'::uuid), lower(name)) where archived_at is null;

-- Closure table: one row per (ancestor, descendant), including (unit, unit) at depth 0.
create table public.org_unit_closure (
  institution_id  uuid not null,
  ancestor_id     uuid not null,
  descendant_id   uuid not null,
  depth           integer not null check (depth >= 0),
  primary key (institution_id, ancestor_id, descendant_id),
  foreign key (institution_id, ancestor_id) references public.org_units (institution_id, id) on delete cascade,
  foreign key (institution_id, descendant_id) references public.org_units (institution_id, id) on delete cascade
);
create index org_unit_closure_descendant_idx on public.org_unit_closure (institution_id, descendant_id, depth);

create table public.branches (
  institution_id  uuid not null,
  org_unit_id     uuid not null,
  address         text check (address is null or length(address) <= 500),
  phone           text,
  head_user_id    uuid references auth.users (id) on delete set null,
  updated_at      timestamptz not null default now(),
  primary key (institution_id, org_unit_id),
  foreign key (institution_id, org_unit_id) references public.org_units (institution_id, id) on delete restrict,
  constraint branches_phone_ascii check (app.is_ascii_phone(phone))
);
create trigger branches_normalize_phone before insert or update of phone on public.branches
  for each row execute function app.normalize_phone_columns('phone');

create table public.org_unit_members (
  institution_id  uuid not null,
  org_unit_id     uuid not null,
  user_id         uuid not null,
  added_at        timestamptz not null default now(),
  primary key (institution_id, org_unit_id, user_id),
  foreign key (institution_id, org_unit_id) references public.org_units (institution_id, id) on delete restrict,
  foreign key (institution_id, user_id) references public.institution_members (institution_id, user_id) on delete cascade
);
create index org_unit_members_user_idx on public.org_unit_members (institution_id, user_id);

create table public.org_unit_managers (
  institution_id  uuid not null,
  org_unit_id     uuid not null,
  user_id         uuid not null,
  added_at        timestamptz not null default now(),
  primary key (institution_id, org_unit_id, user_id),
  foreign key (institution_id, org_unit_id) references public.org_units (institution_id, id) on delete restrict,
  foreign key (institution_id, user_id) references public.institution_members (institution_id, user_id) on delete cascade
);
create index org_unit_managers_user_idx on public.org_unit_managers (institution_id, user_id);

-- The member's home branch (column added in 0A.04) now points at a real branch; a branch with members cannot go.
alter table public.institution_members add constraint institution_members_branch_fk
  foreign key (institution_id, branch_id) references public.branches (institution_id, org_unit_id) on delete restrict;
create index institution_members_branch_idx on public.institution_members (institution_id, branch_id);

-- RLS: members read their institution's tree; writes only through the RPCs below.
alter table public.org_units enable row level security;
alter table public.org_unit_closure enable row level security;
alter table public.branches enable row level security;
alter table public.org_unit_members enable row level security;
alter table public.org_unit_managers enable row level security;
revoke all on public.org_units, public.org_unit_closure, public.branches, public.org_unit_members, public.org_unit_managers
  from anon, authenticated;
grant select on public.org_units, public.org_unit_closure, public.branches, public.org_unit_members, public.org_unit_managers
  to authenticated;
create policy org_units_read on public.org_units for select to authenticated
  using (institution_id = (select app.auth_institution_id()));
create policy org_unit_closure_read on public.org_unit_closure for select to authenticated
  using (institution_id = (select app.auth_institution_id()));
create policy branches_read on public.branches for select to authenticated
  using (institution_id = (select app.auth_institution_id()));
create policy org_unit_members_read on public.org_unit_members for select to authenticated
  using (institution_id = (select app.auth_institution_id()));
create policy org_unit_managers_read on public.org_unit_managers for select to authenticated
  using (institution_id = (select app.auth_institution_id()));

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. Tree maintenance (closure rows and branch_id), run as the table owner by triggers
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function app.org_units_before_write() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.kind = 'branch' then
    new.branch_id := new.id;
  elsif new.parent_id is null then
    new.branch_id := null;
  else
    select p.branch_id into new.branch_id from public.org_units p
     where p.institution_id = new.institution_id and p.id = new.parent_id;
  end if;
  return new;
end $$;
create trigger org_units_before_write before insert or update of parent_id, kind on public.org_units
  for each row execute function app.org_units_before_write();

create or replace function app.org_units_after_insert() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.org_unit_closure (institution_id, ancestor_id, descendant_id, depth)
  select new.institution_id, c.ancestor_id, new.id, c.depth + 1
    from public.org_unit_closure c
   where c.institution_id = new.institution_id and c.descendant_id = new.parent_id
  union all
  select new.institution_id, new.id, new.id, 0;
  return null;
end $$;
create trigger org_units_after_insert after insert on public.org_units
  for each row execute function app.org_units_after_insert();

-- Move: drop the links between the moved subtree and its old ancestors, add links to the new ones, and refresh
-- branch_id for the whole subtree.
create or replace function app.org_units_after_move() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.parent_id is not distinct from old.parent_id then
    return null;
  end if;
  delete from public.org_unit_closure c
   where c.institution_id = new.institution_id
     and c.descendant_id in (select s.descendant_id from public.org_unit_closure s
                              where s.institution_id = new.institution_id and s.ancestor_id = new.id)
     and c.ancestor_id not in (select s.descendant_id from public.org_unit_closure s
                                where s.institution_id = new.institution_id and s.ancestor_id = new.id);
  insert into public.org_unit_closure (institution_id, ancestor_id, descendant_id, depth)
  select new.institution_id, up.ancestor_id, down.descendant_id, up.depth + down.depth + 1
    from public.org_unit_closure up
    join public.org_unit_closure down on down.institution_id = new.institution_id and down.ancestor_id = new.id
   where up.institution_id = new.institution_id and up.descendant_id = new.parent_id;
  update public.org_units u
     set branch_id = case when u.kind = 'branch' then u.id else new.branch_id end
   where u.institution_id = new.institution_id
     and u.id in (select s.descendant_id from public.org_unit_closure s
                   where s.institution_id = new.institution_id and s.ancestor_id = new.id and s.depth > 0);
  return null;
end $$;
create trigger org_units_after_move after update of parent_id on public.org_units
  for each row execute function app.org_units_after_move();

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. Feature gate and helpers
-- ---------------------------------------------------------------------------------------------------------------------
-- Placeholder setting; 0B replaces branches_enabled() with the module system and plan limits (Starter 1 branch,
-- Standard 2–3, Pro unlimited, extra branches as add-on). Off: branch fields are left out of API answers.
insert into public.setting_definitions (key, scope, schema, default_value, area, description) values
  ('branches_enabled', 'institution', '{"type":"boolean"}', 'false', 'settings.organisation',
   'Branches / campuses are used (placeholder until the module system and plan limits, 0B).');

create or replace function app.branches_enabled(p_institution uuid default null) returns boolean
language sql stable set search_path = '' as $$
  select coalesce((app.setting_value(coalesce(p_institution, app.auth_institution_id()), 'branches_enabled'))::boolean, false)
$$;
create or replace function public.branches_enabled() returns boolean
language sql stable set search_path = '' as $$ select app.branches_enabled(app.auth_institution_id()) $$;

-- Who may change the organisation. Until permissions exist (0A.17): the platform Master Admin only (fail-closed).
create or replace function app.org_write_allowed(p_institution uuid) returns boolean
language sql stable set search_path = '' as $$
  select app.settings_write_allowed(p_institution, 'settings.organisation')
$$;

/** Every unit in the subtree of p_unit (itself included): one index range scan on the closure table. */
create or replace function app.org_subtree(p_institution uuid, p_unit uuid) returns setof uuid
language sql stable set search_path = '' as $$
  select c.descendant_id from public.org_unit_closure c where c.institution_id = p_institution and c.ancestor_id = p_unit
$$;

grant execute on function app.branches_enabled(uuid), public.branches_enabled(), app.org_write_allowed(uuid),
  app.org_subtree(uuid, uuid) to authenticated, service_role;

create or replace function app.org_unit_or_fail(p_institution uuid, p_unit uuid) returns public.org_units
language plpgsql stable set search_path = '' as $$
declare
  v public.org_units;
begin
  select * into v from public.org_units where institution_id = p_institution and id = p_unit;
  if not found then
    raise exception 'org_unit_unknown' using errcode = 'P0404', detail = p_unit::text;
  end if;
  return v;
end $$;

create or replace function app.org_log(p_institution uuid, p_event text, p_unit uuid, p_payload jsonb) returns void
language plpgsql set search_path = '' as $$
begin
  perform app.audit(p_institution, p_event, 'org_unit', p_unit::text, null, p_payload);
  perform app.emit_event(p_institution, p_event, 1, 'org_unit', p_unit::text, jsonb_build_object('org_unit_id', p_unit) || p_payload);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 4. RPCs (SECURITY DEFINER: the app has no write grants). Target institution as for settings and secrets.
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function public.org_unit_create(p_name text, p_kind text, p_parent_id uuid default null,
                                                  p_institution_id uuid default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.secret_target_institution(p_institution_id);
  v_parent      public.org_units;
  v_id          uuid;
begin
  if not app.org_write_allowed(v_institution) then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  if p_kind = 'branch' then
    raise exception 'org_unit_invalid' using errcode = 'P0422', detail = 'use branch_create for branches';
  end if;
  if p_parent_id is not null then
    v_parent := app.org_unit_or_fail(v_institution, p_parent_id);
    if v_parent.archived_at is not null then
      raise exception 'org_unit_archived' using errcode = 'P0422', detail = p_parent_id::text;
    end if;
  end if;
  insert into public.org_units (institution_id, parent_id, kind, name, created_by)
  values (v_institution, p_parent_id, p_kind, btrim(p_name), auth.uid()) returning id into v_id;
  perform app.org_log(v_institution, 'org_unit.created', v_id, jsonb_build_object('kind', p_kind, 'name', btrim(p_name)));
  return v_id;
end $$;

create or replace function public.org_unit_update(p_id uuid, p_name text, p_institution_id uuid default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.secret_target_institution(p_institution_id);
  v_unit        public.org_units;
begin
  if not app.org_write_allowed(v_institution) then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  v_unit := app.org_unit_or_fail(v_institution, p_id);
  update public.org_units set name = btrim(p_name) where institution_id = v_institution and id = p_id;
  perform app.org_log(v_institution, 'org_unit.updated', p_id, jsonb_build_object('name', btrim(p_name), 'previous_name', v_unit.name));
end $$;

-- Move a unit (and everything under it) to a new parent (null = directly under the institution).
create or replace function public.org_unit_move(p_id uuid, p_new_parent_id uuid, p_institution_id uuid default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.secret_target_institution(p_institution_id);
  v_unit        public.org_units;
  v_parent      public.org_units;
begin
  if not app.org_write_allowed(v_institution) then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  v_unit := app.org_unit_or_fail(v_institution, p_id);
  if v_unit.kind = 'branch' and p_new_parent_id is not null then
    raise exception 'org_unit_invalid' using errcode = 'P0422', detail = 'a branch stays directly under the institution';
  end if;
  if p_new_parent_id is not null then
    v_parent := app.org_unit_or_fail(v_institution, p_new_parent_id);
    if v_parent.archived_at is not null then
      raise exception 'org_unit_archived' using errcode = 'P0422', detail = p_new_parent_id::text;
    end if;
    -- No cycles: the new parent may not be the unit itself or anything below it.
    if exists (select 1 from public.org_unit_closure c
               where c.institution_id = v_institution and c.ancestor_id = p_id and c.descendant_id = p_new_parent_id) then
      raise exception 'org_unit_cycle' using errcode = 'P0422', detail = 'a unit cannot move under itself';
    end if;
  end if;
  update public.org_units set parent_id = p_new_parent_id where institution_id = v_institution and id = p_id;
  perform app.org_log(v_institution, 'org_unit.moved', p_id,
                      jsonb_build_object('from_parent_id', v_unit.parent_id, 'to_parent_id', p_new_parent_id));
end $$;

-- Archive (never delete): only when no active unit, member, manager or member's home branch is left in it.
create or replace function public.org_unit_archive(p_id uuid, p_institution_id uuid default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.secret_target_institution(p_institution_id);
  v_unit        public.org_units;
  v_left        text[];
begin
  if not app.org_write_allowed(v_institution) then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  v_unit := app.org_unit_or_fail(v_institution, p_id);
  if v_unit.archived_at is not null then
    return;
  end if;
  v_left := array_remove(array[
    case when exists (select 1 from public.org_units c where c.institution_id = v_institution and c.parent_id = p_id
                      and c.archived_at is null) then 'units' end,
    case when exists (select 1 from public.org_unit_members m where m.institution_id = v_institution and m.org_unit_id = p_id)
         then 'members' end,
    case when exists (select 1 from public.org_unit_managers m where m.institution_id = v_institution and m.org_unit_id = p_id)
         then 'managers' end,
    case when v_unit.kind = 'branch' and exists (select 1 from public.institution_members im
                      where im.institution_id = v_institution and im.branch_id = p_id) then 'staff_home_branch' end
    -- 1A/1B add their records here (leads, clients, offerings, cohorts, payments with this branch_id).
  ], null);
  if array_length(v_left, 1) > 0 then
    raise exception 'org_unit_not_empty' using errcode = 'P0409',
      detail = 'move these first: ' || array_to_string(v_left, ', ');
  end if;
  update public.org_units set archived_at = now() where institution_id = v_institution and id = p_id;
  perform app.org_log(v_institution, case when v_unit.kind = 'branch' then 'branch.archived' else 'org_unit.archived' end,
                      p_id, jsonb_build_object('name', v_unit.name));
end $$;

create or replace function public.org_unit_add_member(p_unit_id uuid, p_user_id uuid, p_institution_id uuid default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.secret_target_institution(p_institution_id);
  v_unit        public.org_units;
begin
  if not app.org_write_allowed(v_institution) then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  v_unit := app.org_unit_or_fail(v_institution, p_unit_id);
  if v_unit.archived_at is not null then
    raise exception 'org_unit_archived' using errcode = 'P0422', detail = p_unit_id::text;
  end if;
  if not exists (select 1 from public.institution_members m where m.institution_id = v_institution and m.user_id = p_user_id
                 and m.status = 'active') then
    raise exception 'not_a_member' using errcode = 'P0403';
  end if;
  insert into public.org_unit_members (institution_id, org_unit_id, user_id) values (v_institution, p_unit_id, p_user_id)
  on conflict do nothing;
  if found then
    perform app.org_log(v_institution, 'org_unit.member_added', p_unit_id, jsonb_build_object('user_id', p_user_id));
  end if;
end $$;

create or replace function public.org_unit_remove_member(p_unit_id uuid, p_user_id uuid, p_institution_id uuid default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.secret_target_institution(p_institution_id);
begin
  if not app.org_write_allowed(v_institution) then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  delete from public.org_unit_members where institution_id = v_institution and org_unit_id = p_unit_id and user_id = p_user_id;
  if found then
    perform app.org_log(v_institution, 'org_unit.member_removed', p_unit_id, jsonb_build_object('user_id', p_user_id));
  end if;
end $$;

-- Managers: a manager's "team" scope (0A.17) is the unit and everything under it.
create or replace function public.set_manager(p_unit_id uuid, p_user_id uuid, p_is_manager boolean, p_institution_id uuid default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.secret_target_institution(p_institution_id);
  v_unit        public.org_units;
begin
  if not app.org_write_allowed(v_institution) then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  v_unit := app.org_unit_or_fail(v_institution, p_unit_id);
  if p_is_manager then
    if v_unit.archived_at is not null then
      raise exception 'org_unit_archived' using errcode = 'P0422', detail = p_unit_id::text;
    end if;
    if not exists (select 1 from public.institution_members m where m.institution_id = v_institution and m.user_id = p_user_id
                   and m.status = 'active') then
      raise exception 'not_a_member' using errcode = 'P0403';
    end if;
    insert into public.org_unit_managers (institution_id, org_unit_id, user_id) values (v_institution, p_unit_id, p_user_id)
    on conflict do nothing;
  else
    delete from public.org_unit_managers where institution_id = v_institution and org_unit_id = p_unit_id and user_id = p_user_id;
  end if;
  perform app.org_log(v_institution, 'org_unit.manager_set', p_unit_id, jsonb_build_object('user_id', p_user_id, 'is_manager', p_is_manager));
end $$;

-- Branches: an org unit of kind 'branch' plus details (Settings → Branches, Ch 12.2).
create or replace function public.branch_create(p_name text, p_address text default null, p_phone text default null,
                                                p_head_user_id uuid default null, p_institution_id uuid default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.secret_target_institution(p_institution_id);
  v_id          uuid;
begin
  if not app.org_write_allowed(v_institution) then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  if not app.branches_enabled(v_institution) then
    raise exception 'branches_disabled' using errcode = 'P0403';
  end if;
  insert into public.org_units (institution_id, parent_id, kind, name, created_by)
  values (v_institution, null, 'branch', btrim(p_name), auth.uid()) returning id into v_id;
  insert into public.branches (institution_id, org_unit_id, address, phone, head_user_id)
  values (v_institution, v_id, nullif(btrim(p_address), ''), app.require_valid_phone(p_phone, v_institution), p_head_user_id);
  perform app.org_log(v_institution, 'branch.created', v_id, jsonb_build_object('name', btrim(p_name)));
  return v_id;
end $$;

create or replace function public.branch_update(p_id uuid, p_name text, p_address text default null, p_phone text default null,
                                                p_head_user_id uuid default null, p_institution_id uuid default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.secret_target_institution(p_institution_id);
  v_unit        public.org_units;
begin
  if not app.org_write_allowed(v_institution) then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  v_unit := app.org_unit_or_fail(v_institution, p_id);
  if v_unit.kind <> 'branch' then
    raise exception 'org_unit_invalid' using errcode = 'P0422', detail = 'not a branch';
  end if;
  update public.org_units set name = btrim(p_name) where institution_id = v_institution and id = p_id;
  update public.branches set address = nullif(btrim(p_address), ''), phone = app.require_valid_phone(p_phone, v_institution),
         head_user_id = p_head_user_id, updated_at = now()
   where institution_id = v_institution and org_unit_id = p_id;
  perform app.org_log(v_institution, 'branch.updated', p_id, jsonb_build_object('name', btrim(p_name)));
end $$;

-- INVOKER: it only forwards to org_unit_archive, which does every check.
create or replace function public.branch_archive(p_id uuid, p_institution_id uuid default null)
returns void language sql set search_path = '' as $$
  select public.org_unit_archive(p_id, p_institution_id)
$$;

-- The whole tree in one call (Done-when): units with parent, kind, depth, managers, member counts and, when branches
-- are on, branch details. Branch fields are left out when branches are off (Ch 12.2).
create or replace function public.org_tree_get(p_include_archived boolean default false) returns jsonb
language sql stable security definer set search_path = '' as $$
  with inst as (select app.auth_institution_id() as id, app.branches_enabled(app.auth_institution_id()) as branches_on)
  select jsonb_build_object(
    'branches_enabled', (select branches_on from inst),
    'units', coalesce(jsonb_agg(
      jsonb_build_object('id', u.id, 'parent_id', u.parent_id, 'kind', u.kind, 'name', u.name, 'archived', u.archived_at is not null,
        'depth', (select max(c.depth) from public.org_unit_closure c where c.institution_id = u.institution_id and c.descendant_id = u.id),
        'managers', coalesce((select jsonb_agg(m.user_id order by m.added_at) from public.org_unit_managers m
                              where m.institution_id = u.institution_id and m.org_unit_id = u.id), '[]'::jsonb),
        'member_count', (select count(*) from public.org_unit_members m where m.institution_id = u.institution_id and m.org_unit_id = u.id))
      || case when (select branches_on from inst) then jsonb_build_object('branch_id', u.branch_id,
           'branch', (select jsonb_build_object('address', b.address, 'phone', b.phone, 'head_user_id', b.head_user_id)
                      from public.branches b where b.institution_id = u.institution_id and b.org_unit_id = u.id))
         else '{}'::jsonb end
      order by u.kind <> 'branch', u.name), '[]'::jsonb))
  from public.org_units u, inst
  where u.institution_id = inst.id and (p_include_archived or u.archived_at is null)
$$;

revoke all on function public.org_unit_create(text, text, uuid, uuid), public.org_unit_update(uuid, text, uuid),
  public.org_unit_move(uuid, uuid, uuid), public.org_unit_archive(uuid, uuid), public.org_unit_add_member(uuid, uuid, uuid),
  public.org_unit_remove_member(uuid, uuid, uuid), public.set_manager(uuid, uuid, boolean, uuid),
  public.branch_create(text, text, text, uuid, uuid), public.branch_update(uuid, text, text, text, uuid, uuid),
  public.branch_archive(uuid, uuid), public.org_tree_get(boolean), public.branches_enabled() from public, anon;
grant execute on function public.org_unit_create(text, text, uuid, uuid), public.org_unit_update(uuid, text, uuid),
  public.org_unit_move(uuid, uuid, uuid), public.org_unit_archive(uuid, uuid), public.org_unit_add_member(uuid, uuid, uuid),
  public.org_unit_remove_member(uuid, uuid, uuid), public.set_manager(uuid, uuid, boolean, uuid),
  public.branch_create(text, text, text, uuid, uuid), public.branch_update(uuid, text, text, text, uuid, uuid),
  public.branch_archive(uuid, uuid), public.org_tree_get(boolean), public.branches_enabled() to authenticated;

insert into app.definer_registry (function_name, reason, added_in, reviewer, tenant_check)
select f, r, '0A.15', 'architecture review 0A.15', t from (values
  ('public.org_unit_create', 'Writes org_units (no app write grant); target via secret_target_institution(); audited.', 'filters_active_institution'),
  ('public.org_unit_update', 'Renames a unit of the target institution; audited.', 'filters_active_institution'),
  ('public.org_unit_move', 'Moves a unit within the target institution; cycle and branch rules; audited.', 'filters_active_institution'),
  ('public.org_unit_archive', 'Archives an empty unit of the target institution (never deletes); audited.', 'filters_active_institution'),
  ('public.org_unit_add_member', 'Adds an active member of the target institution to a unit; audited.', 'filters_active_institution'),
  ('public.org_unit_remove_member', 'Removes a member from a unit of the target institution; audited.', 'filters_active_institution'),
  ('public.set_manager', 'Sets / unsets a unit manager in the target institution; audited.', 'filters_active_institution'),
  ('public.branch_create', 'Creates a branch unit + details in the target institution when branches are on; audited.', 'filters_active_institution'),
  ('public.branch_update', 'Updates a branch of the target institution; phone normalised; audited.', 'filters_active_institution'),
  ('public.org_tree_get', 'Reads the active institution''s tree in one call (aggregates across org tables).', 'filters_active_institution'),
  ('app.org_units_after_insert', 'Trigger: writes closure rows for the inserted unit (same institution).', 'not_tenant_data'),
  ('app.org_units_after_move', 'Trigger: rewrites closure rows of the moved subtree (same institution).', 'not_tenant_data')
) as v (f, r, t);


-- ---------------------------------------------------------------------------------------------------------------------
-- 5. Events (catalogue)
-- ---------------------------------------------------------------------------------------------------------------------
insert into public.event_definitions (event_key, version, entity_type, payload_schema, description)
select k, 1, 'org_unit', '{"type":"object","required":["org_unit_id"],"properties":{"org_unit_id":{"type":"string"}}}'::jsonb, d
from (values
  ('org_unit.created', 'A department, team or other unit was created.'),
  ('org_unit.updated', 'A unit was renamed.'),
  ('org_unit.moved', 'A unit (with everything under it) moved to another parent.'),
  ('org_unit.archived', 'A unit was archived.'),
  ('org_unit.member_added', 'A person was added to a unit.'),
  ('org_unit.member_removed', 'A person was removed from a unit.'),
  ('org_unit.manager_set', 'A unit manager was set or removed.'),
  ('branch.created', 'A branch was created.'),
  ('branch.updated', 'A branch''s details changed.'),
  ('branch.archived', 'A branch was archived.')
) as v (k, d);
