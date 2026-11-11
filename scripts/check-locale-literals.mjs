// Locale lint (0B.01-T7, Ch 51 lesson on hard-coding): Bangladesh defaults — the time zone "Asia/Dhaka", the taka
// sign "৳" and the country code 880 — live in the settings seed only. Anywhere else in app or server code they would
// be the single-college hard-coding of the old app again. Tests, docs and the files below (with a reason) are allowed.
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

export const PATTERNS = [/Asia\/Dhaka/, /৳/, /(?<![0-9])\+?880(?![0-9]{9})/];
export const ALLOWED = new Map([
  ['supabase/migrations/20261110200000_locale.sql', 'the settings seed: locale defaults (0A.11); parse_number strips typed currency signs'],
  ['supabase/migrations/20261112090000_settings_catalog.sql', 'the settings catalog (0B.01)'],
  ['src/lib/format.ts', 'typed-number parsing ignores a currency sign the person typed (same characters as app.parse_number)'],
  ['supabase/functions/_shared/redact.ts', 'log redaction must catch Bangladeshi numbers in any form, whatever the institution setting'],
]);
const ROOTS = ['src', 'supabase/functions', 'supabase/migrations', 'supabase/extensions', 'scripts'];
const SKIP = [/^scripts\/(tests|e2e|ui)\//, /^supabase\/tests\//, /\.test\./, /^scripts\/check-locale-literals\.mjs$/, /i18n\/locales\//];

function files(dir) {
  const out = [];
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) out.push(...files(p));
    else if (/\.(ts|tsx|mjs|js|sql)$/.test(name)) out.push(p);
  }
  return out;
}

/** @returns {{ file: string, line: number, text: string }[]} */
export function checkText(file, text) {
  if (ALLOWED.has(file) || SKIP.some((r) => r.test(file))) return [];
  const findings = [];
  text.split('\n').forEach((line, i) => {
    if (PATTERNS.some((p) => p.test(line))) findings.push({ file, line: i + 1, text: line.trim().slice(0, 120) });
  });
  return findings;
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const findings = ROOTS.flatMap((root) => files(root)).flatMap((f) => checkText(f, readFileSync(f, 'utf8')));
  if (findings.length) {
    for (const f of findings) console.error(`${f.file}:${f.line} hard-coded locale value: ${f.text}`);
    console.error('Locale lint failed: read time zone, currency and phone rules from the settings (useFormat / app.phone_rules).');
    process.exit(1);
  }
  console.log('Locale lint passed.');
}
