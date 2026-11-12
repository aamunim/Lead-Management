// UI tests (0B.07) on the web build with the local Supabase: the institution's status banner (read only) and the full
// export from Settings → Plan and usage (Super Admin), while writes are refused on the server.
import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';

import { INSTITUTION, adminSql } from '../e2e/helpers.mjs';
import { SCREENSHOTS, startWeb } from './helpers.mjs';

let web;
const cleanUp = () => adminSql(`update public.institutions set status = 'active' where id = '${INSTITUTION.A}';
  delete from public.institution_exports where institution_id = '${INSTITUTION.A}';
  update public.profiles set preferred_language = null where email = 'owner.admin@example.test';`);
before(async () => {
  web = await startWeb();
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

describe('Institution lifecycle in the app', () => {
  it('read only: banner on Home, the full export still works, writes are refused', async () => {
    adminSql(`update public.institutions set status = 'read_only' where id = '${INSTITUTION.A}'`);
    const ctx = await web.browser.newContext({ viewport: { width: 400, height: 860 }, acceptDownloads: true });
    const page = await ctx.newPage();
    await signIn(page, 'owner.admin@example.test');
    await page.getByTestId('status-banner-read_only').waitFor({ timeout: 20000 });
    await page.screenshot({ path: `${SCREENSHOTS}/home-read-only.png`, fullPage: true });
    await page.goto(`${web.base}/admin/plan`);
    await page.getByTestId('export-make').click();
    await page.locator('[data-testid^="export-"]:not([data-testid="export-make"])').first().waitFor({ timeout: 20000 });
    const download = page.waitForEvent('download');
    await page.locator('[data-testid^="export-"]:not([data-testid="export-make"])').first().click();
    assert.match((await download).suggestedFilename(), /^export-.*\.json$/);
    // A write from the app is refused with the read-only message.
    await page.goto(`${web.base}/admin/custom-fields`);
    await page.getByTestId('fields-add').click();
    await page.getByTestId('field-en-input').fill('Blocked');
    await page.getByTestId('field-bn-input').fill('বন্ধ');
    await page.getByTestId('field-save').click();
    await page.getByText(/read only/i).first().waitFor({ timeout: 15000 });
    assert.match(adminSql(`select count(*) from public.custom_field_definitions where institution_id = '${INSTITUTION.A}' and key = 'blocked'`), /\b0\b/);
    await ctx.close();
  });
});
