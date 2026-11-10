// Role-matrix test (0A.20-T2, Ch 11.13): for every role template × every registered permission, the expected grant is
// written down in config/role-matrix.json (reviewed by people; a new permission without an entry FAILS), and the
// database is checked against it in two ways, inside one transaction that is rolled back:
//   1. the template roles of a freshly seeded institution per template set grant exactly the expected scope;
//   2. can() and the RLS rule (app.row_visible) give the right answer for records inside and outside every scope —
//      own / team / unit / branch / all, a branch-limited and an offering-limited assignment, records without a branch
//      or offering — for each role's real grants and for a synthetic permission per scope.
//
//   npm run test:role-matrix              # check (CI gate)
//   npm run test:role-matrix -- --write   # rewrite the expectations from the current templates (review the diff!)
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';

import { generate } from '../seed/generate.mjs';

const DB_URL = process.env.DB_URL || 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const FILE = 'config/role-matrix.json';
const psql = (sql) => execFileSync('psql', [DB_URL, '-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1'], { input: sql, encoding: 'utf8', maxBuffer: 64 << 20 });
const json = (sql) => JSON.parse(psql(sql).trim() || 'null');

// What the templates grant now (template defaults from the registry; the Super Admin role has everything).
const registry = json(`select json_build_object(
  'permissions', (select json_agg(json_build_object('key', key, 'scopable', scopable, 'defaults', default_for_templates) order by key)
                  from public.permissions where kind = 'institution' and key <> '*' and retired_at is null),
  'roles', (select json_agg(json_build_object('profile', type_profile_key, 'role', role_key, 'super', is_super_admin, 'extra', extra_grants)
                            order by type_profile_key, sort) from public.role_templates))`);

function currentGrant(role, permission) {
  if (role.super) return permission.scopable ? 'all' : true;
  const value = permission.defaults?.[role.role] ?? role.extra?.[permission.key];
  if (value === undefined || value === null) return false;
  if (!permission.scopable) return true;
  return value === true ? 'own' : value;
}

if (process.argv.includes('--write')) {
  const out = { $comment: 'Role matrix (0A.20-T2): the expected grant of every permission for every template role. true = granted (not scopable), a scope = granted at that scope, false = not granted. Checked by `npm run test:role-matrix`; a permission missing here fails the test. Owner-reviewed list of template roles: D26.' };
  for (const role of registry.roles) {
    out[role.profile] ??= {};
    out[role.profile][role.role] = Object.fromEntries(registry.permissions.map((p) => [p.key, currentGrant(role, p)]));
  }
  writeFileSync(FILE, `${JSON.stringify(out, null, 2)}\n`);
  console.log(`Wrote ${FILE}. Review the diff before committing.`);
  process.exit(0);
}

// 1. Completeness: every template role × every permission has an expectation.
const expected = JSON.parse(readFileSync(FILE, 'utf8'));
const problems = [];
for (const role of registry.roles) {
  for (const p of registry.permissions) {
    const value = expected[role.profile]?.[role.role]?.[p.key];
    if (value === undefined) problems.push(`[missing] ${role.profile}/${role.role}: no expectation for "${p.key}" — add it to ${FILE}`);
    else if (p.scopable ? !(value === false || ['own', 'team', 'org_unit', 'branch', 'all'].includes(value)) : typeof value !== 'boolean') {
      problems.push(`[invalid] ${role.profile}/${role.role}/${p.key}: ${JSON.stringify(value)}`);
    }
  }
}
for (const [profile, roles] of Object.entries(expected)) {
  if (profile.startsWith('$')) continue;
  for (const role of Object.keys(roles)) {
    if (!registry.roles.some((r) => r.profile === profile && r.role === role)) problems.push(`[unknown] ${profile}/${role} is not a template role`);
  }
}
if (problems.length) {
  for (const p of problems) console.error(p);
  console.error(`Role matrix: ${problems.length} problem(s) in ${FILE}.`);
  process.exit(1);
}

// 2. The database, in one transaction.
const rows = [];
for (const role of registry.roles) {
  for (const p of registry.permissions) {
    const v = expected[role.profile][role.role][p.key];
    rows.push(`('${role.profile}', '${role.role}', '${p.key}', ${v === false ? 'null' : `'${v === true ? 'all' : v}'`})`);
  }
}
const SCOPES = ['own', 'team', 'org_unit', 'branch', 'all'];
const sql = `
begin;
${generate(['matrix'])}
-- Synthetic permissions, one per scope, given to every non-Super-Admin template role (rolled back at the end).
select app.sync_permissions('[{"module":"matrix","release":"test","permissions":[${SCOPES.map((s) => `{"key":"matrix.${s}","scopable":true,"sensitive":false,"defaults":{}}`).join(',')}]}]');
create temp table expect (profile text, role_key text, permission text, scope text);
insert into expect values ${rows.join(',\n  ')};
insert into public.role_permissions (institution_id, role_id, permission_key, scope)
select r.institution_id, r.id, 'matrix.' || s, s from public.roles r cross join unnest(array[${SCOPES.map((s) => `'${s}'`).join(',')}]) s
 where r.is_system and not r.is_super_admin and r.institution_id in (select id from public.institutions where slug in ('test-college', 'test-school', 'test-coaching'));
insert into expect select t.type_profile_key, t.role_key, 'matrix.' || s, case when t.is_super_admin then 'all' else s end
  from public.role_templates t cross join unnest(array[${SCOPES.map((s) => `'${s}'`).join(',')}]) s where t.type_profile_key in ('college', 'school', 'coaching');
create temp table failures (what text);
create temp table counts (k text, n integer);

do $$
declare
  i        record;
  r        record;
  e        record;
  pos      record;
  v_x      uuid; v_y uuid; v_team uuid;
  v_c      uuid; v_b uuid; v_o uuid;   -- colleague in the team, branch-mate outside the team, person in the other branch
  v_lim    uuid; v_off uuid;           -- branch-limited and offering-limited subjects
  v_o1     uuid := gen_random_uuid(); v_o2 uuid := gen_random_uuid();
  v_rec    jsonb;
  v_can    boolean; v_rls boolean; v_want boolean;
  v_n      integer := 0;
  v_actual text;
  v_role   uuid;
  v_claims jsonb;
begin
  for i in select id, slug, replace(slug, 'test-', '') as profile from public.institutions where slug in ('test-college', 'test-school', 'test-coaching') loop
    insert into public.app_settings (institution_id, key, value) values (i.id, 'branches_enabled', 'true') on conflict (institution_id, key) do update set value = 'true';
    v_x := gen_random_uuid(); v_y := gen_random_uuid(); v_team := gen_random_uuid();
    insert into public.org_units (institution_id, id, kind, name) values (i.id, v_x, 'branch', 'X'), (i.id, v_y, 'branch', 'Y');
    insert into public.branches (institution_id, org_unit_id) values (i.id, v_x), (i.id, v_y);
    insert into public.org_units (institution_id, id, parent_id, kind, name) values (i.id, v_team, v_x, 'team', 'T');
    -- Fixture people: reuse three generated users of another institution would mix tenants, so add plain members.
    v_c := gen_random_uuid(); v_b := gen_random_uuid(); v_o := gen_random_uuid(); v_lim := gen_random_uuid(); v_off := gen_random_uuid();
    insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at)
    select '00000000-0000-0000-0000-000000000000', u, 'authenticated', 'authenticated', u::text || '@matrix.test', now(), now()
      from unnest(array[v_c, v_b, v_o, v_lim, v_off]) u;
    insert into public.institution_members (institution_id, user_id, status, branch_id) values
      (i.id, v_c, 'active', v_x), (i.id, v_b, 'active', v_x), (i.id, v_o, 'active', v_y), (i.id, v_lim, 'active', v_x), (i.id, v_off, 'active', v_x);
    insert into public.org_unit_members (institution_id, org_unit_id, user_id) values (i.id, v_team, v_c);
    -- Every role holder (subject): home branch X, member and manager of team T.
    update public.institution_members set branch_id = v_x where institution_id = i.id and user_id in (select user_id from public.role_assignments where institution_id = i.id);
    insert into public.org_unit_members (institution_id, org_unit_id, user_id) select i.id, v_team, user_id from public.role_assignments where institution_id = i.id on conflict do nothing;
    insert into public.org_unit_managers (institution_id, org_unit_id, user_id) select i.id, v_team, user_id from public.role_assignments where institution_id = i.id on conflict do nothing;
    -- Limited assignments of a role holding matrix.all: one to branch Y, one to offering O1.
    select id into v_role from public.roles where institution_id = i.id and is_system and not is_super_admin order by rank_for_sorting limit 1;
    insert into public.role_assignments (institution_id, user_id, role_id, branch_id) values (i.id, v_lim, v_role, v_y);
    insert into public.role_assignments (institution_id, user_id, role_id, offering_limit) values (i.id, v_off, v_role, array[v_o1]);
    perform app.flush_access_queue(i.id);

    -- (1) granted scope per template role and permission
    for e in select * from expect where profile = i.profile and permission not like 'matrix.%' loop
      select coalesce(case when ro.is_super_admin then 'all' end, rp.scope, case when rp.permission_key is not null then 'all' end) into v_actual
        from public.roles ro left join public.role_permissions rp on rp.institution_id = ro.institution_id and rp.role_id = ro.id and rp.permission_key = e.permission
       where ro.institution_id = i.id and ro.is_system and ro.template_key = e.role_key;
      v_n := v_n + 1;
      if v_actual is distinct from e.scope then
        insert into failures values (format('[grant] %s/%s/%s: expected %s, template gives %s', i.profile, e.role_key, e.permission, coalesce(e.scope, 'none'), coalesce(v_actual, 'none')));
      end if;
    end loop;

    -- (2) can() and RLS for records inside and outside each scope, per role holder
    for r in select ra.user_id, ro.template_key from public.role_assignments ra join public.roles ro on ro.institution_id = ra.institution_id and ro.id = ra.role_id
              where ra.institution_id = i.id and ra.user_id not in (v_lim, v_off) loop
      v_claims := (public.custom_access_token_hook(jsonb_build_object('user_id', r.user_id, 'claims', jsonb_build_object('sub', r.user_id, 'role', 'authenticated')))) -> 'claims';
      perform set_config('request.jwt.claims', v_claims::text, true);
      for e in select * from expect where profile = i.profile and role_key = r.template_key loop
        for pos in select * from (values
            ('own',          jsonb_build_object('owner_id', r.user_id, 'branch_id', v_x, 'created_by', r.user_id), array['own','team','org_unit','branch','all']),
            ('team',         jsonb_build_object('owner_id', v_c, 'branch_id', v_x, 'created_by', v_c),          array['team','org_unit','branch','all']),
            ('branch_mate',  jsonb_build_object('owner_id', v_b, 'branch_id', v_x, 'created_by', v_b),          array['branch','all']),
            ('other_branch', jsonb_build_object('owner_id', v_o, 'branch_id', v_y, 'created_by', v_o),          array['all']),
            ('null_mine',    jsonb_build_object('owner_id', r.user_id, 'branch_id', null, 'created_by', r.user_id), array['own','team','org_unit','branch','all']),
            ('null_other',   jsonb_build_object('owner_id', v_o, 'branch_id', null, 'created_by', v_o),         array['all'])
          ) as t (name, rec, allowed_scopes) loop
          v_want := e.scope is not null and e.scope = any (pos.allowed_scopes);
          v_can := app.can(e.permission, pos.rec);
          v_rls := app.row_visible(e.permission, (pos.rec ->> 'owner_id')::uuid, (pos.rec ->> 'branch_id')::uuid, null, (pos.rec ->> 'created_by')::uuid);
          v_n := v_n + 1;
          if v_can is distinct from v_want or v_rls is distinct from v_want then
            insert into failures values (format('[access] %s/%s/%s on %s record: expected %s, can() %s, RLS %s', i.profile, r.template_key, e.permission, pos.name, v_want, v_can, v_rls));
          end if;
        end loop;
      end loop;
    end loop;

    -- (3) a branch-limited assignment (all records, branch Y only) and an offering-limited one (offering O1 only)
    perform set_config('request.jwt.claims', ((public.custom_access_token_hook(jsonb_build_object('user_id', v_lim, 'claims', jsonb_build_object('sub', v_lim, 'role', 'authenticated')))) -> 'claims')::text, true);
    for pos in select * from (values
        ('branch Y record', jsonb_build_object('owner_id', v_o, 'branch_id', v_y, 'created_by', v_o), true),
        ('branch X record', jsonb_build_object('owner_id', v_b, 'branch_id', v_x, 'created_by', v_b), false),
        ('no branch, not mine', jsonb_build_object('owner_id', v_o, 'branch_id', null, 'created_by', v_o), false),
        ('no branch, created by me', jsonb_build_object('owner_id', v_o, 'branch_id', null, 'created_by', v_lim), true)) as t (name, rec, want) loop
      v_n := v_n + 1;
      if app.can('matrix.all', pos.rec) is distinct from pos.want then
        insert into failures values (format('[branch limit] %s: %s expected %s', i.profile, pos.name, pos.want));
      end if;
    end loop;
    perform set_config('request.jwt.claims', ((public.custom_access_token_hook(jsonb_build_object('user_id', v_off, 'claims', jsonb_build_object('sub', v_off, 'role', 'authenticated')))) -> 'claims')::text, true);
    for pos in select * from (values
        ('offering O1', jsonb_build_object('owner_id', v_o, 'branch_id', v_y, 'offering_id', v_o1, 'created_by', v_o), true),
        ('offering O2', jsonb_build_object('owner_id', v_o, 'branch_id', v_y, 'offering_id', v_o2, 'created_by', v_o), false),
        ('no offering, not mine', jsonb_build_object('owner_id', v_o, 'branch_id', v_y, 'created_by', v_o), false),
        ('no offering, created by me', jsonb_build_object('owner_id', v_o, 'branch_id', v_y, 'created_by', v_off), true)) as t (name, rec, want) loop
      v_n := v_n + 1;
      if app.can('matrix.all', pos.rec) is distinct from pos.want
         or app.row_visible('matrix.all', (pos.rec ->> 'owner_id')::uuid, (pos.rec ->> 'branch_id')::uuid, (pos.rec ->> 'offering_id')::uuid,
                            (pos.rec ->> 'created_by')::uuid) is distinct from pos.want then
        insert into failures values (format('[offering limit] %s: %s expected %s', i.profile, pos.name, pos.want));
      end if;
    end loop;
    perform set_config('request.jwt.claims', '', true);
  end loop;
  insert into counts values ('checks', v_n);
end $$;
select json_build_object('checks', (select n from counts where k = 'checks'), 'failures', coalesce((select json_agg(what) from failures), '[]'::json));
rollback;
`;
const out = psql(sql).trim().split('\n').filter((l) => l.startsWith('{')).at(-1);
const result = JSON.parse(out);
if (result.failures.length) {
  for (const f of result.failures.slice(0, 50)) console.error(f);
  console.error(`Role matrix failed: ${result.failures.length} of ${result.checks} checks.`);
  process.exit(1);
}
console.log(`Role matrix passed: ${result.checks} checks (${registry.roles.length} template roles × ${registry.permissions.length} permissions + scopes).`);
