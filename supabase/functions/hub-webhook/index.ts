// Webhook router (0B.12-T7): POST /functions/v1/hub-webhook/<connection_id>. The connection named in the URL is
// loaded first, and the request is trusted only if it carries that connection's own signature (I4). Every callback is
// stored once (a duplicate is ignored), then applied to the message sent through that same connection.
import { createClient } from 'npm:@supabase/supabase-js@2';

import { createLogger } from '../_shared/logger.ts';
import { adapterRegistry } from '../_shared/hub/registry.ts';
import { resolveHost } from '../_shared/hub/resolve-deno.ts';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

Deno.serve(async (req) => {
  const log = createLogger({ function: 'hub-webhook', request_id: crypto.randomUUID() });
  const connectionId = new URL(req.url).pathname.split('/').filter(Boolean).pop() ?? '';
  if (req.method !== 'POST' || !UUID.test(connectionId)) return new Response('not found', { status: 404 });
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? Deno.env.get('SUPABASE_SECRET_KEY') ?? '';
  const client = createClient(Deno.env.get('SUPABASE_URL') ?? '', serviceKey, { auth: { persistSession: false } });
  const { data: conn } = await client.rpc('hub_webhook_connection', { p_connection: connectionId });
  const c = conn as { owner: 'institution' | 'platform'; institution_id: string | null; provider: string; status: string } | null;
  const adapter = c ? adapterRegistry(Deno.env.get('HUB_ALLOW_MOCK') === '1', resolveHost)[c.provider] : undefined;
  if (!c || !adapter) return new Response('not found', { status: 404 });
  const raw = await req.text();
  const secret = await client.rpc('connection_secret_for_service', { p_institution: c.institution_id, p_connection: connectionId, p_field: 'webhook_secret' });
  const ok = await adapter.verifyWebhook({ id: connectionId, owner: c.owner, provider: c.provider, sandbox: false, settings: {},
    secrets: { webhook_secret: (secret.data as string | null) ?? null } }, req.headers, raw);
  const report = adapter.parseStatus(raw);
  let payload: unknown = {};
  try {
    payload = JSON.parse(raw);
  } catch {
    payload = { raw: raw.slice(0, 2000) };
  }
  const { data: result } = await client.rpc('hub_webhook_record', {
    p_connection: connectionId, p_signature_ok: ok, p_event_key: report?.eventKey ?? `raw:${raw.length}:${raw.slice(0, 64)}`,
    p_payload: payload, p_provider_message_id: report?.providerMessageId ?? null, p_status: report?.status ?? null,
  });
  log.info('hub.webhook', { connection: connectionId, signature_ok: ok, result });
  return new Response(ok ? 'ok' : 'invalid signature', { status: ok ? 200 : 401 });
});
