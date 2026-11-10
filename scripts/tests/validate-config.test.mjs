import assert from 'node:assert/strict';
import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

import { checkConfig } from '../validate-config.mjs';

const repoRoot = fileURLToPath(new URL('../..', import.meta.url));
const tempDirs = [];

// Copy only what the check reads (config/ and app.json) into a temp project.
function makeProject(mutate) {
  const dir = mkdtempSync(join(tmpdir(), 'cfg-'));
  tempDirs.push(dir);
  cpSync(join(repoRoot, 'config'), join(dir, 'config'), { recursive: true });
  cpSync(join(repoRoot, 'app.json'), join(dir, 'app.json'));
  if (mutate) {
    const product = JSON.parse(readFileSync(join(dir, 'config/product.json'), 'utf8'));
    const app = JSON.parse(readFileSync(join(dir, 'app.json'), 'utf8'));
    mutate({ product, app: app.expo });
    writeFileSync(join(dir, 'config/product.json'), JSON.stringify(product));
    writeFileSync(join(dir, 'app.json'), JSON.stringify(app));
  }
  return dir;
}

after(() => tempDirs.forEach((d) => rmSync(d, { recursive: true, force: true })));

describe('checkConfig', () => {
  it('passes for the repository as committed', () => {
    const { problems } = checkConfig(repoRoot);
    assert.deepEqual(problems, []);
  });

  it('rejects an education word in the Android package', () => {
    const dir = makeProject(({ product, app }) => {
      product.androidPackage = 'com.schoolapp.app';
      app.android.package = 'com.schoolapp.app';
    });
    const { problems } = checkConfig(dir);
    assert.ok(problems.some((p) => p.includes('forbidden word "school"')), problems.join('\n'));
  });

  it('rejects an app.json package that differs from config/product.json', () => {
    const dir = makeProject(({ app }) => {
      app.android.package = 'com.other.app';
    });
    const { problems } = checkConfig(dir);
    assert.ok(problems.some((p) => p.includes('differs from config/product.json')), problems.join('\n'));
  });

  it('rejects a missing runtimeVersion', () => {
    const dir = makeProject(({ app }) => {
      delete app.runtimeVersion;
    });
    const { problems } = checkConfig(dir);
    assert.ok(problems.some((p) => p.includes('runtimeVersion')), problems.join('\n'));
  });

  it('rejects config that breaks its schema', () => {
    const dir = makeProject(({ product }) => {
      product.languages = ['en'];
    });
    const { problems } = checkConfig(dir);
    assert.ok(problems.some((p) => p.startsWith('config/product.json/languages')), problems.join('\n'));
  });
});
