-- 0A.06 Tenant isolation beyond tables: Storage paths, Realtime channels and the session check for Edge Functions.
-- Plan: Ch 4.3, Ch 3.7, Ch 48.8. Conventions are documented in docs/dev/ISOLATION.md.

-- ---------------------------------------------------------------------------------------------------------------------
-- Storage: one private bucket for institution files. Every object path starts with the institution id:
--   <institution_id>/<area>/<...>      e.g.  a0000000-.../documents/2026/receipt-0001.pdf
-- A signed-in user can read and write only under the ACTIVE institution's folder.
-- ---------------------------------------------------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('institution-files', 'institution-files', false)
on conflict (id) do update set public = false;

create or replace function app.storage_path_institution(p_name text) returns uuid
language sql immutable set search_path = '' as $$
  -- First folder of the object path as a uuid, or NULL when it is not a uuid.
  select case when split_part(p_name, '/', 1) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
              then split_part(p_name, '/', 1)::uuid end
$$;
grant execute on function app.storage_path_institution(text) to authenticated, anon, service_role;

create policy institution_files_select on storage.objects for select to authenticated
  using (bucket_id = 'institution-files'
         and app.storage_path_institution(name) = (select app.auth_institution_id()));
create policy institution_files_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'institution-files'
              and app.storage_path_institution(name) = (select app.auth_institution_id()));
create policy institution_files_update on storage.objects for update to authenticated
  using (bucket_id = 'institution-files'
         and app.storage_path_institution(name) = (select app.auth_institution_id()))
  with check (bucket_id = 'institution-files'
              and app.storage_path_institution(name) = (select app.auth_institution_id()));
create policy institution_files_delete on storage.objects for delete to authenticated
  using (bucket_id = 'institution-files'
         and app.storage_path_institution(name) = (select app.auth_institution_id()));

-- ---------------------------------------------------------------------------------------------------------------------
-- Realtime: private channels are named  inst:<institution_id>:<topic>  (e.g. inst:a0000000-...:leads).
-- Broadcast / presence authorization reads realtime.topic(); a user may join only the ACTIVE institution's channels.
-- postgres_changes on tables already follows each table's RLS (covered by the table leak probe).
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function app.realtime_topic_institution(p_topic text) returns uuid
language sql immutable set search_path = '' as $$
  select case when p_topic ~ '^inst:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}:.+$'
              then split_part(p_topic, ':', 2)::uuid end
$$;
grant execute on function app.realtime_topic_institution(text) to authenticated, anon, service_role;

create policy institution_channels_receive on realtime.messages for select to authenticated
  using (app.realtime_topic_institution((select realtime.topic())) = (select app.auth_institution_id()));
create policy institution_channels_send on realtime.messages for insert to authenticated
  with check (app.realtime_topic_institution((select realtime.topic())) = (select app.auth_institution_id()));

-- ---------------------------------------------------------------------------------------------------------------------
-- Session check used by every Edge Function (supabase/functions/_shared/tenant.ts): the server — not the request body —
-- says who the user is and which institution is active; membership and access_version are re-checked here.
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function public.current_session() returns jsonb
language plpgsql stable security invoker set search_path = '' as $$
declare
  v_institution uuid := app.require_active_session();
begin
  return jsonb_build_object(
    'user_id', auth.uid(),
    'institution_id', v_institution,
    'access_version', app.claim_access_version(),
    'user_kind', coalesce(auth.jwt() ->> 'user_kind', 'staff'));
end $$;
revoke execute on function public.current_session() from public, anon;
grant execute on function public.current_session() to authenticated;
