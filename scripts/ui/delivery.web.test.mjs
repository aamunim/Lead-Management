// UI test (0B.12): the Master Admin sends a test through one connection from the Integrations tab (it is queued
// pinned to that connection), and the Delivery log page shows results, fallbacks and the billable ledger.
import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';

import { INSTITUTION, adminSql, totp } from '../e2e/helpers.mjs';
import { SCREENSHOTS, startWeb } from './helpers.mjs';

const CONN = 'c3000000-0000-4000-8000-0000000000a1';
const CONN2 = 'c3000000-0000-4000-8000-0000000000a2';
let web;
const cleanUp = () => adminSql(`delete from public.platform_login_devices; delete from public.platform_alerts;
  delete from public.outbox where institution_id = '${INSTITUTION.A}' and (idempotency_key like 'test:%' or idempotency_key like 'ui-hub-%');
  delete from public.delivery_log where connection_id = '${CONN}';
  delete from public.usage_ledger where provider = 'mock_sms' and institution_id = '${INSTITUTION.A}';
  delete from public.integration_audit where connection_id = '${CONN}';
  delete from public.integration_audit where connection_id = '${CONN2}';
  delete from public.integration_connections where id in ('${CONN}', '${CONN2}');`);
before(async () => {
  web = await startWeb();
  cleanUp();
  adminSql(`insert into public.integration_connections (institution_id, id, kind, provider_key, label, mode, settings, live_test_passed_at)
    values ('${INSTITUTION.A}', '${CONN}', 'sms', 'mock_sms', 'Office SMS', 'live', '{"price_per_part":0.25}', now());
    insert into public.integration_connections (institution_id, id, kind, provider_key, label, mode, settings, priority)
    values ('${INSTITUTION.A}', '${CONN2}', 'sms', 'custom_http_sms', 'New gateway', 'live',
      '{"send_url":"https://sms.example.com/send","sender_id":"ACME","route":"transactional","masking":{"type":"masked","status":"applied"}}', 2);
    insert into public.delivery_log (institution_id, outbox_id, recipient, channel, category, result, connection_id, connection_owner, fallback_from, parts, cost)
    values ('${INSTITUTION.A}', gen_random_uuid(), '01711000123', 'sms', 'notification', 'sent', '${CONN}', 'institution', gen_random_uuid(), 1, 0.25),
           ('${INSTITUTION.A}', gen_random_uuid(), '01711000124', 'sms', 'bulk', 'given_up', '${CONN}', 'institution', null, null, null);
    insert into public.usage_ledger (institution_id, day, provider, channel, category, payer, count, parts, cost)
    values ('${INSTITUTION.A}', current_date, 'mock_sms', 'sms', 'notification', 'platform', 1, 1, 0.25);`);
});
after(async () => {
  cleanUp();
  await web?.stop();
});

describe('Delivery log and the Test button', () => {
  it('Test queues a message pinned to the connection; the delivery log shows results and the ledger', async () => {
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
    await page.getByTestId('connection-Office SMS').click();
    await page.getByTestId('connection-test-to-input').fill('01711000999');
    await page.getByTestId('connection-test-body-input').fill('আপনার ভর্তি নিশ্চিত হয়েছে। অফিসে এসে কাগজপত্র জমা দিন। ধন্যবাদ, ভর্তি অফিস।');
    assert.match(await page.getByTestId('connection-test-parts').innerText(), /2 parts .*Bangla.*cost 0\.5/);
    await page.getByTestId('connection-test-send').click();
    await page.getByText(/Test queued/).waitFor({ timeout: 15000 });
    assert.match(adminSql(`select status || '|' || (payload ->> 'pin_connection') from public.outbox
      where institution_id = '${INSTITUTION.A}' and idempotency_key like 'test:%'`), new RegExp(`queued\\|${CONN}`));

    // Switch gateway (D33 / D34): the new gateway becomes primary in one action; masking status shown.
    await page.goto(`${web.base}/panel/institution/${INSTITUTION.A}`);
    await page.getByTestId('institution-tab-integrations').click();
    assert.match(await page.getByTestId('connection-New gateway').innerText(), /masked sender: applied for/);
    await page.getByTestId('connection-New gateway').click();
    await page.getByTestId('connection-make-primary').click();
    await page.getByText(/now the primary connection/).waitFor({ timeout: 15000 });
    assert.match(adminSql(`select priority from public.integration_connections where id = '${CONN2}'`), /\b1\b/);

    await page.goto(`${web.base}/panel/delivery`);
    await page.getByTestId('delivery-log').getByText('01711000123', { exact: false }).waitFor({ timeout: 20000 });
    const html = await page.getByTestId('delivery-log').innerText();
    assert.match(html, /sent by the backup/);
    assert.match(html, /Given up/);
    assert.match(await page.getByTestId('delivery-ledger').innerText(), /Billable/);
    await page.screenshot({ path: `${SCREENSHOTS}/panel-delivery.png`, fullPage: true });
    await ctx.close();
  });
});
