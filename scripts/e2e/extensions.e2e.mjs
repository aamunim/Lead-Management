// 0A.09 end-to-end through the real API: an extension switched on for A only; B and the core are unaffected.
// Needs the example extension applied (npm run db:extensions).
import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';

import { INSTITUTION, adminSql, signInAs } from './helpers.mjs';

const BODY = `e2e note ${Date.now()}`;

describe('extensions through the real API', () => {
  before(async () => {
    const { client } = await signInAs('platform.admin@example.test');
    const { error } = await client.rpc('extension_set_enabled', {
      p_institution_id: INSTITUTION.A, p_extension_key: 'example', p_enabled: true,
    });
    assert.equal(error, null);
  });

  after(async () => {
    const { client } = await signInAs('platform.admin@example.test');
    await client.rpc('extension_set_enabled', { p_institution_id: INSTITUTION.A, p_extension_key: 'example', p_enabled: false });
    adminSql(`delete from ext_example.notes where body = '${BODY}'`);
  });

  it('staff cannot switch an extension on', async () => {
    const { client } = await signInAs('b.member@example.test');
    const { error } = await client.rpc('extension_set_enabled', {
      p_institution_id: INSTITUTION.B, p_extension_key: 'example', p_enabled: true,
    });
    assert.equal(error?.message, 'permission_denied');
  });

  it('A (extension on) adds and lists a note', async () => {
    const { client } = await signInAs('a.member@example.test');
    const added = await client.rpc('ext_example_note_add', { p_body: BODY });
    assert.equal(added.error, null);
    const list = await client.rpc('ext_example_notes_list');
    assert.equal(list.error, null);
    assert.ok(list.data.some((n) => n.body === BODY));
  });

  it('B (extension off) gets extension_disabled and sees none of A\'s notes', async () => {
    const { client } = await signInAs('b.member@example.test');
    const added = await client.rpc('ext_example_note_add', { p_body: 'x' });
    assert.equal(added.error?.message, 'extension_disabled');
    const list = await client.rpc('ext_example_notes_list');
    assert.deepEqual(list.data, []);
  });

  it('the core keeps working for B', async () => {
    const { client } = await signInAs('b.member@example.test');
    const { data, error } = await client.rpc('settings_get_all');
    assert.equal(error, null);
    assert.ok(data.values);
  });

  it('staff cannot read the audit log or the event log before permissions exist', async () => {
    const { client } = await signInAs('a.member@example.test');
    const audit = await client.from('audit_log').select('id');
    const events = await client.from('domain_events').select('id');
    assert.deepEqual(audit.data, []);
    assert.deepEqual(events.data, []);
  });
});
