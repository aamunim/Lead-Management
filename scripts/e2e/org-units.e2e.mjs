// 0A.15 end-to-end through the real API: branches and units in one tree call; B sees nothing of A.
import assert from 'node:assert/strict';
import { after, describe, it } from 'node:test';

import { INSTITUTION, adminSql, signInAs } from './helpers.mjs';

describe('org units through the real API', () => {
  after(() => {
    adminSql(`delete from public.org_unit_managers where institution_id = '${INSTITUTION.A}';
              delete from public.org_unit_members where institution_id = '${INSTITUTION.A}';
              delete from public.branches where institution_id = '${INSTITUTION.A}';
              update public.org_units set parent_id = null where institution_id = '${INSTITUTION.A}';
              delete from public.org_units where institution_id = '${INSTITUTION.A}';
              delete from public.app_settings where key = 'branches_enabled';`);
  });

  it('the Master Admin builds a branch → department → team; A reads it in one call', async () => {
    const admin = await signInAs('platform.admin@example.test');
    const on = await admin.client.rpc('setting_set', { p_key: 'branches_enabled', p_value: true, p_institution_id: INSTITUTION.A });
    assert.equal(on.error, null);
    const branch = await admin.client.rpc('branch_create', { p_name: 'E2E Campus', p_phone: '+880 1711-223344', p_institution_id: INSTITUTION.A });
    assert.equal(branch.error, null);
    const dept = await admin.client.rpc('org_unit_create', { p_name: 'E2E Admissions', p_kind: 'department', p_parent_id: branch.data, p_institution_id: INSTITUTION.A });
    const team = await admin.client.rpc('org_unit_create', { p_name: 'E2E Callers', p_kind: 'team', p_parent_id: dept.data, p_institution_id: INSTITUTION.A });
    assert.equal(team.error, null);

    const a = await signInAs('a.member@example.test');
    const tree = await a.client.rpc('org_tree_get');
    assert.equal(tree.error, null);
    const names = tree.data.units.map((u) => u.name);
    assert.deepEqual(names.sort(), ['E2E Admissions', 'E2E Callers', 'E2E Campus']);
    assert.equal(tree.data.units.find((u) => u.name === 'E2E Callers').branch_id, branch.data);
    assert.equal(tree.data.units.find((u) => u.kind === 'branch').branch.phone, '01711223344');
  });

  it('a cycle is refused with a contract error', async () => {
    const admin = await signInAs('platform.admin@example.test');
    const a = await signInAs('a.member@example.test');
    const units = (await a.client.rpc('org_tree_get')).data.units;
    const dept = units.find((u) => u.kind === 'department');
    const team = units.find((u) => u.kind === 'team');
    const { error } = await admin.client.rpc('org_unit_move', { p_id: dept.id, p_new_parent_id: team.id, p_institution_id: INSTITUTION.A });
    assert.equal(error?.message, 'org_unit_cycle');
  });

  it('B sees none of A\'s units', async () => {
    const b = await signInAs('b.member@example.test');
    assert.deepEqual((await b.client.rpc('org_tree_get')).data.units, []);
    assert.deepEqual((await b.client.from('org_units').select('id')).data, []);
  });
});
