// Unit tests for the 0A.18 role editor / compare / change-log helpers (src/lib/admin-core.ts).
import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  auditChanges, changedKeys, compareReleases, compareRoles, groupByModule, hasPermission, newestRelease, normaliseSearch,
  permissionTextKey, setGrant, touchesSensitive,
} from '../../src/lib/admin-core.ts';

const perm = (key, extra = {}) => ({ key, module: key.split('.')[0] === 'settings' ? 'core' : key.split('.')[0], action: key.split('.')[1] ?? 'all',
  scopable: false, sensitive: false, introduced_in_release: '0A.16', ...extra });
const PERMS = [perm('*'), perm('settings.users'), perm('audit.view', { sensitive: true }), perm('lead.view', { scopable: true, introduced_in_release: '1A.02' }),
  perm('lead.edit', { scopable: true, introduced_in_release: '1A.02' })];
const role = (grants, extra = {}) => ({ id: 'r', name: 'R', name_key: null, is_system: false, is_super_admin: false, template_key: null, rank: 1,
  inherits_from_role_id: null, flags: [], archived: false, grants, ...extra });

describe('role editor helpers', () => {
  it('permission label keys follow the registry key; * is "all"', () => {
    assert.equal(permissionTextKey('settings.users', 'label'), 'settings.users.label');
    assert.equal(permissionTextKey('*', 'help'), 'all.help');
  });
  it('groups by module with core first and never lists *', () => {
    const groups = groupByModule(PERMS);
    assert.deepEqual(groups.map((g) => g.module), ['core', 'audit', 'lead']);
    assert.ok(!groups.flatMap((g) => g.permissions).some((p) => p.key === '*'));
  });
  it('releases sort in delivery order (0A.9 < 0A.16 < 0B.1 < 1A.2)', () => {
    assert.deepEqual(['1A.2', '0A.16', '0B.1', '0A.9'].sort(compareReleases), ['0A.9', '0A.16', '0B.1', '1A.2']);
  });
  it('"new in this release" = the newest release in the registry', () => {
    const latest = newestRelease(PERMS);
    assert.equal(latest.release, '1A.02');
    assert.deepEqual(latest.permissions.map((p) => p.key), ['lead.view', 'lead.edit']);
  });
  it('setGrant: scopable starts at own; unscoped is true; null removes', () => {
    let g = setGrant({}, PERMS[3], true);
    assert.deepEqual(g, { 'lead.view': 'own' });
    g = setGrant(g, PERMS[3], 'branch');
    g = setGrant(g, PERMS[1], 'all');
    assert.deepEqual(g, { 'lead.view': 'branch', 'settings.users': true });
    assert.deepEqual(setGrant(g, PERMS[3], null), { 'settings.users': true });
  });
  it('a sensitive change is detected only when a sensitive permission is added or removed', () => {
    assert.equal(touchesSensitive({}, { 'audit.view': true }, PERMS), true);
    assert.equal(touchesSensitive({ 'audit.view': true }, {}, PERMS), true);
    assert.equal(touchesSensitive({ 'lead.view': 'own' }, { 'lead.view': 'all' }, PERMS), false);
    assert.deepEqual(changedKeys({ a: true, b: 'own' }, { b: 'all', c: true }), ['a', 'b', 'c']);
  });
  it('compare: differences first; the Super Admin role has everything', () => {
    const rows = compareRoles(role({ 'settings.users': true, 'lead.view': 'own' }), role({ 'lead.view': 'own' }), PERMS);
    assert.deepEqual(rows.map((r) => [r.key, r.same]), [['settings.users', false], ['lead.view', true]]);
    const sa = compareRoles(role({}, { is_super_admin: true }), role({}), PERMS);
    assert.equal(sa.length, 4);
    assert.ok(sa.every((r) => r.a === 'all' && r.b === null));
  });
  it('hasPermission mirrors can() at any scope; * covers all', () => {
    assert.equal(hasPermission({ 'settings.users': ['all'] }, 'settings.users'), true);
    assert.equal(hasPermission({ 'settings.users': ['all'] }, 'settings.roles'), false);
    assert.equal(hasPermission({ '*': ['all'] }, 'settings.roles'), true);
    assert.equal(hasPermission(null, 'settings.users'), false);
  });
  it('search typed with Bangla digits matches phone numbers', () => {
    assert.equal(normaliseSearch(' ০১৭১১ '), '01711');
  });
  it('change log lines list only what changed', () => {
    assert.deepEqual(auditChanges({ status: 'pending', x: 1 }, { status: 'active', x: 1 }), [{ field: 'status', from: 'pending', to: 'active' }]);
    assert.deepEqual(auditChanges(null, { a: 1 }), []);
  });
});
