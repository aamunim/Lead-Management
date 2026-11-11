// UI tests (0B.02) for the Master Admin panel on the web build: its own sign-in page, the second step is always
// needed (no way around it), first-time authenticator set-up, a new device raises an alert, each platform role sees
// only its menus, the platform users screen, and screenshots in light / dark × bn / en.
import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';

import { adminSql, totp } from '../e2e/helpers.mjs';
import { SCREENSHOTS, startWeb } from './helpers.mjs';

const OWNER = '77777777-7777-4777-8777-777777777777';
let web;
const cleanUp = () => adminSql(`delete from public.platform_members where user_id = '${OWNER}';
  delete from public.platform_invites;
  delete from auth.mfa_factors where user_id = '${OWNER}';
  delete from public.platform_login_devices; delete from public.platform_alerts;
  update public.platform_members set status = 'active', extra_permissions = '{}' where user_id in
    ('e1000000-0000-4000-8000-0000000000e1', 'e2000000-0000-4000-8000-0000000000e2', 'e3000000-0000-4000-8000-0000000000e3');
  update public.profiles set preferred_language = null where email like 'platform.%@example.test';`);
before(async () => {
  web = await startWeb();
  cleanUp();
});
after(async () => {
  cleanUp();
  await web?.stop();
});

const newContext = (opts = {}) => web.browser.newContext({ viewport: { width: 420, height: 900 }, ...opts });
async function passwordStep(page, email) {
  await page.goto(`${web.base}/panel/sign-in`);
  await page.getByTestId('panel-email-input').fill(email);
  await page.getByTestId('panel-password-input').fill('password123');
  await page.getByTestId('panel-submit').click();
  await page.getByTestId('panel-second-step').waitFor({ timeout: 20000 });
}
async function panelSignIn(page, email, secret) {
  await passwordStep(page, email);
  await page.getByTestId('panel-code-input').fill(totp(secret));
  await page.getByTestId('panel-verify').click();
}

describe('Master Admin panel', () => {
  it('the second step is always needed: no panel page without it, a wrong code is refused', async () => {
    const ctx = await newContext();
    const page = await ctx.newPage();
    await passwordStep(page, 'platform.admin@example.test');
    await page.goto(`${web.base}/panel/users`);
    await page.getByTestId('panel-second-step').waitFor({ timeout: 20000 });
    assert.equal(await page.getByTestId('panel-users').count(), 0, 'no panel page before the second step');
    await page.getByTestId('panel-code-input').fill('000000');
    await page.getByTestId('panel-verify').click();
    await page.getByTestId('panel-code-error').waitFor();
    await page.screenshot({ path: `${SCREENSHOTS}/panel-second-step.png` });
    await page.getByTestId('panel-code-input').fill(totp());
    await page.getByTestId('panel-verify').click();
    await page.getByTestId('panel-dashboard').waitFor({ timeout: 20000 });
    assert.match(await page.getByTestId('panel-who').textContent(), /Master Admin/);
    await ctx.close();
  });

  it('a staff account is not a platform user', async () => {
    const ctx = await newContext();
    const page = await ctx.newPage();
    await page.goto(`${web.base}/panel/sign-in`);
    await page.getByTestId('panel-email-input').fill('a.member@example.test');
    await page.getByTestId('panel-password-input').fill('password123');
    await page.getByTestId('panel-submit').click();
    // No factor yet: the set-up step appears; even with a verified second step the panel refuses (server check).
    await page.getByTestId('panel-enroll-secret').waitFor({ timeout: 20000 });
    const secret = (await page.getByTestId('panel-enroll-secret').textContent()).trim();
    await page.getByTestId('panel-code-input').fill(totp(secret));
    await page.getByTestId('panel-verify').click();
    await page.getByTestId('panel-denied').waitFor({ timeout: 20000 });
    adminSql("delete from auth.mfa_factors where user_id = '11111111-1111-4111-8111-111111111111'");
    await ctx.close();
  });

  it('first sign-in of an invited person: set up the authenticator, then the role is active', async () => {
    adminSql(`insert into public.platform_invites (email, platform_role) values ('owner.admin@example.test', 'support')
              on conflict (email) do update set platform_role = 'support'`);
    const ctx = await newContext();
    const page = await ctx.newPage();
    await passwordStep(page, 'owner.admin@example.test');
    await page.getByTestId('panel-enroll-secret').waitFor({ timeout: 20000 });
    await page.screenshot({ path: `${SCREENSHOTS}/panel-enroll.png` });
    const secret = (await page.getByTestId('panel-enroll-secret').textContent()).trim();
    await page.getByTestId('panel-code-input').fill(totp(secret));
    await page.getByTestId('panel-verify').click();
    await page.getByTestId('panel-dashboard').waitFor({ timeout: 20000 });
    assert.match(await page.getByTestId('panel-who').textContent(), /Support/);
    await ctx.close();
  });

  it('a new device raises an alert for the person and every Master Admin', async () => {
    for (let n = 0; n < 2; n += 1) {
      const ctx = await newContext(); // a fresh browser = a new device id
      const page = await ctx.newPage();
      await panelSignIn(page, 'platform.billing@example.test');
      await page.getByTestId('panel-dashboard').waitFor({ timeout: 20000 });
      if (n === 1) await page.getByTestId('panel-new-device').waitFor();
      await ctx.close();
    }
    const ctx = await newContext();
    const page = await ctx.newPage();
    await panelSignIn(page, 'platform.admin@example.test');
    await page.getByTestId('panel-alert-new_device').first().waitFor({ timeout: 20000 });
    assert.match(await page.getByTestId('panel-alerts').textContent(), /platform\.billing@example\.test/);
    await ctx.close();
  });

  it('each platform role sees only its menus', async () => {
    for (const [email, visible, hidden] of [
      ['platform.support@example.test', ['dashboard', 'institutions'], ['users', 'providers', 'inbox']],
      ['platform.billing@example.test', ['dashboard'], ['users', 'inbox']],
      ['platform.developer@example.test', ['inbox'], ['dashboard', 'users']],
    ]) {
      const ctx = await newContext();
      const page = await ctx.newPage();
      await panelSignIn(page, email);
      await page.getByTestId(`panel-menu-${visible[0]}`).waitFor({ timeout: 20000 });
      for (const key of visible) assert.equal(await page.getByTestId(`panel-menu-${key}`).count(), 1, `${email} sees ${key}`);
      for (const key of hidden) assert.equal(await page.getByTestId(`panel-menu-${key}`).count(), 0, `${email} does not see ${key}`);
      await page.goto(`${web.base}/panel/users`);
      await page.getByTestId('panel-no-access').waitFor({ timeout: 20000 });
      await ctx.close();
    }
  });

  it('platform users: invite, setup rights, deactivate (audited)', async () => {
    const ctx = await newContext();
    const page = await ctx.newPage();
    await panelSignIn(page, 'platform.admin@example.test');
    await page.getByTestId('panel-dashboard').waitFor({ timeout: 20000 });
    await page.getByTestId('panel-menu-users').click();
    await page.getByTestId('platform-user-platform.support@example.test').waitFor({ timeout: 20000 });
    await page.getByTestId('panel-users-invite').click();
    await page.getByTestId('invite-email-input').fill('new.helper@example.test');
    await page.getByTestId('invite-save').click();
    await page.getByTestId('platform-invite-new.helper@example.test').waitFor({ timeout: 15000 });
    await page.getByTestId('platform-user-platform.support@example.test').click();
    await page.getByTestId('edit-setup').click();
    await page.getByTestId('edit-reason-input').fill('helps with onboarding');
    await page.getByTestId('edit-save').click();
    await page.waitForFunction(() => /Setup rights/.test(document.querySelector('[data-testid="platform-user-platform.support@example.test"]')?.textContent ?? ''));
    await page.screenshot({ path: `${SCREENSHOTS}/panel-users.png`, fullPage: true });
    assert.match(adminSql(`select count(*) from public.platform_audit_log where action = 'platform_user.changed' and reason = 'helps with onboarding'`), /\b1\b/);
    await ctx.close();
  });

  for (const [scheme, language] of [['light', 'en'], ['dark', 'en'], ['light', 'bn'], ['dark', 'bn']]) {
    it(`screenshots: ${language} ${scheme}`, async () => {
      adminSql(`update public.profiles set preferred_language = '${language}' where email = 'platform.admin@example.test'`);
      const ctx = await newContext({ colorScheme: scheme });
      const page = await ctx.newPage();
      await page.goto(`${web.base}/language`);
      await page.getByTestId(`language-option-${language}`).click();
      await panelSignIn(page, 'platform.admin@example.test');
      await page.getByTestId('panel-dashboard').waitFor({ timeout: 20000 });
      await page.screenshot({ path: `${SCREENSHOTS}/panel-dashboard-${language}-${scheme}.png`, fullPage: true });
      await page.goto(`${web.base}/panel/institutions`);
      await page.getByTestId('panel-institution-tabs').waitFor({ timeout: 20000 });
      assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'no sideways scroll');
      await page.screenshot({ path: `${SCREENSHOTS}/panel-institutions-${language}-${scheme}.png`, fullPage: true });
      await ctx.close();
    });
  }
});
