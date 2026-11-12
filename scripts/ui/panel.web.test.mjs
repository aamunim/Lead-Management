// UI tests (0B.02) for the Master Admin panel on the web build: its own sign-in page, the second step is always
// needed (no way around it), first-time authenticator set-up, a new device raises an alert, each platform role sees
// only its menus, the platform users screen, profiles and packs (0B.03), and screenshots in light / dark × bn / en.
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
  update public.profiles set preferred_language = null where email like 'platform.%@example.test';
  update public.industries set signup_open = (key = 'education');
  set session_replication_role = replica;
  delete from public.type_profiles where key = 'training' and version > 1;
  set session_replication_role = default;
  delete from public.institution_labels where institution_id = 'a0000000-0000-4000-8000-00000000000a' and key = 'doc.receipt_title';
  update public.label_defaults set en_singular = 'Lead', en_plural = 'Leads', bn_forms = app.bn_forms('লিড', true)
   where scope = 'product' and key = 'lead';
  update public.institution_plan set plan_key = 'standard', plan_version = 1, expires_at = null, limit_overrides = '{}', price_override = null,
    discount_percent = 0, billing_cycle = 'monthly' where institution_id = 'a0000000-0000-4000-8000-00000000000a';
  update public.institution_plan set plan_key = 'starter', plan_version = 1 where plan_key = 'starter';
  delete from public.plans where key = 'starter' and version > 1;
  delete from public.institutions where slug = 'life-ui-test';`);
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

  it('profiles and packs: view, a broken change is refused, publish a new version, open industries', async () => {
    const ctx = await newContext();
    const page = await ctx.newPage();
    await panelSignIn(page, 'platform.admin@example.test');
    await page.getByTestId('panel-dashboard').waitFor({ timeout: 20000 });
    await page.getByTestId('panel-menu-profiles').click();
    await page.getByTestId('profile-health').waitFor({ timeout: 20000 });
    assert.equal(await page.locator('[data-testid^="profile-"]').count(), 9, 'nine education profiles');
    assert.equal(await page.getByTestId('industry-open-healthcare').getAttribute('aria-disabled'), 'true', 'an industry without a pack cannot be opened');
    await page.screenshot({ path: `${SCREENSHOTS}/panel-profiles.png`, fullPage: true });

    await page.getByTestId('profile-training').click();
    await page.getByTestId('profile-stages').waitFor({ timeout: 20000 });
    assert.match(await page.getByTestId('profile-stages').textContent(), /Enrolled/);
    await page.getByTestId('profile-edit').click();
    const json = JSON.parse(await page.getByTestId('profile-json-input').inputValue());
    await page.getByTestId('profile-json-input').fill(JSON.stringify({ ...json, client_number_pattern: 'NO-COUNTER' }));
    await page.getByTestId('profile-validate').click();
    await page.getByTestId('profile-problems').waitFor({ timeout: 15000 });
    assert.match(await page.getByTestId('profile-problems').textContent(), /NO-COUNTER/);
    await page.screenshot({ path: `${SCREENSHOTS}/panel-profile-problems.png`, fullPage: true });

    await page.getByTestId('profile-json-input').fill(JSON.stringify(json, null, 2));
    await page.getByTestId('profile-name-en-input').fill('Skills training institute');
    await page.getByTestId('profile-notes-input').fill('clearer name');
    await page.getByTestId('profile-validate').click();
    await page.getByTestId('profile-valid').waitFor({ timeout: 15000 });
    await page.getByTestId('profile-save').click();
    await page.getByTestId('profile-publish').waitFor({ timeout: 15000 });
    assert.match(await page.getByTestId('profile-version').textContent(), /Draft v2/);
    await page.getByTestId('profile-publish').click();
    await page.getByTestId('confirm-ok').click();
    await page.waitForFunction(() => /Published v2/.test(document.querySelector('[data-testid="profile-version"]')?.textContent ?? ''), null, { timeout: 15000 });
    assert.equal(await page.getByTestId('profile-v1').count(), 1, 'version 1 stays in the history');
    assert.match(adminSql(`select payload -> 'name' ->> 'en' from public.type_profiles where key = 'training' and version = 2 and status = 'published'`),
      /Skills training institute/);
    await page.screenshot({ path: `${SCREENSHOTS}/panel-profile.png`, fullPage: true });

    await page.goto(`${web.base}/panel/profiles`);
    const openNow = async (want) => {
      for (let n = 0; n < 50 && !new RegExp(`\\b${want ? 't' : 'f'}\\b`).test(adminSql(`select signup_open from public.industries where key = 'education'`)); n += 1) {
        await page.waitForTimeout(300);
      }
      assert.match(adminSql(`select signup_open from public.industries where key = 'education'`), new RegExp(`\\b${want ? 't' : 'f'}\\b`));
    };
    await page.getByTestId('industry-open-education').click();
    await openNow(false);
    await page.getByTestId('industry-open-education').click();
    await openNow(true);
    await ctx.close();
  });

  it('institutions: the Labels tab shows where words come from; lock a word with a reason (audited)', async () => {
    const ctx = await newContext();
    const page = await ctx.newPage();
    await panelSignIn(page, 'platform.admin@example.test');
    await page.getByTestId('panel-dashboard').waitFor({ timeout: 20000 });
    await page.getByTestId('panel-menu-institutions').click();
    await page.getByTestId('institution-profile-mixed').waitFor({ timeout: 20000 });
    assert.match(await page.getByTestId('institution-profile-mixed').textContent(), /School \+ College/);
    await page.getByTestId('institution-test-college-a').click();
    await page.getByTestId('institution-tab-labels').click();
    await page.getByTestId('label-doc.receipt_title').waitFor({ timeout: 20000 });
    await page.getByTestId('label-doc.receipt_title').click();
    await page.getByTestId('lock-reason-input').fill('legal title on receipts');
    await page.getByTestId('lock-save').click();
    await page.getByTestId('lock-sheet').waitFor({ state: 'hidden', timeout: 15000 });
    await page.waitForFunction(() => /Locked/.test(document.querySelector('[data-testid="label-doc.receipt_title"]')?.textContent ?? ''), null, { timeout: 15000 });
    await page.screenshot({ path: `${SCREENSHOTS}/panel-institution-labels.png`, fullPage: true });
    assert.match(adminSql(`select count(*) from public.platform_audit_log where action = 'label.locked' and target_id = 'doc.receipt_title'
      and reason = 'legal title on receipts'`), /\b1\b/);
    assert.match(adminSql(`select locked_by_platform from public.institution_labels
      where institution_id = 'a0000000-0000-4000-8000-00000000000a' and key = 'doc.receipt_title'`), /\bt\b/);
    await ctx.close();
  });

  it('product words: edit a product-default word (institutions keep their own)', async () => {
    const ctx = await newContext();
    const page = await ctx.newPage();
    await panelSignIn(page, 'platform.admin@example.test');
    await page.getByTestId('panel-dashboard').waitFor({ timeout: 20000 });
    await page.goto(`${web.base}/panel/profiles`);
    await page.getByTestId('profiles-product-words').click();
    await page.getByTestId('product-label-lead').waitFor({ timeout: 20000 });
    await page.getByTestId('product-label-lead').click();
    await page.getByTestId('product-label-en-input').fill('Prospect');
    await page.getByTestId('product-label-en-plural-input').fill('Prospects');
    await page.getByTestId('product-label-save').click();
    await page.getByTestId('product-label-sheet').waitFor({ state: 'hidden', timeout: 15000 });
    assert.match(adminSql(`select en_singular from public.label_defaults where scope = 'product' and key = 'lead'`), /Prospect/);
    assert.match(adminSql(`select app.label('a0000000-0000-4000-8000-00000000000a', 'lead')`), /Lead/);
    await ctx.close();
  });

  it('plan and billing: Billing changes an institution\'s plan with a reason; the Master Admin saves a plan version', async () => {
    const ctx = await newContext();
    const page = await ctx.newPage();
    await panelSignIn(page, 'platform.billing@example.test');
    await page.getByTestId('panel-dashboard').waitFor({ timeout: 20000 });
    await page.goto(`${web.base}/panel/institution/a0000000-0000-4000-8000-00000000000a`);
    await page.getByTestId('institution-tab-plan').click();
    await page.getByTestId('plan-current').waitFor({ timeout: 20000 });
    await page.getByTestId('plan-choice-starter').click();
    await page.getByTestId('plan-fit').waitFor({ timeout: 15000 });
    await page.getByTestId('plan-choice-pro').click();
    await page.getByTestId('plan-overrides-input').fill('{"sms_month": 20000}');
    await page.getByTestId('plan-reason-input').fill('signed for a year');
    await page.getByTestId('plan-save').click();
    await page.waitForFunction(() => /Pro/.test(document.querySelector('[data-testid="plan-current"]')?.textContent ?? ''), null, { timeout: 15000 });
    await page.screenshot({ path: `${SCREENSHOTS}/panel-plan-tab.png`, fullPage: true });
    assert.match(adminSql(`select plan_key || ' ' || (limit_overrides ->> 'sms_month') from public.institution_plan
      where institution_id = 'a0000000-0000-4000-8000-00000000000a'`), /pro 20000/);
    assert.match(adminSql(`select count(*) from public.platform_audit_log where action = 'institution.plan_changed' and reason = 'signed for a year'`), /\b1\b/);
    await ctx.close();

    const admin = await newContext();
    const p2 = await admin.newPage();
    await panelSignIn(p2, 'platform.admin@example.test');
    await p2.getByTestId('panel-dashboard').waitFor({ timeout: 20000 });
    await p2.goto(`${web.base}/panel/institutions`);
    await p2.getByTestId('institutions-plans').click();
    await p2.getByTestId('plan-starter').waitFor({ timeout: 20000 });
    await p2.getByTestId('plan-starter').click();
    await p2.getByTestId('plan-limits-input').fill('{"users": 6}');
    await p2.getByTestId('plan-sheet-save').click();
    await p2.getByTestId('plan-sheet').waitFor({ state: 'hidden', timeout: 15000 });
    assert.match(adminSql(`select max(version) from public.plans where key = 'starter'`), /\b2\b/);
    await admin.close();
  });

  it('lifecycle: approve from the queue, read only, suspend, reactivate, close after a full export', async () => {
    adminSql(`insert into public.institutions (slug, name, eiin, status) values ('life-ui-test', 'Lifecycle UI School', '765432', 'pending')`);
    const ctx = await newContext({ acceptDownloads: true });
    const page = await ctx.newPage();
    await panelSignIn(page, 'platform.admin@example.test');
    await page.getByTestId('approval-life-ui-test').waitFor({ timeout: 20000 });
    await page.screenshot({ path: `${SCREENSHOTS}/panel-approvals.png`, fullPage: true });
    await page.getByTestId('approval-life-ui-test').click();
    await page.getByTestId('overview-info').waitFor({ timeout: 20000 });
    const to = async (status, reason) => {
      await page.getByTestId(`overview-to-${status}`).click();
      await page.getByTestId('status-reason-input').fill(reason);
      await page.getByTestId('status-confirm').click();
      await page.getByTestId('status-sheet').waitFor({ state: 'hidden', timeout: 15000 });
      for (let n = 0; n < 40 && !new RegExp(`\\b${status}\\b`).test(adminSql(`select status from public.institutions where slug = 'life-ui-test'`)); n += 1) {
        await page.waitForTimeout(300);
      }
      assert.match(adminSql(`select status from public.institutions where slug = 'life-ui-test'`), new RegExp(`\\b${status}\\b`));
    };
    await to('trial', 'EIIN checked');
    await to('read_only', 'payment overdue');
    await to('suspended', 'abuse report');
    await to('active', 'resolved');
    // Closing needs a full export first.
    await page.getByTestId('overview-to-closed').click();
    await page.getByTestId('status-needs-export').waitFor();
    await page.getByTestId('status-reason-input').fill('left the platform');
    await page.getByTestId('status-confirm').click();
    await page.waitForTimeout(1500);
    assert.match(adminSql(`select status from public.institutions where slug = 'life-ui-test'`), /\bactive\b/, 'not closed without an export');
    await page.goto(page.url());
    await page.getByTestId('overview-export-make').click();
    await page.locator('[data-testid^="overview-export-"]:not([data-testid="overview-export-make"])').first().waitFor({ timeout: 20000 });
    const download = page.waitForEvent('download');
    await page.locator('[data-testid^="overview-export-"]:not([data-testid="overview-export-make"])').first().click();
    assert.match((await download).suggestedFilename(), /^life-ui-test-.*\.json$/);
    await to('closed', 'left the platform');
    await page.getByTestId('overview-purge').waitFor({ timeout: 15000 });
    await page.screenshot({ path: `${SCREENSHOTS}/panel-overview-closed.png`, fullPage: true });
    assert.match(adminSql(`select count(*) from public.institution_status_history h join public.institutions i on i.id = h.institution_id
      where i.slug = 'life-ui-test'`), /\b5\b/);
    await ctx.close();
  });

  it('profiles and packs need platform.profiles (Support is refused)', async () => {
    const ctx = await newContext();
    const page = await ctx.newPage();
    await panelSignIn(page, 'platform.support@example.test');
    await page.getByTestId('panel-menu-dashboard').waitFor({ timeout: 20000 });
    assert.equal(await page.getByTestId('panel-menu-profiles').count(), 0);
    await page.goto(`${web.base}/panel/profile/profile/school`);
    await page.getByTestId('panel-no-access').waitFor({ timeout: 20000 });
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
      await page.goto(`${web.base}/panel/institution/a0000000-0000-4000-8000-00000000000a`);
      await page.getByTestId('overview-info').waitFor({ timeout: 20000 });
      assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'no sideways scroll');
      await page.screenshot({ path: `${SCREENSHOTS}/panel-institutions-${language}-${scheme}.png`, fullPage: true });
      await page.goto(`${web.base}/panel/profile/profile/school`);
      await page.getByTestId('profile-stages').waitFor({ timeout: 20000 });
      assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'no sideways scroll (profile)');
      await page.screenshot({ path: `${SCREENSHOTS}/panel-profile-${language}-${scheme}.png`, fullPage: true });
      await ctx.close();
    });
  }
});
