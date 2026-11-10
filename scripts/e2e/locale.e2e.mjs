// 0A.11 end-to-end through the real API: anonymous calls work (regression), server time and locale settings per
// institution, phones stored as ASCII.
import assert from 'node:assert/strict';
import { after, describe, it } from 'node:test';

import { INSTITUTION, adminSql, anonymousClient, signInAs } from './helpers.mjs';

describe('locale through the real API', () => {
  after(() => {
    adminSql(`delete from public.app_settings where key = 'time_zone' and institution_id = '${INSTITUTION.B}'`);
    adminSql(`update public.profiles set phone = null where email = 'a.member@example.test'`);
  });

  it('anonymous calls are not blocked by the request hook (regression found in 0A.11)', async () => {
    const anon = anonymousClient();
    const defaults = await anon.rpc('locale_defaults');
    assert.equal(defaults.error, null);
    assert.equal(defaults.data.time_zone, 'Asia/Dhaka');
    assert.equal(defaults.data.currency.symbol, '৳');
    const time = await anon.rpc('server_time');
    assert.equal(time.error, null);
    assert.ok(Math.abs(Date.parse(time.data.now) - Date.now()) < 60_000);
  });

  it('server_time follows the institution\'s time zone setting', async () => {
    const admin = await signInAs('platform.admin@example.test');
    const set = await admin.client.rpc('setting_set', { p_key: 'time_zone', p_value: 'Europe/London', p_institution_id: INSTITUTION.B });
    assert.equal(set.error, null);
    const b = await signInAs('b.member@example.test');
    assert.equal((await b.client.rpc('server_time')).data.time_zone, 'Europe/London');
    const a = await signInAs('a.member@example.test');
    assert.equal((await a.client.rpc('server_time')).data.time_zone, 'Asia/Dhaka');
  });

  it('an unknown time zone is refused', async () => {
    const admin = await signInAs('platform.admin@example.test');
    const { error } = await admin.client.rpc('setting_set', { p_key: 'time_zone', p_value: 'Mars/Olympus', p_institution_id: INSTITUTION.B });
    assert.equal(error?.message, 'setting_invalid');
  });

  it('a phone saved with Bangla digits is stored as ASCII', async () => {
    const { client, session } = await signInAs('a.member@example.test');
    const update = await client.from('profiles').update({ phone: '+৮৮০ ১৭১১-২২৩৩৪৪' }).eq('user_id', session.user.id);
    assert.equal(update.error, null);
    const { data } = await client.from('profiles').select('phone').eq('user_id', session.user.id).single();
    assert.equal(data.phone, '01711223344');
  });
});
