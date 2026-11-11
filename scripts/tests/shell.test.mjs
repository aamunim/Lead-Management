// Unit tests for 0A.14: cache namespaces (nothing of the previous user / institution stays) and the API wrapper.
import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { createApiFetch } from '../../src/lib/api-core.ts';
import { cacheKey, clearCaches, keysToClear, parseCacheKey } from '../../src/lib/cache-core.ts';

const A = 'a0000000-0000-4000-8000-00000000000a';
const B = 'b0000000-0000-4000-8000-00000000000b';
const U1 = 'user-1';
const U2 = 'user-2';

function memoryStore(keys) {
  const data = new Map(keys.map((k) => [k, 'x']));
  return { data, getAllKeys: async () => [...data.keys()], multiRemove: async (ks) => ks.forEach((k) => data.delete(k)) };
}

describe('cache namespaces', () => {
  it('builds and parses owner-scoped keys', () => {
    const key = cacheKey({ userId: U1, institutionId: A }, 'settings');
    assert.equal(key, `c|${U1}|${A}|settings`);
    assert.deepEqual(parseCacheKey(key), { userId: U1, institutionId: A, rest: 'settings' });
    assert.equal(parseCacheKey('appearance'), null);
  });

  const keys = [
    cacheKey({ userId: U1, institutionId: A }, 'settings'), cacheKey({ userId: U1, institutionId: A }, 'draft', 'lead'),
    cacheKey({ userId: U1, institutionId: B }, 'settings'), cacheKey({ userId: U2, institutionId: A }, 'settings'),
    'appearance', 'ui_language', 'locale_defaults',
  ];

  it('the cache is empty after sign-out (device preferences stay)', async () => {
    const store = memoryStore(keys);
    let cleared = 0;
    await clearCaches(store, [() => { cleared += 1; }], { type: 'signOut' });
    assert.deepEqual([...store.data.keys()], ['appearance', 'ui_language', 'locale_defaults']);
    assert.equal(cleared, 1, 'in-memory stores were told to clear');
  });

  it('after an institution switch nothing of the previous institution remains', async () => {
    const store = memoryStore(keys);
    await clearCaches(store, [], { type: 'institutionSwitch', from: A });
    assert.ok([...store.data.keys()].every((k) => !k.includes(`|${A}|`)));
    assert.ok(store.data.has(cacheKey({ userId: U1, institutionId: B }, 'settings')), 'other institutions are untouched');
  });

  it('another person signing in removes the previous person\'s data', () => {
    const removed = keysToClear(keys, { type: 'userChange', userId: U2 });
    assert.equal(removed.length, 3);
    assert.ok(removed.every((k) => k.startsWith(`c|${U1}|`)));
  });

  it('an access change clears that institution only', () => {
    assert.equal(keysToClear(keys, { type: 'accessChanged', institutionId: B }).length, 1);
  });
});

function fakeFetch(responses) {
  const calls = [];
  const fn = async (input, init) => {
    calls.push({ input, init, headers: Object.fromEntries(new Headers(init.headers).entries()) });
    const next = responses.shift();
    if (next instanceof Error) throw next;
    if (next === 'hang') {
      return new Promise((_, reject) => init.signal.addEventListener('abort', () => reject(init.signal.reason)));
    }
    return new Response(JSON.stringify(next.body ?? {}), { status: next.status ?? 200, headers: next.headers ?? {} });
  };
  return { fn, calls };
}
const noSleep = async () => {};

describe('API wrapper', () => {
  it('sends the app version and the idempotency key of writes', async () => {
    const f = fakeFetch([{ status: 200 }]);
    const api = createApiFetch({ fetch: f.fn, appVersion: '1.2.3', sleep: noSleep });
    await api('https://x/rest/v1/rpc/payment_add', { method: 'POST', body: JSON.stringify({ p_amount: 5, p_idempotency_key: 'k-1' }) });
    assert.equal(f.calls[0].headers['x-app-version'], '1.2.3');
    assert.equal(f.calls[0].headers['x-idempotency-key'], 'k-1');
  });

  it('retries a read after a network error (slow 3G), then succeeds', async () => {
    const f = fakeFetch([new TypeError('Network request failed'), new TypeError('Network request failed'), { status: 200 }]);
    const api = createApiFetch({ fetch: f.fn, appVersion: '1', sleep: noSleep });
    const res = await api('https://x/rest/v1/leads', {});
    assert.equal(res.status, 200);
    assert.equal(f.calls.length, 3);
  });

  it('never repeats a write without an idempotency key', async () => {
    const f = fakeFetch([new TypeError('Network request failed'), { status: 200 }]);
    const api = createApiFetch({ fetch: f.fn, appVersion: '1', sleep: noSleep });
    await assert.rejects(api('https://x/rest/v1/rpc/lead_add', { method: 'POST', body: '{"p_name":"x"}' }));
    assert.equal(f.calls.length, 1);
  });

  it('repeats a write that has an idempotency key, also on 503', async () => {
    const f = fakeFetch([{ status: 503 }, { status: 200 }]);
    const api = createApiFetch({ fetch: f.fn, appVersion: '1', sleep: noSleep });
    const res = await api('https://x/rest/v1/rpc/payment_add', { method: 'POST', body: '{"p_idempotency_key":"k"}' });
    assert.equal(res.status, 200);
    assert.equal(f.calls.length, 2);
  });

  it('gives up after the time limit and the retries', async () => {
    const f = fakeFetch(['hang', 'hang', 'hang']);
    const api = createApiFetch({ fetch: f.fn, appVersion: '1', timeoutMs: 20, sleep: noSleep });
    await assert.rejects(api('https://x/rest/v1/leads', {}), /timeout/);
    assert.equal(f.calls.length, 3);
  });

  it('reports "upgrade required"', async () => {
    let flagged = false;
    const f = fakeFetch([{ status: 400, body: { message: 'upgrade_required', code: 'P0426' } }]);
    const api = createApiFetch({ fetch: f.fn, appVersion: '0.0.1', sleep: noSleep, onUpgradeRequired: () => { flagged = true; } });
    await api('https://x/rest/v1/leads', {});
    assert.equal(flagged, true);
  });

  it('refreshes the session once on "session_refresh_required" and repeats with the new token', async () => {
    const f = fakeFetch([{ status: 409, body: { message: 'session_refresh_required' } }, { status: 200 }]);
    let refreshes = 0;
    const api = createApiFetch({ fetch: f.fn, appVersion: '1', sleep: noSleep, refreshSession: async () => { refreshes += 1; return 'new-token'; } });
    const res = await api('https://x/rest/v1/rpc/x', { method: 'POST', headers: { Authorization: 'Bearer old' }, body: '{}' });
    assert.equal(res.status, 200);
    assert.equal(refreshes, 1);
    assert.equal(f.calls[1].headers.authorization, 'Bearer new-token');
  });

  it('reports the settings version of every response', async () => {
    const seen = [];
    const f = fakeFetch([{ status: 200, headers: { 'x-settings-version': '7' } }]);
    const api = createApiFetch({ fetch: f.fn, appVersion: '1', sleep: noSleep, reportSettingsVersion: (v) => seen.push(v) });
    await api('https://x/rest/v1/x', {});
    assert.deepEqual(seen, ['7']);
  });
});

describe('cache writes after sign-out or a switch (0B.01 fix)', async () => {
  const { mayWriteKey, cacheKey } = await import('../../src/lib/cache-core.ts');
  const U = 'user-1';
  it('only the signed-in person and their active institution may write', () => {
    assert.equal(mayWriteKey(cacheKey({ userId: U, institutionId: 'A' }, 'settings'), { userId: U, institutionId: 'A' }), true);
    assert.equal(mayWriteKey(cacheKey({ userId: U, institutionId: 'A' }, 'settings'), { userId: U, institutionId: 'B' }), false);
    assert.equal(mayWriteKey(cacheKey({ userId: U, institutionId: 'A' }, 'settings'), { userId: null, institutionId: null }), false);
    assert.equal(mayWriteKey(cacheKey({ userId: U, institutionId: null }, 'profile'), { userId: U, institutionId: 'B' }), true);
    assert.equal(mayWriteKey('ui_language', { userId: null, institutionId: null }), true);
  });
});
