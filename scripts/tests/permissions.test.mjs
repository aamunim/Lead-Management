// Unit tests for 0A.16 module manifests: labels in both languages, neutral keys, scopes.
import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { checkManifests, readManifests, readPermissionLabels, syncSql } from '../permissions/manifests.mjs';

const labels = { en: { lead: { view: { label: 'View', help: 'Help' } } }, bn: { lead: { view: { label: 'দেখা', help: 'সাহায্য' } } } };
const manifest = (permissions, extra = {}) => [{ file: 'x.json', module: 'x', release: '1', permissions, ...extra }];

describe('module manifests', () => {
  it('the real manifests pass', () => {
    assert.deepEqual(checkManifests(readManifests(), readPermissionLabels()), []);
  });
  it('fails when a permission lacks a Bangla label', () => {
    const out = checkManifests(manifest([{ key: 'lead.view', scopable: true, defaults: { caller: 'own' } }]),
      { en: labels.en, bn: { lead: { view: { help: 'সাহায্য' } } } }).join('\n');
    assert.match(out, /"lead\.view" has no bn label/);
  });
  it('fails on education words and bad key formats', () => {
    const out = checkManifests(manifest([{ key: 'student.view' }, { key: 'Lead-View' }]), labels).join('\n');
    assert.match(out, /education word/);
    assert.match(out, /not a module\.action key/);
  });
  it('checks default scopes against scopable', () => {
    const out = checkManifests(manifest([{ key: 'lead.view', scopable: true, defaults: { caller: true } }]), labels).join('\n');
    assert.match(out, /needs a scope/);
  });
  it('builds safe SQL for the sync', () => {
    assert.match(syncSql(manifest([{ key: 'lead.view' }])), /^select coalesce\(array_to_string\(app\.sync_permissions\(\$manifests_json\$/);
    assert.throws(() => syncSql(manifest([{ key: 'x.y', note: '$manifests_json$' }])));
  });
});
