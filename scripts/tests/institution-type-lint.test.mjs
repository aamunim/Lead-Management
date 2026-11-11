// 0B.03-T11: the institution_type lint fails on a planted branch outside the profile applier.
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';

import { findings } from '../profiles/lint-institution-type.mjs';

test('the repository passes the institution_type lint', () => {
  assert.deepEqual(findings('.'), []);
});

test('a planted institution_type branch fails; the applier may read it', () => {
  const root = mkdtempSync(join(tmpdir(), 'type-lint-'));
  try {
    mkdirSync(join(root, 'src/lib'), { recursive: true });
    mkdirSync(join(root, 'supabase/migrations'), { recursive: true });
    writeFileSync(join(root, 'src/lib/fees.ts'), "export const monthly = (i: { institution_type: string }) => i.institution_type === 'school';\n");
    writeFileSync(join(root, 'supabase/migrations/1_x.sql'), "select 1 where institution_type = 'college';\n");
    writeFileSync(join(root, 'supabase/migrations/2_profile_applier.sql'), "select institution_type from x;\n");
    const found = findings(root);
    assert.equal(found.length, 2);
    assert.ok(found.some((f) => f.includes('fees.ts')) && found.some((f) => f.includes('1_x.sql')));
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
