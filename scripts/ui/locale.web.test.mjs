// UI test (0A.11) on the web build connected to the local Supabase (`npm run export:web:local`):
// money in lakh style and dates from the institution settings, in English and Bangla, light and dark, with
// screenshots of the money field and the date picker (saved to ui-screenshots/ and uploaded by CI).
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

async function openSamples(colorScheme, language) {
  const page = await web.browser.newPage({ colorScheme, viewport: { width: 400, height: 900 } });
  await page.goto(`${web.base}/language`);
  await page.getByTestId(`language-option-${language}`).click();
  await page.goto(`${web.base}/samples`);
  await page.getByTestId('money-100000').waitFor();
  // Wait for the locale settings (currency symbol) from the server.
  await page.waitForFunction(() => document.querySelector('[data-testid="money-100000"]')?.textContent?.includes('৳'), null, { timeout: 15000 });
  return page;
}

describe('formats and locale samples on the web build', () => {
  for (const colorScheme of ['light', 'dark']) {
    it(`English (${colorScheme}): lakh money, Dhaka date near midnight, ASCII storage`, async () => {
      const page = await openSamples(colorScheme, 'en');
      assert.equal(await page.getByTestId('money-100000').textContent(), '৳1,00,000');
      assert.equal(await page.getByTestId('number-12345678').textContent(), '1,23,45,678');
      assert.equal(await page.getByTestId('date-midnight').textContent(), '11 Nov 2026, 12:30 AM');
      assert.equal(await page.getByTestId('date-only').textContent(), '11 November 2026 · 11 Nov 2026');

      await page.getByTestId('input-phone').fill('০১৭১১-২২৩৩৪৪');
      assert.equal(await page.getByTestId('input-phone').inputValue(), '01711-223344', 'Bangla digits become ASCII while typing');
      assert.equal(await page.getByTestId('input-phone-stored').textContent(), 'Stored as: 01711223344');
      await page.getByTestId('input-amount').fill('১,৫০,০০০');
      assert.equal(await page.getByTestId('input-amount-stored').textContent(), 'Stored as: 150000');
      await page.getByTestId('input-phone').click();
      assert.equal(await page.getByTestId('input-amount').inputValue(), '৳1,50,000', 'amount shown in lakh style after editing');
      await page.getByTestId('input-amount').screenshot({ path: `${SCREENSHOTS}/money-field-en-${colorScheme}.png` });

      await page.getByTestId('input-date').click();
      await page.getByTestId('input-date-calendar-month').waitFor();
      await page.waitForTimeout(700); // let the fade-in finish before the screenshot
      assert.equal(await page.getByTestId('input-date-calendar-month').textContent(), 'November 2026');
      await page.screenshot({ path: `${SCREENSHOTS}/date-picker-en-${colorScheme}.png` });
      await page.getByTestId('day-2026-11-20').click();
      await page.getByTestId('input-date-done').click();
      assert.equal(await page.getByTestId('input-date-stored').textContent(), 'Stored as: 2026-11-20', 'a date-only value is never shifted');
      await page.close();
    });

    it(`Bangla (${colorScheme}): words, day periods and optional Bangla digits`, async () => {
      const page = await openSamples(colorScheme, 'bn');
      assert.equal(await page.getByTestId('money-100000').textContent(), '৳1,00,000', 'Bangla digits are off by default');
      assert.equal(await page.getByTestId('date-midnight').textContent(), '11 নভে 2026, রাত 12:30');
      await page.getByTestId('samples-bangla-digits').click();
      assert.equal(await page.getByTestId('money-100000').textContent(), '৳১,০০,০০০');
      assert.equal(await page.getByTestId('date-midnight').textContent(), '১১ নভে ২০২৬, রাত ১২:৩০');
      await page.getByTestId('input-amount').fill('১০০০০০');
      await page.getByTestId('input-phone').click();
      assert.equal(await page.getByTestId('input-amount-stored').textContent(), 'যেভাবে সংরক্ষণ হবে: 100000', 'storage stays ASCII');
      await page.getByTestId('input-amount').screenshot({ path: `${SCREENSHOTS}/money-field-bn-${colorScheme}.png` });

      await page.getByTestId('input-datetime').click();
      await page.getByTestId('hour-15').click();
      await page.getByTestId('minute-30').click();
      await page.waitForTimeout(700);
      await page.screenshot({ path: `${SCREENSHOTS}/date-picker-bn-${colorScheme}.png` });
      await page.getByTestId('input-datetime-done').click();
      const stored = await page.getByTestId('input-datetime-stored').textContent();
      assert.match(stored, /T09:30:00\.000Z$/, '15:30 in Dhaka is stored as 09:30 UTC');
      await page.close();
    });
  }
});
