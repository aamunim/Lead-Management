// UI tests (0B.04) on the web build with the local Supabase: Settings → Institution type. Role matrix, choosing a
// mixed type with a word conflict in the preview, applying, reset of own words to the profile defaults with a
// preview, and screenshots in light / dark × bn / en.
import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';

import { INSTITUTION, adminSql } from '../e2e/helpers.mjs';
import { SCREENSHOTS, startWeb } from './helpers.mjs';

let web;
let rolesBefore = '';
const cleanUp = () => adminSql(`delete from public.seeded_items where institution_id = '${INSTITUTION.A}';
  delete from public.institution_profiles where institution_id = '${INSTITUTION.A}';
  delete from public.institution_labels where institution_id = '${INSTITUTION.A}';
  delete from public.role_permissions rp using public.roles r where rp.role_id = r.id and r.institution_id = '${INSTITUTION.A}'
    and r.id::text <> all (string_to_array('${rolesBefore}', ','))
    and not exists (select 1 from public.role_assignments ra where ra.role_id = r.id);
  delete from public.roles r where r.institution_id = '${INSTITUTION.A}' and r.id::text <> all (string_to_array('${rolesBefore}', ','))
    and not exists (select 1 from public.role_assignments ra where ra.role_id = r.id);
  update public.profiles set preferred_language = null where email = 'owner.admin@example.test';
  select app.bump_settings_version('${INSTITUTION.A}');`);
before(async () => {
  web = await startWeb();
  rolesBefore = adminSql(`select string_agg(id::text, ',') from public.roles where institution_id = '${INSTITUTION.A}'`)
    .match(/[0-9a-f]{8}-[0-9a-f-]{27}(,[0-9a-f]{8}-[0-9a-f-]{27})*/)[0];
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

describe('Settings → Institution type', () => {
  it('role matrix: staff without the permission do not see it', async () => {
    const page = await newPage();
    await signIn(page, 'a.member@example.test');
    await page.getByTestId('tab-settings').click();
    await page.getByTestId('settings-empty').waitFor();
    assert.equal(await page.getByTestId('settings-types').count(), 0);
    await page.close();
  });

  it('mixed school + coaching: the word conflict is chosen in the preview, then applied', async () => {
    const page = await newPage();
    await signIn(page, 'owner.admin@example.test');
    await page.getByTestId('tab-settings').click();
    await page.getByTestId('settings-types').click();
    await page.getByTestId('types-none').waitFor({ timeout: 20000 });
    await page.getByTestId('types-option-school').click();
    await page.getByTestId('types-option-coaching').click();
    await page.getByTestId('types-preview').click();
    await page.getByTestId('types-conflict-offering').waitFor({ timeout: 15000 });
    await page.getByTestId('types-conflict-offering-coaching').click();
    // The preview is fetched again with the choice: the word for "offering" becomes the coaching one.
    await page.getByTestId('types-area-labels').click();
    await page.waitForFunction(() => /Course/.test(document.querySelector('[data-testid="types-item-labels-offering"]')?.textContent ?? ''),
      null, { timeout: 15000 });
    await page.screenshot({ path: `${SCREENSHOTS}/types-preview.png`, fullPage: true });
    await page.getByTestId('types-reason-input').fill('school with coaching batches');
    await page.getByTestId('types-apply').click();
    await page.getByTestId('confirm-ok').click();
    await page.getByTestId('type-coaching').waitFor({ timeout: 20000 });
    assert.match(adminSql(`select string_agg(profile_key, ',' order by position) from public.institution_profiles where institution_id = '${INSTITUTION.A}'`),
      /school,coaching/);
    assert.match(adminSql(`select app.label('${INSTITUTION.A}', 'offering')`), /Course/);
    assert.match(adminSql(`select reason from public.audit_log where institution_id = '${INSTITUTION.A}' and action = 'institution.profiles_applied'
      order by at desc limit 1`), /school with coaching batches/);
    await page.close();
  });

  it('reset own words to the profile defaults: preview first, then confirm', async () => {
    adminSql(`insert into public.institution_labels (institution_id, key, en_singular, en_plural, bn_forms)
      values ('${INSTITUTION.A}', 'cohort', 'Group', 'Groups', app.bn_forms('গ্রুপ', false))
      on conflict (institution_id, key) do update set en_singular = excluded.en_singular;
      select app.bump_settings_version('${INSTITUTION.A}');`);
    const page = await newPage();
    await signIn(page, 'owner.admin@example.test');
    await page.goto(`${web.base}/admin/institution-type`);
    await page.getByTestId('types-reset-settings.terminology').click();
    await page.getByTestId('reset-item-cohort').waitFor({ timeout: 15000 });
    assert.match(await page.getByTestId('reset-item-cohort').textContent(), /Group → Session/);
    await page.screenshot({ path: `${SCREENSHOTS}/types-reset.png`, fullPage: true });
    assert.match(adminSql(`select count(*) from public.institution_labels where institution_id = '${INSTITUTION.A}' and key = 'cohort'`), /\b1\b/,
      'nothing changes before confirming');
    await page.getByTestId('reset-confirm').click();
    await page.getByTestId('reset-sheet').waitFor({ state: 'hidden', timeout: 15000 });
    assert.match(adminSql(`select count(*) from public.institution_labels where institution_id = '${INSTITUTION.A}' and key = 'cohort'`), /\b0\b/);
    await page.close();
  });

  for (const [scheme, language] of [['light', 'en'], ['dark', 'en'], ['light', 'bn'], ['dark', 'bn']]) {
    it(`screenshots: ${language} ${scheme}`, async () => {
      adminSql(`update public.profiles set preferred_language = '${language}' where email = 'owner.admin@example.test'`);
      const page = await newPage({ colorScheme: scheme });
      await page.goto(`${web.base}/language`);
      await page.getByTestId(`language-option-${language}`).click();
      await signIn(page, 'owner.admin@example.test');
      await page.goto(`${web.base}/admin/institution-type`);
      await page.getByTestId('types-choose').waitFor({ timeout: 20000 });
      await page.getByTestId('types-preview').click();
      await page.getByTestId('types-preview-result').waitFor({ timeout: 15000 });
      assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'no sideways scroll');
      await page.screenshot({ path: `${SCREENSHOTS}/types-${language}-${scheme}.png`, fullPage: true });
      await page.close();
    });
  }
});
