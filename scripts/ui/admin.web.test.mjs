// UI tests (0A.18) on the web build with the local Supabase: Settings → Users / Roles / explainer / change log.
// Role matrix (screens hidden without the permission), approve a join request, the acceptance flow (a Super Admin
// creates a role from a template, gives it for one branch with an end date, sees it in the change log), the
// explainer telling why, and screenshots in light / dark × bn / en with weird labels.
import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';

import { INSTITUTION, adminSql } from '../e2e/helpers.mjs';
import { SCREENSHOTS, startWeb } from './helpers.mjs';

const A_MEMBER = '11111111-1111-4111-8111-111111111111';
const PENDING = '88888888-8888-4888-8888-888888888888';
const BRANCH_X = 'd0000000-0000-4000-8000-0000000000a1';
const BRANCH_Y = 'd0000000-0000-4000-8000-0000000000a2';

let web;
const cleanUp = () => {
  adminSql(`delete from public.role_assignments where institution_id = '${INSTITUTION.A}' and user_id = '${A_MEMBER}';
            delete from public.role_permissions where institution_id = '${INSTITUTION.A}'
              and role_id in (select id from public.roles where institution_id = '${INSTITUTION.A}' and name like 'Season caller%');
            delete from public.roles where institution_id = '${INSTITUTION.A}' and name like 'Season caller%';
            delete from public.branches where institution_id = '${INSTITUTION.A}' and org_unit_id in ('${BRANCH_X}', '${BRANCH_Y}');
            delete from public.org_units where institution_id = '${INSTITUTION.A}' and id in ('${BRANCH_X}', '${BRANCH_Y}');
            delete from public.app_settings where institution_id = '${INSTITUTION.A}' and key = 'branches_enabled';
            update public.institution_members set status = 'pending' where institution_id = '${INSTITUTION.A}' and user_id = '${PENDING}';
            select app.flush_access_queue('${INSTITUTION.A}');`);
};
before(async () => {
  web = await startWeb();
  cleanUp();
  adminSql(`insert into public.app_settings (institution_id, key, value) values ('${INSTITUTION.A}', 'branches_enabled', 'true')
              on conflict (institution_id, key) do update set value = excluded.value;
            insert into public.org_units (institution_id, id, kind, name) values ('${INSTITUTION.A}', '${BRANCH_X}', 'branch', 'North campus'),
              ('${INSTITUTION.A}', '${BRANCH_Y}', 'branch', 'South campus') on conflict do nothing;
            insert into public.branches (institution_id, org_unit_id) values ('${INSTITUTION.A}', '${BRANCH_X}'), ('${INSTITUTION.A}', '${BRANCH_Y}')
              on conflict do nothing;`);
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
const choose = async (page, field, option) => {
  await page.getByTestId(`${field}-open`).click();
  await page.getByTestId(option).click();
  await page.getByTestId(`${field}-sheet`).waitFor({ state: 'hidden' });
};

describe('Settings → Users and Roles', () => {
  it('role matrix: without settings.users the screens are hidden and the server refuses', async () => {
    const page = await newPage();
    await signIn(page, 'a.member@example.test');
    await page.getByTestId('tab-settings').click();
    await page.getByTestId('settings-empty').waitFor();
    assert.equal(await page.getByTestId('settings-users').count(), 0);
    await page.goto(`${web.base}/admin/users`);
    await page.getByTestId('users-list-error').waitFor({ timeout: 15000 });
    assert.match(await page.getByTestId('users-list-error-message').textContent(), /permission/);
    await page.close();
  });

  it('role matrix: the Admin role sees Users but not Roles or the change log', async () => {
    adminSql(`insert into public.role_assignments (institution_id, user_id, role_id)
              select institution_id, '${A_MEMBER}', id from public.roles where institution_id = '${INSTITUTION.A}' and template_key = 'admin';
              select app.flush_access_queue('${INSTITUTION.A}');`);
    const page = await newPage();
    await signIn(page, 'a.member@example.test');
    await page.getByTestId('tab-settings').click();
    await page.getByTestId('settings-users').waitFor();
    assert.equal(await page.getByTestId('settings-roles').count(), 0);
    assert.equal(await page.getByTestId('settings-audit').count(), 0);
    adminSql(`delete from public.role_assignments where institution_id = '${INSTITUTION.A}' and user_id = '${A_MEMBER}';
              select app.flush_access_queue('${INSTITUTION.A}');`);
    await page.close();
  });

  it('users list: pending first, search, filter; approving a request', async () => {
    const page = await newPage();
    await signIn(page, 'owner.admin@example.test');
    await page.getByTestId('tab-settings').click();
    await page.getByTestId('settings-users').click();
    await page.getByTestId('user-pending.member').waitFor({ timeout: 15000 });
    await page.screenshot({ path: `${SCREENSHOTS}/admin-users.png` });
    await page.getByTestId('users-search-input').fill('nobody-like-this');
    await page.getByTestId('users-empty').waitFor();
    await page.getByTestId('users-search-input').fill('');
    await page.getByTestId('users-filter-deactivated').click();
    await page.getByTestId('user-gone.member').waitFor();
    assert.equal(await page.getByTestId('user-pending.member').count(), 0);
    await page.getByTestId('users-filter-pending').click();
    await page.getByTestId('user-pending.member').click();
    await page.getByTestId('user-approve').click();
    await page.getByTestId('confirm-ok').click();
    await page.waitForFunction(() => /Active/.test(document.querySelector('[data-testid="user-status"]')?.textContent ?? ''));
    assert.match(adminSql(`select status from public.institution_members where institution_id = '${INSTITUTION.A}' and user_id = '${PENDING}'`), /active/);
    await page.close();
  });

  it('acceptance: create a role from a template, give it for one branch with an end date, see it in the change log', async () => {
    const page = await newPage();
    await signIn(page, 'owner.admin@example.test');
    // 1. New role from the Caller template.
    await page.goto(`${web.base}/admin/roles`);
    await page.getByTestId('roles-new').click();
    await choose(page, 'new-role-from', 'new-role-from-Caller');
    await page.getByTestId('new-role-name-input').fill('Season caller');
    await page.getByTestId('new-role-save').click();
    await page.getByTestId('role-permissions').waitFor({ timeout: 15000 });
    // Generated from the registry: labels and help, sensitive badge; add a non-sensitive permission and save.
    assert.ok(await page.getByText('Manage users', { exact: true }).isVisible());
    await page.getByTestId('grant-settings.general').click();
    await page.getByTestId('role-save').click();
    await page.getByText('Role saved').waitFor();
    await page.screenshot({ path: `${SCREENSHOTS}/admin-role-editor.png`, fullPage: true });

    // 2. Give it to a.member for North campus, ending next month.
    await page.goto(`${web.base}/admin/user/${A_MEMBER}`);
    await page.getByTestId('user-add-role').click();
    await choose(page, 'assign-role', 'assign-role-Season caller');
    await choose(page, 'assign-branch', 'assign-branch-North campus');
    await page.getByTestId('assign-preview').getByText('General settings', { exact: false }).waitFor();
    await page.getByTestId('assign-to').click();
    await page.getByLabel('Next month').click();
    const next = new Date();
    next.setUTCDate(15);
    next.setUTCMonth(next.getUTCMonth() + 1);
    await page.getByTestId(`day-${next.toISOString().slice(0, 10)}`).click();
    await page.getByTestId('assign-to-done').click();
    await page.getByTestId('assign-to-done').waitFor({ state: 'hidden' });
    await page.screenshot({ path: `${SCREENSHOTS}/admin-assign.png`, fullPage: true });
    await page.getByTestId('assign-save').click();
    await page.getByTestId('assignment-Season caller').waitFor({ timeout: 15000 });
    assert.match(await page.getByTestId('assignment-Season caller-where').textContent(), /North campus/);
    assert.match(adminSql(`select count(*) from public.role_assignments ra join public.roles r on r.id = ra.role_id
      where ra.user_id = '${A_MEMBER}' and r.name = 'Season caller' and ra.branch_id = '${BRANCH_X}' and ra.valid_to is not null`), /\b1\b/);
    await page.screenshot({ path: `${SCREENSHOTS}/admin-user.png`, fullPage: true });

    // 3. The change log shows the new role and the assignment.
    await page.goto(`${web.base}/admin/audit`);
    await page.getByTestId('audit-role.assigned').first().waitFor({ timeout: 15000 });
    assert.ok(await page.getByTestId('audit-role.created').first().isVisible());
    await page.getByTestId('audit-area-assignments').click();
    // The filtered list replaces the full one when it arrives: wait for that, then check.
    await page.waitForFunction(() => document.querySelectorAll('[data-testid="audit-role.created"]').length === 0, null, { timeout: 15000 });
    await page.getByTestId('audit-role.assigned').first().waitFor();
    assert.equal(await page.getByTestId('audit-role.created').count(), 0);
    await page.screenshot({ path: `${SCREENSHOTS}/admin-audit.png`, fullPage: true });

    // 4. The explainer tells why: allowed in North campus, blocked in South campus by the branch limit.
    await page.goto(`${web.base}/admin/explain?user=${A_MEMBER}`);
    await choose(page, 'explain-permission', 'explain-permission-settings.general');
    await choose(page, 'explain-branch', 'explain-branch-South campus');
    await page.getByTestId('explain-check').click();
    await page.getByTestId('explain-result').waitFor({ timeout: 15000 });
    assert.match(await page.getByTestId('explain-verdict').textContent(), /cannot/);
    assert.match(await page.getByTestId('explain-reason-Season caller-rule').textContent(), /Limited to another/);
    await choose(page, 'explain-branch', 'explain-branch-North campus');
    await page.getByTestId('explain-check').click();
    await page.waitForFunction(() => /can do this/.test(document.querySelector('[data-testid="explain-verdict"]')?.textContent ?? '')
      && !/cannot/.test(document.querySelector('[data-testid="explain-verdict"]')?.textContent ?? ''));
    await page.screenshot({ path: `${SCREENSHOTS}/admin-explain.png`, fullPage: true });
    await page.close();
  });

  it('compare two roles and the new permissions of this release', async () => {
    const page = await newPage();
    await signIn(page, 'owner.admin@example.test');
    await page.goto(`${web.base}/admin/role-compare`);
    await page.getByTestId('compare-a-open').click();
    await page.getByTestId('compare-a-sheet').getByText('Admin', { exact: true }).click();
    await page.getByTestId('compare-b-open').click();
    await page.getByTestId('compare-b-sheet').getByText('Viewer / Auditor', { exact: true }).click();
    await page.getByTestId('compare-rows').waitFor();
    assert.ok(await page.getByTestId('compare-audit.view').isVisible(), 'a difference is listed');
    await page.goto(`${web.base}/admin/new-permissions`);
    // This release's new permissions (0B.05): sensitive, so not given to any role by themselves (Super Admin has all).
    await page.getByTestId('new-settings.modules').waitFor({ timeout: 15000 });
    assert.match(await page.getByTestId('new-settings.modules').textContent(), /Not given to any role yet/);
    await page.close();
  });

  for (const [scheme, language] of [['light', 'en'], ['dark', 'en'], ['light', 'bn'], ['dark', 'bn']]) {
    it(`screenshots with weird labels: ${language} ${scheme}`, async () => {
      const page = await newPage({ colorScheme: scheme });
      await signIn(page, 'weird.member@example.test');
      await page.goto(`${web.base}/language`);
      await page.getByTestId(`language-option-${language}`).click();
      for (const [path, ready] of [['/settings', 'settings-users'], ['/admin/users', 'user-weird.member'], ['/admin/roles', 'roles-compare'],
        ['/admin/explain', 'explain-check'], ['/admin/audit', 'audit-area-all']]) {
        await page.goto(`${web.base}${path}`);
        await page.getByTestId(ready).waitFor({ timeout: 30000 }).catch(async (e) => {
          await page.screenshot({ path: `${SCREENSHOTS}/admin-weird-FAILED-${language}-${scheme}.png` });
          throw e;
        });
        await page.waitForTimeout(300);
        assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), `${path}: page overflows`);
        await page.screenshot({ path: `${SCREENSHOTS}/admin-weird${path.replaceAll('/', '-')}-${language}-${scheme}.png`, fullPage: true });
      }
      adminSql("update public.profiles set preferred_language = null where email = 'weird.member@example.test'");
      await page.close();
    });
  }
});
