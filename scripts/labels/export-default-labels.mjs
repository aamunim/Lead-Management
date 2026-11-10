// Bundled default labels (0A.12): the education-pack words the app shows before the institution's own labels arrive
// (first start, offline). Generated from the database so they can never drift:
//   node scripts/labels/export-default-labels.mjs           → writes src/i18n/locales/{en,bn}/labels.json + src/i18n/label-meta.json
//   node scripts/labels/export-default-labels.mjs --check   → fails if the files differ from the database (CI)
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';

const DB_URL = process.env.DB_URL ?? 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const PACK = 'education'; // D20: education only for now; per-pack bundles come with 0B type profiles

const sql = `
  select jsonb_object_agg(k.key, r order by k.sort_order)
  from public.label_keys k
  cross join lateral (
    select jsonb_build_object('en_singular', d.en_singular, 'en_plural', d.en_plural, 'bn_forms', d.bn_forms) as r
    from public.label_defaults d
    where d.key = k.key and ((d.scope = 'pack' and d.scope_key = '${PACK}') or d.scope = 'product')
    order by case d.scope when 'pack' then 1 else 2 end limit 1) x`;
const rows = JSON.parse(execFileSync('psql', [DB_URL, '-X', '-A', '-t', '-c', sql], { encoding: 'utf8' }));
const metaSql = `select jsonb_object_agg(key, jsonb_build_object('group', label_group, 'animate', animate, 'max_length', max_length,
  'lockable', lockable, 'legacy_key', legacy_key, 'sort_order', sort_order)) from public.label_keys`;
const meta = JSON.parse(execFileSync('psql', [DB_URL, '-X', '-A', '-t', '-c', metaSql], { encoding: 'utf8' }));
const sortedMeta = Object.fromEntries(Object.entries(meta).sort((a, b) => a[1].sort_order - b[1].sort_order));

/** "module.clients" → { module: { clients: … } } so t('labels:module.clients.plural') works. */
function nest(target, key, value) {
  const parts = key.split('.');
  let node = target;
  for (const part of parts.slice(0, -1)) node = node[part] ??= {};
  node[parts.at(-1)] = value;
}

const en = {};
const bn = {};
for (const [key, r] of Object.entries(rows)) {
  nest(en, key, { singular: r.en_singular, plural: r.en_plural });
  const f = r.bn_forms;
  nest(bn, key, { singular: f.base, plural: f.plural, possessive: f.possessive, objective: f.objective, plural_oblique: f.plural_oblique });
}

const files = { 'src/i18n/locales/en/labels.json': en, 'src/i18n/locales/bn/labels.json': bn, 'src/i18n/label-meta.json': sortedMeta };
let stale = false;
for (const [path, data] of Object.entries(files)) {
  const text = `${JSON.stringify(data, null, 2)}\n`;
  if (process.argv.includes('--check')) {
    let current = '';
    try { current = readFileSync(path, 'utf8'); } catch { /* missing */ }
    if (current !== text) {
      console.error(`${path} differs from the database defaults. Run: node scripts/labels/export-default-labels.mjs`);
      stale = true;
    }
  } else {
    writeFileSync(path, text);
  }
}
if (stale) process.exit(1);
console.log(process.argv.includes('--check') ? 'Bundled labels match the database.' : `Wrote ${Object.keys(rows).length} labels.`);
