// Module manifests (0A.16-T2): config/modules/*.json declare permissions and sensitive fields as data.
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

export const MODULES_DIR = 'config/modules';
const KEY = /^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$/;
const EDUCATION_WORD = /(^|[._])(students?|courses?|batch(es)?|admissions?|guardians?|alumni|alumnus|college|school|papers)($|[._])/;
const SCOPES = new Set(['own', 'team', 'org_unit', 'branch', 'all']);

export function readManifests(dir = MODULES_DIR) {
  return readdirSync(dir).filter((f) => f.endsWith('.json')).sort()
    .map((f) => ({ file: f, ...JSON.parse(readFileSync(join(dir, f), 'utf8')) }));
}

export function readPermissionLabels() {
  return {
    en: JSON.parse(readFileSync('src/i18n/locales/en/permissions.json', 'utf8')),
    bn: JSON.parse(readFileSync('src/i18n/locales/bn/permissions.json', 'utf8')),
  };
}

const lookup = (tree, path) => path.split('.').reduce((node, part) => (node && typeof node === 'object' ? node[part] : undefined), tree);

/** Problems in the manifests: key format, neutral names, scopes, duplicate keys, missing labels in either language. */
export function checkManifests(manifests, labels) {
  const problems = [];
  const seen = new Set();
  const declared = new Set(manifests.flatMap((m) => (m.permissions ?? []).map((p) => p.key)));
  for (const m of manifests) {
    if (!m.module || !m.release) problems.push(`${m.file}: "module" and "release" are required`);
    for (const p of [...(m.permissions ?? []), ...(m.platform_permissions ?? [])]) {
      if (!KEY.test(p.key ?? '')) problems.push(`${m.file}: "${p.key}" is not a module.action key`);
      if (EDUCATION_WORD.test(p.key ?? '')) problems.push(`${m.file}: "${p.key}" uses an education word; use the neutral key (Ch 8)`);
      if (seen.has(p.key)) problems.push(`${m.file}: "${p.key}" is declared twice`);
      seen.add(p.key);
      for (const [lang, tree] of Object.entries(labels)) {
        if (typeof lookup(tree, `${p.key}.label`) !== 'string') problems.push(`${m.file}: "${p.key}" has no ${lang} label (permissions.json)`);
        if (typeof lookup(tree, `${p.key}.help`) !== 'string') problems.push(`${m.file}: "${p.key}" has no ${lang} help text (permissions.json)`);
      }
    }
    for (const p of m.permissions ?? []) {
      for (const [role, scope] of Object.entries(p.defaults ?? {})) {
        if (p.scopable && !SCOPES.has(scope)) problems.push(`${m.file}: "${p.key}" default for ${role} needs a scope (${[...SCOPES].join(', ')})`);
        if (!p.scopable && scope !== true) problems.push(`${m.file}: "${p.key}" is not scopable; default for ${role} must be true`);
      }
    }
    for (const f of m.fields ?? []) {
      if (f.permission && !declared.has(f.permission)) problems.push(`${m.file}: field ${f.entity}.${f.field} points to unknown permission "${f.permission}"`);
    }
  }
  return problems;
}

/** The SQL that loads the manifests (dollar-quoted JSON; the tag may not appear in the text). */
export function syncSql(manifests) {
  const payload = JSON.stringify(manifests.map(({ file, ...m }) => m));
  const tag = '$manifests_json$';
  if (payload.includes(tag)) throw new Error('manifest text may not contain the quoting tag');
  return `select coalesce(array_to_string(app.sync_permissions(${tag}${payload}${tag}::jsonb), ', '), '')`;
}
