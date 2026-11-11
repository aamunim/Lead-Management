// UI tests (0B.05) on the web build with the local Supabase: Settings → Modules (turning a module off removes it from
// the menus and keeps its data), Settings → Plan and usage, the limit banner at 80 % / 100 % (numbers and Upgrade for
// people who see the plan, "tell your Admin" for everyone else), screenshots light / dark × bn / en.
import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';

import { INSTITUTION, adminSql } from '../e2e/helpers.mjs';
import { SCREENSHOTS, startWeb } from './helpers.mjs';

let web;
const cleanUp = () => adminSql(`delete from public.institution_modules where institution_id = '${INSTITUTION.A}';
  update public.institution_plan set limit_overrides = '{}' where institution_id = '${INSTITUTION.A}';
  delete from public.app_settings where institution_id = '${INSTITUTION.A}' and key = 'branches_enabled';
  update public.profiles set preferred_language = null where email = 'owner.admin@example.test';
  select app.bump_settings_version('${INSTITUTION.A}');`);
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

describe('Modules, plan and limits', () => {
  it('role matrix: staff without the permissions see neither entry', async () => {
    const page = await newPage();
    await signIn(page, 'a.member@example.test');
    await page.getByTestId('tab-settings').click();
    await page.getByTestId('settings-empty').waitFor();
    assert.equal(await page.getByTestId('settings-modules').count(), 0);
    assert.equal(await page.getByTestId('settings-plan').count(), 0);
    await page.close();
  });

  it('turning the branches module off removes Branches from Settings; on again brings it back', async () => {
    adminSql(`insert into public.app_settings (institution_id, key, value) values ('${INSTITUTION.A}', 'branches_enabled', 'true')
      on conflict (institution_id, key) do update set value = excluded.value; select app.bump_settings_version('${INSTITUTION.A}');`);
    const page = await newPage();
    await signIn(page, 'owner.admin@example.test');
    await page.getByTestId('tab-settings').click();
    await page.getByTestId('settings-branches').waitFor({ timeout: 20000 });
    await page.getByTestId('settings-modules').click();
    await page.getByTestId('module-leads').waitFor({ timeout: 20000 });
    assert.equal(await page.getByTestId('module-leads').getAttribute('aria-disabled'), 'true', 'core leads cannot be turned off');
    await page.getByTestId('module-branches').click();
    await page.getByTestId('module-confirm').waitFor();
    await page.screenshot({ path: `${SCREENSHOTS}/modules-off-sheet.png`, fullPage: true });
    await page.getByTestId('module-confirm').click();
    await page.getByTestId('module-sheet').waitFor({ state: 'hidden', timeout: 15000 });
    assert.match(adminSql(`select app.module_enabled('${INSTITUTION.A}', 'branches', 0)`), /\bf\b/);
    await page.goto(`${web.base}/settings`);
    await page.getByTestId('settings-modules').waitFor({ timeout: 20000 });
    assert.equal(await page.getByTestId('settings-branches').count(), 0, 'Branches is gone from Settings');
    await page.getByTestId('settings-modules').click();
    await page.getByTestId('module-branches').click();
    await page.getByTestId('module-confirm').click();
    await page.getByTestId('module-sheet').waitFor({ state: 'hidden', timeout: 15000 });
    await page.goto(`${web.base}/settings`);
    await page.getByTestId('settings-branches').waitFor({ timeout: 20000 });
    await page.close();
  });

  it('limit banner: numbers and Upgrade for the Admin, "tell your Admin" for staff; the plan screen shows usage', async () => {
    adminSql(`update public.institution_plan set limit_overrides = jsonb_build_object('users', app.usage_of('${INSTITUTION.A}', 'users'))
      where institution_id = '${INSTITUTION.A}';`);
    const page = await newPage();
    await signIn(page, 'owner.admin@example.test');
    await page.getByTestId('limit-banner').waitFor({ timeout: 20000 });
    assert.ok(await page.getByTestId('limit-users').isVisible());
    await page.screenshot({ path: `${SCREENSHOTS}/limit-banner-admin.png`, fullPage: true });
    await page.getByTestId('limit-upgrade').click();
    await page.getByTestId('usage-users').waitFor({ timeout: 20000 });
    assert.match(await page.getByTestId('usage-users').textContent(), /Limit reached/);
    await page.close();
    const staff = await newPage();
    await signIn(staff, 'a.member@example.test');
    await staff.getByTestId('limit-banner').waitFor({ timeout: 20000 });
    assert.match(await staff.getByTestId('limit-banner').textContent(), /Tell your Admin/);
    assert.equal(await staff.getByTestId('limit-upgrade').count(), 0);
    await staff.close();
  });

  for (const [scheme, language] of [['light', 'en'], ['dark', 'en'], ['light', 'bn'], ['dark', 'bn']]) {
    it(`screenshots: ${language} ${scheme}`, async () => {
      adminSql(`update public.institution_plan set limit_overrides = jsonb_build_object('users', app.usage_of('${INSTITUTION.A}', 'users') + 1)
          where institution_id = '${INSTITUTION.A}';
        update public.profiles set preferred_language = '${language}' where email = 'owner.admin@example.test'`);
      const page = await newPage({ colorScheme: scheme });
      await page.goto(`${web.base}/language`);
      await page.getByTestId(`language-option-${language}`).click();
      await signIn(page, 'owner.admin@example.test');
      await page.getByTestId('limit-banner').waitFor({ timeout: 20000 });
      await page.screenshot({ path: `${SCREENSHOTS}/home-limit-${language}-${scheme}.png`, fullPage: true });
      for (const path of ['/admin/modules', '/admin/plan']) {
        await page.goto(`${web.base}${path}`);
        await page.getByTestId(path === '/admin/modules' ? 'module-leads' : 'usage-users').waitFor({ timeout: 20000 });
        assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), `no sideways scroll on ${path}`);
        await page.screenshot({ path: `${SCREENSHOTS}/${path.slice(7)}-${language}-${scheme}.png`, fullPage: true });
      }
      await page.close();
    });
  }
});
