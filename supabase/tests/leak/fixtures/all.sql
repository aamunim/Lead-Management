-- Table-specific leak fixtures (0A.05-T1). Add a function here when the generic insert cannot fill a table:
--   create function leak_fixtures.public__<table>(p_institution uuid) returns void language plpgsql as $$
--   begin insert into public.<table> (institution_id, ...) values (p_institution, ...); end $$;
-- The runner calls it once for institution A and once for B.

-- 0A.07 institution_secrets: a real Vault value per institution. A's value is also a leak marker, so no table or RPC
-- may ever return it to a viewer of B.
create function leak_fixtures.public__institution_secrets(p_institution uuid) returns void language plpgsql as $$
declare
  v_value text := 'leak-secret-value-' || p_institution::text;
  v_vault uuid;
begin
  v_vault := vault.create_secret(v_value, 'leak:' || p_institution::text || ':' || gen_random_uuid(), 'leak fixture');
  insert into public.institution_secrets (institution_id, secret_ref, vault_id, hint)
  values (p_institution, 'sms.primary.api_key', v_vault, app.secret_hint(v_value));
  if p_institution = leak.id('inst_a') then
    insert into leak.markers values (v_value, 'secret value of A') on conflict do nothing;
  end if;
end $$;

-- 0A.09 event log and audit log: a row per institution, written the way the app writes them (backend call, no user).
create function leak_fixtures.public__domain_events(p_institution uuid) returns void language plpgsql as $$
begin
  perform app.emit_event(p_institution, 'setting.changed', 1, 'setting', 'leak.key',
                         jsonb_build_object('key', 'leak.key', 'value', 'leak-event-' || p_institution::text));
  if p_institution = leak.id('inst_a') then
    insert into leak.markers values ('leak-event-' || p_institution::text, 'event payload of A') on conflict do nothing;
  end if;
end $$;

create function leak_fixtures.public__audit_log(p_institution uuid) returns void language plpgsql as $$
begin
  perform app.audit(p_institution, 'setting.changed', 'setting', 'leak.key', null,
                    jsonb_build_object('value', 'leak-audit-' || p_institution::text));
  if p_institution = leak.id('inst_a') then
    insert into leak.markers values ('leak-audit-' || p_institution::text, 'audit entry of A') on conflict do nothing;
  end if;
end $$;

-- Extensions: switch the example extension on for both institutions, so the extension's own RLS is what is tested
-- (not merely "the extension is off").
create function leak_fixtures.public__institution_extensions(p_institution uuid) returns void language plpgsql as $$
begin
  insert into public.institution_extensions (institution_id, extension_key, enabled)
  values (p_institution, 'example', true)
  on conflict (institution_id, extension_key) do update set enabled = true;
end $$;

create function leak_fixtures.ext_example__notes(p_institution uuid) returns void language plpgsql as $$
begin
  perform leak_fixtures.public__institution_extensions(p_institution);
  insert into ext_example.notes (institution_id, body) values (p_institution, 'leak-note-' || p_institution::text);
  if p_institution = leak.id('inst_a') then
    insert into leak.markers values ('leak-note-' || p_institution::text, 'extension note of A') on conflict do nothing;
  end if;
end $$;

create function leak_fixtures.ext_example__setting_change_counts(p_institution uuid) returns void language plpgsql as $$
begin
  perform leak_fixtures.public__institution_extensions(p_institution);
  insert into ext_example.setting_change_counts (institution_id, changes, last_key)
  values (p_institution, 1, 'leak-count-' || p_institution::text);
  if p_institution = leak.id('inst_a') then
    insert into leak.markers values ('leak-count-' || p_institution::text, 'extension data of A') on conflict do nothing;
  end if;
end $$;

-- 0A.12 labels: A's renamed word is a leak marker, so no table or RPC (labels_get, …) may show it to B.
create function leak_fixtures.public__institution_labels(p_institution uuid) returns void language plpgsql as $$
declare
  v_word text := 'leak-label-' || left(p_institution::text, 8);
begin
  insert into public.institution_labels (institution_id, key, en_singular, en_plural, bn_forms)
  values (p_institution, 'client', v_word, v_word || 's', app.bn_forms(v_word, true));
  if p_institution = leak.id('inst_a') then
    insert into leak.markers values (v_word, 'renamed label of A') on conflict do nothing;
  end if;
end $$;

-- 0A.15 org units: per institution a branch (with details) → department, with a member and a manager.
-- One builder, called by every org table's fixture (whichever the runner reaches first builds it).
create function leak_fixtures.org_tree(p_institution uuid) returns void language plpgsql as $$
declare
  v_branch uuid := gen_random_uuid();
  v_dept   uuid := gen_random_uuid();
  v_user   uuid;
begin
  if exists (select 1 from public.org_units where institution_id = p_institution) then
    return;
  end if;
  select user_id into v_user from public.institution_members where institution_id = p_institution and status = 'active' limit 1;
  insert into public.org_units (institution_id, id, kind, name) values (p_institution, v_branch, 'branch', 'leak-branch-' || left(p_institution::text, 8));
  insert into public.branches (institution_id, org_unit_id, address) values (p_institution, v_branch, 'leak-address-' || left(p_institution::text, 8));
  insert into public.org_units (institution_id, id, parent_id, kind, name) values (p_institution, v_dept, v_branch, 'department', 'leak-dept');
  insert into public.org_unit_members (institution_id, org_unit_id, user_id) values (p_institution, v_dept, v_user);
  insert into public.org_unit_managers (institution_id, org_unit_id, user_id) values (p_institution, v_branch, v_user);
  if p_institution = leak.id('inst_a') then
    insert into leak.markers values ('leak-branch-' || left(p_institution::text, 8), 'branch name of A'),
                                    ('leak-address-' || left(p_institution::text, 8), 'branch address of A') on conflict do nothing;
  end if;
end $$;
create function leak_fixtures.public__org_units(p uuid) returns void language sql as $$ select leak_fixtures.org_tree(p) $$;
create function leak_fixtures.public__org_unit_closure(p uuid) returns void language sql as $$ select leak_fixtures.org_tree(p) $$;
create function leak_fixtures.public__branches(p uuid) returns void language sql as $$ select leak_fixtures.org_tree(p) $$;
create function leak_fixtures.public__org_unit_members(p uuid) returns void language sql as $$ select leak_fixtures.org_tree(p) $$;
create function leak_fixtures.public__org_unit_managers(p uuid) returns void language sql as $$ select leak_fixtures.org_tree(p) $$;

-- 0A.16 roles: the coaching template roles plus a custom role whose name is a marker for A.
create function leak_fixtures.roles_for(p_institution uuid) returns void language plpgsql as $$
begin
  if exists (select 1 from public.roles where institution_id = p_institution) then
    return;
  end if;
  perform app.apply_role_template(p_institution, 'coaching');
  insert into public.roles (institution_id, name, flags) values (p_institution, 'leak-role-' || left(p_institution::text, 8), '{assignable}');
  if p_institution = leak.id('inst_a') then
    insert into leak.markers values ('leak-role-' || left(p_institution::text, 8), 'custom role name of A') on conflict do nothing;
  end if;
end $$;
create function leak_fixtures.public__roles(p uuid) returns void language sql as $$ select leak_fixtures.roles_for(p) $$;
create function leak_fixtures.public__role_permissions(p uuid) returns void language sql as $$ select leak_fixtures.roles_for(p) $$;

-- 0A.17 access: a Super Admin assignment (gives user_access rows) and a queued rebuild per institution.
create function leak_fixtures.access_for(p_institution uuid) returns void language plpgsql as $$
declare
  v_user uuid;
begin
  perform leak_fixtures.roles_for(p_institution);
  select user_id into v_user from public.institution_members where institution_id = p_institution and status = 'active' order by user_id limit 1;
  -- Seeds (0A.18) may already hold assignments; each table still gets its own row.
  if not exists (select 1 from public.role_assignments where institution_id = p_institution) then
    insert into public.role_assignments (institution_id, user_id, role_id)
    select p_institution, v_user, id from public.roles where institution_id = p_institution and is_super_admin;
  end if;
  perform app.flush_access_queue(p_institution);
  insert into public.access_rebuild_queue (institution_id, user_id) values (p_institution, v_user) on conflict do nothing;
end $$;
create function leak_fixtures.public__role_assignments(p uuid) returns void language sql as $$ select leak_fixtures.access_for(p) $$;
create function leak_fixtures.public__user_access(p uuid) returns void language sql as $$ select leak_fixtures.access_for(p) $$;
create function leak_fixtures.public__access_rebuild_queue(p uuid) returns void language sql as $$ select leak_fixtures.access_for(p) $$;

-- 0B.01 settings: a value per institution (A's is a marker), and the history row the change writes.
create function leak_fixtures.public__app_settings(p_institution uuid) returns void language plpgsql as $$
declare
  v_value text := case when p_institution = leak.id('inst_a') then 'LEAKA-0B01' else 'OTHER-0B01' end;
begin
  insert into public.app_settings (institution_id, key, value) values (p_institution, 'receipt_prefix', to_jsonb(v_value))
  on conflict (institution_id, key) do update set value = excluded.value;
  if p_institution = leak.id('inst_a') then
    insert into leak.markers values (v_value, 'setting value of A') on conflict do nothing;
  end if;
end $$;
create function leak_fixtures.public__app_settings_history(p uuid) returns void language sql as $$ select leak_fixtures.public__app_settings(p) $$;

-- 0B.06 custom fields: a field and a value per institution (A's are markers).
create function leak_fixtures.public__custom_field_definitions(p_institution uuid) returns void language plpgsql as $$
declare
  v_mark text := case when p_institution = leak.id('inst_a') then 'LEAKA-0B06' else 'OTHER-0B06' end;
begin
  insert into public.custom_field_definitions (institution_id, id, entity, key, label, type)
  values (p_institution, md5('leak-cf-' || p_institution)::uuid, 'lead', 'leak_field', jsonb_build_object('en', v_mark, 'bn', v_mark), 'text')
  on conflict do nothing;
  insert into public.custom_field_values (institution_id, field_id, entity, record_id, value_text)
  values (p_institution, md5('leak-cf-' || p_institution)::uuid, 'lead', gen_random_uuid(), v_mark || '-VALUE')
  on conflict do nothing;
  if p_institution = leak.id('inst_a') then
    insert into leak.markers values (v_mark, 'custom field of A'), (v_mark || '-VALUE', 'custom field value of A') on conflict do nothing;
  end if;
end $$;
create function leak_fixtures.public__custom_field_values(p uuid) returns void language sql as $$ select leak_fixtures.public__custom_field_definitions(p) $$;

-- 0B.08 support sessions: one per institution, entered by the platform Master Admin (the reason of A's is a marker).
create function leak_fixtures.public__support_sessions(p_institution uuid) returns void language plpgsql as $$
declare
  v_reason text := case when p_institution = leak.id('inst_a') then 'LEAKA-0B08 support reason' else 'OTHER-0B08 support reason' end;
begin
  insert into public.support_sessions (institution_id, platform_user_id, reason, started_at, expires_at, ended_at)
  values (p_institution, '55555555-5555-4555-8555-555555555555', v_reason, now() - interval '2 hours', now() - interval '1 hour', now() - interval '1 hour');
  if p_institution = leak.id('inst_a') then
    insert into leak.markers values ('LEAKA-0B08', 'support session reason of A') on conflict do nothing;
  end if;
end $$;

-- 0B.09: a Super Admin invitation (the email is the marker).
create function leak_fixtures.public__institution_invites(p_institution uuid) returns void language plpgsql as $$
declare
  v_email text := case when p_institution = leak.id('inst_a') then 'leaka-0b09@example.test' else 'other-0b09@example.test' end;
begin
  insert into public.institution_invites (institution_id, email, role_id)
  select p_institution, v_email, r.id from public.roles r where r.institution_id = p_institution and r.is_super_admin;
  if not found then
    insert into public.roles (institution_id, name_key, is_system, is_super_admin) values (p_institution, 'role.super_admin', true, true);
    insert into public.institution_invites (institution_id, email, role_id)
    select p_institution, v_email, r.id from public.roles r where r.institution_id = p_institution and r.is_super_admin;
  end if;
  if p_institution = leak.id('inst_a') then
    insert into leak.markers values ('leaka-0b09', 'Super Admin invitation email of A') on conflict do nothing;
  end if;
end $$;

-- 0B.10: a checklist item ticked by hand (the note is the marker).
create function leak_fixtures.public__institution_checklist(p_institution uuid) returns void language plpgsql as $$
begin
  insert into public.institution_checklist (institution_id, item_key, status, note, completed_at)
  values (p_institution, 'pipeline_words', 'done',
          case when p_institution = leak.id('inst_a') then 'LEAKA-0B10 checklist note' else 'OTHER-0B10 checklist note' end, now())
  on conflict (institution_id, item_key) do update set note = excluded.note;
  if p_institution = leak.id('inst_a') then
    insert into leak.markers values ('LEAKA-0B10', 'checklist note of A') on conflict do nothing;
  end if;
end $$;

-- 0B.11: who pays for SMS (no free text: the institution's row itself is the probe), and a connection whose label is
-- the marker (integration_connections has a generic-insert-safe shape, this keeps the marker explicit).
create function leak_fixtures.public__institution_service_payers(p_institution uuid) returns void language plpgsql as $$
begin
  insert into public.institution_service_payers (institution_id, kind, payer) values (p_institution, 'sms', 'direct')
  on conflict (institution_id, kind) do nothing;
end $$;

-- 0B.12: a queued message, its delivery-log row and a ledger day (the recipient / provider are the markers).
create function leak_fixtures.public__outbox(p_institution uuid) returns void language plpgsql as $$
declare
  v_to text := case when p_institution = leak.id('inst_a') then 'LEAKA-0B12-recipient' else 'OTHER-0B12-recipient' end;
begin
  insert into public.outbox (institution_id, channel, priority, lane, recipient, payload, idempotency_key)
  values (p_institution, 'sms', 'transactional', 3, v_to, '{"body":"leak fixture"}', 'leak-fixture-' || p_institution)
  on conflict (institution_id, idempotency_key) do nothing;
  if p_institution = leak.id('inst_a') then
    insert into leak.markers values ('LEAKA-0B12-recipient', 'outbox recipient of A') on conflict do nothing;
  end if;
end $$;
create function leak_fixtures.public__delivery_log(p_institution uuid) returns void language plpgsql as $$
declare
  v_to text := case when p_institution = leak.id('inst_a') then 'LEAKA-0B12-delivered' else 'OTHER-0B12-delivered' end;
begin
  insert into public.delivery_log (institution_id, outbox_id, recipient, channel, category, result)
  values (p_institution, gen_random_uuid(), v_to, 'sms', 'notification', 'sent');
  if p_institution = leak.id('inst_a') then
    insert into leak.markers values ('LEAKA-0B12-delivered', 'delivery log recipient of A') on conflict do nothing;
  end if;
end $$;
create function leak_fixtures.public__usage_ledger(p_institution uuid) returns void language plpgsql as $$
declare
  v_provider text := case when p_institution = leak.id('inst_a') then 'LEAKA-0B12-provider' else 'OTHER-0B12-provider' end;
begin
  insert into public.usage_ledger (institution_id, day, provider, channel, category, payer, count)
  values (p_institution, current_date, v_provider, 'sms', 'notification', 'direct', 1)
  on conflict do nothing;
  if p_institution = leak.id('inst_a') then
    insert into leak.markers values ('LEAKA-0B12-provider', 'ledger provider of A') on conflict do nothing;
  end if;
end $$;
create function leak_fixtures.public__webhook_events(p_institution uuid) returns void language plpgsql as $$
declare
  v_key text := case when p_institution = leak.id('inst_a') then 'LEAKA-0B12-event' else 'OTHER-0B12-event' end;
begin
  insert into public.webhook_events (institution_id, connection_id, connection_owner, provider, event_key, signature_ok, payload)
  values (p_institution, gen_random_uuid(), 'institution', 'mock_sms', v_key, true, '{}');
  if p_institution = leak.id('inst_a') then
    insert into leak.markers values ('LEAKA-0B12-event', 'callback event of A') on conflict do nothing;
  end if;
end $$;

-- 0B.14: a sending domain (the domain is the marker).
create function leak_fixtures.public__email_domains(p_institution uuid) returns void language plpgsql as $$
declare
  v_domain text := case when p_institution = leak.id('inst_a') then 'leaka-0b14.example.test' else 'other-0b14.example.test' end;
begin
  insert into public.email_domains (institution_id, domain, provider) values (p_institution, v_domain, 'resend') on conflict do nothing;
  if p_institution = leak.id('inst_a') then
    insert into leak.markers values ('leaka-0b14.example.test', 'sending domain of A') on conflict do nothing;
  end if;
end $$;
