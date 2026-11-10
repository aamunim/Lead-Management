// 0A.08 end-to-end through real PostgREST: x-settings-version on responses, min_app_version enforcement, and a
// change becoming visible to another signed-in device on its next request.
import { createClient } from '@supabase/supabase-js';
import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';

import { adminSql, API_URL, INSTITUTION, PUBLIC_KEY, SEED_PASSWORD } from './helpers.mjs';

const KEY = 'e2e.followup_days';

/** A signed-in "device": a client whose fetch records the last x-settings-version and can send x-app-version. */
async function device(email, appVersion = '0.1.0') {
  const seen = { version: null };
  const client = createClient(API_URL, PUBLIC_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: {
      fetch: async (input, init) => {
        const headers = new Headers(init?.headers);
        headers.set('x-app-version', appVersion);
        const response = await fetch(input, { ...init, headers });
        const v = response.headers.get('x-settings-version');
        if (v) seen.version = Number(v);
        return response;
      },
    },
  });
  const { error } = await client.auth.signInWithPassword({ email, password: SEED_PASSWORD });
  assert.equal(error, null);
  return { client, seen };
}

describe('settings through the real API', () => {
  before(() => {
    adminSql(`update public.profiles set last_active_institution_id = null where email like '%@example.test';
      insert into public.setting_definitions (key, scope, schema, default_value, area, description)
      values ('${KEY}', 'institution', '{"type":"integer","minimum":1,"maximum":30}', '3', 'settings.followups', 'e2e')
      on conflict (key) do nothing;`);
  });
  after(() => {
    adminSql(`delete from public.app_settings where key = '${KEY}'; delete from public.setting_definitions where key = '${KEY}';
      delete from public.product_settings where key = 'min_app_version';`);
  });

  it('every response carries x-settings-version for the active institution', async () => {
    const a = await device('a.member@example.test');
    const { data, error } = await a.client.rpc('settings_get_all');
    assert.equal(error, null);
    assert.equal(data.values[KEY], 3);
    assert.equal(a.seen.version, data.settings_version);
    // also on plain table reads
    a.seen.version = null;
    await a.client.from('institutions').select('id');
    assert.equal(typeof a.seen.version, 'number');
  });

  it('a change is visible to another signed-in device on its next request (no restart)', async () => {
    const phone = await device('a.member@example.test');
    const laptop = await device('a.member@example.test');
    const { data: before } = await phone.client.rpc('settings_get_all');
    const admin = await device('platform.admin@example.test');
    const set = await admin.client.rpc('setting_set', { p_key: KEY, p_value: 12, p_institution_id: INSTITUTION.A });
    assert.equal(set.error, null);
    // any next request of the laptop reveals the newer version …
    await laptop.client.from('institutions').select('id');
    assert.ok(laptop.seen.version > before.settings_version, 'newer settings_version seen on the next request');
    // … and the reload returns the new value
    const { data: after } = await laptop.client.rpc('settings_get_all');
    assert.equal(after.values[KEY], 12);
  });

  it('invalid values are rejected with a field-level message', async () => {
    const admin = await device('platform.admin@example.test');
    const { error } = await admin.client.rpc('setting_set', { p_key: KEY, p_value: 99, p_institution_id: INSTITUTION.A });
    assert.equal(error?.message, 'setting_invalid');
    assert.match(error?.details ?? '', /maximum of 30/);
  });

  it('an app older than min_app_version gets upgrade_required on any request', async () => {
    const admin = await device('platform.admin@example.test', '9.9.9');
    const set = await admin.client.rpc('product_setting_set', { p_key: 'min_app_version', p_value: '0.2.0' });
    assert.equal(set.error, null);
    const oldApp = await device('a.member@example.test', '0.1.0');
    const read = await oldApp.client.from('institutions').select('id');
    assert.equal(read.error?.message, 'upgrade_required');
    const newApp = await device('a.member@example.test', '0.2.0');
    const ok = await newApp.client.from('institutions').select('id');
    assert.equal(ok.error, null);
  });
});
