// 0A.10 end-to-end through the real API: each person's own language, the institution default, and the fallback.
import assert from 'node:assert/strict';
import { after, describe, it } from 'node:test';

import { INSTITUTION, adminSql, signInAs } from './helpers.mjs';

describe('UI language through the real API', () => {
  after(async () => {
    adminSql(`update public.profiles set preferred_language = null
              where email in ('a.member@example.test', 'b.member@example.test')`);
    adminSql(`delete from public.app_settings where key = 'default_language' and institution_id = '${INSTITUTION.A}'`);
  });

  it('with nothing chosen the language is English', async () => {
    const { client } = await signInAs('b.member@example.test');
    const { data, error } = await client.rpc('my_language');
    assert.equal(error, null);
    assert.equal(data.language, 'en');
  });

  it('the institution default applies, and the person\'s own choice wins over it', async () => {
    const admin = await signInAs('platform.admin@example.test');
    const set = await admin.client.rpc('setting_set', { p_key: 'default_language', p_value: 'bn', p_institution_id: INSTITUTION.A });
    assert.equal(set.error, null);
    const { client } = await signInAs('a.member@example.test');
    assert.equal((await client.rpc('my_language')).data.language, 'bn');
    const mine = await client.rpc('set_my_language', { p_language: 'en' });
    assert.equal(mine.error, null);
    assert.equal(mine.data.language, 'en');
    assert.equal((await client.rpc('set_my_language', { p_language: null })).data.language, 'bn');
  });

  it('B is not affected by A\'s default', async () => {
    const { client } = await signInAs('b.member@example.test');
    assert.equal((await client.rpc('my_language')).data.language, 'en');
  });

  it('an unsupported language is refused with a contract error', async () => {
    const { client } = await signInAs('a.member@example.test');
    const { error } = await client.rpc('set_my_language', { p_language: 'fr' });
    assert.equal(error?.message, 'language_unsupported');
  });
});
