// Lint (0B.03-T11, Ch 7.2, Ch 9.2): code follows settings and modules, never the institution's type. No code may read
// `institution_type` except the profile applier (0B.04), which seeds an institution from its type profiles once.
//   node scripts/profiles/lint-institution-type.mjs [root]   → exit 1 and a list of places when the rule is broken
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const CODE = /\.(ts|tsx|js|mjs|cjs|sql|sh|py)$/;
const DIRS = ['src', 'supabase/migrations', 'supabase/functions', 'supabase/seeds', 'supabase/extensions', 'scripts'];
// The applier is the one place allowed to read the type; this lint itself names the word.
const ALLOWED = [/profile[-_]applier[^/]*$/, /^scripts\/profiles\/lint-institution-type\.mjs$/, /^scripts\/tests\/institution-type-lint\.test\.mjs$/];

export function findings(root = '.') {
  const out = [];
  const walk = (dir) => {
    let entries;
    try {
      entries = readdirSync(join(root, dir));
    } catch {
      return;
    }
    for (const entry of entries) {
      if (entry === 'node_modules' || entry.startsWith('.')) continue;
      const path = join(dir, entry);
      if (statSync(join(root, path)).isDirectory()) walk(path);
      else if (CODE.test(entry) && !ALLOWED.some((re) => re.test(path))) {
        readFileSync(join(root, path), 'utf8').split('\n').forEach((line, i) => {
          if (/(?<!settings\.)\binstitution_type\b/.test(line)) out.push(`${relative('.', path)}:${i + 1}: ${line.trim()}`);
        });
      }
    }
  };
  for (const dir of DIRS) walk(dir);
  return out;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const found = findings(process.argv[2] ?? '.');
  if (found.length) {
    console.error(found.join('\n'));
    console.error('LINT [institution_type] only the profile applier may read institution_type; use settings and modules instead (Ch 7.2).');
    process.exit(1);
  }
}
