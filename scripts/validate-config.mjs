// Validates product-level config (config/*.json) against config/schemas/*.schema.json,
// and checks that app identifiers contain no education words (Ch 3.8, D21).
// Run: npm run check:config   (exit code 1 on any problem)
import Ajv from 'ajv';
import { readFileSync, readdirSync } from 'node:fs';
import { basename, join } from 'node:path';
import { fileURLToPath } from 'node:url';

/** Returns a list of problems found in the project at `root` (empty list = all good). */
export function checkConfig(root) {
  const configDir = join(root, 'config');
  const schemaDir = join(configDir, 'schemas');
  const ajv = new Ajv({ allErrors: true, strict: false });
  const problems = [];

  const readJson = (path) => {
    try {
      return JSON.parse(readFileSync(path, 'utf8'));
    } catch (error) {
      problems.push(`${path}: cannot read JSON (${error.message})`);
      return undefined;
    }
  };

  const configFiles = readdirSync(configDir).filter((f) => f.endsWith('.json'));
  for (const file of configFiles) {
    const name = basename(file, '.json');
    const schema = readJson(join(schemaDir, `${name}.schema.json`));
    const data = readJson(join(configDir, file));
    if (!schema || !data) continue;
    const validate = ajv.compile(schema);
    if (!validate(data)) {
      for (const err of validate.errors ?? []) {
        problems.push(`config/${file}${err.instancePath}: ${err.message}`);
      }
    }
  }

  // Identifier check: package id, scheme and slug must stay neutral and match config/product.json.
  const product = readJson(join(configDir, 'product.json'));
  const app = readJson(join(root, 'app.json'))?.expo;
  if (product && app) {
    const identifiers = {
      'app.json android.package': app.android?.package,
      'app.json scheme': app.scheme,
      'app.json slug': app.slug,
    };
    for (const [where, value] of Object.entries(identifiers)) {
      for (const word of product.forbiddenWordsInIdentifiers ?? []) {
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
    // OTA updates (app-update workflow) reach a build only if the expo-updates module is in it.
    let pkg = null;
    try {
      pkg = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8'));
    } catch { /* a temp test project without package.json */ }
    if (app.updates?.url && pkg && !pkg.dependencies?.['expo-updates']) {
      problems.push('app.json sets updates.url but expo-updates is not a dependency: builds would never receive OTA updates');
    }
  }
  return { problems, fileCount: configFiles.length };
}

// CLI entry point.
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const root = fileURLToPath(new URL('..', import.meta.url));
  const { problems, fileCount } = checkConfig(root);
  if (problems.length) {
    console.error('Config check failed:\n- ' + problems.join('\n- '));
    process.exit(1);
  }
  console.log(`Config check passed (${fileCount} file(s)).`);
}
