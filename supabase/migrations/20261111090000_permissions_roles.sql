-- 0A.16 Permission registry, roles, behaviour flags and role templates (D23, D26, D10). See docs/dev/PERMISSIONS.md.
-- Permissions are data: modules declare them in config/modules/*.json; scripts/permissions/sync.mjs loads them with
-- app.sync_permissions() on every deploy. Roles are scoped sets of permissions plus behaviour flags. Checking a
-- permission (can()) and role assignments come in 0A.17.

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Registry (platform tables)
-- ---------------------------------------------------------------------------------------------------------------------
create table public.permissions (
  key                    text primary key
                         check (key = '*' or key ~ '^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$')
                         -- R1 / Ch 8: neutral keys only; the education words belong in labels.
                         check (key !~ '(^|[._])(students?|courses?|batch(es)?|admissions?|guardians?|alumni|alumnus|college|school|papers)($|[._])'),
  kind                   text not null default 'institution' check (kind in ('institution', 'platform')),
  module                 text not null,
  action                 text not null,
  scopable               boolean not null default false,
  sensitive              boolean not null default false,
  introduced_in_release  text not null,
  default_for_templates  jsonb not null default '{}'::jsonb check (jsonb_typeof(default_for_templates) = 'object'),
  retired_at             timestamptz,
  updated_at             timestamptz not null default now(),
  unique (key, kind)
);
comment on column public.permissions.default_for_templates is
  'Role template key → scope ("all", "branch", "org_unit", "team", "own") or true; system roles get these by default.';

insert into public.permissions (key, kind, module, action, scopable, sensitive, introduced_in_release)
values ('*', 'institution', 'core', 'all', false, true, '0A.16');

create table public.field_registry (
  entity          text not null check (entity ~ '^[a-z][a-z0-9_]*$'),
  field           text not null check (field ~ '^[a-z][a-z0-9_]*$'),
  sensitive       boolean not null default false,
  permission_key  text references public.permissions (key),
  primary key (entity, field)
);
comment on table public.field_registry is
  'Field-level rules (Ch 11.11): sensitive fields need permission_key to be seen, are masked otherwise (1B) and are never sent to AI.';

create table public.behaviour_flags (
  key          text primary key check (key ~ '^[a-z][a-z0-9_]*$'),
  description  text not null
);
insert into public.behaviour_flags (key, description) values
  ('assignable', 'In assignment lists and round robin (Ch 11.9).'),
  ('counts_on_leaderboard', 'Credited on the leaderboard and scorecard (Ch 39).'),
  ('receives_escalations', 'Receives speed-to-lead and overdue escalations (Ch 18).'),
  ('counts_as_manager', 'Used for team scope and team reports.'),
  ('shown_in_team_activity', 'Tracked in team activity (Ch 38).'),
  ('call_log_sync_required', 'Android call-log sync required (Ch 41).');

-- Templates per type profile (D26). Grants come from the permissions' default_for_templates (single source, the
-- module manifests); `extra_grants` only for template-specific additions.
create table public.role_templates (
  type_profile_key  text not null check (type_profile_key ~ '^[a-z][a-z0-9_]*$'),
  role_key          text not null check (role_key ~ '^[a-z][a-z0-9_]*$'),
  name_key          text not null,        -- roles:names.<role_key> (labels for caller / team_lead / conversion_officer)
  is_super_admin    boolean not null default false,
  flags             text[] not null default '{}',
  extra_grants      jsonb not null default '{}'::jsonb,
  sort              integer not null,
  primary key (type_profile_key, role_key)
);

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. Roles of an institution
-- ---------------------------------------------------------------------------------------------------------------------
create table public.roles (
  institution_id         uuid not null references public.institutions (id) on delete cascade,
  id                     uuid not null default gen_random_uuid(),
  name                   text check (name is null or length(btrim(name)) between 1 and 60),
  name_key               text,           -- default name from translations / labels until the institution renames it
  is_system              boolean not null default false,
  is_super_admin         boolean not null default false,
  template_key           text,           -- role_key of the template it came from (system roles)
  type_profile_key       text,
  rank_for_sorting       integer not null default 100,  -- sorting only; never decides who may manage whom (R8)
  inherits_from_role_id  uuid,
  flags                  text[] not null default '{}',
  archived_at            timestamptz,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  primary key (institution_id, id),
  foreign key (institution_id, inherits_from_role_id) references public.roles (institution_id, id) on delete set null (inherits_from_role_id),
  check (name is not null or name_key is not null),
  check (not is_super_admin or is_system)
);
create unique index roles_template_idx on public.roles (institution_id, template_key) where is_system;
create unique index roles_super_admin_idx on public.roles (institution_id) where is_super_admin;

create or replace function app.check_role_flags() returns trigger
language plpgsql set search_path = '' as $$
declare
  v_unknown text[];
begin
  select array_agg(f) into v_unknown from unnest(new.flags) f where f not in (select key from public.behaviour_flags);
  if v_unknown is not null then
    raise exception 'role_invalid' using errcode = 'P0422', detail = 'unknown flags: ' || array_to_string(v_unknown, ', ');
  end if;
  new.flags := array(select distinct f from unnest(new.flags) f order by f);
  return new;
end $$;
create trigger roles_check_flags before insert or update of flags on public.roles
  for each row execute function app.check_role_flags();

create table public.role_permissions (
  institution_id   uuid not null,
  role_id          uuid not null,
  permission_key   text not null,
  -- T10: an institution role can never hold a platform permission — enforced by this foreign key on (key, kind).
  permission_kind  text not null default 'institution' check (permission_kind = 'institution'),
  scope            text check (scope in ('own', 'team', 'org_unit', 'branch', 'all')),
  granted_at       timestamptz not null default now(),
  primary key (institution_id, role_id, permission_key),
  foreign key (institution_id, role_id) references public.roles (institution_id, id) on delete cascade,
  foreign key (permission_key, permission_kind) references public.permissions (key, kind) on delete cascade
);
create index role_permissions_key_idx on public.role_permissions (institution_id, permission_key);

-- Grant rules: `*` only on the Super Admin system role (R6); scope given exactly when the permission is scopable.
create or replace function app.check_role_permission() returns trigger
language plpgsql set search_path = '' as $$
declare
  v_perm public.permissions;
  v_role public.roles;
begin
  select * into v_perm from public.permissions where key = new.permission_key;
  select * into v_role from public.roles where institution_id = new.institution_id and id = new.role_id;
  if new.permission_key = '*' and not v_role.is_super_admin then
    raise exception 'role_invalid' using errcode = 'P0422', detail = '* is only for the Super Admin role';
  end if;
  if v_perm.scopable and new.scope is null then
    new.scope := 'own';
  elsif not v_perm.scopable then
    new.scope := null;
  end if;
  return new;
end $$;
create trigger role_permissions_check before insert or update on public.role_permissions
  for each row execute function app.check_role_permission();

alter table public.permissions enable row level security;
alter table public.field_registry enable row level security;
alter table public.behaviour_flags enable row level security;
alter table public.role_templates enable row level security;
alter table public.roles enable row level security;
alter table public.role_permissions enable row level security;
revoke all on public.permissions, public.field_registry, public.behaviour_flags, public.role_templates, public.roles,
  public.role_permissions from anon, authenticated;
grant select on public.permissions, public.field_registry, public.behaviour_flags, public.role_templates, public.roles,
  public.role_permissions to authenticated;
create policy permissions_read on public.permissions for select to authenticated using (true);
create policy field_registry_read on public.field_registry for select to authenticated using (true);
create policy behaviour_flags_read on public.behaviour_flags for select to authenticated using (true);
create policy role_templates_read on public.role_templates for select to authenticated using (true);
create policy roles_read on public.roles for select to authenticated using (institution_id = (select app.auth_institution_id()));
create policy role_permissions_read on public.role_permissions for select to authenticated
  using (institution_id = (select app.auth_institution_id()));

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. Templates (D26, Ch 11.7). Role names: roles:names.<key>; caller / team_lead / conversion_officer use labels.
-- ---------------------------------------------------------------------------------------------------------------------
insert into public.role_templates (type_profile_key, role_key, name_key, is_super_admin, flags, sort)
select p, r, 'roles:names.' || r, sa, f, s from (values
  ('college', 'principal', true, '{receives_escalations}'::text[], 10),
  ('college', 'vice_principal', false, '{receives_escalations,counts_as_manager}', 20),
  ('college', 'admin', false, '{receives_escalations}', 30),
  ('college', 'branch_manager', false, '{receives_escalations,counts_as_manager,shown_in_team_activity}', 40),
  ('college', 'department_head', false, '{receives_escalations,counts_as_manager,shown_in_team_activity}', 50),
  ('college', 'team_lead', false, '{assignable,counts_on_leaderboard,receives_escalations,counts_as_manager,shown_in_team_activity}', 60),
  ('college', 'caller', false, '{assignable,counts_on_leaderboard,shown_in_team_activity,call_log_sync_required}', 70),
  ('college', 'conversion_officer', false, '{shown_in_team_activity}', 80),
  ('college', 'accountant', false, '{}', 90),
  ('college', 'viewer', false, '{}', 100),
  ('college', 'governing_body', false, '{}', 110),
  ('school', 'principal', true, '{receives_escalations}', 10),
  ('school', 'head_teacher', false, '{receives_escalations,counts_as_manager}', 12),
  ('school', 'assistant_head_teacher', false, '{receives_escalations,counts_as_manager}', 14),
  ('school', 'vice_principal', false, '{receives_escalations,counts_as_manager}', 20),
  ('school', 'admin', false, '{receives_escalations}', 30),
  ('school', 'branch_manager', false, '{receives_escalations,counts_as_manager,shown_in_team_activity}', 40),
  ('school', 'department_head', false, '{receives_escalations,counts_as_manager,shown_in_team_activity}', 50),
  ('school', 'team_lead', false, '{assignable,counts_on_leaderboard,receives_escalations,counts_as_manager,shown_in_team_activity}', 60),
  ('school', 'caller', false, '{assignable,counts_on_leaderboard,shown_in_team_activity,call_log_sync_required}', 70),
  ('school', 'conversion_officer', false, '{shown_in_team_activity}', 80),
  ('school', 'class_teacher', false, '{}', 85),
  ('school', 'accountant', false, '{}', 90),
  ('school', 'viewer', false, '{}', 100),
  ('school', 'governing_body', false, '{}', 110),
  ('coaching', 'owner', true, '{receives_escalations}', 10),
  ('coaching', 'manager', false, '{assignable,receives_escalations,counts_as_manager,shown_in_team_activity}', 20),
  ('coaching', 'caller', false, '{assignable,counts_on_leaderboard,shown_in_team_activity,call_log_sync_required}', 70)
) as v (p, r, sa, f, s);
update public.role_templates set name_key = 'labels:' || role_key || '.singular' where role_key in ('caller', 'team_lead', 'conversion_officer');

-- Creates (or completes) the template roles of an institution, with the grants the manifests declare. Run by
-- onboarding (0B) with the institution's type profile, and by tests / seeds. Never removes anything.
create or replace function app.apply_role_template(p_institution uuid, p_profile text) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  t record;
  v_role uuid;
  v_count integer := 0;
begin
  if not exists (select 1 from public.role_templates where type_profile_key = p_profile) then
    raise exception 'role_template_unknown' using errcode = 'P0404', detail = p_profile;
  end if;
  for t in select * from public.role_templates where type_profile_key = p_profile order by sort loop
    select id into v_role from public.roles where institution_id = p_institution and is_system and template_key = t.role_key;
    if v_role is null then
      insert into public.roles (institution_id, name_key, is_system, is_super_admin, template_key, type_profile_key, rank_for_sorting, flags)
      values (p_institution, t.name_key, true, t.is_super_admin, t.role_key, p_profile, t.sort, t.flags)
      returning id into v_role;
      v_count := v_count + 1;
    end if;
    if t.is_super_admin then
      insert into public.role_permissions (institution_id, role_id, permission_key) values (p_institution, v_role, '*') on conflict do nothing;
    else
      insert into public.role_permissions (institution_id, role_id, permission_key, scope)
      select p_institution, v_role, p.key, case when p.scopable then coalesce(nullif(g.value #>> '{}', 'true'), 'own') end
        from public.permissions p
        cross join lateral (select coalesce(p.default_for_templates -> t.role_key, t.extra_grants -> p.key) as value) g
       where p.kind = 'institution' and p.key <> '*' and p.retired_at is null and g.value is not null
      on conflict do nothing;
    end if;
  end loop;
  return v_count;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 4. Registry sync and new-release rollout (0A.16-T2, T7)
-- ---------------------------------------------------------------------------------------------------------------------
-- p_manifests: array of module manifests (config/modules/*.json). Upserts permissions and fields; a permission that is
-- new in this run is given to system roles by its template defaults, and to custom roles that inherit from a role
-- holding it — only when it is not sensitive (R20). Returns the keys that were new.
create or replace function app.sync_permissions(p_manifests jsonb) returns text[]
language plpgsql security definer set search_path = '' as $$
declare
  m jsonb;
  p jsonb;
  v_new text[] := '{}';
  v_key text;
begin
  for m in select * from jsonb_array_elements(p_manifests) loop
    for p in select * from jsonb_array_elements(coalesce(m -> 'permissions', '[]'::jsonb)) loop
      v_key := p ->> 'key';
      if not exists (select 1 from public.permissions where key = v_key) then
        v_new := v_new || v_key;
      end if;
      insert into public.permissions (key, kind, module, action, scopable, sensitive, introduced_in_release, default_for_templates)
      values (v_key, 'institution', m ->> 'module', split_part(v_key, '.', 2), coalesce((p ->> 'scopable')::boolean, false),
              coalesce((p ->> 'sensitive')::boolean, false), coalesce(p ->> 'introduced_in_release', m ->> 'release'),
              coalesce(p -> 'defaults', '{}'::jsonb))
      on conflict (key) do update set module = excluded.module, scopable = excluded.scopable, sensitive = excluded.sensitive,
        default_for_templates = excluded.default_for_templates, retired_at = null, updated_at = now();
    end loop;
    for p in select * from jsonb_array_elements(coalesce(m -> 'platform_permissions', '[]'::jsonb)) loop
      insert into public.permissions (key, kind, module, action, sensitive, introduced_in_release)
      values (p ->> 'key', 'platform', m ->> 'module', split_part(p ->> 'key', '.', 2), coalesce((p ->> 'sensitive')::boolean, true),
              coalesce(p ->> 'introduced_in_release', m ->> 'release'))
      on conflict (key) do update set sensitive = excluded.sensitive, retired_at = null, updated_at = now();
    end loop;
    for p in select * from jsonb_array_elements(coalesce(m -> 'fields', '[]'::jsonb)) loop
      insert into public.field_registry (entity, field, sensitive, permission_key)
      values (p ->> 'entity', p ->> 'field', coalesce((p ->> 'sensitive')::boolean, false), p ->> 'permission')
      on conflict (entity, field) do update set sensitive = excluded.sensitive, permission_key = excluded.permission_key;
    end loop;
  end loop;

  if array_length(v_new, 1) > 0 then
    -- System roles: the defaults declared for their template.
    insert into public.role_permissions (institution_id, role_id, permission_key, scope)
    select r.institution_id, r.id, pm.key, case when pm.scopable then coalesce(nullif(pm.default_for_templates -> r.template_key #>> '{}', 'true'), 'own') end
      from public.roles r
      join public.permissions pm on pm.key = any (v_new) and pm.default_for_templates ? r.template_key
     where r.is_system and not r.is_super_admin and r.archived_at is null
    on conflict do nothing;
    -- Custom roles that inherit: only non-sensitive new permissions their parent now holds.
    insert into public.role_permissions (institution_id, role_id, permission_key, scope)
    select c.institution_id, c.id, rp.permission_key, rp.scope
      from public.roles c
      join public.role_permissions rp on rp.institution_id = c.institution_id and rp.role_id = c.inherits_from_role_id
      join public.permissions pm on pm.key = rp.permission_key
     where not c.is_system and c.archived_at is null and pm.key = any (v_new) and not pm.sensitive
    on conflict do nothing;
  end if;
  return v_new;
end $$;

revoke all on function app.apply_role_template(uuid, text), app.sync_permissions(jsonb) from public, anon, authenticated;
grant execute on function app.apply_role_template(uuid, text), app.sync_permissions(jsonb) to service_role;

-- ---------------------------------------------------------------------------------------------------------------------
-- 5. Role RPCs (the role editor UI is 0A.18). Writes need settings.roles (Master Admin until can() in 0A.17).
-- ---------------------------------------------------------------------------------------------------------------------
-- Sensitive permissions (R6, Ch 11.5): changing a role that grants one needs a two-step (aal2) session.
create or replace function app.require_aal2() returns void
language plpgsql stable set search_path = '' as $$
begin
  if coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'aal', 'aal1') <> 'aal2' then
    raise exception 'mfa_required' using errcode = 'P0401', hint = 'Sign in with the second step to change sensitive permissions.';
  end if;
end $$;
grant execute on function app.require_aal2() to authenticated;

create or replace function app.role_or_fail(p_institution uuid, p_role uuid) returns public.roles
language plpgsql stable set search_path = '' as $$
declare
  v public.roles;
begin
  select * into v from public.roles where institution_id = p_institution and id = p_role;
  if not found then
    raise exception 'role_unknown' using errcode = 'P0404', detail = p_role::text;
  end if;
  return v;
end $$;

create or replace function public.roles_get() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', r.id, 'name', r.name, 'name_key', r.name_key, 'is_system', r.is_system, 'is_super_admin', r.is_super_admin,
    'template_key', r.template_key, 'rank', r.rank_for_sorting, 'inherits_from_role_id', r.inherits_from_role_id,
    'flags', to_jsonb(r.flags), 'archived', r.archived_at is not null,
    'grants', coalesce((select jsonb_object_agg(rp.permission_key, coalesce(to_jsonb(rp.scope), 'true'::jsonb))
                        from public.role_permissions rp where rp.institution_id = r.institution_id and rp.role_id = r.id), '{}'::jsonb))
    order by r.rank_for_sorting, r.created_at), '[]'::jsonb)
  from public.roles r where r.institution_id = app.auth_institution_id()
$$;

create or replace function public.role_create(p_name text, p_inherits_from_role_id uuid default null, p_flags text[] default '{}',
                                              p_rank integer default 100, p_institution_id uuid default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.secret_target_institution(p_institution_id);
  v_parent      public.roles;
  v_id          uuid;
begin
  if not app.settings_write_allowed(v_institution, 'settings.roles') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  if p_inherits_from_role_id is not null then
    v_parent := app.role_or_fail(v_institution, p_inherits_from_role_id);
  end if;
  insert into public.roles (institution_id, name, inherits_from_role_id, flags, rank_for_sorting)
  values (v_institution, btrim(p_name), p_inherits_from_role_id, coalesce(p_flags, '{}'), coalesce(p_rank, 100)) returning id into v_id;
  -- A copy starts with the parent's non-sensitive grants; sensitive ones must be added explicitly (with aal2).
  if v_parent.id is not null then
    insert into public.role_permissions (institution_id, role_id, permission_key, scope)
    select v_institution, v_id, rp.permission_key, rp.scope
      from public.role_permissions rp join public.permissions pm on pm.key = rp.permission_key
     where rp.institution_id = v_institution and rp.role_id = v_parent.id and not pm.sensitive and rp.permission_key <> '*';
  end if;
  perform app.audit(v_institution, 'role.created', 'role', v_id::text, null, jsonb_build_object('name', btrim(p_name)));
  perform app.emit_event(v_institution, 'role.changed', 1, 'role', v_id::text, jsonb_build_object('role_id', v_id, 'change', 'created'));
  return v_id;
end $$;

create or replace function public.role_update(p_role_id uuid, p_name text, p_flags text[], p_rank integer default null,
                                              p_institution_id uuid default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.secret_target_institution(p_institution_id);
  v_role        public.roles;
begin
  if not app.settings_write_allowed(v_institution, 'settings.roles') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  v_role := app.role_or_fail(v_institution, p_role_id);
  update public.roles set name = nullif(btrim(p_name), ''), name_key = case when nullif(btrim(p_name), '') is null then v_role.name_key end,
         flags = coalesce(p_flags, flags), rank_for_sorting = coalesce(p_rank, rank_for_sorting), updated_at = now()
   where institution_id = v_institution and id = p_role_id;
  perform app.audit(v_institution, 'role.updated', 'role', p_role_id::text,
                    jsonb_build_object('name', v_role.name, 'flags', v_role.flags), jsonb_build_object('name', p_name, 'flags', p_flags));
  perform app.emit_event(v_institution, 'role.changed', 1, 'role', p_role_id::text, jsonb_build_object('role_id', p_role_id, 'change', 'updated'));
end $$;

-- Replace a role's grants: p_grants = { "permission.key": "scope" | true }.
create or replace function public.role_set_grants(p_role_id uuid, p_grants jsonb, p_institution_id uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.secret_target_institution(p_institution_id);
  v_role        public.roles;
  v_before      jsonb;
  v_bad         text[];
  v_sensitive   boolean;
begin
  if not app.settings_write_allowed(v_institution, 'settings.roles') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  v_role := app.role_or_fail(v_institution, p_role_id);
  if v_role.is_super_admin then
    raise exception 'role_invalid' using errcode = 'P0422', detail = 'the Super Admin role always has every permission';
  end if;
  select array_agg(k) into v_bad from jsonb_object_keys(coalesce(p_grants, '{}'::jsonb)) k
   where not exists (select 1 from public.permissions p where p.key = k and p.kind = 'institution' and p.key <> '*' and p.retired_at is null);
  if v_bad is not null then
    raise exception 'role_invalid' using errcode = 'P0422', detail = 'unknown or not allowed: ' || array_to_string(v_bad, ', ');
  end if;
  select coalesce(jsonb_object_agg(permission_key, coalesce(to_jsonb(scope), 'true'::jsonb)), '{}'::jsonb) into v_before
    from public.role_permissions where institution_id = v_institution and role_id = p_role_id;
  -- Adding or removing a sensitive permission needs two-step sign-in.
  select exists (select 1 from public.permissions p where p.sensitive and p.key in (
            select k from jsonb_object_keys(v_before) k where not (coalesce(p_grants, '{}'::jsonb) ? k)
            union select k from jsonb_object_keys(coalesce(p_grants, '{}'::jsonb)) k where not (v_before ? k))) into v_sensitive;
  if v_sensitive then
    perform app.require_aal2();
  end if;
  delete from public.role_permissions where institution_id = v_institution and role_id = p_role_id;
  insert into public.role_permissions (institution_id, role_id, permission_key, scope)
  select v_institution, p_role_id, g.key, nullif(g.value #>> '{}', 'true') from jsonb_each(coalesce(p_grants, '{}'::jsonb)) g;
  perform app.audit(v_institution, 'role.grants_changed', 'role', p_role_id::text, v_before, p_grants);
  perform app.emit_event(v_institution, 'role.changed', 1, 'role', p_role_id::text, jsonb_build_object('role_id', p_role_id, 'change', 'grants'));
  return (select coalesce(jsonb_object_agg(permission_key, coalesce(to_jsonb(scope), 'true'::jsonb)), '{}'::jsonb)
            from public.role_permissions where institution_id = v_institution and role_id = p_role_id);
end $$;

revoke all on function public.roles_get(), public.role_create(text, uuid, text[], integer, uuid),
  public.role_update(uuid, text, text[], integer, uuid), public.role_set_grants(uuid, jsonb, uuid) from public, anon;
grant execute on function public.roles_get(), public.role_create(text, uuid, text[], integer, uuid),
  public.role_update(uuid, text, text[], integer, uuid), public.role_set_grants(uuid, jsonb, uuid) to authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- 6. "Who" selector for NON-access settings (0A.16-T8, Ch 11.10): notification recipients, dashboard cards …
--    {mode: 'all' | 'roles' | 'users', roles: [role ids], user_ids: [user ids]}; the Super Admin role is never listed.
--    Access rules are scoped permissions instead (e.g. conversion.mark).
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function app.validate_who(p_institution uuid, p_who jsonb) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_mode text := p_who ->> 'mode';
begin
  if v_mode is null or v_mode not in ('all', 'roles', 'users') then
    raise exception 'who_invalid' using errcode = 'P0422', detail = 'mode must be all, roles or users';
  end if;
  if v_mode = 'roles' and exists (select 1 from jsonb_array_elements_text(coalesce(p_who -> 'roles', '[]'::jsonb)) r
     join public.roles x on x.institution_id = p_institution and x.id::text = r.value where x.is_super_admin) then
    raise exception 'who_invalid' using errcode = 'P0422', detail = 'the Super Admin role is not offered here';
  end if;
  return jsonb_build_object('mode', v_mode, 'roles', coalesce(p_who -> 'roles', '[]'::jsonb), 'user_ids', coalesce(p_who -> 'user_ids', '[]'::jsonb));
end $$;
grant execute on function app.validate_who(uuid, jsonb) to authenticated, service_role;

insert into app.definer_registry (function_name, reason, added_in, reviewer, tenant_check)
select f, r, '0A.16', 'architecture review 0A.16', t from (values
  ('app.apply_role_template', 'Onboarding / seeds: creates template roles for an institution; service_role only.', 'service_role_only'),
  ('app.sync_permissions', 'Deploy step: loads module manifests into the registry and rolls out new permissions; service_role only.', 'service_role_only'),
  ('public.roles_get', 'Reads the active institution''s roles with grants and flags.', 'filters_active_institution'),
  ('public.role_create', 'Creates a custom role in the target institution (non-sensitive grants copied from the parent); audited.', 'filters_active_institution'),
  ('public.role_update', 'Renames / sets flags of a role of the target institution; audited.', 'filters_active_institution'),
  ('public.role_set_grants', 'Replaces a role''s grants in the target institution; aal2 for sensitive changes; audited.', 'filters_active_institution')
) as v (f, r, t);

insert into public.event_definitions (event_key, version, entity_type, payload_schema, description) values
  ('role.changed', 1, 'role', '{"type":"object","required":["role_id","change"],"properties":{"role_id":{"type":"string"},"change":{"enum":["created","updated","grants"]}}}',
   'A role was created, renamed, got other flags or other permissions.');
