// Hub worker (0B.12-T3): woken by pg_cron only when work is due, and at once for OTP / urgent (app.hub_kick). Only the
// service role may call it. One round: OTP lane first, then the rest, within the time budget; then a health round.
import { createClient } from 'npm:@supabase/supabase-js@2';

import { createLogger } from '../_shared/logger.ts';
import { adapterRegistry } from '../_shared/hub/registry.ts';
import { resolveHost } from '../_shared/hub/resolve-deno.ts';
import { openSmtp } from '../_shared/hub/smtp-deno.ts';
import { supabaseStore } from '../_shared/hub/store.ts';
import { runContracts, runHealth, runPoll, runRound } from '../_shared/hub/worker-core.ts';
import { safeEqual } from '../_shared/hub/adapters.ts';

const BUDGET_MS = 45_000;

Deno.serve(async (req) => {
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? Deno.env.get('SUPABASE_SECRET_KEY') ?? '';
  const given = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '');
  if (!serviceKey || !safeEqual(given, serviceKey)) return new Response('forbidden', { status: 403 });
  const log = createLogger({ function: 'hub-worker', request_id: crypto.randomUUID() });
  const client = createClient(Deno.env.get('SUPABASE_URL') ?? '', serviceKey, { auth: { persistSession: false } });
  const store = supabaseStore(client);
  const adapters = adapterRegistry(Deno.env.get('HUB_ALLOW_MOCK') === '1', resolveHost, openSmtp);
  const started = Date.now();
  const body = await req.json().catch(() => ({})) as { lane?: string };
  if (body.lane === 'contract') {
    const tested = await runContracts(store.contract, adapters);
    log.info('hub.contracts', { tested });
    return new Response(JSON.stringify({ tested }), { headers: { 'content-type': 'application/json' } });
  }
  const report = await runRound(store, adapters, { worker: `edge-${started}`, deadline: started + BUDGET_MS });
  const checked = body.lane === 'otp' ? 0 : await runHealth(store, adapters);
  const polled = body.lane === 'otp' ? 0 : await runPoll(store, adapters);
  log.info('hub.round', { ...report, health_checked: checked, polled, ms: Date.now() - started });
  return new Response(JSON.stringify({ ...report, health_checked: checked, polled }), { headers: { 'content-type': 'application/json' } });
});
