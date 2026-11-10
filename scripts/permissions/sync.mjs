// Loads every module manifest into the permission registry (app.sync_permissions). Run after migrations on every
// deploy and after `supabase db reset` locally / in CI. New permissions are rolled out by the database function to
// system roles (template defaults) and to inheriting custom roles (never sensitive ones).
import { execFileSync } from 'node:child_process';

import { checkManifests, readManifests, readPermissionLabels, syncSql } from './manifests.mjs';

const DB_URL = process.env.DB_URL || 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const manifests = readManifests();
const problems = checkManifests(manifests, readPermissionLabels());
if (problems.length) {
  for (const p of problems) console.error(p);
  process.exit(1);
}
const added = execFileSync('psql', [DB_URL, '-X', '-A', '-t', '-v', 'ON_ERROR_STOP=1'], { input: syncSql(manifests), encoding: 'utf8' }).trim();
console.log(`Permission registry synced (${manifests.length} module(s)). New: ${added || 'none'}`);
