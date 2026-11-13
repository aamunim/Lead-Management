// UI tests (0B.11) on the web build with the local Supabase: the Master Admin adds a connection for an institution,
// sets its key (only the hint is ever shown), marks the live test and sees the change log; the Providers page lists the
// catalog; the institution sees status only (no keys, no settings).
import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';

import { INSTITUTION, adminSql, totp } from '../e2e/helpers.mjs';
import { SCREENSHOTS, startWeb } from './helpers.mjs';

let web;
const KEY = 'qqqqqqqqqqqq7777'; // a made-up key for the test
const cleanUp = () => adminSql(`delete from public.platform_login_devices; delete from public.platform_alerts;
  delete from vault.secrets where id in (select vault_id from public.institution_secrets where institution_id = '${INSTITUTION.A}' and secret_ref like 'conn.%');
  delete from public.institution_secrets where institution_id = '${INSTITUTION.A}' and secret_ref like 'conn.%';
  delete from public.integration_connections where institution_id = '${INSTITUTION.A}';
  delete from public.integration_audit where institution_id = '${INSTITUTION.A}';`);
before(async () => {
  web = await startWeb();
  cleanUp();
});
after(async () => {
  cleanUp();
  await web?.stop();
});

async function panelSignIn(page) {
  await page.goto(`${web.base}/panel/sign-in`);
  await page.getByTestId('panel-email-input').fill('platform.admin@example.test');
  await page.getByTestId('panel-password-input').fill('password123');
  await page.getByTestId('panel-submit').click();
  await page.getByTestId('panel-second-step').waitFor({ timeout: 20000 });
  await page.getByTestId('panel-code-input').fill(totp());
  await page.getByTestId('panel-verify').click();
  await page.getByTestId('panel-dashboard').waitFor({ timeout: 20000 });
}

describe('Integration hub', () => {
  it('Master Admin: add a connection, set its key (hint only), live test, change log; Providers catalog', async () => {
    const ctx = await web.browser.newContext({ viewport: { width: 420, height: 900 } });
    const page = await ctx.newPage();
    await panelSignIn(page);
    await page.goto(`${web.base}/panel/providers`);
    await page.getByTestId('provider-custom_http_sms').waitFor({ timeout: 20000 });
    await page.screenshot({ path: `${SCREENSHOTS}/panel-providers.png`, fullPage: true });

    await page.goto(`${web.base}/panel/institution/${INSTITUTION.A}`);
    await page.getByTestId('institution-tab-integrations').click();
    await page.getByTestId('integrations-add').click();
    await page.getByTestId('connection-provider-open').click();
    await page.getByTestId('connection-provider-custom_http_sms').click();
    await page.getByTestId('connection-label-input').fill('Main SMS');
    await page.getByTestId('connection-mode-live').click();
    await page.getByTestId('connection-setting-send_url-input').fill('https://sms.example.test/send');
    await page.getByTestId('connection-setting-sender_id-input').fill('ACME');
    await page.getByTestId('connection-save').click();
    await page.getByTestId('connection-Main SMS').waitFor({ timeout: 20000 });

    await page.getByTestId('connection-Main SMS').click();
    await page.getByTestId('secret-field-api_key').click();
    await page.getByTestId('secret-value-input').fill(KEY);
    await page.getByTestId('secret-save').click();
    await page.getByTestId('connection-Main SMS').getByText(/qqqq…7777/).waitFor({ timeout: 20000 });
    assert.doesNotMatch(await page.content(), new RegExp(KEY), 'the key itself is never on the page');

    await page.getByTestId('connection-Main SMS').click();
    await page.getByTestId('connection-live-test').click();
    await page.getByTestId('integrations-audit').getByText(/Live test passed/).waitFor({ timeout: 20000 });
    await page.screenshot({ path: `${SCREENSHOTS}/panel-integrations.png`, fullPage: true });
    assert.match(adminSql(`select count(*) from public.integration_audit where institution_id = '${INSTITUTION.A}'`), /\b[3-9]\b/);
    await ctx.close();
  });

  it('the institution sees status only', async () => {
    const ctx = await web.browser.newContext({ viewport: { width: 400, height: 900 } });
    const page = await ctx.newPage();
    await page.goto(`${web.base}/sign-in`);
    await page.getByTestId('sign-in-email-input').fill('owner.admin@example.test');
    await page.getByTestId('sign-in-password-input').fill('password123');
    await page.getByTestId('sign-in-submit').click();
    await page.getByTestId('home').waitFor({ timeout: 20000 });
    await page.goto(`${web.base}/admin/connections`);
    await page.getByTestId('connection-sms-1').waitFor({ timeout: 20000 });
    const html = await page.content();
    assert.doesNotMatch(html, /qqqq|sms\.example\.test/, 'no key hint and no settings for the institution');
    await page.screenshot({ path: `${SCREENSHOTS}/connections-status.png`, fullPage: true });
    await ctx.close();
  });
});
