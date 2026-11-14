// End-to-end (0B.12): the real worker core and the mock adapters, through the API as the service role (the path the
// hub-worker Edge Function takes), against the local database. Two institutions send at once: each message goes
// through its own connection (I1, asserted on the mock adapter); the delivery log and the ledger fill; a failing
// primary falls back to the backup; a signed callback marks the message delivered, a forged one changes nothing.
import { createClient } from '@supabase/supabase-js';
import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';

import { hmacHex } from '../../supabase/functions/_shared/hub/adapters.ts';
import { mockSent } from '../../supabase/functions/_shared/hub/mock.ts';
import { adapterRegistry } from '../../supabase/functions/_shared/hub/registry.ts';
import { supabaseStore } from '../../supabase/functions/_shared/hub/store.ts';
import { runRound } from '../../supabase/functions/_shared/hub/worker-core.ts';
import { API_URL, INSTITUTION, adminSql, local } from './helpers.mjs';

const service = createClient(API_URL, local.SECRET_KEY ?? local.SERVICE_ROLE_KEY, { auth: { persistSession: false } });
const CONN = { a1: 'c2000000-0000-4000-8000-0000000000a1', a2: 'c2000000-0000-4000-8000-0000000000a2', b1: 'c2000000-0000-4000-8000-0000000000b1' };
const cleanUp = () => adminSql(`delete from public.outbox where idempotency_key like 'e2e-hub-%';
  delete from public.delivery_log where connection_id in ('${CONN.a1}', '${CONN.a2}', '${CONN.b1}');
  delete from public.usage_ledger where provider = 'mock_sms';
  delete from public.webhook_events where connection_id in ('${CONN.a1}', '${CONN.a2}', '${CONN.b1}');
  delete from vault.secrets where id in (select vault_id from public.institution_secrets where secret_ref like 'conn.c2000000%');
  delete from public.institution_secrets where secret_ref like 'conn.c2000000%';
  delete from public.integration_connections where id in ('${CONN.a1}', '${CONN.a2}', '${CONN.b1}');
  delete from public.platform_alerts where kind = 'circuit_open';`);

async function setKey(institution, connection, field, value) {
  const ref = `conn.${connection.replaceAll('-', '')}.${field}`;
  adminSql(`insert into public.institution_secrets (institution_id, secret_ref, vault_id, hint)
    values ('${institution}', '${ref}', vault.create_secret('${value}', 'e2e:${ref}:' || gen_random_uuid()), '••••')`);
}
async function enqueue(institution, key, body, priority = 'transactional') {
  adminSql(`select app.outbox_enqueue('${institution}', 'sms', '${priority}', '0171100${key.slice(-4)}', '{"body":"${body}"}', 'e2e-hub-${key}')`);
}

before(() => {
  cleanUp();
  adminSql(`insert into public.integration_connections (institution_id, id, kind, provider_key, label, mode, settings, priority, live_test_passed_at) values
    ('${INSTITUTION.A}', '${CONN.a1}', 'sms', 'mock_sms', 'A main', 'live', '{"price_per_part":0.25}', 1, now()),
    ('${INSTITUTION.A}', '${CONN.a2}', 'sms', 'mock_sms', 'A backup', 'live', '{"price_per_part":0.30}', 2, now()),
    ('${INSTITUTION.B}', '${CONN.b1}', 'sms', 'mock_sms', 'B main', 'live', '{"price_per_part":0.20}', 1, now())`);
});
after(() => cleanUp());

describe('hub runtime through the API', () => {
  it('two institutions at once: each message through its own connection; log and ledger fill', async () => {
    await setKey(INSTITUTION.A, CONN.a1, 'api_key', 'a-main-key');
    await setKey(INSTITUTION.B, CONN.b1, 'api_key', 'b-main-key');
    for (let i = 0; i < 3; i++) {
      await enqueue(INSTITUTION.A, `a-000${i}`, `Hello A ${i}`);
      await enqueue(INSTITUTION.B, `b-000${i}`, `Hello B ${i}`);
    }
    mockSent.length = 0;
    const report = await runRound(supabaseStore(service), adapterRegistry(true), { worker: 'e2e' });
    assert.equal(report.sent, 6);
    for (const s of mockSent) {
      assert.equal(s.connectionId, s.body.startsWith('Hello A') ? CONN.a1 : CONN.b1, 'never another institution\'s connection');
    }
    assert.match(adminSql(`select count(*) from public.delivery_log where connection_id in ('${CONN.a1}', '${CONN.b1}') and result = 'sent'`), /\b6\b/);
    assert.match(adminSql(`select count || '|' || cost from public.usage_ledger where institution_id = '${INSTITUTION.A}' and provider = 'mock_sms'`), /3\|0?\.75/);
  });

  it('a failing primary falls back to the backup, noted on the message', async () => {
    adminSql(`delete from vault.secrets where id in (select vault_id from public.institution_secrets where secret_ref = 'conn.${CONN.a1.replaceAll('-', '')}.api_key');
      delete from public.institution_secrets where secret_ref = 'conn.${CONN.a1.replaceAll('-', '')}.api_key';`);
    await setKey(INSTITUTION.A, CONN.a2, 'api_key', 'a-backup-key');
    await enqueue(INSTITUTION.A, 'a-fb01', 'Fallback please');
    const report = await runRound(supabaseStore(service), adapterRegistry(true), { worker: 'e2e' });
    assert.equal(report.fallbacks, 1);
    assert.match(adminSql(`select connection_id || '|' || fallback_from from public.outbox where idempotency_key = 'e2e-hub-a-fb01'`),
      new RegExp(`${CONN.a2}\\|${CONN.a1}`));
  });

  it('callbacks: only the connection\'s own signature is trusted; duplicates are ignored', async () => {
    await setKey(INSTITUTION.A, CONN.a2, 'webhook_secret', 'hook-secret-a2');
    const msgId = adminSql(`select provider_message_id from public.outbox where idempotency_key = 'e2e-hub-a-fb01'`).match(/mock-[\w-]+/)[0];
    const body = JSON.stringify({ message_id: msgId, status: 'delivered', event_id: `${msgId}:d` });
    const conn = (await service.rpc('hub_webhook_connection', { p_connection: CONN.a2 })).data;
    const secret = (await service.rpc('connection_secret_for_service', { p_institution: conn.institution_id, p_connection: CONN.a2, p_field: 'webhook_secret' })).data;
    const adapter = adapterRegistry(true).mock_sms;
    const ctx = { id: CONN.a2, owner: conn.owner, provider: conn.provider, sandbox: false, settings: {}, secrets: { webhook_secret: secret } };
    const forged = await adapter.verifyWebhook(ctx, new Headers({ 'x-mock-signature': await hmacHex('wrong', body) }), body);
    const real = await adapter.verifyWebhook(ctx, new Headers({ 'x-mock-signature': await hmacHex('hook-secret-a2', body) }), body);
    assert.equal(forged, false);
    assert.equal(real, true);
    const rec = (ok) => service.rpc('hub_webhook_record', { p_connection: CONN.a2, p_signature_ok: ok, p_event_key: ok ? `${msgId}:d` : `${msgId}:forged`,
      p_payload: JSON.parse(body), p_provider_message_id: msgId, p_status: 'delivered' });
    assert.equal((await rec(false)).data, 'rejected');
    assert.equal((await rec(true)).data, 'delivered');
    assert.equal((await rec(true)).data, 'duplicate');
    assert.match(adminSql(`select status from public.outbox where idempotency_key = 'e2e-hub-a-fb01'`), /delivered/);
  });

  it('people cannot call the worker API', async () => {
    const anon = createClient(API_URL, local.PUBLISHABLE_KEY ?? local.ANON_KEY);
    const { error } = await anon.rpc('hub_claim', { p_worker: 'x', p_limit: 1, p_lanes: [1] });
    assert.ok(error, 'refused');
  });
});
