// Design-system harness (0A.13-T9) on the web build connected to the local Supabase (`npm run export:web:local`).
// Renders the component gallery in light / dark × English / Bangla, with the weird-labels institution, with a large
// font and with a hard brand colour, saves screenshots (ui-screenshots/, uploaded by CI) and checks automatically:
//   - text contrast against its real background (WCAG AA: 4.5:1, 3:1 for large text)
//   - Bangla text has a line height ≥ 1.5× its font size (vowel signs ু ৃ are not clipped, Ch 13.4)
//   - nothing overflows the screen width
//   - every button / radio / switch is at least 48 × 48 (Ch 47.8)
// It also checks the behaviours: instant theme switch, undo snackbar, dialog, sheet, double submit, draft, Back prompt.
import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';

import { SCREENSHOTS, startWeb } from './helpers.mjs';

let web;
before(async () => {
  web = await startWeb();
});
after(async () => {
  await web?.stop();
});

async function open({ scheme = 'light', language = 'en', query = '', weird = false, height = 5600 }) {
  const page = await web.browser.newPage({ colorScheme: scheme, viewport: { width: 400, height } });
  if (weird) {
    await page.goto(`${web.base}/dev-sign-in`);
    await page.getByPlaceholder('email').fill('weird.member@example.test');
    await page.getByPlaceholder('password').fill('password123');
    await page.getByText('Sign in', { exact: true }).click();
    await page.waitForFunction(() => /"active_institution_id":"[0-9a-f-]{36}"/.test(document.querySelector('[data-testid="dev-claims"]')?.textContent ?? ''));
  }
  await page.goto(`${web.base}/language`);
  await page.getByTestId(`language-option-${language}`).click();
  await page.goto(`${web.base}/dev/gallery${query}`);
  await page.getByTestId('gallery-states').waitFor({ timeout: 20000 });
  if (weird) await page.waitForFunction(() => /Prospective|সম্ভাব্য/.test(document.body.innerText));
  await page.waitForTimeout(600);
  return page;
}

/** Runs the automatic checks inside the page; returns a list of problems. */
async function audit(page) {
  return page.evaluate(() => {
    const problems = [];
    const rgba = (c) => {
      const m = c.match(/rgba?\(([^)]+)\)/);
      if (!m) return null;
      const [r, g, b, a = '1'] = m[1].split(',').map((x) => x.trim());
      return { r: +r, g: +g, b: +b, a: +a };
    };
    const lum = ({ r, g, b }) => {
      const f = (v) => { v /= 255; return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; };
      return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
    };
    const ratio = (x, y) => { const [a, b] = [lum(x), lum(y)].sort((p, q) => q - p); return (a + 0.05) / (b + 0.05); };
    const background = (el) => {
      for (let n = el; n; n = n.parentElement) {
        const c = rgba(getComputedStyle(n).backgroundColor);
        if (c && c.a >= 0.99) return c;
      }
      return { r: 255, g: 255, b: 255, a: 1 };
    };
    const dimmed = (el) => {
      for (let n = el; n; n = n.parentElement) {
        if (Number(getComputedStyle(n).opacity) < 0.99 || n.getAttribute('aria-disabled') === 'true') return true;
      }
      return false;
    };
    const visible = (el) => { const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0; };
    if (document.documentElement.scrollWidth > window.innerWidth + 1) problems.push(`page overflows: ${document.documentElement.scrollWidth}px`);
    for (const el of document.querySelectorAll('input, textarea, [role="button"], [role="radio"], [role="switch"], [role="alert"]')) {
      if (!visible(el)) continue;
      const r = el.getBoundingClientRect();
      if (r.right > window.innerWidth + 1 || r.left < -1) problems.push(`off screen (${Math.round(r.left)}–${Math.round(r.right)}px): ${el.tagName} "${(el.getAttribute('aria-label') ?? el.textContent ?? '').slice(0, 30)}"`);
    }
    for (const el of document.querySelectorAll('body *')) {
      const own = [...el.childNodes].filter((n) => n.nodeType === 3).map((n) => n.textContent).join('').trim();
      if (!own || !visible(el)) continue;
      const style = getComputedStyle(el);
      const size = parseFloat(style.fontSize);
      if (/[ঀ-৿]/.test(own)) {
        const lh = style.lineHeight === 'normal' ? size * 1.2 : parseFloat(style.lineHeight);
        if (lh / size < 1.5) problems.push(`Bangla line height ${(lh / size).toFixed(2)} for "${own.slice(0, 30)}"`);
      }
      if (el.scrollWidth > el.clientWidth + 2 && ['hidden', 'clip'].includes(style.overflowX)) problems.push(`clipped: "${own.slice(0, 30)}"`);
      const box = el.getBoundingClientRect();
      if (box.right > window.innerWidth + 1) problems.push(`text off screen (${Math.round(box.right)}px): "${own.slice(0, 30)}"`);
      if (dimmed(el)) continue;
      const fg = rgba(style.color);
      if (!fg) continue;
      const large = size >= 24 || (size >= 18.6 && Number(style.fontWeight) >= 600);
      const r = ratio(fg, background(el));
      if (r < (large ? 3 : 4.5)) problems.push(`contrast ${r.toFixed(2)} for "${own.slice(0, 30)}" (${style.color})`);
    }
    for (const el of document.querySelectorAll('[role="button"],[role="radio"],[role="switch"]')) {
      if (!visible(el)) continue;
      const r = el.getBoundingClientRect();
      if (r.width < 47.5 || r.height < 47.5) problems.push(`small target ${Math.round(r.width)}×${Math.round(r.height)}: "${(el.getAttribute('aria-label') ?? el.textContent ?? '').slice(0, 30)}"`);
    }
    return problems;
  });
}

const VARIANTS = [
  { name: 'en-light', scheme: 'light', language: 'en' },
  { name: 'en-dark', scheme: 'dark', language: 'en' },
  { name: 'bn-light', scheme: 'light', language: 'bn' },
  { name: 'bn-dark', scheme: 'dark', language: 'bn' },
  { name: 'weird-en-light', scheme: 'light', language: 'en', weird: true },
  { name: 'weird-bn-dark', scheme: 'dark', language: 'bn', weird: true },
  { name: 'large-font-bn-light', scheme: 'light', language: 'bn', query: '?fontScale=1.8', height: 9000 },
  { name: 'large-font-en-dark', scheme: 'dark', language: 'en', query: '?fontScale=1.8', height: 9000 },
  { name: 'yellow-brand-en-light', scheme: 'light', language: 'en', query: '?brand=FFF59D' },
  { name: 'yellow-brand-bn-dark', scheme: 'dark', language: 'bn', query: '?brand=FFF59D' },
];

describe('component gallery screenshots and automatic checks', () => {
  for (const variant of VARIANTS) {
    it(variant.name, async () => {
      const page = await open(variant);
      await page.screenshot({ path: `${SCREENSHOTS}/gallery-${variant.name}.png`, fullPage: true });
      const problems = await audit(page);
      assert.deepEqual(problems, [], problems.join('\n'));
      await page.close();
    });
  }
});

describe('design-system behaviours', () => {
  it('theme switches instantly, without a reload', async () => {
    const page = await web.browser.newPage({ colorScheme: 'light', viewport: { width: 400, height: 900 } });
    await page.goto(`${web.base}/appearance`);
    await page.getByTestId('appearance-dark').waitFor();
    await page.evaluate(() => { window.__noReload = true; });
    const bg = () => page.getByTestId('appearance').evaluate((el) => getComputedStyle(el).backgroundColor);
    const before = await bg();
    await page.getByTestId('appearance-dark').click();
    await page.waitForFunction((b) => getComputedStyle(document.querySelector('[data-testid="appearance"]')).backgroundColor !== b, before);
    assert.equal(await page.evaluate(() => window.__noReload), true);
    await page.screenshot({ path: `${SCREENSHOTS}/appearance-dark.png` });
    await page.getByTestId('appearance-system').click();
    await page.close();
  });

  it('undo snackbar, confirmation dialog and bottom sheet', async () => {
    const page = await open({ height: 900 });
    await page.getByTestId('gallery-snackbar').click();
    assert.equal(await page.getByTestId('snackbar-text').textContent(), 'Note deleted.');
    await page.getByTestId('snackbar-action').click();
    assert.equal(await page.getByTestId('snackbar-text').textContent(), 'Note restored.');
    await page.getByTestId('gallery-dialog').click();
    await page.getByTestId('confirm-dialog').waitFor();
    await page.screenshot({ path: `${SCREENSHOTS}/dialog-en-light.png` });
    await page.getByTestId('confirm-cancel').click();
    await page.getByTestId('confirm-dialog').waitFor({ state: 'detached' });
    await page.getByTestId('gallery-sheet').click();
    await page.getByTestId('gallery-sheet-view').waitFor();
    await page.waitForTimeout(500);
    await page.screenshot({ path: `${SCREENSHOTS}/sheet-en-light.png` });
    await page.getByTestId('gallery-sheet-view-close').click();
    await page.getByTestId('gallery-sheet-view').waitFor({ state: 'detached' });
    await page.close();
  });

  it('long form: double submit saves once, the draft survives a reload, Back asks before discarding', async () => {
    const page = await open({ height: 900 });
    await page.getByTestId('gallery-open-form').click();
    await page.getByTestId('lf-name-input').waitFor();
    await page.getByTestId('lf-name-input').fill('Rahim');
    await page.getByTestId('long-form-save').click();
    await page.getByTestId('long-form-save').click({ force: true }).catch(() => undefined);
    await page.getByTestId('long-form-save').click({ force: true }).catch(() => undefined);
    await page.waitForFunction(() => document.querySelector('[data-testid="long-form-notice"]')?.textContent === 'Saved 1 time(s).');
    assert.equal(await page.getByTestId('lf-name-input').inputValue(), '', 'cleared after save');

    await page.getByTestId('lf-name-input').fill('Karim');
    await page.waitForTimeout(900); // draft autosave
    await page.reload();
    await page.getByTestId('lf-name-input').waitFor();
    await page.waitForFunction(() => document.querySelector('[data-testid="lf-name-input"]')?.value === 'Karim');
    assert.equal(await page.getByTestId('long-form-notice').textContent(), 'Your unsaved draft was restored.');

    await page.goto(`${web.base}/dev/gallery`);
    await page.getByTestId('gallery-open-form').click();
    await page.getByTestId('lf-name-input').waitFor();
    await page.waitForFunction(() => document.querySelector('[data-testid="lf-name-input"]')?.value === 'Karim');
    await page.goBack();
    await page.getByTestId('confirm-dialog').waitFor();
    assert.match(await page.getByTestId('confirm-dialog').textContent(), /Discard changes\?/);
    await page.getByTestId('confirm-cancel').click();
    assert.equal(await page.getByTestId('lf-name-input').inputValue(), 'Karim', 'still on the form after "Keep editing"');
    await page.close();
  });
});
