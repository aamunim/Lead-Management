-- 0A.19 Settings → Branches and Settings → Terminology (Ch 12.2, 12.5, Ch 8.6, 8.8, 8.10 #4; D9, D13).
-- No new data. Branches: what still uses a branch before it can be archived, and one call that moves all of it to
-- another branch (Ch 12.2 "move to another branch first"). Terminology: reset all words to the defaults, the Bangla
-- forms the server would derive (for the live preview), and old / new values in the audit log for every change.

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Branch archive guard (0A.19-T2)
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function app.branch_or_fail(p_institution uuid, p_branch uuid) returns public.org_units
language plpgsql stable set search_path = '' as $$
declare
  v public.org_units := app.org_unit_or_fail(p_institution, p_branch);
begin
  if v.kind <> 'branch' then
    raise exception 'org_unit_invalid' using errcode = 'P0422', detail = 'not a branch';
  end if;
  return v;
end $$;
grant execute on function app.branch_or_fail(uuid, uuid) to authenticated;

-- What still uses the branch (counts). Records (leads, clients, payments …) are added here by 1A / 1B.
create or replace function app.branch_usage(p_institution uuid, p_branch uuid) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'units', (select count(*) from public.org_units c where c.institution_id = p_institution and c.parent_id = p_branch and c.archived_at is null),
    'unit_members', (select count(*) from public.org_unit_members m where m.institution_id = p_institution and m.org_unit_id = p_branch),
    'managers', (select count(*) from public.org_unit_managers m where m.institution_id = p_institution and m.org_unit_id = p_branch),
    'staff_home_branch', (select count(*) from public.institution_members im where im.institution_id = p_institution and im.branch_id = p_branch),
    'role_assignments', (select count(*) from public.role_assignments ra where ra.institution_id = p_institution and ra.branch_id = p_branch))
$$;
grant execute on function app.branch_usage(uuid, uuid) to authenticated;

create or replace function public.branch_archive_check(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_institution uuid := app.auth_institution_id();
  v_usage       jsonb;
begin
  if not app.settings_read_allowed('settings.organisation') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  perform app.branch_or_fail(v_institution, p_id);
  v_usage := app.branch_usage(v_institution, p_id);
  return v_usage || jsonb_build_object('total', (select sum(value::bigint) from jsonb_each_text(v_usage)));
end $$;

-- Moves everything that uses p_from to p_to: sub-units (with their subtrees), unit members and managers, staff whose
-- home branch it is, and role assignments limited to it. Then the branch can be archived. Audited with the counts.
create or replace function public.branch_move_contents(p_from uuid, p_to uuid, p_institution_id uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.secret_target_institution(p_institution_id);
  v_from        public.org_units;
  v_to          public.org_units;
  v_usage       jsonb;
  c             record;
begin
  if not app.org_write_allowed(v_institution) then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  v_from := app.branch_or_fail(v_institution, p_from);
  v_to := app.branch_or_fail(v_institution, p_to);
  if p_from = p_to or v_to.archived_at is not null then
    raise exception 'org_unit_invalid' using errcode = 'P0422', detail = 'choose another active branch';
  end if;
  v_usage := app.branch_usage(v_institution, p_from);
  for c in select id from public.org_units where institution_id = v_institution and parent_id = p_from and archived_at is null loop
    perform public.org_unit_move(c.id, p_to, v_institution);
  end loop;
  insert into public.org_unit_members (institution_id, org_unit_id, user_id)
  select institution_id, p_to, user_id from public.org_unit_members where institution_id = v_institution and org_unit_id = p_from
  on conflict do nothing;
  delete from public.org_unit_members where institution_id = v_institution and org_unit_id = p_from;
  insert into public.org_unit_managers (institution_id, org_unit_id, user_id)
  select institution_id, p_to, user_id from public.org_unit_managers where institution_id = v_institution and org_unit_id = p_from
  on conflict do nothing;
  delete from public.org_unit_managers where institution_id = v_institution and org_unit_id = p_from;
  update public.institution_members set branch_id = p_to, updated_at = now() where institution_id = v_institution and branch_id = p_from;
  -- The same role for the same person in the target branch already exists: the moved one is a duplicate.
  delete from public.role_assignments ra where ra.institution_id = v_institution and ra.branch_id = p_from
     and exists (select 1 from public.role_assignments o where o.institution_id = v_institution and o.branch_id = p_to
                 and o.user_id = ra.user_id and o.role_id = ra.role_id and o.org_unit_id is not distinct from ra.org_unit_id);
  update public.role_assignments set branch_id = p_to where institution_id = v_institution and branch_id = p_from;
  perform app.flush_access_queue(v_institution);
  perform app.audit(v_institution, 'branch.contents_moved', 'branch', p_from::text, v_usage,
                    jsonb_build_object('to_branch_id', p_to, 'to_name', v_to.name));
  return v_usage;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. Terminology (0A.19-T5/T6/T7)
-- ---------------------------------------------------------------------------------------------------------------------
-- The Bangla forms the server would store for a base word (+ optional manual forms): the live preview shows exactly
-- what will be saved. Product data only (no tenant data).
create or replace function public.label_bn_forms(p_key text, p_base text, p_overrides jsonb default '{}'::jsonb) returns jsonb
language sql stable security definer set search_path = '' as $$
  select app.bn_forms(p_base, k.animate, coalesce(p_overrides, '{}'::jsonb)) from public.label_keys k where k.key = p_key
$$;

-- Reset one word: the audit row now has the default it went back to as the "after" value, and the change is emitted.
create or replace function public.label_reset(p_key text, p_institution_id uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.secret_target_institution(p_institution_id);
  v_row         public.institution_labels;
  v_after       jsonb;
begin
  if not exists (select 1 from public.label_keys where key = p_key) then
    raise exception 'label_unknown' using errcode = 'P0404', detail = p_key;
  end if;
  if not app.settings_write_allowed(v_institution, 'settings.terminology') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  select * into v_row from public.institution_labels where institution_id = v_institution and key = p_key;
  if v_row.locked_by_platform and not app.is_platform_admin() then
    raise exception 'label_locked' using errcode = 'P0423', detail = p_key;
  end if;
  delete from public.institution_labels where institution_id = v_institution and key = p_key;
  if found then
    v_after := app.label_resolved(v_institution, p_key);
    perform app.audit(v_institution, 'label.changed', 'label', p_key,
                      jsonb_build_object('en_singular', v_row.en_singular, 'en_plural', v_row.en_plural, 'bn_forms', v_row.bn_forms),
                      v_after - 'source' - 'locked', 'reset to default');
    perform app.emit_event(v_institution, 'label.changed', 1, 'label', p_key,
                           jsonb_build_object('key', p_key, 'en_singular', v_after ->> 'en_singular', 'bn_base', v_after -> 'bn_forms' ->> 'base'));
  end if;
  return jsonb_build_object('key', p_key, 'label', app.label_resolved(v_institution, p_key),
                            'settings_version', app.bump_settings_version(v_institution));
end $$;

-- Reset every renamed word of the institution (locked words stay). One audit row per word with old and new values.
create or replace function public.label_reset_all(p_institution_id uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.secret_target_institution(p_institution_id);
  r             public.institution_labels;
  v_after       jsonb;
  v_count       integer := 0;
begin
  if not app.settings_write_allowed(v_institution, 'settings.terminology') then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  for r in delete from public.institution_labels
            where institution_id = v_institution and not (locked_by_platform and not app.is_platform_admin())
           returning * loop
    v_after := app.label_resolved(v_institution, r.key);
    perform app.audit(v_institution, 'label.changed', 'label', r.key,
                      jsonb_build_object('en_singular', r.en_singular, 'en_plural', r.en_plural, 'bn_forms', r.bn_forms),
                      v_after - 'source' - 'locked', 'reset all to default');
    perform app.emit_event(v_institution, 'label.changed', 1, 'label', r.key,
                           jsonb_build_object('key', r.key, 'en_singular', v_after ->> 'en_singular', 'bn_base', v_after -> 'bn_forms' ->> 'base'));
    v_count := v_count + 1;
  end loop;
  return jsonb_build_object('reset', v_count, 'settings_version', app.bump_settings_version(v_institution));
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. Grants and registry
-- ---------------------------------------------------------------------------------------------------------------------
revoke all on function public.branch_archive_check(uuid), public.branch_move_contents(uuid, uuid, uuid),
  public.label_bn_forms(text, text, jsonb), public.label_reset_all(uuid) from public, anon;
grant execute on function public.branch_archive_check(uuid), public.branch_move_contents(uuid, uuid, uuid),
  public.label_bn_forms(text, text, jsonb), public.label_reset_all(uuid) to authenticated;

insert into app.definer_registry (function_name, reason, added_in, reviewer, tenant_check)
select f, r, '0A.19', 'architecture review 0A.19', t from (values
  ('public.branch_archive_check', 'Counts what still uses a branch of the active institution; needs settings.organisation.', 'filters_active_institution'),
  ('public.branch_move_contents', 'Moves units, members, managers, home-branch staff and branch-limited roles of the target institution to another branch; can(settings.organisation); audited.', 'filters_active_institution'),
  ('public.label_bn_forms', 'Derives Bangla word forms for a product label key (no tenant data) for the live preview.', 'not_tenant_data'),
  ('public.label_reset_all', 'Resets the target institution''s renamed words (locked ones stay); can(settings.terminology); audited per word.', 'filters_active_institution')
) as v (f, r, t);
