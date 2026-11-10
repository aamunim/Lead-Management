// Validates product-level config (config/*.json) against config/schemas/*.schema.json,
// and checks that app identifiers contain no education words (Ch 3.8, D21).
// Run: npm run check:config   (exit code 1 on any problem)
import Ajv from 'ajv';
import { readFileSync, readdirSync } from 'node:fs';
import { basename, join } from 'node:path';

const root = new URL('..', import.meta.url).pathname;
const configDir = join(root, 'config');
const schemaDir = join(configDir, 'schemas');
const ajv = new Ajv({ allErrors: true, strict: false });
const problems = [];

const readJson = (path) => {
  try {
    return JSON.parse(readFileSync(path, 'utf8'));
  } catch (error) {
    problems.push(`${path}: not valid JSON (${error.message})`);
    return undefined;
  }
};

const configFiles = readdirSync(configDir).filter((f) => f.endsWith('.json'));
for (const file of configFiles) {
  const name = basename(file, '.json');
  const schemaPath = join(schemaDir, `${name}.schema.json`);
  const schema = readJson(schemaPath);
  const data = readJson(join(configDir, file));
  if (!schema || !data) continue;
  const validate = ajv.compile(schema);
  if (!validate(data)) {
    for (const err of validate.errors ?? []) {
      problems.push(`config/${file}${err.instancePath}: ${err.message}`);
    }
  }
}

// Identifier check: package id, scheme and slug must stay neutral.
const product = readJson(join(configDir, 'product.json'));
const app = readJson(join(root, 'app.json'))?.expo;
if (product && app) {
  const identifiers = {
    'app.json android.package': app.android?.package,
    'app.json scheme': app.scheme,
    'app.json slug': app.slug,
  };
  for (const [where, value] of Object.entries(identifiers)) {
    for (const word of product.forbiddenWordsInIdentifiers) {
      if (typeof value === 'string' && value.toLowerCase().includes(word)) {
        problems.push(`${where} "${value}" contains the forbidden word "${word}"`);
      }
    }
  }
  if (app.android?.package !== product.androidPackage) {
    problems.push(`app.json android.package (${app.android?.package}) differs from config/product.json (${product.androidPackage})`);
  }
  if (app.scheme !== product.deepLinkScheme) {
    problems.push(`app.json scheme (${app.scheme}) differs from config/product.json (${product.deepLinkScheme})`);
  }
  if (!app.runtimeVersion || typeof app.runtimeVersion !== 'string') {
    problems.push('app.json runtimeVersion must be pinned to a fixed string (Ch 3.8)');
  }
}

if (problems.length) {
  console.error('Config check failed:\n- ' + problems.join('\n- '));
  process.exit(1);
}
console.log(`Config check passed (${configFiles.length} file(s)).`);
