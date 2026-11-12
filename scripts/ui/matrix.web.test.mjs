// Screenshot matrix (0A.20-T3, Ch 47.9 / 47.11, Ch 8.9 rule 4): every screen route × light / dark × bn / en, signed in
// as the weird-labels institution's Super Admin, compared with the committed baselines in tests/screenshots/.
// - A route file without an entry in ROUTES fails the test (new screens join the matrix).
// - Parts that change on their own (dates, the change log) are masked.
// - A small difference is tolerated (anti-aliasing); a real change fails and writes a diff image to ui-screenshots/diff/.
// Baselines are made in CI (the GitHub runner draws text differently from other machines): run the workflow
// "screenshots-update" on the branch after an intended change; it commits tests/screenshots/. The diff runs in CI
// (or with SCREENSHOT_DIFF=1); elsewhere the matrix still captures every screen and checks the route list.
// Run a subset: SCREENS=users,roles npm run test:ui -- scripts/ui/matrix.web.test.mjs
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { join, relative } from 'node:path';
import { after, before, describe, it } from 'node:test';
import { createRequire } from 'node:module';

import { adminSql } from '../e2e/helpers.mjs';
import { SCREENSHOTS, startWeb } from './helpers.mjs';

const require = createRequire(import.meta.url);
const { PNG } = require('pngjs');

const BASELINES = 'tests/screenshots';
const UPDATE = process.env.UPDATE_SCREENSHOTS === '1';
const COMPARE = process.env.CI === 'true' || process.env.SCREENSHOT_DIFF === '1';
const ONLY = process.env.SCREENS ? new Set(process.env.SCREENS.split(',')) : null;
const INST_C = 'c0000000-0000-4000-8000-00000000000c';
const WEIRD = '66666666-6666-4666-8666-666666666666';
// A pixel differs when a colour channel moves more than CHANNEL; an image fails above MAX_RATIO of its pixels.
const CHANNEL = 48;
const MAX_RATIO = 0.005;

// Every screen route: file under src/app, the URL, the element that says "loaded", what to mask, signed in or not.
const ROUTES = [
  { name: 'sign-in', file: 'sign-in.tsx', path: '/sign-in', ready: 'sign-in-submit', signedOut: true },
  { name: 'language', file: 'language.tsx', path: '/language', ready: 'language' },
  { name: 'appearance', file: 'appearance.tsx', path: '/appearance', ready: 'appearance' },
  { name: 'words', file: 'terminology.tsx', path: '/terminology', ready: 'terminology-samples' },
  { name: 'samples', file: 'samples.tsx', path: '/samples', ready: 'samples-title', mask: ['[data-testid^="date"]', '[data-testid^="time"]', '[data-testid*="today"]'] },
  { name: 'home', file: '(app)/(tabs)/home.tsx', path: '/home', ready: 'home' },
  { name: 'more', file: '(app)/(tabs)/more.tsx', path: '/more', ready: 'more' },
  { name: 'settings', file: '(app)/(tabs)/settings.tsx', path: '/settings', ready: 'settings-users' },
  { name: 'profile', file: '(app)/profile.tsx', path: '/profile', ready: 'profile' },
  { name: 'users', file: '(app)/admin/users.tsx', path: '/admin/users', ready: 'user-weird.member' },
  { name: 'user', file: '(app)/admin/user/[id].tsx', path: `/admin/user/${WEIRD}`, ready: 'user-roles', mask: ['[data-testid^="assignment-"]'] },
  { name: 'assign', file: '(app)/admin/assign.tsx', path: `/admin/assign?user=${WEIRD}`, ready: 'assign-role' },
  { name: 'roles', file: '(app)/admin/roles.tsx', path: '/admin/roles', ready: 'roles-compare' },
  { name: 'role', file: '(app)/admin/role/[id].tsx', path: '/admin/role/{role}', ready: 'role-permissions' },
  { name: 'role-compare', file: '(app)/admin/role-compare.tsx', path: '/admin/role-compare', ready: 'compare-a' },
  { name: 'new-permissions', file: '(app)/admin/new-permissions.tsx', path: '/admin/new-permissions', ready: 'new-permissions' },
  { name: 'explain', file: '(app)/admin/explain.tsx', path: '/admin/explain', ready: 'explain-check' },
  { name: 'audit', file: '(app)/admin/audit.tsx', path: '/admin/audit', ready: 'audit-area-all', mask: ['[data-testid="audit-list"]', '[data-testid="audit-empty"]'] },
  { name: 'branches', file: '(app)/admin/branches.tsx', path: '/admin/branches', ready: 'branches-add' },
  { name: 'terminology', file: '(app)/admin/terminology.tsx', path: '/admin/terminology', ready: 'term-client' },
  { name: 'institution-type', file: '(app)/admin/institution-type.tsx', path: '/admin/institution-type', ready: 'types-choose' },
  { name: 'modules', file: '(app)/admin/modules.tsx', path: '/admin/modules', ready: 'module-leads' },
  { name: 'plan', file: '(app)/admin/plan.tsx', path: '/admin/plan', ready: 'usage-users' },
  { name: 'custom-fields', file: '(app)/admin/custom-fields.tsx', path: '/admin/custom-fields', ready: 'fields-add' },
  { name: 'support-log', file: '(app)/admin/support-log.tsx', path: '/admin/support-log', ready: 'support-log-empty' },
];
// Not in the matrix on purpose: redirects and developer-only screens.
// The Master Admin panel needs a two-step sign-in; its screens are captured by scripts/ui/panel.web.test.mjs.
const SKIPPED = new Set(['index.tsx', 'dev-sign-in.tsx', 'dev/form.tsx', 'dev/gallery.tsx',
  'panel/sign-in.tsx', 'panel/index.tsx', 'panel/users.tsx', 'panel/[section].tsx', 'panel/profiles.tsx', 'panel/profile/[kind]/[key].tsx',
  'panel/institutions.tsx', 'panel/institution/[id].tsx', 'panel/product-labels.tsx', 'panel/plans.tsx']);

function routeFiles(dir = 'src/app') {
  const out = [];
  for (const entry of readdirSync(dir)) {
    const path = join(dir, entry);
    if (statSync(path).isDirectory()) out.push(...routeFiles(path));
    else if (entry.endsWith('.tsx') && !entry.startsWith('_') && !entry.startsWith('+')) out.push(relative('src/app', path));
  }
  return out;
}

/** Share of pixels that differ by more than CHANNEL in any colour channel; writes a red-on-grey diff image. */
function compare(actualBuffer, baselinePath, diffPath) {
  const a = PNG.sync.read(actualBuffer);
  const b = PNG.sync.read(readFileSync(baselinePath));
  if (a.width !== b.width || a.height !== b.height) return { ratio: 1, reason: `size ${a.width}×${a.height} vs ${b.width}×${b.height}` };
  const diff = new PNG({ width: a.width, height: a.height });
  let changed = 0;
  for (let i = 0; i < a.data.length; i += 4) {
    const d = Math.max(Math.abs(a.data[i] - b.data[i]), Math.abs(a.data[i + 1] - b.data[i + 1]), Math.abs(a.data[i + 2] - b.data[i + 2]));
    const grey = (a.data[i] + a.data[i + 1] + a.data[i + 2]) / 6;
    if (d > CHANNEL) {
      changed += 1;
      diff.data.set([255, 0, 0, 255], i);
    } else {
      diff.data.set([grey, grey, grey, 255], i);
    }
  }
  const ratio = changed / (a.width * a.height);
  if (ratio > MAX_RATIO) writeFileSync(diffPath, PNG.sync.write(diff));
  return { ratio };
}

let web;
let roleId;
before(async () => {
  web = await startWeb();
  mkdirSync(BASELINES, { recursive: true });
  mkdirSync(join(SCREENSHOTS, 'diff'), { recursive: true });
  // Weird-labels institution with branches on and one long-named branch (stable data for the screens).
  adminSql(`insert into public.app_settings (institution_id, key, value) values ('${INST_C}', 'branches_enabled', 'true')
              on conflict (institution_id, key) do update set value = 'true';
            insert into public.org_units (institution_id, id, kind, name) values ('${INST_C}', 'c1000000-0000-4000-8000-0000000000c1', 'branch',
              'Professional Studies Campus of the Northern Region') on conflict do nothing;
            insert into public.branches (institution_id, org_unit_id, address, phone) values ('${INST_C}', 'c1000000-0000-4000-8000-0000000000c1',
              'House 12, Road 7, A Very Long Address Line, Dhaka 1209', '01711000003') on conflict do nothing;
            select app.bump_settings_version('${INST_C}');`);
  roleId = adminSql(`select id from public.roles where institution_id = '${INST_C}' and template_key = 'admin'`).match(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/)[0];
});
after(async () => {
  adminSql(`delete from public.branches where institution_id = '${INST_C}' and org_unit_id = 'c1000000-0000-4000-8000-0000000000c1';
            delete from public.org_units where institution_id = '${INST_C}' and id = 'c1000000-0000-4000-8000-0000000000c1';
            delete from public.app_settings where institution_id = '${INST_C}' and key = 'branches_enabled';
            update public.profiles set preferred_language = null where email = 'weird.member@example.test';`);
  await web?.stop();
});

describe('screenshot matrix', () => {
  it('every screen route is in the matrix', () => {
    const missing = routeFiles().filter((f) => !SKIPPED.has(f) && !ROUTES.some((r) => r.file === f));
    assert.deepEqual(missing, [], `add these routes to ROUTES in ${relative('.', import.meta.filename)}`);
  });

  for (const [scheme, language] of [['light', 'en'], ['dark', 'en'], ['light', 'bn'], ['dark', 'bn']]) {
    it(`${language} ${scheme}`, async () => {
      const failures = [];
      const page = await web.browser.newPage({ viewport: { width: 400, height: 860 }, colorScheme: scheme });
      // Sign in once; choose the language (stored on the profile, so it follows the person).
      await page.goto(`${web.base}/sign-in`);
      await page.getByTestId('sign-in-email-input').fill('weird.member@example.test');
      await page.getByTestId('sign-in-password-input').fill('password123');
      await page.getByTestId('sign-in-submit').click();
      await page.getByTestId('home').waitFor({ timeout: 20000 });
      await page.goto(`${web.base}/language`);
      await page.getByTestId(`language-option-${language}`).click();
      const signedOut = await web.browser.newPage({ viewport: { width: 400, height: 860 }, colorScheme: scheme });
      await signedOut.goto(`${web.base}/language`);
      await signedOut.getByTestId(`language-option-${language}`).click();

      for (const route of ROUTES) {
        if (ONLY && !ONLY.has(route.name)) continue;
        const p = route.signedOut ? signedOut : page;
        await p.goto(`${web.base}${route.path.replace('{role}', roleId)}`);
        await p.getByTestId(route.ready).first().waitFor({ timeout: 30000 });
        await p.evaluate(() => document.fonts.ready);
        await p.waitForTimeout(500);
        const name = `${route.name}-${language}-${scheme}.png`;
        const shot = await p.screenshot({ mask: (route.mask ?? []).map((s) => p.locator(s)), animations: 'disabled' });
        writeFileSync(join(SCREENSHOTS, `matrix-${name}`), shot);
        const baseline = join(BASELINES, name);
        if (UPDATE || !COMPARE) {
          if (!UPDATE) continue;
          writeFileSync(baseline, shot);
          continue;
        }
        if (!existsSync(baseline)) {
          failures.push(`${name}: no baseline (run npm run screens:update and commit tests/screenshots/)`);
          continue;
        }
        const result = compare(shot, baseline, join(SCREENSHOTS, 'diff', name));
        if (result.ratio > MAX_RATIO) failures.push(`${name}: ${(result.ratio * 100).toFixed(2)} % of pixels changed${result.reason ? ` (${result.reason})` : ''}`);
      }
      await signedOut.close();
      await page.close();
      assert.deepEqual(failures, [], 'screens changed; see ui-screenshots/diff/ (intended? run npm run screens:update)');
    });
  }
});
