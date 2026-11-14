// Unit tests for the hub worker core and adapters (0B.12): each message is sent through its own institution's
// connection (I1, asserted on the mock adapter), OTP is sent before bulk, a failing primary falls back to the backup
// and says so, a gate is reported, callbacks are trusted only with the connection's own signature.
import assert from 'node:assert/strict';
import { beforeEach, describe, it } from 'node:test';

import { hmacHex } from '../../supabase/functions/_shared/hub/adapters.ts';
import { mockSent, mockSms } from '../../supabase/functions/_shared/hub/mock.ts';
import { adapterRegistry } from '../../supabase/functions/_shared/hub/registry.ts';
import { runRound } from '../../supabase/functions/_shared/hub/worker-core.ts';

const A = 'inst-a';
const B = 'inst-b';
const conn = (id, owner = 'institution', provider = 'mock_sms') => ({ owner, id, provider, settings: {}, sandbox: false, secret_fields: ['api_key'] });

/** A fake store: messages by lane, connections per institution, keys per connection, every call recorded. */
function fakeStore({ messages, routes, keys, gates = {} }) {
  const calls = { results: [], outcomes: [], claimedLanes: [] };
  const queue = [...messages];
  return {
    calls,
    async claim(_worker, limit, lanes) {
      calls.claimedLanes.push(lanes.join(','));
      const picked = queue.filter((m) => lanes.includes(m.lane)).slice(0, limit);
      for (const m of picked) queue.splice(queue.indexOf(m), 1);
      return picked;
    },
    async route(inst, id) {
      return { gate: gates[id] ?? null, connections: routes[inst] ?? [] };
    },
    async secret(_inst, connectionId, field) {
      return keys[`${connectionId}.${field}`] ?? null;
    },
    async outcome(inst, owner, connectionId, ok, code) {
      calls.outcomes.push({ inst, connectionId, ok, code });
    },
    async result(r) {
      calls.results.push(r);
      return r.ok ? 'sent' : r.errorCode === 'limit_reached' ? 'held' : 'failed';
    },
  };
}
const msg = (inst, id, lane, body = 'Hello', priority = 'transactional') =>
  ({ institution_id: inst, id, lane, channel: 'sms', priority, recipient: '01711000000', payload: { body } });
const adapters = adapterRegistry(true);

beforeEach(() => {
  mockSent.length = 0;
});

describe('hub worker core', () => {
  it('sends each message through its own institution\'s connection (I1)', async () => {
    const store = fakeStore({
      messages: [msg(A, 'a1', 3), msg(B, 'b1', 3), msg(A, 'a2', 3)],
      routes: { [A]: [conn('conn-a')], [B]: [conn('conn-b')] },
      keys: { 'conn-a.api_key': 'ka', 'conn-b.api_key': 'kb' },
    });
    const report = await runRound(store, adapters, { worker: 't' });
    assert.equal(report.sent, 3);
    assert.deepEqual(mockSent.map((s) => s.connectionId), ['conn-a', 'conn-b', 'conn-a']);
    assert.ok(store.calls.results.every((r) => (r.institutionId === A ? r.connectionId === 'conn-a' : r.connectionId === 'conn-b')));
  });

  it('claims the OTP lane before the others', async () => {
    const store = fakeStore({
      messages: [msg(A, 'bulk1', 4, 'Offer', 'bulk'), msg(B, 'otp1', 1, 'Code 1234', 'otp')],
      routes: { [A]: [conn('conn-a')], [B]: [conn('conn-b')] }, keys: { 'conn-a.api_key': 'k', 'conn-b.api_key': 'k' },
    });
    await runRound(store, adapters, { worker: 't' });
    assert.equal(store.calls.claimedLanes[0], '1');
    assert.equal(mockSent[0].body, 'Code 1234');
  });

  it('falls back to the backup and records the fallback; the failed connection gets its own result', async () => {
    const store = fakeStore({
      messages: [msg(A, 'a1', 3)],
      routes: { [A]: [conn('primary'), conn('backup')] },
      keys: { 'backup.api_key': 'k' }, // the primary has no key: auth_failed
    });
    const report = await runRound(store, adapters, { worker: 't' });
    assert.equal(report.fallbacks, 1);
    assert.equal(store.calls.results[0].connectionId, 'backup');
    assert.equal(store.calls.results[0].fallbackFrom, 'primary');
    assert.deepEqual(store.calls.outcomes.map((o) => [o.connectionId, o.ok, o.code]), [['primary', false, 'auth_failed'], ['backup', true, null]]);
  });

  it('reports a failure with whose side it is when every connection fails', async () => {
    const store = fakeStore({ messages: [msg(A, 'a1', 3, 'BALANCE')], routes: { [A]: [conn('conn-a')] }, keys: { 'conn-a.api_key': 'k' } });
    await runRound(store, adapters, { worker: 't' });
    assert.equal(store.calls.results[0].ok, false);
    assert.equal(store.calls.results[0].errorCode, 'balance_low');
    assert.equal(mockSent.length, 0);
  });

  it('a closed gate is reported without sending; no connection at all is "no_connection"', async () => {
    const store = fakeStore({ messages: [msg(A, 'held1', 4), msg(B, 'b1', 3)], routes: { [A]: [conn('conn-a')] },
      keys: { 'conn-a.api_key': 'k' }, gates: { held1: 'limit_reached' } });
    const report = await runRound(store, adapters, { worker: 't' });
    assert.equal(report.held, 1);
    assert.equal(mockSent.length, 0);
    assert.equal(store.calls.results.find((r) => r.messageId === 'b1').errorCode, 'no_connection');
  });

  it('an unknown provider (adapter not built yet) fails over without throwing', async () => {
    const store = fakeStore({ messages: [msg(A, 'a1', 3)], routes: { [A]: [conn('x', 'institution', 'custom_http_sms'), conn('conn-a')] },
      keys: { 'conn-a.api_key': 'k' } });
    const report = await runRound(store, adapters, { worker: 't' });
    assert.equal(report.sent, 1);
    assert.equal(report.fallbacks, 1);
  });

  it('the mock adapters exist only when allowed (never in production)', () => {
    assert.equal(adapterRegistry(false).mock_sms, undefined);
    assert.ok(adapterRegistry(true).mock_sms);
  });
});

describe('webhook signatures', () => {
  const ctx = (secret) => ({ id: 'c', owner: 'institution', provider: 'mock_sms', sandbox: false, settings: {}, secrets: { webhook_secret: secret } });
  it('accepts only the connection\'s own signature', async () => {
    const body = JSON.stringify({ message_id: 'm1', status: 'delivered' });
    const good = new Headers({ 'x-mock-signature': await hmacHex('secret-of-a', body) });
    assert.equal(await mockSms.verifyWebhook(ctx('secret-of-a'), good, body), true);
    assert.equal(await mockSms.verifyWebhook(ctx('secret-of-b'), good, body), false, 'another connection\'s secret');
    assert.equal(await mockSms.verifyWebhook(ctx('secret-of-a'), new Headers(), body), false, 'unsigned');
    assert.equal(await mockSms.verifyWebhook(ctx('secret-of-a'), good, body.replace('delivered', 'undelivered')), false, 'tampered');
    assert.deepEqual(mockSms.parseStatus(body), { providerMessageId: 'm1', status: 'delivered', eventKey: 'm1:delivered' });
  });
});
