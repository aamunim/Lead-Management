// UI tests (0A.19) on the web build with the local Supabase: Settings → Branches and Settings → Terminology.
// Role matrix, branches hidden when off, add / edit / archive with the "move everything first" step, renaming words
// with the live preview, the new word on a second device after refresh, reset all, and screenshots in
// light / dark × bn / en × weird labels.
import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';

import { INSTITUTION, adminSql } from '../e2e/helpers.mjs';
import { SCREENSHOTS, startWeb } from './helpers.mjs';

const A_MEMBER = '11111111-1111-4111-8111-111111111111';
const INST_C = 'c0000000-0000-4000-8000-00000000000c';

let web;
const cleanUp = () => {
  adminSql(`delete from public.role_assignments where institution_id = '${INSTITUTION.A}' and user_id = '${A_MEMBER}';
            update public.institution_members set branch_id = null where institution_id in ('${INSTITUTION.A}', '${INST_C}');
            delete from public.branches where institution_id in ('${INSTITUTION.A}', '${INST_C}');
            delete from public.org_units where institution_id in ('${INSTITUTION.A}', '${INST_C}');
            delete from public.app_settings where institution_id in ('${INSTITUTION.A}', '${INST_C}') and key = 'branches_enabled';
            delete from public.institution_labels where institution_id = '${INSTITUTION.A}';
            select app.bump_settings_version('${INSTITUTION.A}');
            select app.flush_access_queue('${INSTITUTION.A}');`);
};
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
const choose = async (page, field, option) => {
  await page.getByTestId(`${field}-open`).click();
  await page.getByTestId(option).click();
  await page.getByTestId(`${field}-sheet`).waitFor({ state: 'hidden' });
};
const enableBranches = (institution) => adminSql(`insert into public.app_settings (institution_id, key, value)
  values ('${institution}', 'branches_enabled', 'true') on conflict (institution_id, key) do update set value = excluded.value;
  select app.bump_settings_version('${institution}');`);

describe('Settings → Branches and Terminology', () => {
  it('role matrix: without the permissions both entries are hidden', async () => {
    enableBranches(INSTITUTION.A);
    const page = await newPage();
    await signIn(page, 'a.member@example.test');
    await page.getByTestId('tab-settings').click();
    await page.getByTestId('settings-empty').waitFor();
    assert.equal(await page.getByTestId('settings-branches').count(), 0);
    assert.equal(await page.getByTestId('settings-terminology').count(), 0);
    adminSql(`delete from public.app_settings where institution_id = '${INSTITUTION.A}' and key = 'branches_enabled'`);
    await page.close();
  });

  it('branches off: no Branches entry, the screen says so, and no branch field when giving a role', async () => {
    const page = await newPage();
    await signIn(page, 'owner.admin@example.test');
    await page.getByTestId('tab-settings').click();
    await page.getByTestId('settings-terminology').waitFor({ timeout: 15000 });
    assert.equal(await page.getByTestId('settings-branches').count(), 0);
    await page.goto(`${web.base}/admin/branches`);
    await page.getByTestId('branches-off').waitFor();
    await page.goto(`${web.base}/admin/assign?user=${A_MEMBER}`);
    await page.getByTestId('assign-role').waitFor({ timeout: 15000 });
    assert.equal(await page.getByTestId('assign-branch').count(), 0);
    await page.close();
  });

  it('add, edit and archive a branch; a branch in use moves everything to another one first', async () => {
    enableBranches(INSTITUTION.A);
    const page = await newPage();
    await signIn(page, 'owner.admin@example.test');
    await page.getByTestId('tab-settings').click();
    await page.getByTestId('settings-branches').click();
    for (const name of ['North campus', 'South campus']) {
      await page.getByTestId('branches-add').click();
      await page.getByTestId('branch-name-input').fill(name);
      if (name === 'North campus') await page.getByTestId('branch-phone').fill('01711-000001');
      await page.getByTestId('branch-save').click();
      await page.getByTestId(`branch-${name}`).waitFor({ timeout: 15000 });
    }
    // Invalid phone: the error is under the field.
    await page.getByTestId('branch-North campus').click();
    await page.getByTestId('branch-phone').fill('12');
    await page.getByTestId('branch-save').click();
    await page.getByTestId('branch-sheet').getByText('This phone number is not valid.').waitFor();
    await page.getByTestId('branch-phone').fill('01711000002');
    await page.getByTestId('branch-address-input').fill('Road 1, Dhaka');
    await page.getByTestId('branch-save').click();
    await page.waitForFunction(() => /Road 1/.test(document.querySelector('[data-testid="branch-North campus"]')?.textContent ?? ''));
    await page.screenshot({ path: `${SCREENSHOTS}/branches-list.png`, fullPage: true });

    // In use: a.member is based in North campus → the move step.
    adminSql(`update public.institution_members set branch_id = (select id from public.org_units where institution_id = '${INSTITUTION.A}' and name = 'North campus')
              where institution_id = '${INSTITUTION.A}' and user_id = '${A_MEMBER}'`);
    await page.getByTestId('branch-North campus').click();
    await page.getByTestId('branch-archive').click();
    await page.getByTestId('branch-usage').waitFor({ timeout: 15000 });
    assert.match(await page.getByTestId('branch-usage').textContent(), /Staff based here: 1/);
    await page.screenshot({ path: `${SCREENSHOTS}/branches-move.png` });
    await choose(page, 'branch-move-to', 'branch-move-to-South campus');
    await page.getByTestId('branch-move-confirm').click();
    await page.getByTestId('branch-archived-North campus').waitFor({ timeout: 15000 });
    assert.match(adminSql(`select o.name from public.institution_members m join public.org_units o on o.id = m.branch_id
      where m.institution_id = '${INSTITUTION.A}' and m.user_id = '${A_MEMBER}'`), /South campus/);
    await page.close();
  });

  it('rename words with the live preview; another device shows them after refresh; reset all', async () => {
    adminSql(`insert into public.role_assignments (institution_id, user_id, role_id)
              select institution_id, '${A_MEMBER}', id from public.roles where institution_id = '${INSTITUTION.A}' and template_key = 'caller';
              select app.flush_access_queue('${INSTITUTION.A}');`);
    const other = await newPage();
    await signIn(other, 'owner.admin@example.test');
    await other.goto(`${web.base}/admin/roles`);
    await other.getByTestId('role-Caller').waitFor({ timeout: 15000 });

    const page = await newPage();
    await signIn(page, 'owner.admin@example.test');
    await page.goto(`${web.base}/admin/terminology`);
    await page.getByTestId('term-client').click();
    await page.getByTestId('term-en-singular-input').fill('Trainee');
    await page.getByTestId('term-en-plural-input').fill('Trainees');
    await page.getByTestId('term-bn-base-input').fill('প্রশিক্ষণার্থী');
    // The preview follows the draft, in both languages, before saving.
    await page.waitForFunction(() => /Trainee: Rahim/.test(document.querySelector('[data-testid="term-preview-receipt"]')?.textContent ?? ''));
    await page.getByTestId('term-preview-bn').click();
    await page.waitForFunction(() => /প্রশিক্ষণার্থী/.test(document.querySelector('[data-testid="term-preview-receipt"]')?.textContent ?? ''));
    await page.waitForFunction(() => document.querySelector('[data-testid="term-bn-plural-input"]')?.value === 'প্রশিক্ষণার্থীরা');
    await page.screenshot({ path: `${SCREENSHOTS}/terms-edit.png`, fullPage: true });
    assert.ok(!(await page.evaluate(() => document.body.innerText)).includes('Trainees:'), 'nothing saved yet');
    await page.getByTestId('term-save').click();
    await page.getByTestId('term-sheet').waitFor({ state: 'hidden' });
    await page.waitForFunction(() => /Trainee/.test(document.querySelector('[data-testid="term-client"]')?.textContent ?? ''));

    await page.getByTestId('term-caller').click();
    await page.getByTestId('term-en-singular-input').fill('Telecaller');
    await page.getByTestId('term-en-plural-input').fill('Telecallers');
    await page.getByTestId('term-bn-base-input').fill('টেলিকলার');
    await page.getByTestId('term-save').click();
    await page.getByTestId('term-sheet').waitFor({ state: 'hidden' });
    // Renamed everywhere on this device: the preview on the screen, the Users list (role names).
    await page.waitForFunction(() => /Telecaller: Karim/.test(document.querySelector('[data-testid="terms-preview-card"]')?.textContent ?? ''));
    await page.goto(`${web.base}/admin/users`);
    await page.getByTestId('user-a.member').waitFor({ timeout: 15000 });
    assert.match(await page.getByTestId('user-a.member').textContent(), /Telecaller/);

    // The other device: after a refresh the roles and users show the new word.
    await other.reload();
    await other.getByTestId('role-Telecaller').waitFor({ timeout: 15000 });
    await other.goto(`${web.base}/admin/users`);
    await other.getByTestId('user-a.member').waitFor({ timeout: 15000 });
    assert.match(await other.getByTestId('user-a.member').textContent(), /Telecaller/);
    assert.match(adminSql(`select count(*) from public.audit_log where institution_id = '${INSTITUTION.A}' and action = 'label.changed'
      and target_id = 'client' and after ->> 'en_singular' = 'Trainee'`), /\b1\b/);

    // Reset all: back to the defaults.
    await page.goto(`${web.base}/admin/terminology`);
    await page.getByTestId('terms-reset-all').click();
    await page.getByTestId('confirm-ok').click();
    await page.waitForFunction(() => /Caller: Karim/.test(document.querySelector('[data-testid="terms-preview-card"]')?.textContent ?? '')
      && !/Telecaller/.test(document.querySelector('[data-testid="terms-preview-card"]')?.textContent ?? ''));
    await other.close();
    await page.close();
  });

  for (const [scheme, language] of [['light', 'en'], ['dark', 'en'], ['light', 'bn'], ['dark', 'bn']]) {
    it(`screenshots with weird labels: ${language} ${scheme}`, async () => {
      enableBranches(INST_C);
      adminSql(`insert into public.org_units (institution_id, kind, name) select '${INST_C}', 'branch', 'Professional Studies Campus of the Northern Region'
                where not exists (select 1 from public.org_units where institution_id = '${INST_C}');
                insert into public.branches (institution_id, org_unit_id, address, phone)
                select institution_id, id, 'House 12, Road 7, A Very Long Address Line, Dhaka 1209', '01711000003' from public.org_units
                where institution_id = '${INST_C}' on conflict do nothing;`);
      const page = await newPage({ colorScheme: scheme });
      await signIn(page, 'weird.member@example.test');
      await page.goto(`${web.base}/language`);
      await page.getByTestId(`language-option-${language}`).click();
      for (const [path, ready] of [['/admin/branches', 'branches-add'], ['/admin/terminology', 'term-client']]) {
        await page.goto(`${web.base}${path}`);
        await page.getByTestId(ready).waitFor({ timeout: 30000 });
        await page.waitForTimeout(300);
        assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), `${path}: page overflows`);
        await page.screenshot({ path: `${SCREENSHOTS}/weird${path.replaceAll('/', '-')}-${language}-${scheme}.png`, fullPage: true });
      }
      await page.getByTestId('term-client').click();
      await page.getByTestId('term-preview').waitFor();
      await page.screenshot({ path: `${SCREENSHOTS}/weird-term-edit-${language}-${scheme}.png`, fullPage: true });
      adminSql("update public.profiles set preferred_language = null where email = 'weird.member@example.test'");
      await page.close();
    });
  }
});
