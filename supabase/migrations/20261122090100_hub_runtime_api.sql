-- 0B.12: the worker and the webhook router call the hub through the API (only the public schema is exposed). These
-- thin wrappers are executable by the service role only; people can never call them.
create or replace function public.hub_claim(p_worker text, p_limit integer, p_lanes smallint[]) returns setof public.outbox
language sql security definer set search_path = '' as $$ select * from app.outbox_claim(p_worker, p_limit, p_lanes) $$;
create or replace function public.hub_route(p_institution uuid, p_id uuid) returns jsonb
language sql security definer set search_path = '' as $$ select app.outbox_route(p_institution, p_id) $$;
create or replace function public.hub_outcome(p_institution uuid, p_owner text, p_connection uuid, p_ok boolean, p_code text, p_detail text)
returns void language sql security definer set search_path = '' as $$
  select app.connection_outcome(p_institution, p_owner, p_connection, p_ok, p_code, p_detail) $$;
create or replace function public.hub_result(p_institution uuid, p_id uuid, p_ok boolean, p_connection uuid, p_owner text, p_provider text,
                                             p_provider_message_id text, p_error_code text, p_detail text, p_fallback_from uuid, p_sandbox boolean)
returns text language sql security definer set search_path = '' as $$
  select app.outbox_result(p_institution, p_id, p_ok, p_connection, p_owner, p_provider, p_provider_message_id, p_error_code, p_detail,
                           p_fallback_from, coalesce(p_sandbox, false)) $$;
create or replace function public.hub_webhook_connection(p_connection uuid) returns jsonb
language sql stable security definer set search_path = '' as $$ select app.webhook_connection(p_connection) $$;
create or replace function public.hub_webhook_record(p_connection uuid, p_signature_ok boolean, p_event_key text, p_payload jsonb,
                                                     p_provider_message_id text, p_status text) returns text
language sql security definer set search_path = '' as $$
  select app.webhook_record(p_connection, p_signature_ok, p_event_key, p_payload, p_provider_message_id, p_status) $$;
create or replace function public.hub_health_due(p_limit integer) returns jsonb
language sql stable security definer set search_path = '' as $$ select app.health_due(p_limit) $$;
create or replace function public.hub_health_record(p_owner text, p_institution uuid, p_connection uuid, p_ok boolean, p_code text, p_detail text)
returns void language sql security definer set search_path = '' as $$
  select app.health_record(p_owner, p_institution, p_connection, p_ok, p_code, p_detail) $$;

revoke all on function public.hub_claim(text, integer, smallint[]), public.hub_route(uuid, uuid),
  public.hub_outcome(uuid, text, uuid, boolean, text, text), public.hub_result(uuid, uuid, boolean, uuid, text, text, text, text, text, uuid, boolean),
  public.hub_webhook_connection(uuid), public.hub_webhook_record(uuid, boolean, text, jsonb, text, text), public.hub_health_due(integer),
  public.hub_health_record(text, uuid, uuid, boolean, text, text) from public, anon, authenticated;
grant execute on function public.hub_claim(text, integer, smallint[]), public.hub_route(uuid, uuid),
  public.hub_outcome(uuid, text, uuid, boolean, text, text), public.hub_result(uuid, uuid, boolean, uuid, text, text, text, text, text, uuid, boolean),
  public.hub_webhook_connection(uuid), public.hub_webhook_record(uuid, boolean, text, jsonb, text, text), public.hub_health_due(integer),
  public.hub_health_record(text, uuid, uuid, boolean, text, text) to service_role;

insert into app.definer_registry (function_name, reason, added_in, reviewer, tenant_check)
select f, 'Service-role wrapper of the hub runtime for the Edge worker / webhook router (0B.12); people cannot call it.', '0B.12',
       'architecture review 0B.12', 'service_role_only'
  from unnest(array['public.hub_claim', 'public.hub_route', 'public.hub_outcome', 'public.hub_result', 'public.hub_webhook_connection',
                    'public.hub_webhook_record', 'public.hub_health_due', 'public.hub_health_record']) f
on conflict (function_name) do update set reason = excluded.reason, added_in = excluded.added_in, tenant_check = excluded.tenant_check;
