// Unit tests for the locale lint (0B.01-T7): a planted literal is caught; allowed files and tests are not.
import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { checkText } from '../check-locale-literals.mjs';

describe('locale lint', () => {
  it('catches a planted time zone, taka sign and country code', () => {
    const found = checkText('src/lib/x.ts', "const tz = 'Asia/Dhaka';\nconst c = '৳';\nconst cc = '+880';");
    assert.equal(found.length, 3);
  });
  it('does not flag long numbers that merely contain 880', () => {
    assert.equal(checkText('src/lib/x.ts', 'const n = 18801234567;').length, 0);
  });
  it('allows the settings seed and tests', () => {
    assert.equal(checkText('supabase/migrations/20261110200000_locale.sql', "'Asia/Dhaka'").length, 0);
    assert.equal(checkText('scripts/tests/format.test.mjs', "'৳'").length, 0);
  });
});
