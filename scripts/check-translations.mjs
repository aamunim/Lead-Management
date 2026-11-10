// Translation completeness check (0A.10-T5). Fails when:
// - a namespace file or a key exists in one language but not in another,
// - a value is empty, or a value's {{placeholders}} differ between languages,
// - a message key or action of the error contract has no translation,
// - a locale contains a renamable term (Student, শিক্ষার্থী …): those come from labels (0A.12, Ch 8).
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

export const LOCALES_DIR = 'src/i18n/locales';

/** Renamable / education-only words that must never be fixed in translations (Ch 8.3, 8.9 rule 1). */
export const FORBIDDEN_TERMS = [
  /\bstudents?\b/i, /\bcourses?\b/i, /\bbatch(es)?\b/i, /\badmissions?\b/i, /\bguardians?\b/i, /\balumni\b/i,
  /শিক্ষার্থী/, /ছাত্র/, /ছাত্রী/, /কোর্স/, /ব্যাচ/, /ভর্তি/, /অভিভাবক/,
];

/** Flattens nested JSON into "a.b.c" → string. */
export function flatten(object, prefix = '') {
  const out = {};
  for (const [key, value] of Object.entries(object ?? {})) {
    const path = prefix ? `${prefix}.${key}` : key;
    if (value && typeof value === 'object' && !Array.isArray(value)) Object.assign(out, flatten(value, path));
    else out[path] = value;
  }
  return out;
}

const placeholders = (text) => [...String(text).matchAll(/\{\{\s*([\w.]+)\s*\}\}/g)].map((m) => m[1]).sort().join(',');

/**
 * @param {Record<string, Record<string, object>>} locales  language → namespace → nested messages
 * @returns {string[]} findings
 */
export function compareLocales(locales) {
  const findings = [];
  const languages = Object.keys(locales);
  const namespaces = new Set(languages.flatMap((lang) => Object.keys(locales[lang])));
  for (const ns of namespaces) {
    const flat = {};
    for (const lang of languages) {
      if (!locales[lang][ns]) findings.push(`[missing_namespace] ${lang}/${ns}.json does not exist`);
      flat[lang] = flatten(locales[lang][ns] ?? {});
    }
    const keys = new Set(languages.flatMap((lang) => Object.keys(flat[lang])));
    for (const key of [...keys].sort()) {
      for (const lang of languages) {
        const value = flat[lang][key];
        if (value === undefined) {
          if (locales[lang][ns]) findings.push(`[missing_key] ${lang}/${ns}: "${key}" is missing`);
          continue;
        }
        if (typeof value !== 'string' || value.trim() === '') findings.push(`[empty] ${lang}/${ns}: "${key}" is empty`);
        for (const term of FORBIDDEN_TERMS) {
          if (term.test(String(value))) {
            findings.push(`[renamable_term] ${lang}/${ns}: "${key}" contains "${String(value).match(term)[0]}"; use a label (0A.12)`);
          }
        }
      }
      const shapes = new Set(languages.filter((l) => flat[l][key] !== undefined).map((l) => placeholders(flat[l][key])));
      if (shapes.size > 1) findings.push(`[placeholders] ${ns}: "${key}" has different {{placeholders}} per language`);
    }
  }
  return findings;
}

/** Every error message key and action of the contract must be translated (errors namespace). */
export function checkErrorContract(locales, errors) {
  const findings = [];
  for (const lang of Object.keys(locales)) {
    const flat = flatten(locales[lang].errors ?? {});
    for (const info of Object.values(errors)) {
      const key = info.messageKey.replace(/^errors\./, '');
      if (!flat[key]) findings.push(`[error_contract] ${lang}/errors: "${key}" (code ${info.code}) is not translated`);
      if (info.action !== 'none' && !flat[`actions.${info.action}`]) {
        findings.push(`[error_contract] ${lang}/errors: "actions.${info.action}" is not translated`);
      }
    }
  }
  return [...new Set(findings)];
}

export function readLocales(dir = LOCALES_DIR) {
  const locales = {};
  for (const lang of readdirSync(dir)) {
    locales[lang] = {};
    for (const file of readdirSync(join(dir, lang)).filter((f) => f.endsWith('.json'))) {
      locales[lang][file.replace(/\.json$/, '')] = JSON.parse(readFileSync(join(dir, lang, file), 'utf8'));
    }
  }
  return locales;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  const { ERRORS } = await import('../supabase/functions/_shared/errors.ts');
  const locales = readLocales();
  const findings = [...compareLocales(locales), ...checkErrorContract(locales, ERRORS)];
  if (findings.length) {
    for (const f of findings) console.error(f);
    console.error(`Translation check failed: ${findings.length} finding(s).`);
    process.exit(1);
  }
  const counts = Object.entries(locales).map(([l, ns]) => `${l}: ${Object.values(ns).reduce((n, o) => n + Object.keys(flatten(o)).length, 0)} keys`);
  console.log(`Translation check passed (${counts.join(', ')}).`);
}
