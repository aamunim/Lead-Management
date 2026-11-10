// 0A.04-T9 RPC-as-real-role harness, and lesson 1 reproduced through the real API:
// an INVOKER RPC that calls a helper revoked from `authenticated` fails for real users — the schema lint
// (rule invoker_sweep) catches this before it can ship, and the app must show the error, never a blank card.
import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';

import { adminSql, INSTITUTION, reloadApiSchema, signInAs } from './helpers.mjs';

describe('RPC-as-real-role harness', () => {
  before(() => {
    adminSql(`
      create or replace function app.e2e_locked_helper() returns int language sql set search_path = '' as $$ select 1 $$;
      revoke execute on function app.e2e_locked_helper() from public, anon, authenticated;
      create or replace function public.e2e_reader() returns int language sql set search_path = '' as $$
        select app.e2e_locked_helper() $$;
      grant execute on function public.e2e_reader() to authenticated;
      create or replace function public.e2e_whoami() returns uuid language sql set search_path = '' as $$
        select app.require_active_session() $$;
      grant execute on function public.e2e_whoami() to authenticated;`);
    reloadApiSchema();
  });

  after(() => {
    adminSql(`drop function if exists public.e2e_reader(); drop function if exists public.e2e_whoami();
              drop function if exists app.e2e_locked_helper();`);
    reloadApiSchema();
  });

  it('a correct RPC called as a real signed-in user returns that user\'s active institution', async () => {
    const { client } = await signInAs('a.member@example.test');
    // PostgREST may need a moment to see the new function.
    let result;
    for (let i = 0; i < 10; i += 1) {
      result = await client.rpc('e2e_whoami');
      if (!result.error) break;
      await new Promise((r) => setTimeout(r, 300));
    }
    assert.equal(result.error, null);
    assert.equal(result.data, INSTITUTION.A);
  });

  it('lesson 1: an invoker RPC calling a revoked helper fails with "permission denied" for real users', async () => {
    const { client } = await signInAs('a.member@example.test');
    let result;
    for (let i = 0; i < 10; i += 1) {
      result = await client.rpc('e2e_reader');
      if (result.error && !/Could not find/i.test(result.error.message)) break;
      await new Promise((r) => setTimeout(r, 300));
    }
    assert.match(result.error?.message ?? '', /permission denied/i);
  });
});
