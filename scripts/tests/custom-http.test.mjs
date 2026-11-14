// Unit tests for the Custom HTTP SMS adapter (0B.13): SSRF guard (https and public hosts only, also after DNS), the
// masked sender id only once approved, parameter filling, success rule and message id, error mapping with whose side,
// the key never in an error detail, and SMS parts for Bangla, English and mixed text.
import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { checkTarget, customHttpAdapter, isBlockedAddress, mapError, senderFor } from '../../supabase/functions/_shared/hub/custom-http.ts';
import { smsParts } from '../../supabase/functions/_shared/hub/sms-parts.ts';

const KEY = 'zzzzzzzzzzzz1234';
const conn = (settings) => ({ id: 'c1', owner: 'institution', provider: 'custom_http_sms', sandbox: false, settings, secrets: { api_key: KEY } });
const msg = { id: 'm1', channel: 'sms', recipient: '01711000001', body: 'আপনার ফি জমা হয়েছে' };
const publicDns = async () => ['203.0.113.10'];

function fakeFetch(status, body, seen = []) {
  return async (url, init) => {
    seen.push({ url, init });
    return new Response(body, { status });
  };
}

describe('Custom HTTP: target safety (SSRF)', () => {
  it('refuses http, internal and private addresses', async () => {
    assert.equal(await checkTarget('http://sms.example.test/send'), 'only https is allowed');
    for (const u of ['https://10.0.0.5/x', 'https://172.16.1.1/x', 'https://192.168.1.1/x', 'https://127.0.0.1/x', 'https://169.254.169.254/latest',
      'https://localhost/x', 'https://[::1]/x', 'https://metadata.google.internal/x', 'https://intranet/x']) {
      assert.ok(await checkTarget(u), u);
    }
    assert.equal(await checkTarget('https://user:pass@sms.example.test/x'), 'no credentials in the address');
  });
  it('refuses a public name that resolves to an internal address', async () => {
    assert.match(await checkTarget('https://evil.example.test/x', async () => ['10.1.2.3']), /internal/);
    assert.equal(await checkTarget('https://sms.example.test/x', publicDns), null);
  });
  it('allows public addresses', () => {
    assert.equal(isBlockedAddress('203.0.113.10'), false);
    assert.equal(isBlockedAddress('sms.gateway.com.bd'), false);
  });
});

describe('Custom HTTP: sending', () => {
  it('fills the parameters, follows the success rule and reads the message id', async () => {
    const seen = [];
    const res = await customHttpAdapter(publicDns).send(conn({
      send_url: 'https://sms.example.test/api/send', method: 'POST', body_format: 'form', sender_id: 'ACME',
      params: { api_key: '{api_key}', to: '{to}', msg: '{message}', from: '{sender_id}', type: '{unicode}' },
      success_match: '"status":"ok"', message_id_path: 'data.id',
    }), msg, fakeFetch(200, '{"status":"ok","data":{"id":"G-77"}}', seen));
    assert.deepEqual(res, { ok: true, providerMessageId: 'G-77' });
    const sent = new URLSearchParams(seen[0].init.body);
    assert.equal(sent.get('to'), '01711000001');
    assert.equal(sent.get('msg'), msg.body);
    assert.equal(sent.get('from'), 'ACME');
    assert.equal(sent.get('type'), '1', 'Bangla is sent as Unicode');
  });
  it('maps failures to whose side they are on, and never puts the key in the detail', async () => {
    const s = { send_url: 'https://sms.example.test/send', params: { key: '{api_key}' } };
    const low = await customHttpAdapter(publicDns).send(conn(s), msg, fakeFetch(200, `Insufficient balance for ${KEY}`));
    assert.equal(low.ok, true, '2xx without a success rule counts as sent');
    const r = await customHttpAdapter(publicDns).send(conn({ ...s, success_match: 'OK' }), msg, fakeFetch(200, `Insufficient balance for ${KEY}`));
    assert.equal(r.ok, false);
    assert.equal(r.errorCode, 'balance_low');
    assert.doesNotMatch(r.detail, new RegExp(KEY));
    assert.equal(mapError(401, ''), 'auth_failed');
    assert.equal(mapError(503, ''), 'provider_down');
    assert.equal(mapError(200, 'Sender ID not approved'), 'sender_not_approved');
  });
  it('refuses an internal target without calling it', async () => {
    const seen = [];
    const r = await customHttpAdapter(async () => ['127.0.0.1']).send(conn({ send_url: 'https://sms.example.test/send' }), msg, fakeFetch(200, 'ok', seen));
    assert.equal(r.ok, false);
    assert.equal(r.errorCode, 'config_invalid');
    assert.equal(seen.length, 0);
  });
  it('uses a masked sender id only once approved (D35)', () => {
    assert.equal(senderFor({ sender_id: 'ACME', masking: { type: 'masked', status: 'applied', non_masked_sender_id: '8801700000000' } }), '8801700000000');
    assert.equal(senderFor({ sender_id: 'ACME', masking: { type: 'masked', status: 'approved' } }), 'ACME');
    assert.equal(senderFor({ sender_id: '8801700000000', masking: { type: 'non_masked' } }), '8801700000000');
  });
  it('reads the balance', async () => {
    const r = await customHttpAdapter(publicDns).health(conn({ send_url: 'https://sms.example.test/send', balance_url: 'https://sms.example.test/balance',
      balance_path: 'balance' }), fakeFetch(200, '{"balance":"152.50"}'));
    assert.deepEqual(r, { ok: true, balance: 152.5 });
  });
});

describe('SMS parts', () => {
  it('counts 160 / 153 for English, 70 / 67 for Bangla and mixed text', () => {
    assert.equal(smsParts('Hello').parts, 1);
    assert.equal(smsParts('a'.repeat(160)).parts, 1);
    assert.equal(smsParts('a'.repeat(161)).parts, 2);
    assert.equal(smsParts('ক'.repeat(70)).parts, 1);
    assert.equal(smsParts('ক'.repeat(71)).parts, 2);
    assert.equal(smsParts('Fee ৳500 received').unicode, true, 'one Bangla character makes the whole text Unicode');
    assert.equal(smsParts('ক'.repeat(135)).parts, 3);
  });
});

describe('SMS parts: the app and the hub agree', async () => {
  const app = await import('../../src/lib/sms-parts.ts');
  it('same answer for the same text', () => {
    for (const t of ['Hello', 'a'.repeat(161), 'ক'.repeat(71), 'Fee ৳500 received', 'আপনার ভর্তি নিশ্চিত হয়েছে। ধন্যবাদ।'.repeat(3)]) {
      assert.deepEqual(app.smsParts(t), smsParts(t), t);
    }
  });
});
