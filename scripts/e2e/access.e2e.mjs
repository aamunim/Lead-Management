// 0A.17 end-to-end through the real API: a role given and taken away takes effect on the next request (R15).
import assert from 'node:assert/strict';
import { after, describe, it } from 'node:test';

import { INSTITUTION, adminSql, signInAs, signInAsPlatform } from './helpers.mjs';

const A_MEMBER = '11111111-1111-4111-8111-111111111111';

describe('role assignments through the real API', () => {
  after(() => {
    adminSql(`delete from public.role_assignments where institution_id = '${INSTITUTION.A}' and user_id = '${A_MEMBER}';
              select app.flush_access_queue('${INSTITUTION.A}');
              delete from public.app_settings where institution_id = '${INSTITUTION.A}' and key = 'working_hours';`);
  });

  it('without a role, staff cannot change settings', async () => {
    const { client } = await signInAs('a.member@example.test');
    const { error } = await client.rpc('setting_set', { p_key: 'working_hours', p_value: { start: '10:00', end: '18:00' } });
    assert.equal(error?.message, 'permission_denied');
  });

  it('the Admin role (given by the Master Admin) opens it; removing it closes it on the next request', async () => {
    adminSql(`select app.apply_role_template('${INSTITUTION.A}', 'college')`);
    const admin = await signInAsPlatform();
    const roles = adminSql(`select id from public.roles where institution_id = '${INSTITUTION.A}' and template_key = 'admin'`);
    const roleId = roles.match(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/)[0];
    const assigned = await admin.client.rpc('role_assign', { p_user_id: A_MEMBER, p_role_id: roleId, p_institution_id: INSTITUTION.A });
    assert.equal(assigned.error, null);

    // The access version changed: the old token is refused once, a refreshed one works.
    const { client } = await signInAs('a.member@example.test');
    const ok = await client.rpc('setting_set', { p_key: 'working_hours', p_value: { start: '10:00', end: '18:00' } });
    assert.equal(ok.error, null);
    const mine = await client.rpc('my_access');
    assert.ok(mine.data.permissions['settings.office']);

    const removed = await admin.client.rpc('role_unassign', { p_assignment_id: assigned.data, p_institution_id: INSTITUTION.A });
    assert.equal(removed.error, null);
    const stale = await client.rpc('setting_set', { p_key: 'working_hours', p_value: { start: '09:00', end: '17:00' } });
    assert.equal(stale.error?.message, 'session_refresh_required', 'the same session is stopped on its next request');
    await client.auth.refreshSession();
    const denied = await client.rpc('setting_set', { p_key: 'working_hours', p_value: { start: '09:00', end: '17:00' } });
    assert.equal(denied.error?.message, 'permission_denied', 'after refreshing, the access is gone');
  });
});
