// UI test (0A.10): on the web build, switch the sample screen between English and Bangla. The text must change
// without a page reload, survive a reload (device copy), and Bangla must render in the Bangla font.
// Run: npm run export:web && npm run test:ui
import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';

import { startWeb } from './helpers.mjs';

let web;
let browser;
let base;

before(async () => {
  web = await startWeb();
  ({ browser, base } = web);
});

after(async () => {
  await web?.stop();
});

describe('language switch on the web build', () => {
  it('switches English ↔ Bangla instantly, without a reload, and remembers it', async () => {
    const page = await browser.newPage();
    await page.goto(`${base}/language`);
    await page.getByTestId('language-title').waitFor();
    assert.equal(await page.getByTestId('language-title').textContent(), 'Language');
    await page.evaluate(() => { window.__noReload = true; });

    await page.getByTestId('language-option-bn').click();
    await page.getByText('ভাষা', { exact: true }).waitFor();
    assert.equal(await page.getByTestId('language-title').textContent(), 'ভাষা');
    assert.equal(await page.getByTestId('language-current').textContent(), 'এখন দেখাচ্ছে: বাংলা');
    assert.equal(await page.evaluate(() => window.__noReload), true, 'no page reload happened');
    const font = await page.getByTestId('language-title').evaluate((el) => getComputedStyle(el).fontFamily);
    assert.match(font, /NotoSansBengali/, 'Bangla text uses the Bangla font');

    await page.reload();
    await page.getByText('ভাষা', { exact: true }).waitFor();
    assert.equal(await page.getByTestId('language-title').textContent(), 'ভাষা', 'choice kept on this device');

    await page.getByTestId('language-option-en').click();
    await page.getByText('Language', { exact: true }).waitFor();
    assert.equal(await page.getByTestId('language-current').textContent(), 'Now showing: English');
    await page.close();
  });

  it('the first screen (sign-in, before sign-in) follows the chosen language', async () => {
    const page = await browser.newPage();
    await page.goto(`${base}/language`);
    await page.getByTestId('language-option-bn').click();
    await page.getByText('ভাষা', { exact: true }).waitFor();
    await page.goto(`${base}/`);
    await page.getByTestId('sign-in-title').waitFor();
    assert.equal(await page.getByTestId('sign-in-title').textContent(), 'সাইন ইন');
    assert.equal(await page.getByTestId('sign-in-submit').textContent(), 'সাইন ইন করুন');
    await page.close();
  });
});
