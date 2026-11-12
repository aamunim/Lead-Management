// UI tests (0B.09) on the web build with the local Supabase: the public "Set up your institution" wizard end to end
// (a new login, Bangla and English, light and dark; every step screenshotted), the result waits for approval with the
// Super Admin signed in; and the Master Admin's "Create institution" with an invitation.
import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';

import { adminSql, totp } from '../e2e/helpers.mjs';
import { SCREENSHOTS, startWeb } from './helpers.mjs';

let web;
const cleanUp = () => adminSql(`delete from public.institutions where name like 'UI Wizard %';
  delete from public.institution_signups where email like 'ui.wizard%@example.test' or user_id in
    (select id from auth.users where email like 'ui.wizard%@example.test');
  delete from auth.users where email like 'ui.wizard%@example.test';`);
before(async () => {
  web = await startWeb();
  cleanUp();
});
after(async () => {
  cleanUp();
  await web?.stop();
});

const newContext = (scheme = 'light') => web.browser.newContext({ viewport: { width: 400, height: 900 }, colorScheme: scheme });
const shot = (page, name) => page.screenshot({ path: `${SCREENSHOTS}/${name}.png`, fullPage: true });

describe('Institution setup wizard', () => {
  for (const [language, scheme] of [['en', 'light'], ['bn', 'dark']]) {
    it(`self sign-up end to end: ${language} ${scheme}`, async () => {
      const ctx = await newContext(scheme);
      const page = await ctx.newPage();
      await page.goto(`${web.base}/language`);
      await page.getByTestId(`language-option-${language}`).click();
      await page.goto(`${web.base}/sign-in`);
      await page.getByTestId('sign-in-setup').click();
      // Only education is open: the wizard starts at the types (step 1 of 4).
      await page.getByTestId('wizard-types').waitFor({ timeout: 20000 });
      assert.match(await page.getByTestId('wizard-step').innerText(), /1.*4|১.*৪/);
      await shot(page, `wizard-1-types-${language}-${scheme}`);
      await page.getByTestId('wizard-type-school').click();
      await page.getByTestId('wizard-type-college').click();
      await page.getByTestId('wizard-next').click();

      await page.getByTestId('wizard-name-input').fill(`UI Wizard ${language} College`);
      await page.getByTestId('wizard-eiin-input').fill('1234567');
      await page.getByTestId('wizard-phone').fill('01711000555');
      await shot(page, `wizard-2-info-${language}-${scheme}`);
      await page.getByTestId('wizard-next').click();

      await page.getByTestId('wizard-admin-name-input').fill('Wizard Principal');
      await page.getByTestId('wizard-admin-email-input').fill(`ui.wizard.${language}@example.test`);
      await page.getByTestId('wizard-admin-password-input').fill('a-long-password-1');
      await shot(page, `wizard-3-admin-${language}-${scheme}`);
      await page.getByTestId('wizard-next').click();

      // Preview: mixed types, the roles part cannot be left out; leave out the custom-field presets.
      await page.getByTestId('wizard-area-roles').waitFor({ timeout: 20000 });
      assert.equal(await page.getByTestId('wizard-area-roles').getAttribute('aria-disabled'), 'true');
      await page.getByTestId('wizard-area-custom_fields').click();
      await shot(page, `wizard-4-preview-${language}-${scheme}`);
      await page.getByTestId('wizard-create').click();
      await page.getByTestId('signup-done').waitFor({ timeout: 30000 });
      await shot(page, `wizard-5-done-${language}-${scheme}`);

      const row = adminSql(`select i.status || '|' || i.eiin || '|' || (select string_agg(profile_key, '+' order by position) from public.institution_profiles p where p.institution_id = i.id)
        || '|' || (select count(*) from public.seeded_items s where s.institution_id = i.id and s.area = 'custom_fields')
        || '|' || (select count(*) from public.role_assignments a join public.roles r on r.institution_id = a.institution_id and r.id = a.role_id
                    where a.institution_id = i.id and r.is_super_admin)
        from public.institutions i where i.name = 'UI Wizard ${language} College'`);
      assert.match(row, /pending\|1234567\|school\+college\|0\|1/);

      // Continue setup: the app opens the new institution with the "waiting for approval" banner.
      await page.getByTestId('signup-continue').click();
      await page.getByTestId('status-banner-pending').waitFor({ timeout: 20000 });
      await ctx.close();
    });
  }

  it('Master Admin creates an institution and invites its Super Admin', async () => {
    const ctx = await newContext();
    const page = await ctx.newPage();
    await page.goto(`${web.base}/panel/sign-in`);
    await page.getByTestId('panel-email-input').fill('platform.admin@example.test');
    await page.getByTestId('panel-password-input').fill('password123');
    await page.getByTestId('panel-submit').click();
    await page.getByTestId('panel-second-step').waitFor({ timeout: 20000 });
    await page.getByTestId('panel-code-input').fill(totp());
    await page.getByTestId('panel-verify').click();
    await page.getByTestId('panel-dashboard').waitFor({ timeout: 20000 });
    await page.goto(`${web.base}/panel/institutions`);
    await page.getByTestId('institutions-create').click();
    await page.getByTestId('wizard-type-coaching').click();
    await page.getByTestId('wizard-next').click();
    await page.getByTestId('wizard-name-input').fill('UI Wizard Panel Coaching');
    await page.getByTestId('wizard-next').click();
    await page.getByTestId('create-admin-email-input').fill('ui.wizard.invitee@example.test');
    await page.getByTestId('create-admin-name-input').fill('Invited Owner');
    await page.getByTestId('wizard-next').click();
    await page.getByTestId('wizard-area-roles').waitFor({ timeout: 20000 });
    await shot(page, 'panel-create-preview');
    await page.getByTestId('create-submit').click();
    await page.getByTestId('overview-invites').waitFor({ timeout: 30000 });
    await page.getByTestId('overview-invite-ui.wizard.invitee@example.test').waitFor();
    assert.match(adminSql(`select status from public.institutions where name = 'UI Wizard Panel Coaching'`), /trial/);
    await ctx.close();
  });
});
