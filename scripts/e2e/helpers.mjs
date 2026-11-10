// RPC-as-real-role harness (0A.04-T9). Every RPC test signs in as a real user with a real JWT and calls the API
// through PostgREST — never as the database owner (lesson 1). Use these helpers in every e2e test.
import { createClient } from '@supabase/supabase-js';
import assert from 'node:assert/strict';
import { execFileSync, execSync } from 'node:child_process';

export const local = JSON.parse(
  execSync('npx --yes supabase@3.1.0 status -o json', { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }),
);
export const API_URL = local.API_URL;
export const PUBLIC_KEY = local.PUBLISHABLE_KEY ?? local.ANON_KEY;
export const SEED_PASSWORD = 'password123'; // local seed data only

export const INSTITUTION = {
  A: 'a0000000-0000-4000-8000-00000000000a',
  B: 'b0000000-0000-4000-8000-00000000000b',
};

/** Signs in through Supabase Auth and returns a client acting as that user, plus the session. */
export async function signInAs(email, password = SEED_PASSWORD) {
  const client = createClient(API_URL, PUBLIC_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data, error } = await client.auth.signInWithPassword({ email, password });
  assert.equal(error, null, `sign-in failed for ${email}: ${error?.message}`);
  return { client, session: data.session };
}

export function anonymousClient() {
  return createClient(API_URL, PUBLIC_KEY, { auth: { persistSession: false } });
}

export const claimsOf = (session) =>
  JSON.parse(Buffer.from(session.access_token.split('.')[1], 'base64url').toString());

/** Test set-up / tear-down SQL on the LOCAL database only (never for assertions about permissions). */
export function adminSql(sql) {
  return execFileSync('psql', [local.DB_URL, '-X', '-q', '-v', 'ON_ERROR_STOP=1', '-c', sql], { encoding: 'utf8' });
}

/** Asks PostgREST to reload its schema cache after a test created a function. */
export function reloadApiSchema() {
  adminSql("notify pgrst, 'reload schema'");
}
