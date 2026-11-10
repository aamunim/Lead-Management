// 0A.12 end-to-end through the real API: renaming a word for one institution (no code change, no migration).
import assert from 'node:assert/strict';
import { after, describe, it } from 'node:test';

import { INSTITUTION, adminSql, signInAs } from './helpers.mjs';

describe('label dictionary through the real API', () => {
  after(() => {
    adminSql(`delete from public.institution_labels where institution_id = '${INSTITUTION.A}'`);
  });

  it('A member gets the education words by default', async () => {
    const { client } = await signInAs('a.member@example.test');
    const { data, error } = await client.rpc('labels_get');
    assert.equal(error, null);
    assert.equal(data.labels.client.resolved.en_singular, 'Student');
    assert.equal(data.labels.client.resolved.bn_forms.plural_oblique, 'শিক্ষার্থীদের');
    assert.equal(Object.keys(data.labels).length, 41);
  });

  it('staff cannot rename words before permissions exist', async () => {
    const { client } = await signInAs('a.member@example.test');
    const { error } = await client.rpc('label_set', { p_key: 'client', p_en_singular: 'Trainee', p_en_plural: 'Trainees', p_bn_forms: { base: 'প্রশিক্ষণার্থী' } });
    assert.equal(error?.message, 'permission_denied');
  });

  it('renaming client → Trainee for A changes A\'s words (and the module name), not B\'s', async () => {
    const admin = await signInAs('platform.admin@example.test');
    const set = await admin.client.rpc('label_set', {
      p_key: 'client', p_en_singular: 'Trainee', p_en_plural: 'Trainees', p_bn_forms: { base: 'প্রশিক্ষণার্থী' }, p_institution_id: INSTITUTION.A,
    });
    assert.equal(set.error, null);
    const a = await signInAs('a.member@example.test');
    const labels = (await a.client.rpc('labels_get')).data.labels;
    assert.equal(labels.client.resolved.en_plural, 'Trainees');
    assert.equal(labels.client.resolved.bn_forms.plural_oblique, 'প্রশিক্ষণার্থীদের');
    assert.equal(labels['module.clients'].resolved.en_singular, 'Trainees');
    const b = await signInAs('b.member@example.test');
    assert.equal((await b.client.rpc('labels_get')).data.labels.client.resolved.en_singular, 'Student');
  });

  it('a word too long for menus is refused with a contract error', async () => {
    const admin = await signInAs('platform.admin@example.test');
    const { error } = await admin.client.rpc('label_set', {
      p_key: 'module.leaderboard', p_en_singular: 'The Most Outstanding Performers', p_en_plural: 'x', p_bn_forms: { base: 'x' }, p_institution_id: INSTITUTION.A,
    });
    assert.equal(error?.message, 'label_too_long');
  });
});
