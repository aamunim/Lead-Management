// 0A.18 end-to-end through the real API: the Users RPCs are refused without settings.users, deactivation ends the
// person's sessions at once (their refresh token stops working), and a sensitive role change needs two-step sign-in.
import assert from 'node:assert/strict';
import { after, describe, it } from 'node:test';

import { INSTITUTION, adminSql, signInAs } from './helpers.mjs';

const PENDING = '88888888-8888-4888-8888-888888888888';

describe('users and roles through the real API', () => {
  after(() => {
    adminSql(`update public.institution_members set status = 'pending' where institution_id = '${INSTITUTION.A}' and user_id = '${PENDING}';
              delete from public.role_permissions where institution_id = '${INSTITUTION.A}'
                and role_id in (select id from public.roles where institution_id = '${INSTITUTION.A}' and name = 'E2E sensitive');
              delete from public.roles where institution_id = '${INSTITUTION.A}' and name = 'E2E sensitive';
              select app.flush_access_queue('${INSTITUTION.A}');`);
  });

  it('without settings.users the Users RPCs are refused', async () => {
    const { client } = await signInAs('a.member@example.test');
    const { error } = await client.rpc('users_list', {});
    assert.equal(error?.message, 'permission_denied');
    const audit = await client.rpc('audit_list', {});
    assert.equal(audit.error?.message, 'permission_denied');
  });

  it('deactivation ends the person\'s session at once', async () => {
    const owner = await signInAs('owner.admin@example.test');
    assert.equal((await owner.client.rpc('user_approve', { p_user_id: PENDING })).error, null);
    const person = await signInAs('pending.member@example.test');
    assert.equal((await person.client.rpc('current_session')).error, null, 'works while active');

    assert.equal((await owner.client.rpc('user_deactivate', { p_user_id: PENDING, p_reason: 'e2e' })).error, null);
    const stale = await person.client.rpc('current_session');
    assert.equal(stale.error?.message, 'membership_not_active', 'the old token is refused on the next request');
    const access = await person.client.rpc('my_access');
    assert.deepEqual(access.data?.permissions ?? {}, {}, 'and reads nothing of the institution');
    const refreshed = await person.client.auth.refreshSession();
    assert.ok(refreshed.error, 'the refresh token no longer works (sessions ended)');
  });

  it('a sensitive role change without two-step sign-in is refused; a normal one works', async () => {
    const owner = await signInAs('owner.admin@example.test');
    const created = await owner.client.rpc('role_create', { p_name: 'E2E sensitive' });
    assert.equal(created.error, null);
    const sensitive = await owner.client.rpc('role_set_grants', { p_role_id: created.data, p_grants: { 'audit.view': true } });
    assert.equal(sensitive.error?.message, 'mfa_required');
    const normal = await owner.client.rpc('role_set_grants', { p_role_id: created.data, p_grants: { 'settings.general': true } });
    assert.equal(normal.error, null);
  });
});
