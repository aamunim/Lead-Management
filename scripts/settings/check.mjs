// CI check (0B.01-T6): every setting key and configuration group in the database has a schema, an owner module and a
// label (+ help for keys) in English and Bangla; every institution key is guarded by a registered area permission.
// Needs the database (runs after migrations + `npm run db:permissions`).
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

const DB_URL = process.env.DB_URL || 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const rows = JSON.parse(execFileSync('psql', [DB_URL, '-X', '-A', '-t', '-c', `select json_build_object(
  'keys', (select json_agg(json_build_object('key', d.key, 'scope', d.scope, 'label_key', d.label_key, 'owner', d.owner_module,
            'has_schema', d.schema is not null, 'area_ok', d.scope <> 'institution' or exists (select 1 from public.permissions p where p.key = d.area and p.kind = 'institution')))
           from public.setting_definitions d),
  'groups', (select json_agg(json_build_object('key', g.group_key, 'label_key', g.label_key)) from public.config_groups g))`], { encoding: 'utf8' }).trim());

const lookup = (lang, key) => {
  const [ns, path] = key.split(':');
  const tree = JSON.parse(readFileSync(`src/i18n/locales/${lang}/${ns}.json`, 'utf8'));
  return path.split('.').reduce((node, part) => (node && typeof node === 'object' ? node[part] : undefined), tree);
};
const problems = [];
for (const k of rows.keys) {
  if (!k.label_key) problems.push(`${k.key}: no label key`);
  if (!k.owner) problems.push(`${k.key}: no owner module`);
  if (!k.has_schema) problems.push(`${k.key}: no schema`);
  if (!k.area_ok) problems.push(`${k.key}: its area is not a registered permission`);
  for (const lang of ['en', 'bn']) {
    if (k.label_key && typeof lookup(lang, `${k.label_key}.label`) !== 'string') problems.push(`${k.key}: no ${lang} label (${k.label_key}.label)`);
    if (k.label_key && typeof lookup(lang, `${k.label_key}.help`) !== 'string') problems.push(`${k.key}: no ${lang} help (${k.label_key}.help)`);
  }
}
for (const g of rows.groups) {
  for (const lang of ['en', 'bn']) {
    if (typeof lookup(lang, `${g.label_key}.label`) !== 'string') problems.push(`group ${g.key}: no ${lang} label`);
  }
}
if (problems.length) {
  for (const p of problems) console.error(p);
  console.error(`Settings catalog check failed: ${problems.length} problem(s). See docs/dev/SETTINGS.md "Adding a setting key".`);
  process.exit(1);
}
console.log(`Settings catalog passed: ${rows.keys.length} keys, ${rows.groups.length} groups.`);
