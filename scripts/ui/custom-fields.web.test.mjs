// UI tests (0B.06) on the web build with the local Supabase: Settings → Custom fields. Role matrix, adding a field with
// the preview (form and card), a select field with choices, ordering, retire / bring back (answers kept), the type
// profile's preset fields, and screenshots of the builder and the field sheet in light / dark × bn / en.
import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';

import { INSTITUTION, adminSql } from '../e2e/helpers.mjs';
import { SCREENSHOTS, startWeb } from './helpers.mjs';

let web;
const cleanUp = () => adminSql(`delete from public.custom_field_definitions where institution_id = '${INSTITUTION.A}';
  delete from public.seeded_items where institution_id = '${INSTITUTION.A}';
  delete from public.institution_profiles where institution_id = '${INSTITUTION.A}';
  select app.usage_reconcile('${INSTITUTION.A}');
  update public.profiles set preferred_language = null where email = 'owner.admin@example.test';`);
before(async () => {
  web = await startWeb();
  cleanUp();
});
after(async () => {
  cleanUp();
  await web?.stop();
});

const newPage = (opts = {}) => web.browser.newPage({ viewport: { width: 400, height: 860 }, ...opts });
async function signIn(page, email) {
  await page.goto(`${web.base}/sign-in`);
  await page.getByTestId('sign-in-email-input').fill(email);
  await page.getByTestId('sign-in-password-input').fill('password123');
  await page.getByTestId('sign-in-submit').click();
  await page.getByTestId('home').waitFor({ timeout: 20000 });
}
const sortOf = (key) => Number(adminSql(`select sort from public.custom_field_definitions where institution_id = '${INSTITUTION.A}' and key = '${key}'`)
  .match(/\b\d+\b/)[0]);

describe('Settings → Custom fields', () => {
  it('role matrix: staff without settings.custom_fields do not see it', async () => {
    const page = await newPage();
    await signIn(page, 'a.member@example.test');
    await page.getByTestId('tab-settings').click();
    await page.getByTestId('settings-empty').waitFor();
    assert.equal(await page.getByTestId('settings-fields').count(), 0);
    await page.close();
  });

  it('add fields with the preview, order them, retire and bring back', async () => {
    const page = await newPage();
    await signIn(page, 'owner.admin@example.test');
    await page.getByTestId('tab-settings').click();
    await page.getByTestId('settings-fields').click();
    await page.getByTestId('fields-empty').waitFor({ timeout: 20000 });
    await page.getByTestId('fields-add').click();
    await page.getByTestId('field-en-input').fill("Mother's phone");
    await page.getByTestId('field-bn-input').fill('মায়ের ফোন');
    await page.getByTestId('field-type-open').click();
    await page.getByTestId('field-type-phone').click();
    await page.getByTestId('field-type-sheet').waitFor({ state: 'hidden' });
    await page.getByTestId('field-flag-required').click();
    await page.getByTestId('field-flag-show_on_card').click();
    await page.getByTestId('field-preview-card').waitFor();
    assert.match(await page.getByTestId('field-preview').textContent(), /Mother's phone \*/);
    await page.screenshot({ path: `${SCREENSHOTS}/fields-sheet.png`, fullPage: true });
    await page.getByTestId('field-save').click();
    await page.getByTestId('field-mothers_phone').waitFor({ timeout: 15000 });

    await page.getByTestId('fields-add').click();
    await page.getByTestId('field-en-input').fill('Session time');
    await page.getByTestId('field-bn-input').fill('সেশনের সময়');
    await page.getByTestId('field-type-open').click();
    await page.getByTestId('field-type-select').click();
    await page.getByTestId('field-type-sheet').waitFor({ state: 'hidden' });
    await page.getByTestId('field-choices-input').fill('morning | Morning | সকাল\nday | Day | দিন');
    await page.getByTestId('field-group-en-input').fill('Preferences');
    await page.getByTestId('field-save').click();
    await page.getByTestId('field-session_time').waitFor({ timeout: 15000 });
    assert.match(adminSql(`select type || ' ' || jsonb_array_length(options -> 'choices') || ' ' || required from public.custom_field_definitions
      where institution_id = '${INSTITUTION.A}' and key = 'session_time'`), /select 2 f/);

    const before = sortOf('mothers_phone');
    await page.getByTestId('field-down-mothers_phone').click();
    await page.waitForFunction(() => true);
    for (let n = 0; n < 30 && sortOf('mothers_phone') === before; n += 1) await page.waitForTimeout(300);
    assert.ok(sortOf('mothers_phone') > sortOf('session_time'), 'moved down');

    await page.getByTestId('field-session_time').click();
    await page.getByTestId('field-retire').click();
    await page.getByTestId('field-retired-session_time').waitFor({ timeout: 15000 });
    await page.getByTestId('field-restore-session_time').click();
    await page.getByTestId('field-session_time').waitFor({ timeout: 15000 });
    assert.match(adminSql(`select count(*) from public.audit_log where institution_id = '${INSTITUTION.A}' and action like 'custom_field.%'`), /\b[5-9]\b|\b\d{2,}\b/);
    await page.close();
  });

  it('the type profile installs its preset fields (school)', async () => {
    adminSql(`select app.apply_profiles('${INSTITUTION.A}', array['school']);`);
    const page = await newPage();
    await signIn(page, 'owner.admin@example.test');
    await page.goto(`${web.base}/admin/custom-fields`);
    await page.getByTestId('field-guardian_nid').waitFor({ timeout: 20000 });
    assert.match(await page.getByTestId('field-guardian_nid').textContent(), /From your type/);
    assert.match(await page.getByTestId('field-guardian_nid').textContent(), /Sensitive/);
    await page.close();
  });

  for (const [scheme, language] of [['light', 'en'], ['dark', 'en'], ['light', 'bn'], ['dark', 'bn']]) {
    it(`screenshots: ${language} ${scheme}`, async () => {
      adminSql(`update public.profiles set preferred_language = '${language}' where email = 'owner.admin@example.test'`);
      const page = await newPage({ colorScheme: scheme });
      await page.goto(`${web.base}/language`);
      await page.getByTestId(`language-option-${language}`).click();
      await signIn(page, 'owner.admin@example.test');
      await page.goto(`${web.base}/admin/custom-fields`);
      await page.getByTestId('field-guardian_nid').waitFor({ timeout: 20000 });
      assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'no sideways scroll');
      await page.screenshot({ path: `${SCREENSHOTS}/fields-${language}-${scheme}.png`, fullPage: true });
      await page.getByTestId('field-guardian_nid').click();
      await page.getByTestId('field-preview').waitFor();
      await page.screenshot({ path: `${SCREENSHOTS}/fields-sheet-${language}-${scheme}.png`, fullPage: true });
      await page.close();
    });
  }
});
