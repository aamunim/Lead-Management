// The hub store backed by the database through the service-role client (Edge Functions only). Every call is one
// service-role RPC (public.hub_*); the institution always comes from the claimed message, never from a request (I1).
import type { SupabaseClient } from 'npm:@supabase/supabase-js@2';

import type { ClaimedMessage, HubStore, Route, RouteConnection } from './worker-core.ts';

async function call<T>(client: SupabaseClient, fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await client.rpc(fn, args);
  if (error) throw new Error(`${fn}: ${error.message}`);
  return data as T;
}

export function supabaseStore(client: SupabaseClient) {
  const store: HubStore & {
    healthDue(): Promise<(RouteConnection & { institution_id: string | null })[]>;
    healthRecord(owner: string, institutionId: string | null, connectionId: string, ok: boolean, code: string | null, detail: string | null): Promise<void>;
  } = {
    claim: (worker, limit, lanes) => call<ClaimedMessage[]>(client, 'hub_claim', { p_worker: worker, p_limit: limit, p_lanes: lanes }),
    route: (institutionId, messageId) => call<Route>(client, 'hub_route', { p_institution: institutionId, p_id: messageId }),
    secret: (institutionId, connectionId, field) =>
      call<string | null>(client, 'connection_secret_for_service', { p_institution: institutionId, p_connection: connectionId, p_field: field }),
    outcome: (institutionId, owner, connectionId, ok, code, detail) => call<void>(client, 'hub_outcome',
      { p_institution: institutionId, p_owner: owner, p_connection: connectionId, p_ok: ok, p_code: code, p_detail: detail }),
    result: (r) => call<string>(client, 'hub_result', {
      p_institution: r.institutionId, p_id: r.messageId, p_ok: r.ok, p_connection: r.connectionId, p_owner: r.owner, p_provider: r.provider,
      p_provider_message_id: r.providerMessageId ?? null, p_error_code: r.errorCode ?? null, p_detail: r.detail ?? null,
      p_fallback_from: r.fallbackFrom ?? null, p_sandbox: r.sandbox ?? false,
    }),
    healthDue: () => call(client, 'hub_health_due', { p_limit: 20 }),
    healthRecord: (owner, institutionId, connectionId, ok, code, detail) => call<void>(client, 'hub_health_record',
      { p_owner: owner, p_institution: institutionId, p_connection: connectionId, p_ok: ok, p_code: code, p_detail: detail }),
  };
  return store;
}
