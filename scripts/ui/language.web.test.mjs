// UI test (0A.10): on the web build, switch the sample screen between English and Bangla. The text must change
// without a page reload, survive a reload (device copy), and Bangla must render in the Bangla font.
// Run: npm run export:web && npm run test:ui
import assert from 'node:assert/strict';
import { createReadStream, existsSync, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { createRequire } from 'node:module';
import { extname, join, normalize } from 'node:path';
import { after, before, describe, it } from 'node:test';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');

const DIST = 'dist';
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.ttf': 'font/ttf', '.json': 'application/json', '.png': 'image/png', '.ico': 'image/x-icon' };
let server;
let browser;
let base;

before(async () => {
  assert.ok(existsSync(join(DIST, 'index.html')), 'run `npm run export:web` first');
  server = createServer((req, res) => {
    const path = normalize(decodeURIComponent(new URL(req.url, 'http://x').pathname)).replace(/^(\.\.[/\\])+/, '');
    let file = join(DIST, path);
    if (!existsSync(file) || statSync(file).isDirectory()) file = join(DIST, 'index.html'); // single-page app
    res.setHeader('content-type', TYPES[extname(file)] ?? 'application/octet-stream');
    createReadStream(file).pipe(res);
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  base = `http://127.0.0.1:${server.address().port}`;
  browser = await chromium.launch();
});

after(async () => {
  await browser?.close();
  server?.close();
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

  it('the home screen follows the chosen language', async () => {
    const page = await browser.newPage();
    await page.goto(`${base}/language`);
    await page.getByTestId('language-option-bn').click();
    await page.getByText('ভাষা', { exact: true }).waitFor();
    await page.goto(`${base}/`);
    await page.getByTestId('home-subtitle').waitFor();
    assert.equal(await page.getByTestId('home-subtitle').textContent(), 'লিড, ফলো-আপ আর আপনার টিম, সব এক জায়গায়।');
    await page.close();
  });
});
