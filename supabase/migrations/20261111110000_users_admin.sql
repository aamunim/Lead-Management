-- 0A.18 Users screen, role editor, basic access explainer and audit view (Ch 11.14, R16, R20; D23, D26).
-- No new business data: RPCs over the tables of 0A.03 / 0A.16 / 0A.17, plus a small registry of record types the
-- access explainer can look up (filled by later modules: leads in 1A). See docs/dev/USERS_ADMIN.md.

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Read gate: a settings screen in the ACTIVE institution (the server is the real check; the app only hides).
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function app.settings_read_allowed(p_area text) returns boolean
language sql stable set search_path = '' as $$
  select app.auth_institution_id() is not null and (app.is_platform_admin() or app.can(p_area))
$$;
grant execute on function app.settings_read_allowed(text) to authenticated;

create or replace function app.like_pattern(p_search text) returns text
language sql immutable set search_path = '' as $$
  select '%' || replace(replace(replace(lower(btrim(p_search)), '\', '\\'), '%', '\%'), '_', '\_') || '%'
$$;
grant execute on function app.like_pattern(text) to authenticated;

-- Membership status changes keep their audit row (0A.09 trigger); an RPC can attach the reason for that change.
create or replace function app.on_membership_status_logged() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.status is distinct from old.status then
    insert into public.audit_log (institution_id, actor_user_id, action, target_type, target_id, before, after, reason)
    values (new.institution_id, auth.uid(), 'membership.status_changed', 'membership', new.user_id::text,
            jsonb_build_object('status', old.status), jsonb_build_object('status', new.status),
            nullif(current_setting('app.audit_reason', true), ''));
    insert into public.domain_events (institution_id, event_key, event_version, entity_type, entity_id, actor_user_id, payload)
    values (new.institution_id, 'membership.status_changed', 1, 'membership', new.user_id::text, auth.uid(),
            jsonb_build_object('user_id', new.user_id, 'from', old.status, 'to', new.status));
  end if;
  return null;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. Users list and detail (0A.18-T1)
-- ---------------------------------------------------------------------------------------------------------------------
-- p_status: 'pending' | 'active' | 'deactivated' | null (all). p_search matches name, email or phone (digits).
create or replace function public.users_list(p_status text default null, p_search text default null,
                                             p_limit integer default 100, p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_institution uuid := app.auth_institution_id();
  v_pattern     text := case when nullif(btrim(coalesce(p_search, '')), '') is null then null else app.like_pattern(p_search) end;
  v_digits      text := nullif(regexp_replace(coalesce(p_search, ''), '\D', '', 'g'), '');
  v_result      jsonb;
begin
  if not app.settings_read_allowed('settings.users') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  if p_status is not null and p_status not in ('pending', 'active', 'deactivated') then
    raise exception 'user_state_invalid' using errcode = 'P0422', detail = 'status must be pending, active or deactivated';
  end if;
  with matched as (
    select m.user_id, m.status, m.branch_id, m.joined_at, m.deactivated_at, m.created_at,
           p.display_name, p.email, p.phone
      from public.institution_members m
      join public.profiles p on p.user_id = m.user_id
     where m.institution_id = v_institution
       and (p_status is null or m.status = p_status)
       and (v_pattern is null
            or lower(coalesce(p.display_name, '')) like v_pattern
            or lower(coalesce(p.email, '')) like v_pattern
            or (v_digits is not null and length(v_digits) >= 3 and regexp_replace(coalesce(p.phone, ''), '\D', '', 'g') like '%' || v_digits || '%'))
  )
  select jsonb_build_object(
    'total', (select count(*) from matched),
    'counts', (select jsonb_build_object(
        'pending', count(*) filter (where status = 'pending'),
        'active', count(*) filter (where status = 'active'),
        'deactivated', count(*) filter (where status = 'deactivated'))
       from public.institution_members where institution_id = v_institution),
    'items', coalesce((select jsonb_agg(x.j order by x.ord, x.nm) from (
        select case mm.status when 'pending' then 0 when 'active' then 1 else 2 end as ord,
               lower(coalesce(mm.display_name, mm.email, '')) as nm,
               jsonb_build_object(
                 'user_id', mm.user_id, 'display_name', mm.display_name, 'email', mm.email, 'phone', mm.phone,
                 'status', mm.status, 'branch_id', mm.branch_id, 'joined_at', mm.joined_at, 'deactivated_at', mm.deactivated_at,
                 'requested_at', mm.created_at,
                 'roles', coalesce((select jsonb_agg(distinct jsonb_build_object('id', r.id, 'name', r.name, 'name_key', r.name_key))
                                      from public.role_assignments ra
                                      join public.roles r on r.institution_id = ra.institution_id and r.id = ra.role_id
                                     where ra.institution_id = v_institution and ra.user_id = mm.user_id
                                       and ra.valid_from <= now() and (ra.valid_to is null or ra.valid_to > now())), '[]'::jsonb)) as j
          from matched mm
         order by ord, nm
         limit greatest(1, least(coalesce(p_limit, 100), 500)) offset greatest(0, coalesce(p_offset, 0))) x), '[]'::jsonb))
  into v_result;
  return v_result;
end $$;

create or replace function public.user_detail(p_user_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.auth_institution_id();
  v_member      public.institution_members;
  v_profile     public.profiles;
begin
  if not app.settings_read_allowed('settings.users') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  select * into v_member from public.institution_members where institution_id = v_institution and user_id = p_user_id;
  if not found then
    raise exception 'user_unknown' using errcode = 'P0404', detail = p_user_id::text;
  end if;
  perform app.flush_access_queue(v_institution);
  select * into v_profile from public.profiles where user_id = p_user_id;
  return jsonb_build_object(
    'user_id', p_user_id, 'display_name', v_profile.display_name, 'email', v_profile.email, 'phone', v_profile.phone,
    'status', v_member.status, 'branch_id', v_member.branch_id, 'joined_at', v_member.joined_at,
    'deactivated_at', v_member.deactivated_at, 'requested_at', v_member.created_at,
    'is_self', p_user_id = auth.uid(),
    -- The profile (name, phone, email) is shared by every institution the person belongs to: only they may change it then.
    'profile_shared', exists (select 1 from public.institution_members o where o.user_id = p_user_id and o.institution_id <> v_institution),
    'outranks_you', app.outranks_caller(v_institution, p_user_id),
    'assignments', coalesce((select jsonb_agg(jsonb_build_object(
        'id', ra.id, 'role_id', ra.role_id, 'role_name', r.name, 'role_name_key', r.name_key, 'is_super_admin', r.is_super_admin,
        'org_unit_id', ra.org_unit_id, 'branch_id', ra.branch_id, 'offering_limit', to_jsonb(ra.offering_limit),
        'valid_from', ra.valid_from, 'valid_to', ra.valid_to,
        'state', case when r.archived_at is not null then 'role_archived' when ra.valid_from > now() then 'scheduled'
                      when ra.valid_to is not null and ra.valid_to <= now() then 'expired' else 'active' end)
        order by r.rank_for_sorting, ra.valid_from)
        from public.role_assignments ra join public.roles r on r.institution_id = ra.institution_id and r.id = ra.role_id
       where ra.institution_id = v_institution and ra.user_id = p_user_id), '[]'::jsonb),
    'org_units', coalesce((select jsonb_agg(jsonb_build_object('id', u.id, 'name', u.name, 'kind', u.kind, 'manager', x.manager) order by u.name)
        from (select org_unit_id, bool_or(manager) as manager from (
                select org_unit_id, false as manager from public.org_unit_members where institution_id = v_institution and user_id = p_user_id
                union all
                select org_unit_id, true from public.org_unit_managers where institution_id = v_institution and user_id = p_user_id) y
              group by org_unit_id) x
        join public.org_units u on u.institution_id = v_institution and u.id = x.org_unit_id), '[]'::jsonb),
    'permissions', coalesce((select jsonb_object_agg(k, s) from (
        select ua.permission_key as k, jsonb_agg(distinct coalesce(ua.scope, 'all')) as s from public.user_access ua
         where ua.institution_id = v_institution and ua.user_id = p_user_id and (ua.valid_to is null or ua.valid_to > now())
         group by ua.permission_key) z), '{}'::jsonb),
    'flags', to_jsonb(app.user_flags(v_institution, p_user_id)),
    -- Call-log sync requirement is shown read-only until phase 3 builds it.
    'call_log_sync_required', null);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. Approve / deactivate / reactivate (0A.18-T2). Deactivation bumps the access version (0A.03 trigger), so the
--    person's next request is refused; if this was their only active institution their sign-in sessions end too.
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function app.member_or_fail(p_institution uuid, p_user uuid) returns public.institution_members
language plpgsql stable set search_path = '' as $$
declare
  v public.institution_members;
begin
  select * into v from public.institution_members where institution_id = p_institution and user_id = p_user;
  if not found then
    raise exception 'user_unknown' using errcode = 'P0404', detail = p_user::text;
  end if;
  return v;
end $$;
grant execute on function app.member_or_fail(uuid, uuid) to authenticated;

create or replace function public.user_approve(p_user_id uuid, p_institution_id uuid default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.secret_target_institution(p_institution_id);
  v_member      public.institution_members;
begin
  if not app.settings_write_allowed(v_institution, 'settings.users') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  v_member := app.member_or_fail(v_institution, p_user_id);
  if v_member.status <> 'pending' then
    raise exception 'user_state_invalid' using errcode = 'P0409', detail = 'only a pending request can be approved';
  end if;
  update public.institution_members set status = 'active', updated_at = now()
   where institution_id = v_institution and user_id = p_user_id;
  perform app.flush_access_queue(v_institution);
end $$;

create or replace function public.user_deactivate(p_user_id uuid, p_reason text default null, p_institution_id uuid default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.secret_target_institution(p_institution_id);
  v_member      public.institution_members;
begin
  if not app.settings_write_allowed(v_institution, 'settings.users') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  v_member := app.member_or_fail(v_institution, p_user_id);
  if p_user_id = auth.uid() then
    raise exception 'self_lockout' using errcode = 'P0409', detail = 'you cannot deactivate yourself';
  end if;
  if v_member.status = 'deactivated' then
    raise exception 'user_state_invalid' using errcode = 'P0409', detail = 'already deactivated';
  end if;
  if app.outranks_caller(v_institution, p_user_id) then
    raise exception 'permission_escalation' using errcode = '42501', detail = 'this person has more access than you';
  end if;
  if exists (select 1 from public.role_assignments ra
               join public.roles r on r.institution_id = ra.institution_id and r.id = ra.role_id and r.is_super_admin and r.archived_at is null
              where ra.institution_id = v_institution and ra.user_id = p_user_id
                and ra.valid_from <= now() and (ra.valid_to is null or ra.valid_to > now()))
     and v_member.status = 'active' and app.active_super_admins(v_institution) <= 1 then
    raise exception 'last_super_admin' using errcode = 'P0409', detail = 'give the Super Admin role to someone else first';
  end if;
  perform set_config('app.audit_reason', coalesce(btrim(p_reason), ''), true);
  update public.institution_members set status = 'deactivated', updated_at = now()
   where institution_id = v_institution and user_id = p_user_id;
  perform set_config('app.audit_reason', '', true);
  -- No other active institution: end every sign-in session now (refresh tokens stop working at once).
  if not exists (select 1 from public.institution_members o where o.user_id = p_user_id and o.status = 'active') then
    delete from auth.sessions where user_id = p_user_id;
  end if;
  perform app.flush_access_queue(v_institution);
end $$;

create or replace function public.user_reactivate(p_user_id uuid, p_institution_id uuid default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.secret_target_institution(p_institution_id);
  v_member      public.institution_members;
begin
  if not app.settings_write_allowed(v_institution, 'settings.users') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  v_member := app.member_or_fail(v_institution, p_user_id);
  if v_member.status <> 'deactivated' then
    raise exception 'user_state_invalid' using errcode = 'P0409', detail = 'only a deactivated person can be reactivated';
  end if;
  -- Reactivating someone with more access than you would hand that access back: same rule as assigning it.
  if app.outranks_caller(v_institution, p_user_id) then
    raise exception 'permission_escalation' using errcode = '42501', detail = 'this person has more access than you';
  end if;
  update public.institution_members set status = 'active', updated_at = now()
   where institution_id = v_institution and user_id = p_user_id;
  perform app.flush_access_queue(v_institution);
end $$;

-- Name / phone / email. An email change is applied at once (Ch 11.14). The profile is shared between institutions,
-- so an admin may change it only for people who belong to this institution alone; anyone may change their own.
create or replace function public.user_update_contact(p_user_id uuid, p_display_name text, p_phone text, p_email text,
                                                      p_institution_id uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.secret_target_institution(p_institution_id);
  v_before      public.profiles;
  v_name        text := nullif(btrim(coalesce(p_display_name, '')), '');
  v_phone       text;
  v_email       text := nullif(lower(btrim(coalesce(p_email, ''))), '');
begin
  if p_user_id is distinct from auth.uid() and not app.settings_write_allowed(v_institution, 'settings.users') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  perform app.member_or_fail(v_institution, p_user_id);
  if p_user_id <> auth.uid() then
    if app.outranks_caller(v_institution, p_user_id) then
      raise exception 'permission_escalation' using errcode = '42501', detail = 'this person has more access than you';
    end if;
    if exists (select 1 from public.institution_members o where o.user_id = p_user_id and o.institution_id <> v_institution) then
      raise exception 'profile_shared' using errcode = 'P0409', detail = 'this person also belongs to another institution';
    end if;
  end if;
  if v_name is null or length(v_name) > 120 then
    raise exception 'user_contact_invalid' using errcode = 'P0422', detail = 'name is required (at most 120 characters)';
  end if;
  if nullif(btrim(coalesce(p_phone, '')), '') is not null then
    v_phone := app.require_valid_phone(p_phone, v_institution);
    if v_phone is null then
      raise exception 'phone_invalid' using errcode = 'P0422';
    end if;
  end if;
  if v_email is null or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(v_email) > 254 then
    raise exception 'email_invalid' using errcode = 'P0422';
  end if;
  select * into v_before from public.profiles where user_id = p_user_id;
  if v_email is distinct from lower(coalesce(v_before.email, '')) then
    if exists (select 1 from auth.users u where lower(u.email) = v_email and u.id <> p_user_id) then
      raise exception 'email_taken' using errcode = 'P0409';
    end if;
    update auth.users set email = v_email, email_confirmed_at = coalesce(email_confirmed_at, now()), updated_at = now()
     where id = p_user_id;
  end if;
  update public.profiles set display_name = v_name, phone = v_phone, email = v_email, updated_at = now()
   where user_id = p_user_id;
  perform app.audit(v_institution, 'user.contact_changed', 'user', p_user_id::text,
                    jsonb_build_object('display_name', v_before.display_name, 'phone', v_before.phone, 'email', v_before.email),
                    jsonb_build_object('display_name', v_name, 'phone', v_phone, 'email', v_email), null);
  return jsonb_build_object('display_name', v_name, 'phone', v_phone, 'email', v_email);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 4. Access explainer (0A.18-T6, R16): which role / scope / limit allows or blocks one record for one person.
--    A record is either a registered record type + id ({"entity": "lead", "id": "…"}; 1A registers leads) or a
--    described record ({"permission", "owner_id", "branch_id", "offering_id", "created_by"}).
-- ---------------------------------------------------------------------------------------------------------------------
create table app.record_entities (
  entity_key      text primary key,
  table_name      regclass not null,
  view_permission text not null,
  owner_col       text not null default 'owner_id',
  branch_col      text not null default 'branch_id',
  offering_col    text not null default 'offering_id',
  created_by_col  text not null default 'created_by',
  label_key       text not null,
  added_in        text not null
);
revoke all on app.record_entities from public, anon, authenticated;
grant select on app.record_entities to service_role;

create or replace function public.record_entities_get() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('entity', e.entity_key, 'permission', e.view_permission, 'label_key', e.label_key)
                  order by e.entity_key), '[]'::jsonb)
    from app.record_entities e where app.settings_read_allowed('settings.users')
$$;

create or replace function app.explain_record(p_institution uuid, p_ref jsonb) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_entity app.record_entities;
  v_row    jsonb;
begin
  if p_ref ? 'entity' then
    select * into v_entity from app.record_entities where entity_key = p_ref ->> 'entity';
    if not found then
      raise exception 'record_unknown' using errcode = 'P0404', detail = p_ref ->> 'entity';
    end if;
    execute format('select jsonb_build_object(''owner_id'', %I, ''branch_id'', %I, ''offering_id'', %I, ''created_by'', %I) '
                   'from %s where institution_id = $1 and id::text = $2',
                   v_entity.owner_col, v_entity.branch_col, v_entity.offering_col, v_entity.created_by_col, v_entity.table_name)
      into v_row using p_institution, p_ref ->> 'id';
    if v_row is null then
      raise exception 'record_unknown' using errcode = 'P0404', detail = p_ref ->> 'id';
    end if;
    return v_row || jsonb_build_object('entity', v_entity.entity_key, 'id', p_ref ->> 'id',
                                       'permission', coalesce(p_ref ->> 'permission', v_entity.view_permission));
  end if;
  return jsonb_build_object('permission', p_ref ->> 'permission', 'owner_id', p_ref -> 'owner_id', 'branch_id', p_ref -> 'branch_id',
                            'offering_id', p_ref -> 'offering_id', 'created_by', p_ref -> 'created_by');
end $$;

create or replace function public.access_explain(p_user_id uuid, p_record_ref jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.auth_institution_id();
  v_member      public.institution_members;
  v_record      jsonb;
  v_perm        text;
  v_owner       uuid;
  v_branch      uuid;
  v_offering    uuid;
  v_creator     uuid;
  v_reasons     jsonb := '[]'::jsonb;
  v_allowed     boolean := false;
  a             record;
  g             record;
  ua            public.user_access;
  v_rule        text;
  v_detail      jsonb;
begin
  if not app.settings_read_allowed('settings.users') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  v_member := app.member_or_fail(v_institution, p_user_id);
  v_record := app.explain_record(v_institution, coalesce(p_record_ref, '{}'::jsonb));
  v_perm := v_record ->> 'permission';
  if v_perm is null or not exists (select 1 from public.permissions p where p.key = v_perm and p.kind = 'institution' and p.key <> '*') then
    raise exception 'permission_unknown' using errcode = 'P0422', detail = coalesce(v_perm, '');
  end if;
  v_owner := nullif(v_record ->> 'owner_id', '')::uuid;
  v_branch := nullif(v_record ->> 'branch_id', '')::uuid;
  v_offering := nullif(v_record ->> 'offering_id', '')::uuid;
  v_creator := nullif(v_record ->> 'created_by', '')::uuid;
  perform app.flush_access_queue(v_institution);

  for a in
    select ra.*, r.name as role_name, r.name_key as role_name_key, r.is_super_admin, r.archived_at as role_archived_at
      from public.role_assignments ra join public.roles r on r.institution_id = ra.institution_id and r.id = ra.role_id
     where ra.institution_id = v_institution and ra.user_id = p_user_id
     order by r.rank_for_sorting, ra.valid_from
  loop
    v_rule := null;
    v_detail := '{}'::jsonb;
    select rp.permission_key, coalesce(rp.scope, 'all') as scope into g from public.role_permissions rp
     where rp.institution_id = v_institution and rp.role_id = a.role_id and rp.permission_key in (v_perm, '*')
     order by rp.permission_key = v_perm desc limit 1;
    if not found then
      v_rule := 'no_permission';
    elsif a.role_archived_at is not null then
      v_rule := 'role_archived';
    elsif a.valid_from > now() then
      v_rule := 'not_started';
      v_detail := jsonb_build_object('valid_from', a.valid_from);
    elsif a.valid_to is not null and a.valid_to <= now() then
      v_rule := 'expired';
      v_detail := jsonb_build_object('valid_to', a.valid_to);
    elsif v_member.status <> 'active' then
      v_rule := 'membership_inactive';
    else
      select * into ua from public.user_access x
       where x.institution_id = v_institution and x.user_id = p_user_id and x.assignment_id = a.id
         and x.permission_key = g.permission_key;
      if not found then
        v_rule := 'not_built';   -- should not happen after the flush; reported rather than guessed
      elsif ua.branch_ids is not null and not (v_branch = any (ua.branch_ids)) and v_creator is distinct from p_user_id then
        v_rule := case when v_branch is null then 'no_branch_on_record' else 'branch_limit' end;
        v_detail := jsonb_build_object('allowed_branch_ids', to_jsonb(ua.branch_ids));
      elsif ua.user_ids is not null and not (v_owner = any (ua.user_ids)) and v_creator is distinct from p_user_id then
        v_rule := 'owner_scope';
        v_detail := jsonb_build_object('scope', ua.scope, 'allowed_owner_count', cardinality(ua.user_ids));
      elsif ua.offering_ids is not null and not (v_offering = any (ua.offering_ids))
            and not (v_offering is null and v_creator is not distinct from p_user_id) then
        v_rule := case when v_offering is null then 'no_offering_on_record' else 'offering_limit' end;
        v_detail := jsonb_build_object('allowed_offering_ids', to_jsonb(ua.offering_ids));
      else
        v_rule := case
          when g.permission_key = '*' then 'super_admin'
          when (ua.branch_ids is not null and not (v_branch = any (ua.branch_ids)))
            or (ua.user_ids is not null and not (v_owner = any (ua.user_ids)))
            or (ua.offering_ids is not null and v_offering is null) then 'creator'
          else 'scope_' || coalesce(ua.scope, 'all') end;
        v_allowed := true;
      end if;
    end if;
    v_reasons := v_reasons || jsonb_build_array(jsonb_build_object(
      'assignment_id', a.id, 'role_id', a.role_id, 'role_name', a.role_name, 'role_name_key', a.role_name_key,
      'granted', case when g.permission_key is null then null else g.permission_key end,
      'scope', case when g.permission_key is null then null else g.scope end,
      'branch_id', a.branch_id, 'org_unit_id', a.org_unit_id, 'offering_limit', to_jsonb(a.offering_limit),
      'valid_from', a.valid_from, 'valid_to', a.valid_to,
      'verdict', case when v_rule in ('super_admin', 'creator') or v_rule like 'scope\_%' then 'allows'
                      when v_rule = 'no_permission' then 'not_relevant' else 'blocks' end,
      'rule', v_rule, 'detail', v_detail));
    g := null;
  end loop;

  return jsonb_build_object(
    'allowed', v_allowed and v_member.status = 'active',
    'summary', case when v_member.status <> 'active' then 'membership_inactive'
                    when jsonb_array_length(v_reasons) = 0 then 'no_roles'
                    when v_allowed then 'allowed'
                    when not exists (select 1 from jsonb_array_elements(v_reasons) r where r ->> 'verdict' <> 'not_relevant') then 'no_role_grants'
                    else 'blocked_by_limits' end,
    'permission', v_perm, 'membership_status', v_member.status,
    'record', v_record - 'permission',
    'reasons', v_reasons);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 5. Audit viewer (0A.18-T7): role, assignment, user, field-rule and settings changes; filter by area, actor, dates.
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function public.audit_list(p_filters jsonb default '{}'::jsonb, p_limit integer default 50) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_institution uuid := app.auth_institution_id();
  f             jsonb := coalesce(p_filters, '{}'::jsonb);
  v_area        text := coalesce(f ->> 'area', 'all');
  v_actor       uuid := nullif(f ->> 'actor_user_id', '')::uuid;
  v_from        timestamptz := nullif(f ->> 'from', '')::timestamptz;
  v_to          timestamptz := nullif(f ->> 'to', '')::timestamptz;
  v_before_at   timestamptz := nullif(f ->> 'before_at', '')::timestamptz;
  v_before_id   uuid := nullif(f ->> 'before_id', '')::uuid;
  v_target      text := nullif(f ->> 'target_id', '');
  v_limit       integer := greatest(1, least(coalesce(p_limit, 50), 200));
  v_items       jsonb;
begin
  if v_institution is null or not (app.is_platform_admin() or app.can('audit.view')) then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  if v_area not in ('all', 'roles', 'assignments', 'users', 'settings', 'field_rules') then
    raise exception 'audit_filter_invalid' using errcode = 'P0422', detail = v_area;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', l.id, 'at', l.at, 'actor_user_id', l.actor_user_id, 'actor_name', p.display_name,
           'action', l.action, 'target_type', l.target_type, 'target_id', l.target_id,
           'before', l.before, 'after', l.after, 'reason', l.reason) order by l.at desc, l.id desc), '[]'::jsonb)
    into v_items
    from (select * from public.audit_log a
           where a.institution_id = v_institution
             and case v_area
                   when 'roles' then a.target_type = 'role'
                   when 'assignments' then a.target_type = 'role_assignment'
                   when 'users' then a.target_type in ('membership', 'user')
                   when 'settings' then a.target_type in ('setting', 'label', 'secret', 'extension', 'branch', 'org_unit')
                   when 'field_rules' then a.target_type = 'field_rule'
                   else true end
             and (v_actor is null or a.actor_user_id = v_actor)
             and (v_target is null or a.target_id = v_target)
             and (v_from is null or a.at >= v_from)
             and (v_to is null or a.at < v_to)
             and (v_before_at is null or (a.at, a.id) < (v_before_at, coalesce(v_before_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
           order by a.at desc, a.id desc
           limit v_limit) l
    left join public.profiles p on p.user_id = l.actor_user_id;
  return jsonb_build_object('items', v_items, 'has_more', jsonb_array_length(v_items) = v_limit);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 6. Grants, registry, errors
-- ---------------------------------------------------------------------------------------------------------------------
revoke all on function public.users_list(text, text, integer, integer), public.user_detail(uuid), public.user_approve(uuid, uuid),
  public.user_deactivate(uuid, text, uuid), public.user_reactivate(uuid, uuid), public.user_update_contact(uuid, text, text, text, uuid),
  public.record_entities_get(), public.access_explain(uuid, jsonb), public.audit_list(jsonb, integer) from public, anon;
grant execute on function public.users_list(text, text, integer, integer), public.user_detail(uuid), public.user_approve(uuid, uuid),
  public.user_deactivate(uuid, text, uuid), public.user_reactivate(uuid, uuid), public.user_update_contact(uuid, text, text, text, uuid),
  public.record_entities_get(), public.access_explain(uuid, jsonb), public.audit_list(jsonb, integer) to authenticated;
revoke all on function app.explain_record(uuid, jsonb) from public, anon, authenticated;

insert into app.definer_registry (function_name, reason, added_in, reviewer, tenant_check)
select f, r, '0A.18', 'architecture review 0A.18', t from (values
  ('public.users_list', 'Lists members of the active institution with profile fields; needs settings.users.', 'filters_active_institution'),
  ('public.user_detail', 'One member of the active institution: profile, assignments, units, access summary; needs settings.users.', 'filters_active_institution'),
  ('public.user_approve', 'Approves a pending member of the target institution; can(settings.users); audited by trigger.', 'filters_active_institution'),
  ('public.user_deactivate', 'Deactivates a member of the target institution and ends their sessions when no other institution is active; can(settings.users); audited.', 'filters_active_institution'),
  ('public.user_reactivate', 'Reactivates a member of the target institution; can(settings.users); audited by trigger.', 'filters_active_institution'),
  ('public.user_update_contact', 'Changes name / phone / email of a member who belongs to this institution only (or the caller); updates auth.users email at once; audited.', 'filters_active_institution'),
  ('public.record_entities_get', 'Lists record types the access explainer can look up (no tenant data); needs settings.users.', 'not_tenant_data'),
  ('public.access_explain', 'Explains one member''s access to one record of the active institution from their assignments; needs settings.users.', 'filters_active_institution'),
  ('public.audit_list', 'Reads the active institution''s audit log with actor names; needs audit.view.', 'filters_active_institution')
) as v (f, r, t);

-- my_access (0A.17) now refuses a stale session with a typed error instead of answering "no permissions": the
-- Settings tab hides screens from it, and an empty answer for an outdated token would hide them wrongly. The API
-- wrapper refreshes the session on session_refresh_required and asks again.
create or replace function public.my_access() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_institution uuid := app.require_active_session();
begin
  return jsonb_build_object(
    'permissions', coalesce((select jsonb_object_agg(k, s) from (
        select ua.permission_key as k, jsonb_agg(distinct coalesce(ua.scope, 'all')) as s from public.user_access ua
         where ua.institution_id = v_institution and ua.user_id = auth.uid() and (ua.valid_to is null or ua.valid_to > now())
         group by ua.permission_key) x), '{}'::jsonb),
    'flags', to_jsonb(app.user_flags(v_institution, auth.uid())));
end $$;
