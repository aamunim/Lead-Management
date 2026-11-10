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
