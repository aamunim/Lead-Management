// UI tests (0B.10) on the web build with the local Supabase: Settings → Setup checklist (tick a manual item, progress),
// Settings → Branding (short name, colour, logo upload) shown in the header and the tab title after sign-in while the
// sign-in page stays neutral; the panel Overview shows the same checklist. Screenshots light / dark × bn / en with a
// long Bangla name.
import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';

import { INSTITUTION, adminSql, totp } from '../e2e/helpers.mjs';
import { SCREENSHOTS, startWeb } from './helpers.mjs';

// A 1×1 PNG.
const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==', 'base64');
let web;
let originalName;
const cleanUp = () => adminSql(`delete from public.platform_login_devices; delete from public.platform_alerts;
  delete from public.app_settings where institution_id = '${INSTITUTION.A}' and key in ('brand_color', 'brand_logo_path');
  delete from public.institution_checklist where institution_id = '${INSTITUTION.A}';
  select set_config('storage.allow_delete_query', 'true', false);
  delete from storage.objects where bucket_id = 'institution-files' and name like '${INSTITUTION.A}/branding/%';
  update public.institutions set name = ${originalName ? `'${originalName.replace(/'/g, "''")}'` : 'name'}, short_name = null where id = '${INSTITUTION.A}';
  update public.profiles set preferred_language = null where email = 'owner.admin@example.test';`);
before(async () => {
  web = await startWeb();
  originalName = adminSql(`select name from public.institutions where id = '${INSTITUTION.A}'`).trim().split('\n').find((l) => l.trim() && !/^-|name|row/.test(l))?.trim();
  cleanUp();
});
after(async () => {
  cleanUp();
  await web?.stop();
});

async function signIn(page, email) {
  await page.goto(`${web.base}/sign-in`);
  await page.getByTestId('sign-in-email-input').fill(email);
  await page.getByTestId('sign-in-password-input').fill('password123');
  await page.getByTestId('sign-in-submit').click();
  await page.getByTestId('home').waitFor({ timeout: 20000 });
}

describe('Setup checklist and branding', () => {
  it('checklist: tick a manual item; the Home card and progress follow', async () => {
    const ctx = await web.browser.newContext({ viewport: { width: 400, height: 900 } });
    const page = await ctx.newPage();
    await signIn(page, 'owner.admin@example.test');
    await page.getByTestId('home-setup-card').waitFor({ timeout: 20000 });
    await page.getByTestId('home-setup-open').click();
    await page.getByTestId('checklist').waitFor({ timeout: 20000 });
    const progress = page.getByTestId('checklist-screen').getByTestId('checklist-progress');
    const before = await progress.innerText();
    await page.getByTestId('checklist-pipeline_words').click();
    await page.waitForFunction((b) => document.querySelector('[data-testid="checklist-screen"] [data-testid="checklist-progress"]')?.textContent !== b, before,
      { timeout: 15000 });
    assert.equal(await page.getByTestId('checklist-pipeline_words').getAttribute('aria-checked'), 'true');
    // A platform item cannot be ticked here.
    assert.notEqual(await page.getByTestId('checklist-payment_merchant').getAttribute('aria-disabled'), 'true');
    assert.equal(await page.getByTestId('checklist-branding').getAttribute('aria-disabled'), 'true');
    await ctx.close();
  });

  it('branding: short name, colour and logo appear after sign-in; the sign-in page stays neutral', async () => {
    const ctx = await web.browser.newContext({ viewport: { width: 400, height: 900 } });
    const page = await ctx.newPage();
    await signIn(page, 'owner.admin@example.test');
    await page.goto(`${web.base}/admin/branding`);
    await page.getByTestId('branding-short-input').fill('IDL');
    await page.getByTestId('branding-color-0F766E').click();
    const chooser = page.waitForEvent('filechooser');
    await page.getByTestId('branding-logo-choose').click();
    await (await chooser).setFiles({ name: 'logo.png', mimeType: 'image/png', buffer: PNG });
    await page.getByTestId('branding-logo-image').waitFor({ timeout: 20000 });
    await page.getByTestId('branding-save').click();
    await page.getByTestId('app-header-logo').waitFor({ timeout: 20000 });
    assert.match(adminSql(`select value from public.app_settings where institution_id = '${INSTITUTION.A}' and key = 'brand_color'`), /#0F766E/);
    assert.equal(await page.title(), (await page.getByTestId('app-header-title').innerText()).trim());
    // The checklist's branding item ticked itself.
    await page.goto(`${web.base}/admin/checklist`);
    await page.getByTestId('checklist').waitFor({ timeout: 20000 });
    assert.equal(await page.getByTestId('checklist-branding').getAttribute('aria-checked'), 'true');
    // Signed out, the sign-in page shows the product, not the institution.
    await page.goto(`${web.base}/profile`);
    await page.getByTestId('profile-signout').click();
    await page.getByTestId('confirm-ok').click();
    await page.getByTestId('sign-in').waitFor({ timeout: 20000 });
    assert.equal(await page.getByTestId('app-header-logo').count(), 0);
    await ctx.close();
  });

  for (const [scheme, language] of [['light', 'en'], ['dark', 'bn']]) {
    it(`screenshots with a long Bangla name: ${language} ${scheme}`, async () => {
      adminSql(`update public.institutions set name = 'ঢাকা আইডিয়াল মডেল কলেজ ও বিশ্ববিদ্যালয় কলেজ শাখা, মিরপুর ১০' where id = '${INSTITUTION.A}';
        update public.profiles set preferred_language = '${language}' where email = 'owner.admin@example.test'`);
      const ctx = await web.browser.newContext({ viewport: { width: 400, height: 900 }, colorScheme: scheme });
      const page = await ctx.newPage();
      await page.goto(`${web.base}/language`);
      await page.getByTestId(`language-option-${language}`).click();
      await signIn(page, 'owner.admin@example.test');
      await page.goto(`${web.base}/admin/checklist`);
      await page.getByTestId('checklist').waitFor({ timeout: 20000 });
      await page.screenshot({ path: `${SCREENSHOTS}/checklist-${language}-${scheme}.png`, fullPage: true });
      await page.goto(`${web.base}/admin/branding`);
      await page.getByTestId('branding-color').waitFor({ timeout: 20000 });
      await page.screenshot({ path: `${SCREENSHOTS}/branding-${language}-${scheme}.png`, fullPage: true });
      await ctx.close();
    });
  }

  it('the panel Overview shows the same checklist', async () => {
    const ctx = await web.browser.newContext({ viewport: { width: 420, height: 900 } });
    const page = await ctx.newPage();
    await page.goto(`${web.base}/panel/sign-in`);
    await page.getByTestId('panel-email-input').fill('platform.admin@example.test');
    await page.getByTestId('panel-password-input').fill('password123');
    await page.getByTestId('panel-submit').click();
    await page.getByTestId('panel-second-step').waitFor({ timeout: 20000 });
    await page.getByTestId('panel-code-input').fill(totp());
    await page.getByTestId('panel-verify').click();
    await page.getByTestId('panel-dashboard').waitFor({ timeout: 20000 });
    await page.goto(`${web.base}/panel/institution/${INSTITUTION.A}`);
    await page.getByTestId('overview-checklist').waitFor({ timeout: 20000 });
    await page.getByTestId('checklist-payment_merchant').click();
    await page.waitForFunction(() => document.querySelector('[data-testid="checklist-payment_merchant"]')?.getAttribute('aria-checked') === 'true',
      null, { timeout: 15000 });
    await page.screenshot({ path: `${SCREENSHOTS}/panel-overview-checklist.png`, fullPage: true });
    await ctx.close();
  });
});
