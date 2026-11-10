// CI check (0A.16-T2): every manifest permission has a label and help text in English and Bangla, and a neutral key.
import { checkManifests, readManifests, readPermissionLabels } from './manifests.mjs';

const problems = checkManifests(readManifests(), readPermissionLabels());
if (problems.length) {
  for (const p of problems) console.error(p);
  console.error(`Permission manifest check failed: ${problems.length} problem(s).`);
  process.exit(1);
}
console.log('Permission manifests passed.');
