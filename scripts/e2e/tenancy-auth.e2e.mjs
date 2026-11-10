// End-to-end check of 0A.03 against a running local Supabase (`supabase start`):
// real email/password sign-in through Supabase Auth, the custom access-token hook, RLS through the REST API,
// and switching the active institution with set_active_institution + refreshSession.
// Run: npm run test:e2e
import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { adminSql, anonymousClient, claimsOf, INSTITUTION, signInAs } from './helpers.mjs';

const INST_A = INSTITUTION.A;
const INST_B = INSTITUTION.B;
const signIn = signInAs;

// Start from a known state: clear stored institution selections of the seed users (local database only).
adminSql("update public.profiles set last_active_institution_id = null where email like '%@example.test'");

describe('tenancy core through real Supabase Auth', () => {
  it('a single-institution user gets that institution in the token and sees only it', async () => {
    const { client, session } = await signIn('a.member@example.test');
    const claims = claimsOf(session);
    assert.equal(claims.active_institution_id, INST_A);
    assert.equal(claims.user_kind, 'staff');
    assert.equal(claims.access_version, 1);
    const { data, error } = await client.from('institutions').select('id');
    assert.equal(error, null);
    assert.deepEqual(data.map((r) => r.id), [INST_A]);
  });

  it('a user in two institutions starts with none, switches to B, then to A (D25)', async () => {
    const { client, session } = await signIn('both.member@example.test');
    assert.equal(claimsOf(session).active_institution_id, null);
    const { data: list } = await client.from('institutions').select('id').order('id');
    assert.deepEqual(list.map((r) => r.id), [INST_A, INST_B]);

    const { error: e1 } = await client.rpc('set_active_institution', { p_institution_id: INST_B });
    assert.equal(e1, null);
    const { data: r1 } = await client.auth.refreshSession();
    assert.equal(claimsOf(r1.session).active_institution_id, INST_B);

    const { error: e2 } = await client.rpc('set_active_institution', { p_institution_id: INST_A });
    assert.equal(e2, null);
    const { data: r2 } = await client.auth.refreshSession();
    assert.equal(claimsOf(r2.session).active_institution_id, INST_A);
  });

  it('a user cannot activate an institution they do not belong to', async () => {
    const { client } = await signIn('b.member@example.test');
    const { error } = await client.rpc('set_active_institution', { p_institution_id: INST_A });
    assert.equal(error?.message, 'not_a_member');
  });

  it('a deactivated member signs in but gets no institution and sees no institution data', async () => {
    const { client, session } = await signIn('gone.member@example.test');
    assert.equal(claimsOf(session).active_institution_id, null);
    const { data } = await client.from('institutions').select('id');
    assert.deepEqual(data, []);
  });

  it('anonymous visitors cannot read institutions', async () => {
    const anon = anonymousClient();
    const { data, error } = await anon.from('institutions').select('id');
    assert.ok(error || data.length === 0);
  });
});
