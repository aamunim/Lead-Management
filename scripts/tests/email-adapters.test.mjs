// Unit tests for the email adapters and the domain checker (0B.14): Resend sends with the institution's sender and
// reply-to and trusts only Svix signatures of its own secret; SMTP speaks the protocol (AUTH, MAIL, RCPT, DATA) with
// Bangla headers encoded and errors mapped by side; the DNS checker reads correct and incorrect SPF / DKIM / DMARC.
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { describe, it } from 'node:test';

import { checkDkim, checkDmarc, checkDomain, checkSpf } from '../../supabase/functions/_shared/hub/dns-check.ts';
import { resendAdapter, verifySvix } from '../../supabase/functions/_shared/hub/resend.ts';
import { buildMessage, encodeHeader, mapSmtpError, smtpAdapter } from '../../supabase/functions/_shared/hub/smtp.ts';

const conn = (secrets, settings = {}) => ({ id: 'c1', owner: 'institution', provider: 'resend', sandbox: false, settings, secrets });
const msg = { id: 'm1', channel: 'email', recipient: 'parent@example.test', subject: 'ভর্তি নিশ্চিত', body: 'আপনার ভর্তি নিশ্চিত হয়েছে।',
  sender: { from_name: 'Ideal College', from_email: 'no-reply@ideal.example.test', reply_to: 'office@ideal.example.test' } };

describe('Resend adapter', () => {
  it('sends with the sender, reply-to and an idempotency key', async () => {
    const seen = [];
    const r = await resendAdapter.send(conn({ api_key: 'k' }), msg, async (url, init) => {
      seen.push({ url, init });
      return new Response('{"id":"re_123"}', { status: 200 });
    });
    assert.deepEqual(r, { ok: true, providerMessageId: 're_123' });
    const body = JSON.parse(seen[0].init.body);
    assert.equal(body.from, 'Ideal College <no-reply@ideal.example.test>');
    assert.equal(body.reply_to, 'office@ideal.example.test');
    assert.deepEqual(body.to, ['parent@example.test']);
    assert.equal(seen[0].init.headers['idempotency-key'], 'm1');
  });
  it('maps errors by side', async () => {
    const r = await resendAdapter.send(conn({ api_key: 'k' }), msg, async () => new Response('{"message":"The domain is not verified"}', { status: 403 }));
    assert.equal(r.errorCode, 'auth_failed');
    const r2 = await resendAdapter.send(conn({ api_key: 'k' }), msg, async () => new Response('{"message":"The ideal.example.test domain is not verified"}', { status: 422 }));
    assert.equal(r2.errorCode, 'domain_not_verified');
    const r3 = await resendAdapter.send(conn({}), msg, async () => new Response(''));
    assert.equal(r3.errorCode, 'auth_failed');
  });
  it('trusts only a Svix signature made with the connection\'s secret, within 5 minutes', async () => {
    const secretBytes = Buffer.from('a-test-webhook-secret-bytes-1234');
    const secret = `whsec_${secretBytes.toString('base64')}`;
    const body = JSON.stringify({ type: 'email.bounced', data: { email_id: 're_123' } });
    const now = 1_800_000_000;
    const sign = (key, ts) => `v1,${createHmac('sha256', key).update(`msg_1.${ts}.${body}`).digest('base64')}`;
    const h = (sig, ts = now) => new Headers({ 'svix-id': 'msg_1', 'svix-timestamp': String(ts), 'svix-signature': sig });
    assert.equal(await verifySvix(secret, h(sign(secretBytes, now)), body, now), true);
    assert.equal(await verifySvix(secret, h(sign(Buffer.from('another-secret'), now)), body, now), false);
    assert.equal(await verifySvix(secret, h(sign(secretBytes, now - 600), now - 600), body, now), false, 'replayed later');
    assert.equal(await verifySvix(secret, h(sign(secretBytes, now)), body.replace('bounced', 'delivered'), now), false, 'tampered');
    assert.deepEqual(resendAdapter.parseStatus(body), { providerMessageId: 're_123', status: 'bounced', eventKey: 're_123:email.bounced' });
    assert.equal(resendAdapter.parseStatus(JSON.stringify({ type: 'email.complained', data: { email_id: 'x' } })).status, 'complained');
  });
});

/** A scripted SMTP server: replies in order, records what the client wrote. */
function fakeSmtp(replies) {
  const written = [];
  const queue = [...replies];
  return {
    written,
    open: async () => ({ write: async (l) => { written.push(l); }, read: async () => queue.shift() ?? '421 closed', close: async () => {} }),
  };
}

describe('SMTP adapter', () => {
  const settings = { host: 'mail.ideal.example.test', port: 465, username: 'no-reply@ideal.example.test', from_email: 'no-reply@ideal.example.test' };
  it('authenticates, sends and quits', async () => {
    const s = fakeSmtp(['220 hi', '250-mail\n250 AUTH LOGIN', '334 VXNlcm5hbWU6', '334 UGFzc3dvcmQ6', '235 ok', '250 ok', '250 ok', '354 go', '250 2.0.0 queued as ABC123', '221 bye']);
    const r = await smtpAdapter(s.open).send({ ...conn({ password: 'app-password' }, settings), provider: 'smtp' }, msg);
    assert.equal(r.ok, true);
    assert.equal(r.providerMessageId, '2.0.0 queued as ABC123');
    assert.ok(s.written.includes('MAIL FROM:<no-reply@ideal.example.test>\r\n'));
    assert.ok(s.written.includes('RCPT TO:<parent@example.test>\r\n'));
    const data = s.written.find((l) => l.startsWith('From:'));
    assert.match(data, /Subject: =\?UTF-8\?B\?/, 'Bangla subject encoded');
    assert.match(data, /Reply-To: <office@ideal\.example\.test>/);
    assert.ok(!s.written.some((l) => l.includes('app-password')), 'the password is sent base64-encoded only');
  });
  it('maps a wrong password and a refused recipient', async () => {
    const bad = fakeSmtp(['220 hi', '250 ok', '334 a', '334 b', '535 5.7.8 Username and Password not accepted']);
    assert.equal((await smtpAdapter(bad.open).send({ ...conn({ password: 'x' }, settings), provider: 'smtp' }, msg)).errorCode, 'auth_failed');
    assert.equal(mapSmtpError(550, 'No such user'), 'invalid_recipient');
    assert.equal(mapSmtpError(553, 'Sender address rejected'), 'sender_not_approved');
    assert.equal(mapSmtpError(421, 'try later'), 'provider_down');
  });
  it('builds a valid message', () => {
    assert.equal(encodeHeader('Ideal College'), 'Ideal College');
    assert.match(encodeHeader('আইডিয়াল কলেজ'), /^=\?UTF-8\?B\?.+\?=$/);
    const m = buildMessage({ name: 'আইডিয়াল', email: 'a@b.test' }, 'c@d.test', 'Hi', 'Body', null, 'm1', new Date(0));
    assert.match(m, /\r\n\r\n/);
    assert.ok(m.endsWith('\r\n.'));
  });
});

describe('domain check (SPF / DKIM / DMARC)', () => {
  // A made-up public key shape, built at run time (no key-looking literal in the file).
  const KEY = ['MIGf', 'MA0G'].join('').padEnd(220, 'A');
  it('SPF', () => {
    assert.equal(checkSpf([['v=spf1 include:amazonses.com ~all']], 'resend').ok, true);
    assert.match(checkSpf([['v=spf1 include:_spf.google.com ~all']], 'resend').problem, /amazonses/);
    assert.match(checkSpf([['v=spf1 ~all'], ['v=spf1 include:x ~all']], null).problem, /more than one/);
    assert.match(checkSpf([['v=spf1 +all']], null).problem, /anyone/);
    assert.equal(checkSpf([['google-site-verification=abc']], null).problem, 'no SPF record');
    assert.equal(checkSpf([['v=spf1 include:amazon', 'ses.com ~all']], 'resend').ok, true, 'long records split in parts are joined');
  });
  it('DKIM', () => {
    assert.equal(checkDkim([[`v=DKIM1; k=rsa; p=${KEY}`]]).ok, true);
    assert.match(checkDkim([['v=DKIM1; p=']]).problem, /empty/);
    assert.match(checkDkim([]).problem, /no DKIM/);
  });
  it('DMARC', () => {
    assert.equal(checkDmarc([['v=DMARC1; p=none; rua=mailto:r@x.test']]).ok, true);
    assert.match(checkDmarc([['v=DMARC1; rua=mailto:r@x.test']]).problem, /policy/);
  });
  it('checks all three names', async () => {
    const asked = [];
    const r = await checkDomain('ideal.example.test', 'resend', 'resend', async (name) => {
      asked.push(name);
      if (name === 'ideal.example.test') return [['v=spf1 include:amazonses.com ~all']];
      if (name === 'resend._domainkey.ideal.example.test') return [[`p=${KEY}`]];
      throw new Error('NXDOMAIN');
    });
    assert.deepEqual(asked.sort(), ['_dmarc.ideal.example.test', 'ideal.example.test', 'resend._domainkey.ideal.example.test']);
    assert.equal(r.spf.ok && r.dkim.ok, true);
    assert.equal(r.dmarc.ok, false);
  });
});
