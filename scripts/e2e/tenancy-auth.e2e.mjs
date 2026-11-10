// End-to-end check of 0A.03 against a running local Supabase (`supabase start`):
// real email/password sign-in through Supabase Auth, the custom access-token hook, RLS through the REST API,
// and switching the active institution with set_active_institution + refreshSession.
// Run: npm run test:e2e   (reads the local API URL and publishable key from `supabase status`; nothing is hard-coded)
import { createClient } from '@supabase/supabase-js';
import assert from 'node:assert/strict';
import { execSync } from 'node:child_process';
import { describe, it } from 'node:test';

const status = JSON.parse(execSync('npx --yes supabase@3.1.0 status -o json', { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }));
const url = status.API_URL;
const key = status.PUBLISHABLE_KEY ?? status.ANON_KEY;
const INST_A = 'a0000000-0000-4000-8000-00000000000a';
const INST_B = 'b0000000-0000-4000-8000-00000000000b';

// Start from a known state: clear stored institution selections of the seed users (local database only).
execSync(`psql "${status.DB_URL}" -X -q -c "update public.profiles set last_active_institution_id = null where email like '%@example.test'"`);

const claimsOf = (session) => JSON.parse(Buffer.from(session.access_token.split('.')[1], 'base64url').toString());

async function signIn(email) {
  const client = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data, error } = await client.auth.signInWithPassword({ email, password: 'password123' });
  assert.equal(error, null, `sign-in failed for ${email}: ${error?.message}`);
  return { client, session: data.session };
}

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
    const anon = createClient(url, key, { auth: { persistSession: false } });
    const { data, error } = await anon.from('institutions').select('id');
    assert.ok(error || data.length === 0);
  });
});
