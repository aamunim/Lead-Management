// 0A.07 end-to-end through the real API: the Master Admin writes, staff never read, only the service role reads.
import { createClient } from '@supabase/supabase-js';
import assert from 'node:assert/strict';
import { after, describe, it } from 'node:test';

import { API_URL, INSTITUTION, local, signInAs } from './helpers.mjs';

const REF = `sms.e2e_${Date.now()}.api_key`;
const VALUE = `sk-e2e-${Date.now()}-do-not-leak-xyz123`;
// Local service key, read from `supabase status` at run time (never hard-coded, never used in the app).
const service = createClient(API_URL, local.SECRET_KEY ?? local.SERVICE_ROLE_KEY, { auth: { persistSession: false } });

describe('per-institution secrets through the real API', () => {
  after(async () => {
    const { client } = await signInAs('platform.admin@example.test');
    await client.rpc('secret_revoke', { p_ref: REF, p_institution_id: INSTITUTION.A });
  });

  it('staff of an institution cannot set a secret (until integration.manage exists)', async () => {
    const { client } = await signInAs('a.member@example.test');
    const { error } = await client.rpc('secret_set', { p_ref: REF, p_value: VALUE });
    assert.equal(error?.message, 'permission_denied');
  });

  it('the Master Admin sets A\'s key and gets only the hint back', async () => {
    const { client } = await signInAs('platform.admin@example.test');
    const { data, error } = await client.rpc('secret_set', { p_ref: REF, p_value: VALUE, p_institution_id: INSTITUTION.A });
    assert.equal(error, null);
    assert.equal(data.hint, `${VALUE.slice(0, 4)}…${VALUE.slice(-4)}`);
    assert.ok(!JSON.stringify(data).includes(VALUE));
  });

  it('staff of A see the hint but can never read the value', async () => {
    const { client } = await signInAs('a.member@example.test');
    const meta = await client.from('institution_secrets').select('secret_ref, hint').eq('secret_ref', REF);
    assert.equal(meta.error, null);
    assert.equal(meta.data[0].hint.includes('…'), true);
    const vaultRef = await client.from('institution_secrets').select('vault_id');
    assert.ok(vaultRef.error, 'vault_id column is not readable');
    const read = await client.rpc('secret_read_for_service', { p_institution_id: INSTITUTION.A, p_ref: REF });
    assert.ok(read.error, 'the Edge-only reader is refused');
    assert.ok(!JSON.stringify(read).includes(VALUE));
  });

  it('staff of B see nothing of A\'s secrets', async () => {
    const { client } = await signInAs('b.member@example.test');
    const meta = await client.from('institution_secrets').select('secret_ref').eq('secret_ref', REF);
    assert.deepEqual(meta.data, []);
  });

  it('only the service role (Edge Functions) reads the value', async () => {
    const { data, error } = await service.rpc('secret_read_for_service', { p_institution_id: INSTITUTION.A, p_ref: REF });
    assert.equal(error, null);
    assert.equal(data, VALUE);
  });
});
