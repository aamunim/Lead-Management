// UI test (0A.12) on the web build connected to the local Supabase (`npm run export:web:local`):
// renamed words appear everywhere the label API is used, in English and Bangla, with no code change; the "weird
// labels" institution is screenshotted in bn/en × light/dark to catch broken layouts (Ch 8.9 rule 4).
import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';

import { INSTITUTION, adminSql, signInAs, signInAsPlatform } from '../e2e/helpers.mjs';
import { SCREENSHOTS, startWeb } from './helpers.mjs';

let web;
before(async () => {
  web = await startWeb();
});
after(async () => {
  adminSql(`delete from public.institution_labels where institution_id = '${INSTITUTION.A}'`);
  await web?.stop();
});

async function page(colorScheme = 'light') {
  return web.browser.newPage({ colorScheme, viewport: { width: 400, height: 900 } });
}

async function signIn(p, email) {
  await p.goto(`${web.base}/dev-sign-in`);
  await p.getByPlaceholder('email').fill(email);
  await p.getByPlaceholder('password').fill('password123');
  await p.getByText('Sign in', { exact: true }).click();
  await p.waitForFunction(() => /"active_institution_id":"[0-9a-f-]{36}"/.test(document.querySelector('[data-testid="dev-claims"]')?.textContent ?? ''));
}

async function chooseLanguage(p, language) {
  await p.goto(`${web.base}/language`);
  await p.getByTestId(`language-option-${language}`).click();
}

const text = (p, id) => p.getByTestId(id).textContent();

describe('labels on the web build', () => {
  it('signed out: the bundled education words, and search finds default words', async () => {
    const p = await page();
    await chooseLanguage(p, 'en');
    await p.goto(`${web.base}/terminology`);
    await p.getByTestId('sample-add').waitFor();
    assert.equal(await text(p, 'sample-add'), 'Add Student');
    assert.equal(await text(p, 'sample-count'), 'Students: 25');
    await p.getByTestId('terminology-search-field-input').fill('admission test');
    assert.equal(await p.getByTestId('label-assessment').count(), 1);
    assert.equal(await p.getByTestId('label-lead').count(), 0);
    await p.close();
  });

  it('renaming client → Trainee for A changes every sentence that uses the label (no code change)', async () => {
    const admin = await signInAsPlatform();
    const { error } = await admin.client.rpc('label_set', {
      p_key: 'client', p_en_singular: 'Trainee', p_en_plural: 'Trainees', p_bn_forms: { base: 'প্রশিক্ষণার্থী' }, p_institution_id: INSTITUTION.A,
    });
    assert.equal(error, null);
    const p = await page();
    await signIn(p, 'a.member@example.test');
    await chooseLanguage(p, 'en');
    await p.goto(`${web.base}/terminology`);
    await p.waitForFunction(() => document.querySelector('[data-testid="sample-add"]')?.textContent === 'Add Trainee');
    assert.equal(await text(p, 'sample-count'), 'Trainees: 25');
    assert.equal(await text(p, 'label-module.clients-word'), 'Trainees');
    await p.getByTestId('terminology-search-field-input').fill('student');
    assert.equal(await p.getByTestId('label-module.clients').count(), 1, 'searching the default word finds the renamed module');
    await chooseLanguage(p, 'bn');
    await p.goto(`${web.base}/terminology`);
    await p.waitForFunction(() => document.querySelector('[data-testid="sample-list"]')?.textContent === 'সব প্রশিক্ষণার্থীদের তালিকা');
    assert.equal(await text(p, 'sample-contact'), 'প্রশিক্ষণার্থীর অভিভাবক');
    await p.close();
  });

  for (const colorScheme of ['light', 'dark']) {
    for (const language of ['en', 'bn']) {
      it(`weird labels institution (${language}, ${colorScheme}): long words render, screenshots saved`, async () => {
        const p = await page(colorScheme);
        await signIn(p, 'weird.member@example.test');
        await chooseLanguage(p, language);
        await p.goto(`${web.base}/`);
        await p.getByTestId('home-subtitle').waitFor();
        await p.waitForFunction(() => /Prospective|সম্ভাব্য/.test(document.querySelector('[data-testid="home-subtitle"]')?.textContent ?? ''));
        assert.match(await text(p, 'home-subtitle'), language === 'en' ? /^Prospective Programme Applicants, / : /^সম্ভাব্য কর্মসূচি আবেদনকারী, /);
        await p.screenshot({ path: `${SCREENSHOTS}/weird-home-${language}-${colorScheme}.png` });
        await p.goto(`${web.base}/terminology`);
        await p.waitForFunction(() => /Professional|পেশাগত/.test(document.querySelector('[data-testid="sample-add"]')?.textContent ?? ''));
        assert.equal(await text(p, 'sample-add'), language === 'en' ? 'Add Professional Development Participant' : 'নতুন পেশাগত উন্নয়ন অংশগ্রহণকারী যোগ করুন');
        const overflow = await p.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
        assert.equal(overflow, false, 'no horizontal overflow with long words');
        await p.screenshot({ path: `${SCREENSHOTS}/weird-terminology-${language}-${colorScheme}.png` });
        await p.close();
      });
    }
  }
});
