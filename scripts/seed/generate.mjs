// Seed generator (0A.20-T1): deterministic test institutions as SQL, used by CI (role-matrix and benchmark tests
// load it inside a transaction) and by staging (`--apply`). Ids are derived from names (same input → same ids), every
// statement is idempotent, and nothing here is real data. Password of every generated user: password123.
//
//   node scripts/seed/generate.mjs --set matrix           # print SQL: one institution per role-template set
//   node scripts/seed/generate.mjs --set bench            # print SQL: a large and a small institution
//   node scripts/seed/generate.mjs --set matrix,bench --apply   # run it against $DB_URL (staging rehearsal)
//
// The weird-labels institution, institutions A / B and the dual-membership user are in supabase/seeds/ (loaded by
// every `supabase db reset`). Full type-profile seeds come with type profiles in 0B (D8).
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

export const PROFILES = ['college', 'school', 'coaching'];

/** Deterministic UUID (v4 layout) from a name. */
export function seedId(name) {
  const h = createHash('md5').update(`leadora-seed:${name}`).digest('hex').split('');
  h[12] = '4';
  h[16] = ['8', '9', 'a', 'b'][parseInt(h[16], 16) % 4];
  const s = h.join('');
  return `${s.slice(0, 8)}-${s.slice(8, 12)}-${s.slice(12, 16)}-${s.slice(16, 20)}-${s.slice(20, 32)}`;
}

const q = (v) => (v === null || v === undefined ? 'null' : `'${String(v).replaceAll("'", "''")}'`);

/** Users (auth + identity + profile name). One bcrypt hash for the whole batch keeps big seeds fast. */
export function usersSql(users) {
  if (users.length === 0) return '';
  const rows = users.map((u) => `(${q(u.id)}::uuid, ${q(u.email)}, ${q(u.name)})`).join(',\n  ');
  return `with h as (select extensions.crypt('password123', extensions.gen_salt('bf', 4)) as hash),
u (id, email, name) as (values
  ${rows})
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                        created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change)
select '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.email, h.hash, now(),
       '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '' from u, h
on conflict (id) do nothing;
with u (id, email, name) as (values
  ${rows})
insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
select u.id, u.id, u.id::text, jsonb_build_object('sub', u.id, 'email', u.email, 'email_verified', true), 'email', now(), now(), now() from u
on conflict do nothing;
with u (id, email, name) as (values
  ${rows})
update public.profiles p set display_name = u.name from u where p.user_id = u.id;
`;
}

function institutionSql(id, slug, name, shortName) {
  return `insert into public.institutions (id, slug, name, short_name, status) values (${q(id)}, ${q(slug)}, ${q(name)}, ${q(shortName)}, 'active')
on conflict (id) do nothing;
`;
}

/** One institution per role-template set, with one active user per template role holding that role. */
export function matrixSet() {
  const parts = [];
  for (const profile of PROFILES) {
    const inst = seedId(`institution:${profile}`);
    parts.push(institutionSql(inst, `test-${profile}`, `Test ${profile[0].toUpperCase()}${profile.slice(1)}`, profile.slice(0, 3).toUpperCase()));
    parts.push(`select app.apply_role_template(${q(inst)}, ${q(profile)});\n`);
  }
  // Users per role (role keys come from the templates in the database, so this stays right when templates change).
  parts.push(`do $$
declare
  r record;
  v_hash text := extensions.crypt('password123', extensions.gen_salt('bf', 4));
  v_user uuid;
begin
  for r in select t.type_profile_key as profile, t.role_key, i.id as inst
             from public.role_templates t join public.institutions i on i.slug = 'test-' || t.type_profile_key
            where t.type_profile_key in (${PROFILES.map(q).join(', ')}) loop
    v_user := (select (substr(md5('leadora-seed:user:' || r.profile || ':' || r.role_key), 1, 8) || '-' ||
                       substr(md5('leadora-seed:user:' || r.profile || ':' || r.role_key), 9, 4) || '-4' ||
                       substr(md5('leadora-seed:user:' || r.profile || ':' || r.role_key), 14, 3) || '-8' ||
                       substr(md5('leadora-seed:user:' || r.profile || ':' || r.role_key), 18, 3) || '-' ||
                       substr(md5('leadora-seed:user:' || r.profile || ':' || r.role_key), 21, 12))::uuid);
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                            created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change)
    values ('00000000-0000-0000-0000-000000000000', v_user, 'authenticated', 'authenticated',
            r.profile || '.' || r.role_key || '@example.test', v_hash, now(), '{"provider":"email","providers":["email"]}', '{}',
            now(), now(), '', '', '', '')
    on conflict (id) do nothing;
    insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (v_user, v_user, v_user::text, jsonb_build_object('sub', v_user, 'email', r.profile || '.' || r.role_key || '@example.test',
            'email_verified', true), 'email', now(), now(), now())
    on conflict do nothing;
    update public.profiles set display_name = r.profile || '.' || r.role_key where user_id = v_user;
    insert into public.institution_members (institution_id, user_id, status) values (r.inst, v_user, 'active') on conflict do nothing;
    insert into public.role_assignments (institution_id, user_id, role_id)
    select r.inst, v_user, ro.id from public.roles ro where ro.institution_id = r.inst and ro.is_system and ro.template_key = r.role_key
    on conflict do nothing;
  end loop;
end $$;
select app.flush_access_queue();
`);
  return parts.join('\n');
}

/** A large and a small institution for the benchmark (users only; the benchmark creates its own rows). */
export function benchSet({ largeUsers = 200, smallUsers = 5, largeBranches = 10 } = {}) {
  const out = [];
  const sets = [['large', largeUsers, largeBranches], ['small', smallUsers, 1]];
  for (const [size, count, branches] of sets) {
    const inst = seedId(`institution:bench-${size}`);
    out.push(institutionSql(inst, `bench-${size}`, `Benchmark ${size} institution`, size === 'large' ? 'BLG' : 'BSM'));
    out.push(`insert into public.app_settings (institution_id, key, value) values (${q(inst)}, 'branches_enabled', 'true') on conflict (institution_id, key) do nothing;\n`);
    const unitRows = Array.from({ length: branches }, (_, i) => `(${q(inst)}, ${q(seedId(`branch:bench-${size}:${i}`))}::uuid, 'branch', ${q(`Branch ${i + 1}`)})`);
    out.push(`insert into public.org_units (institution_id, id, kind, name) values ${unitRows.join(', ')} on conflict do nothing;\n`);
    out.push(`insert into public.branches (institution_id, org_unit_id) select institution_id, id from public.org_units where institution_id = ${q(inst)} and kind = 'branch' on conflict do nothing;\n`);
    const users = Array.from({ length: count }, (_, i) => ({ id: seedId(`user:bench-${size}:${i}`), email: `bench.${size}.${i}@example.test`, name: `bench.${size}.${i}` }));
    out.push(usersSql(users));
    out.push(`insert into public.institution_members (institution_id, user_id, status, branch_id)
select ${q(inst)}, u.id, 'active', (select id from public.org_units where institution_id = ${q(inst)} and kind = 'branch' order by name limit 1 offset (u.n % ${branches}))
from (values ${users.map((u, i) => `(${q(u.id)}::uuid, ${i})`).join(', ')}) u (id, n) on conflict do nothing;
select app.apply_role_template(${q(inst)}, 'college');
`);
  }
  return out.join('\n');
}

export function generate(sets) {
  const parts = ['-- Generated by scripts/seed/generate.mjs (0A.20-T1). Test data only.\n'];
  if (sets.includes('matrix')) parts.push(matrixSet());
  if (sets.includes('bench')) parts.push(benchSet());
  return parts.join('\n');
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  const setArg = args[args.indexOf('--set') + 1] ?? 'matrix';
  const sql = generate(setArg.split(','));
  if (args.includes('--apply')) {
    const db = process.env.DB_URL || 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
    execFileSync('psql', [db, '-X', '-q', '-v', 'ON_ERROR_STOP=1'], { input: sql, stdio: ['pipe', 'inherit', 'inherit'] });
    console.log(`Seeded: ${setArg}`);
  } else {
    process.stdout.write(sql);
  }
}
