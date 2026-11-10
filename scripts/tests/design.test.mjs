// Unit tests for 0A.13 design tokens: contrast checker, brand fallback, every role pair readable, Bangla line height.
import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { checkBrand, colorRoles, contrastRatio, DEFAULT_BRAND, TEXT_PAIRS, tone } from '../../src/ui/tokens/color.ts';
import { BANGLA_LINE_HEIGHT, typeScale } from '../../src/ui/tokens/type.ts';

const BRANDS = [DEFAULT_BRAND, '#FFF59D', '#FFEB3B', '#00BCD4', '#4E342E', '#000000', '#FFFFFF', '#E53935', '#2E7D32', '#9C27B0', 'not-a-colour'];

describe('contrast checker', () => {
  it('computes WCAG ratios', () => {
    assert.equal(Math.round(contrastRatio('#000000', '#FFFFFF') * 10) / 10, 21);
    assert.equal(contrastRatio('#777777', '#777777'), 1);
  });
  it('rejects a light-yellow brand colour for text (Ch 47.12 #2)', () => {
    const check = checkBrand('#FFF59D', 'light');
    assert.equal(check.usableAsPrimary, false);
    const roles = colorRoles('#FFF59D', 'light');
    assert.equal(roles.brandAccentOnly, true);
    assert.equal(roles.accent, '#FFF59D', 'the institution colour is kept as an accent');
    assert.ok(contrastRatio(roles.primary, roles.surface) >= 4.5, 'a safe tone of the same hue is used for text');
  });
  it('uses the platform blue itself in light mode', () => {
    const roles = colorRoles(DEFAULT_BRAND, 'light');
    assert.equal(roles.primary, DEFAULT_BRAND);
    assert.equal(roles.brandAccentOnly, false);
  });
  it('generates tones from dark to light', () => {
    assert.ok(contrastRatio(tone(DEFAULT_BRAND, 10), '#FFFFFF') > contrastRatio(tone(DEFAULT_BRAND, 90), '#FFFFFF'));
  });
});

describe('every text/background pair is readable, for any brand colour, light and dark', () => {
  for (const brand of BRANDS) {
    for (const mode of ['light', 'dark']) {
      it(`${brand} ${mode}`, () => {
        const roles = colorRoles(brand, mode);
        for (const [fg, bg, min] of TEXT_PAIRS) {
          const ratio = contrastRatio(roles[fg], roles[bg]);
          assert.ok(ratio >= min, `${fg} on ${bg}: ${ratio.toFixed(2)} < ${min} (${roles[fg]} on ${roles[bg]})`);
        }
      });
    }
  }
});

describe('typography', () => {
  it('Bangla gets a taller line height and the Bangla font', () => {
    const bn = typeScale('bn').body;
    const en = typeScale('en').body;
    assert.ok(bn.lineHeight >= Math.ceil(bn.fontSize * BANGLA_LINE_HEIGHT));
    assert.ok(bn.lineHeight > en.lineHeight);
    assert.equal(bn.fontFamily, 'NotoSansBengali');
    assert.equal(en.fontFamily, undefined);
  });
  it('follows the phone font size, within limits', () => {
    assert.equal(typeScale('en', 1.5).body.fontSize, 24);
    assert.equal(typeScale('en', 5).body.fontSize, 32, 'capped at 2×');
  });
});
