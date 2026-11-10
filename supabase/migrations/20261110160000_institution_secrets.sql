-- 0A.07 Per-institution secrets: values live encrypted in Supabase Vault; the app only ever sees a hint.
-- Plan: Ch 4.10, 4.13 #9, Ch 3.8, Ch 48.5, principle 8, lesson 12. See docs/dev/SECRETS.md.
--
-- Write path : secret_set / secret_revoke (SECURITY DEFINER, registered) — write-only, return the hint.
-- Read path  : secret_read_for_service — executable ONLY by service_role (Edge Functions); never by app users.
-- Who may write until permissions exist (0A.16/0A.17): only the platform Master Admin (D4). Institution staff are
-- refused (fail-closed); the `integration.manage` permission opens it for them later.

-- The DEFINER registry learns a third kind: functions that only the service role may run.
alter table app.definer_registry drop constraint definer_registry_tenant_check_check;
alter table app.definer_registry add constraint definer_registry_tenant_check_check
  check (tenant_check in ('filters_active_institution', 'not_tenant_data', 'service_role_only'));

create table public.institution_secrets (
  institution_id uuid not null references public.institutions (id) on delete cascade,
  id             uuid not null default gen_random_uuid(),
  secret_ref     text not null check (secret_ref ~ '^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$'),
  vault_id       uuid not null,
  hint           text not null,
  valid_from     timestamptz not null default now(),
  created_at     timestamptz not null default now(),
  created_by     uuid references auth.users (id) on delete set null,
  rotated_at     timestamptz,
  revoked_at     timestamptz,
  primary key (institution_id, id),
  unique (institution_id, secret_ref, valid_from)
);
comment on table public.institution_secrets is
  'Metadata of per-institution secrets (never the value). Values are in vault.secrets, referenced by vault_id.';
create index institution_secrets_ref_idx on public.institution_secrets (institution_id, secret_ref, valid_from desc);

alter table public.institution_secrets enable row level security;
revoke all on public.institution_secrets from anon, authenticated;
grant select (institution_id, id, secret_ref, hint, valid_from, created_at, created_by, rotated_at, revoked_at)
  on public.institution_secrets to authenticated;
create policy institution_secrets_read_own on public.institution_secrets for select to authenticated
  using (institution_id = (select app.auth_institution_id()));

-- Hint shown instead of the value: first 4 and last 4 characters for long keys, nothing for short ones.
create or replace function app.secret_hint(p_value text) returns text
language sql immutable set search_path = '' as $$
  select case when length(p_value) >= 16 then left(p_value, 4) || '…' || right(p_value, 4) else '••••' end
$$;

-- Who may write secrets of an institution. Until permissions exist: platform Master Admin only (fail-closed).
create or replace function app.secret_write_allowed(p_institution uuid) returns boolean
language sql stable set search_path = '' as $$
  select exists (select 1 from public.platform_members pm
                 where pm.user_id = auth.uid() and pm.platform_role = 'master_admin')
         and exists (select 1 from public.institutions i where i.id = p_institution)
$$;

-- Target institution: explicit only for the platform Master Admin (Master Admin panel, D4); otherwise the active one.
create or replace function app.secret_target_institution(p_institution uuid) returns uuid
language plpgsql stable set search_path = '' as $$
begin
  if auth.uid() is null then
    raise exception 'not_signed_in' using errcode = 'P0401';
  end if;
  if p_institution is not null then
    return p_institution;
  end if;
  return app.require_active_session();
end $$;

-- Write (set or rotate). p_valid_from in the future = rotation: the current value keeps working until then.
create or replace function public.secret_set(p_ref text, p_value text, p_valid_from timestamptz default null,
                                             p_institution_id uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.secret_target_institution(p_institution_id);
  v_from        timestamptz := coalesce(p_valid_from, now());
  v_vault_id    uuid;
  v_hint        text;
begin
  if not app.secret_write_allowed(v_institution) then
    raise exception 'permission_denied' using errcode = '42501', hint = 'Only the Master Admin may set secrets (D4).';
  end if;
  if p_value is null or length(p_value) < 4 then
    raise exception 'secret_value_invalid' using errcode = 'P0422';
  end if;
  if v_from < now() - interval '1 minute' then
    raise exception 'secret_valid_from_in_past' using errcode = 'P0422';
  end if;
  v_vault_id := vault.create_secret(p_value, format('inst:%s:%s:%s', v_institution, p_ref, gen_random_uuid()),
                                    format('Institution secret %s', p_ref));
  v_hint := app.secret_hint(p_value);
  update public.institution_secrets set rotated_at = now()
   where institution_id = v_institution and secret_ref = p_ref and revoked_at is null and rotated_at is null;
  insert into public.institution_secrets (institution_id, secret_ref, vault_id, hint, valid_from, created_by)
  values (v_institution, p_ref, v_vault_id, v_hint, v_from, auth.uid());
  return jsonb_build_object('ref', p_ref, 'hint', v_hint, 'valid_from', v_from);
end $$;

create or replace function public.secret_revoke(p_ref text, p_institution_id uuid default null)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  v_institution uuid := app.secret_target_institution(p_institution_id);
  v_count       integer;
begin
  if not app.secret_write_allowed(v_institution) then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  -- Destroy the values, keep the metadata (who, when) for the audit trail.
  delete from vault.secrets v using public.institution_secrets s
   where s.vault_id = v.id and s.institution_id = v_institution and s.secret_ref = p_ref;
  update public.institution_secrets set revoked_at = now()
   where institution_id = v_institution and secret_ref = p_ref and revoked_at is null;
  get diagnostics v_count = row_count;
  return v_count;
end $$;

-- Edge-only read: the value currently in force (latest valid_from that has started, not revoked).
create or replace function public.secret_read_for_service(p_institution_id uuid, p_ref text)
returns text language sql stable security definer set search_path = '' as $$
  select d.decrypted_secret
  from public.institution_secrets s
  join vault.decrypted_secrets d on d.id = s.vault_id
  where s.institution_id = p_institution_id and s.secret_ref = p_ref
    and s.revoked_at is null and s.valid_from <= now()
  order by s.valid_from desc
  limit 1
$$;

-- Closing an institution (0B.07): destroy every secret value and its metadata.
create or replace function public.purge_institution_secrets(p_institution_id uuid)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  v_count integer;
begin
  delete from vault.secrets v using public.institution_secrets s
   where s.vault_id = v.id and s.institution_id = p_institution_id;
  delete from public.institution_secrets where institution_id = p_institution_id;
  get diagnostics v_count = row_count;
  return v_count;
end $$;

revoke all on function public.secret_set(text, text, timestamptz, uuid) from public, anon;
revoke all on function public.secret_revoke(text, uuid) from public, anon;
grant execute on function public.secret_set(text, text, timestamptz, uuid) to authenticated;
grant execute on function public.secret_revoke(text, uuid) to authenticated;
revoke all on function public.secret_read_for_service(uuid, text) from public, anon, authenticated;
revoke all on function public.purge_institution_secrets(uuid) from public, anon, authenticated;
grant execute on function public.secret_read_for_service(uuid, text) to service_role;
grant execute on function public.purge_institution_secrets(uuid) to service_role;

insert into app.definer_registry (function_name, reason, added_in, reviewer, tenant_check) values
  ('public.secret_set', 'Writes to Vault (no access for app roles). Target = active institution via require_active_session(), '
   || 'or an explicit one only for the platform Master Admin; write-only, returns the hint.', '0A.07', 'architecture review 0A.07',
   'filters_active_institution'),
  ('public.secret_revoke', 'Deletes Vault values of the active institution (or explicit for the Master Admin).', '0A.07',
   'architecture review 0A.07', 'filters_active_institution'),
  ('public.secret_read_for_service', 'Decrypts a value for Edge Functions. Executable only by service_role.', '0A.07',
   'architecture review 0A.07', 'service_role_only'),
  ('public.purge_institution_secrets', 'Institution closure: destroys all its secrets. Executable only by service_role.',
   '0A.07', 'architecture review 0A.07', 'service_role_only');
