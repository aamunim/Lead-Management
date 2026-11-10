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
