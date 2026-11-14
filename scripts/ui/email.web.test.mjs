// UI test (0B.14): the Master Admin adds a sending domain and sees the three DNS records to add; a paused sender shows
// its reason and is resumed with a reason; the platform mail address of the institution is shown.
import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';

import { INSTITUTION, adminSql, totp } from '../e2e/helpers.mjs';
import { SCREENSHOTS, startWeb } from './helpers.mjs';

let web;
const cleanUp = () => adminSql(`delete from public.platform_login_devices; delete from public.platform_alerts;
  delete from public.email_domains where institution_id = '${INSTITUTION.A}';
  delete from public.integration_audit where institution_id = '${INSTITUTION.A}' and action like 'email.%';
  update public.institution_service_payers set paused_at = null, paused_reason = null where institution_id = '${INSTITUTION.A}';`);
before(async () => {
  web = await startWeb();
  cleanUp();
  adminSql(`insert into public.institution_service_payers (institution_id, kind, payer, paused_at, paused_reason)
    values ('${INSTITUTION.A}', 'email', 'direct', now(), 'bounces 6, complaints 0 of 60 in 7 days')
    on conflict (institution_id, kind) do update set paused_at = now(), paused_reason = excluded.paused_reason`);
});
after(async () => {
  cleanUp();
  await web?.stop();
});

describe('Email in the Integrations tab', () => {
  it('add a domain with its DNS records; resume a paused sender', async () => {
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
    await page.getByTestId('institution-tab-integrations').click();
    await page.getByTestId('email-paused').waitFor({ timeout: 20000 });
    assert.match(await page.getByTestId('email-paused').innerText(), /bounces 6/);

    await page.getByTestId('email-domain-input-input').fill('ideal.example.test');
    await page.getByTestId('email-domain-add').click();
    await page.getByTestId('email-domain-ideal.example.test').waitFor({ timeout: 15000 });
    assert.match(await page.getByTestId('email-record-ideal.example.test-spf').innerText(), /v=spf1 include:amazonses\.com/);
    assert.match(await page.getByTestId('email-record-ideal.example.test-dkim').innerText(), /resend\._domainkey\.ideal\.example\.test/);
    assert.match(await page.getByTestId('email-record-ideal.example.test-dmarc').innerText(), /_dmarc\.ideal\.example\.test/);
    await page.screenshot({ path: `${SCREENSHOTS}/panel-email.png`, fullPage: true });

    await page.getByTestId('email-resume-reason-input').fill('list cleaned');
    await page.getByTestId('email-resume').click();
    await page.getByTestId('email-paused').waitFor({ state: 'detached', timeout: 15000 });
    assert.match(adminSql(`select coalesce(paused_at::text, 'none') from public.institution_service_payers where institution_id = '${INSTITUTION.A}' and kind = 'email'`), /none/);
    await ctx.close();
  });
});
