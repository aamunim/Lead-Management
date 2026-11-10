// Unit tests for the runtime-independent Edge Function modules (0A.06). Node strips the TypeScript types.
import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { Budget, LIMITS, withTimeout } from '../../supabase/functions/_shared/budget.ts';
import { ERRORS, toErrorInfo } from '../../supabase/functions/_shared/errors.ts';
import { createLogger } from '../../supabase/functions/_shared/logger.ts';
import { maskPhone, redact } from '../../supabase/functions/_shared/redact.ts';
import { errorResponseBody, resolveTenant } from '../../supabase/functions/_shared/tenant-core.ts';

const FAKE_JWT = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.c2lnbmF0dXJlLXBhcnQtaGVyZQ';

describe('redaction', () => {
  it('removes secret-looking keys and values', () => {
    const out = redact({ api_key: 'abc', nested: { password: 'p', token: 't' }, note: `use ${FAKE_JWT} and sk-abcdefghijklmnopqrst` });
    assert.equal(out.api_key, '[redacted]');
    assert.equal(out.nested.password, '[redacted]');
    assert.equal(out.nested.token, '[redacted]');
    assert.equal(out.note, 'use [redacted-jwt] and [redacted-key]');
  });
  it('masks Bangladesh phone numbers in every form (D24 style)', () => {
    assert.equal(maskPhone('call 01712345678 or +8801812345678 or 8801912345678'),
      'call 017•••••678 or 018•••••678 or 019•••••678');
    assert.equal(maskPhone('amount 1234567890123'), 'amount 1234567890123');
  });
  it('removes national ids by key and keeps ordinary values', () => {
    const out = redact({ guardian_nid: '1990123456789', fee: 25000, name: 'Rahim' });
    assert.deepEqual(out, { guardian_nid: '[redacted-id]', fee: 25000, name: 'Rahim' });
  });
  it('redacts errors and bearer headers', () => {
    assert.deepEqual(redact(new Error(`Bearer ${FAKE_JWT}`)), { name: 'Error', message: 'Bearer [redacted]' });
  });
});

describe('logger', () => {
  it('writes one JSON line tagged with institution, user and request id, without secrets', () => {
    const lines = [];
    const log = createLogger({ function: 'f', request_id: 'r1' }, (l) => lines.push(l))
      .with({ institution_id: 'inst-a', user_id: 'user-1' });
    log.info('thing.done', { phone: '01712345678', authorization: `Bearer ${FAKE_JWT}` });
    const line = JSON.parse(lines[0]);
    assert.equal(line.institution_id, 'inst-a');
    assert.equal(line.user_id, 'user-1');
    assert.equal(line.request_id, 'r1');
    assert.equal(line.data.phone, '017•••••678');
    assert.equal(line.data.authorization, '[redacted]');
    assert.ok(!lines[0].includes(FAKE_JWT));
  });
});

describe('error contract', () => {
  it('maps database codes to actions the app understands', () => {
    assert.equal(toErrorInfo({ message: 'session_refresh_required' }).action, 'refresh_session');
    assert.equal(toErrorInfo({ message: 'no_active_institution' }).action, 'choose_institution');
    assert.equal(toErrorInfo({ code: '42501', message: 'permission denied for table x' }).code, 'permission_denied');
    assert.equal(toErrorInfo(new Error('timeout')).code, 'timeout');
    assert.equal(toErrorInfo('weird').code, 'unknown');
  });
  it('every error has a message key for translation', () => {
    for (const info of Object.values(ERRORS)) assert.match(info.messageKey, /^errors\.[a-z_]+$/);
  });
});

describe('time budget', () => {
  it('stops new work after 45 s and caps calls at 75 s', () => {
    let now = 0;
    const budget = new Budget(() => now);
    assert.equal(budget.canStartNewWork(), true);
    assert.equal(budget.nextCallMs(), LIMITS.callMs);
    now = 46_000;
    assert.equal(budget.canStartNewWork(), false);
    now = 120_000;
    assert.equal(budget.nextCallMs(), 20_000);
  });
  it('withTimeout rejects slow promises', async () => {
    await assert.rejects(withTimeout(new Promise((r) => setTimeout(r, 200)), 20), /timeout/);
  });
});

describe('tenant middleware core', () => {
  const okSession = async () => ({ data: { user_id: 'u1', institution_id: 'inst-a', access_version: 1, user_kind: 'staff' }, error: null });
  it('refuses a request without a bearer token', async () => {
    const result = await resolveTenant(null, okSession, 'f', 'r', () => {});
    assert.equal(result.ok, false);
    assert.equal(result.error.code, 'not_signed_in');
  });
  it('passes the database verdict through (e.g. stale access version)', async () => {
    const result = await resolveTenant('Bearer x', async () => ({ data: null, error: { message: 'session_refresh_required' } }), 'f', 'r', () => {});
    assert.equal(result.ok, false);
    assert.equal(result.error.action, 'refresh_session');
    assert.deepEqual(errorResponseBody(result.error, 'r').error.code, 'session_refresh_required');
  });
  it('takes user and institution only from the session check', async () => {
    const lines = [];
    const result = await resolveTenant('Bearer x', okSession, 'f', 'r9', (l) => lines.push(l));
    assert.equal(result.ok, true);
    assert.equal(result.context.institutionId, 'inst-a');
    result.context.log.info('x');
    assert.equal(JSON.parse(lines.at(-1)).institution_id, 'inst-a');
  });
});
