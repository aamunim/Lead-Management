// UI tests (0A.14) on the web build connected to the local Supabase (`npm run export:web:local`):
// sign-in → shell, nothing of the previous user / institution left after sign-out or switch, language and theme from
// the profile without reload, offline strip, idle sign-out, upgrade required, deep link that switches institution,
// responsive widths, and screenshots in light / dark × bn / en × weird labels.
import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';

import { INSTITUTION, adminSql } from '../e2e/helpers.mjs';
import { SCREENSHOTS, startWeb } from './helpers.mjs';

let web;
before(async () => {
  web = await startWeb();
});
const resetLanguage = () => adminSql("update public.profiles set preferred_language = null where email like '%@example.test'");
after(async () => {
  resetLanguage();
  adminSql("delete from public.product_settings where key = 'min_app_version'");
  adminSql("delete from public.app_settings where key = 'idle_signout_minutes'");
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

/** Keys this browser holds for cached user / institution data (the `c|` namespace) and the auth session. */
const storedKeys = (page) => page.evaluate(() => Object.keys(localStorage));
const cacheKeys = async (page) => (await storedKeys(page)).filter((k) => k.startsWith('c|'));

describe('app shell', () => {
  it('before sign-in: neutral product name; after: the institution, tabs and Home', async () => {
    const page = await newPage();
    await page.goto(`${web.base}/`);
    await page.getByTestId('sign-in-title').waitFor({ timeout: 20000 });
    assert.equal(await page.getByTestId('app-header-title').textContent(), 'Leadora');
    await signIn(page, 'a.member@example.test');
    await page.waitForFunction(() => document.querySelector('[data-testid="app-header-title"]')?.textContent === 'Test College A');
    assert.ok(await page.getByTestId('tab-more').isVisible());
    await page.close();
  });

  it('wrong password: a clear error under the field, no sign-in', async () => {
    const page = await newPage();
    await page.goto(`${web.base}/sign-in`);
    await page.getByTestId('sign-in-email-input').fill('a.member@example.test');
    await page.getByTestId('sign-in-password-input').fill('wrong-password');
    await page.getByTestId('sign-in-submit').click();
    await page.getByTestId('sign-in-password-error').waitFor();
    assert.match(await page.getByTestId('sign-in-password-error').textContent(), /not right/);
    await page.close();
  });

  it('sign-out leaves nothing of the user on screen or in storage', async () => {
    const page = await newPage();
    await signIn(page, 'a.member@example.test');
    await page.waitForFunction(() => Object.keys(localStorage).some((k) => k.startsWith('c|')));
    assert.ok((await cacheKeys(page)).some((k) => k.includes(`|${INSTITUTION.A}|`)), 'institution data was cached');
    await page.getByTestId('open-profile').click();
    await page.getByTestId('profile-signout').click();
    await page.getByTestId('confirm-ok').click();
    await page.getByTestId('sign-in-title').waitFor();
    assert.deepEqual(await cacheKeys(page), [], 'no cached user or institution data');
    assert.ok(!(await storedKeys(page)).some((k) => k.includes('auth-token')), 'no session token');
    assert.ok(!(await page.evaluate(() => document.body.innerText)).includes('Test College A'), 'nothing of the institution on screen');
    await page.close();
  });

  it('switching institution removes the previous institution\'s data', async () => {
    const page = await newPage();
    await page.goto(`${web.base}/dev-sign-in`);
    await page.getByPlaceholder('email').fill('both.member@example.test');
    await page.getByPlaceholder('password').fill('password123');
    await page.getByText('Sign in', { exact: true }).click();
    await page.getByText('Switch to Test College A').click();
    await page.waitForFunction((a) => document.querySelector('[data-testid="dev-claims"]')?.textContent?.includes(a), INSTITUTION.A);
    await page.goto(`${web.base}/home`);
    await page.waitForFunction(() => document.querySelector('[data-testid="app-header-title"]')?.textContent === 'Test College A');
    await page.waitForFunction((a) => Object.keys(localStorage).some((k) => k.includes(`|${a}|`)), INSTITUTION.A);
    await page.goto(`${web.base}/dev-sign-in`);
    await page.getByText('Switch to Test School B').click();
    await page.waitForFunction((b) => document.querySelector('[data-testid="dev-claims"]')?.textContent?.includes(b), INSTITUTION.B);
    await page.goto(`${web.base}/home`);
    await page.waitForFunction(() => document.querySelector('[data-testid="app-header-title"]')?.textContent === 'Test School B');
    assert.ok(!(await cacheKeys(page)).some((k) => k.includes(`|${INSTITUTION.A}|`)), 'nothing of A left in storage');
    await page.close();
  });

  it('a deep link to another institution switches to it first (D25)', async () => {
    const page = await newPage();
    await page.goto(`${web.base}/dev-sign-in`);
    await page.getByPlaceholder('email').fill('both.member@example.test');
    await page.getByPlaceholder('password').fill('password123');
    await page.getByText('Sign in', { exact: true }).click();
    await page.getByText('Switch to Test College A').click();
    await page.waitForFunction((a) => document.querySelector('[data-testid="dev-claims"]')?.textContent?.includes(a), INSTITUTION.A);
    await page.goto(`${web.base}/home?institution=${INSTITUTION.B}`);
    await page.waitForFunction(() => document.querySelector('[data-testid="app-header-title"]')?.textContent === 'Test School B', null, { timeout: 20000 });
    await page.close();
  });

  it('language and theme change from the profile at once, without a reload', async () => {
    const page = await newPage();
    await signIn(page, 'a.member@example.test');
    await page.evaluate(() => { window.__noReload = true; });
    await page.getByTestId('open-profile').click();
    await page.getByTestId('profile').waitFor();
    await page.getByTestId('language-option-bn').click();
    await page.waitForFunction(() => document.querySelector('[data-testid="profile-title"]')?.textContent === 'প্রোফাইল');
    const bg = () => page.getByTestId('profile').evaluate((el) => getComputedStyle(el).backgroundColor);
    const before = await bg();
    await page.getByTestId('appearance-dark').click();
    await page.waitForFunction((b) => getComputedStyle(document.querySelector('[data-testid="profile"]')).backgroundColor !== b, before);
    assert.equal(await page.evaluate(() => window.__noReload), true);
    await page.getByTestId('header-back').click();
    await page.getByTestId('home').waitFor();
    assert.match(await page.getByTestId('home-title').textContent(), /^স্বাগতম/);
    resetLanguage(); // the choice is saved to the profile (every device); later tests expect English
    await page.close();
  });

  it('offline strip, then "Back online"', async () => {
    const context = await web.browser.newContext({ viewport: { width: 400, height: 860 } });
    const page = await context.newPage();
    await page.goto(`${web.base}/sign-in`);
    await page.getByTestId('sign-in-title').waitFor();
    await context.setOffline(true);
    await page.getByTestId('network-offline').waitFor();
    await page.screenshot({ path: `${SCREENSHOTS}/shell-offline.png` });
    await context.setOffline(false);
    await page.getByTestId('network-online').waitFor();
    assert.match(await page.getByTestId('network-online').textContent(), /Back online/);
    await context.close();
  });

  it('idle sign-out after the institution\'s minutes without activity', async () => {
    resetLanguage();
    adminSql(`insert into public.app_settings (institution_id, key, value) values ('${INSTITUTION.A}', 'idle_signout_minutes', '1')
              on conflict (institution_id, key) do update set value = excluded.value`);
    const page = await newPage();
    await page.clock.install();
    await signIn(page, 'a.member@example.test');
    await page.waitForTimeout(1500); // settings loaded
    await page.clock.fastForward('02:00');
    await page.getByTestId('sign-in-reason').waitFor({ timeout: 20000 });
    assert.match(await page.getByTestId('sign-in-reason').textContent(), /not used for a while/);
    assert.deepEqual(await cacheKeys(page), []);
    adminSql("delete from public.app_settings where key = 'idle_signout_minutes'");
    await page.close();
  });

  it('an app older than min_app_version is blocked with "Please update the app"', async () => {
    adminSql(`insert into public.product_settings (key, value, schema_version) values ('min_app_version', '"9.9.9"', 1)
              on conflict (key) do update set value = excluded.value`);
    const page = await newPage();
    await page.goto(`${web.base}/`);
    await page.getByTestId('upgrade-required').waitFor({ timeout: 20000 });
    await page.screenshot({ path: `${SCREENSHOTS}/shell-upgrade.png` });
    adminSql("delete from public.product_settings where key = 'min_app_version'");
    await page.close();
  });

  for (const [width, height] of [[320, 568], [768, 1024], [1280, 800]]) {
    it(`responsive ${width}×${height}: nothing off screen, tabs visible`, async () => {
      const page = await newPage({ viewport: { width, height } });
      await signIn(page, 'a.member@example.test');
      for (const path of ['/home', '/profile', '/more']) {
        await page.goto(`${web.base}${path}`);
        await page.waitForTimeout(400);
        const off = await page.evaluate(() => [...document.querySelectorAll('[role="button"],[role="radio"],[role="link"],input')]
          .filter((el) => { const r = el.getBoundingClientRect(); return r.width > 0 && (r.right > window.innerWidth + 1 || r.left < -1); }).length);
        assert.equal(off, 0, `${path}: elements off screen`);
        assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), `${path}: page overflows`);
        await page.screenshot({ path: `${SCREENSHOTS}/shell-${path.slice(1)}-${width}x${height}.png` });
      }
      assert.ok(await page.getByTestId('tab-home').isVisible());
      await page.close();
    });
  }

  for (const [scheme, language] of [['light', 'en'], ['dark', 'en'], ['light', 'bn'], ['dark', 'bn']]) {
    it(`screenshots with weird labels: ${language} ${scheme}`, async () => {
      const page = await newPage({ colorScheme: scheme });
      await signIn(page, 'weird.member@example.test');
      // After sign-in the profile's choice wins (0A.10), so the language is chosen once signed in.
      await page.goto(`${web.base}/language`);
      await page.getByTestId(`language-option-${language}`).click();
      await page.goto(`${web.base}/home`);
      await page.waitForFunction(() => /Weird Labels/.test(document.querySelector('[data-testid="app-header-title"]')?.textContent ?? ''));
      await page.waitForFunction((bn) => /[\u0980-\u09FF]/.test(document.querySelector('[data-testid="home-title"]')?.textContent ?? '') === bn, language === 'bn');
      await page.screenshot({ path: `${SCREENSHOTS}/shell-weird-home-${language}-${scheme}.png` });
      await page.getByTestId('open-profile').click();
      await page.getByTestId('profile').waitFor();
      await page.screenshot({ path: `${SCREENSHOTS}/shell-weird-profile-${language}-${scheme}.png` });
      assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1));
      resetLanguage();
      await page.close();
    });
  }
});
