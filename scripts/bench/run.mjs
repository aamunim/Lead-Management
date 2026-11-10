// Benchmark harness (0A.20-T4, Ch 2.7 #4, Ch 47.12 #6): a large and a small institution side by side, with a synthetic
// lead-sized table under the same RLS rule as real record tables (app.create_visibility_policy over user_access).
// Measures, inside one transaction that is rolled back:
//   - the small institution's list query with and without the large institution's rows (noisy neighbour),
//   - the RLS + user_access overhead (same query as the table owner, without RLS),
//   - can() per call, and rebuilding one person's access in the large institution.
// Writes bench-results/latest.json. With --baseline <file> it prints the change against an earlier run (report only;
// a failing CI gate on slow-downs is 0A.20-T5, Proposed). The noisy-neighbour check uses the Proposed threshold below.
//
//   npm run bench                     # run and check the noisy-neighbour threshold
//   npm run bench -- --baseline bench-results/previous.json
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';

import { benchSet, seedId } from '../seed/generate.mjs';

const DB_URL = process.env.DB_URL || 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const LARGE_ROWS = Number(process.env.BENCH_LARGE_ROWS ?? 30000);
const SMALL_ROWS = Number(process.env.BENCH_SMALL_ROWS ?? 3000);
const RUNS = Number(process.env.BENCH_RUNS ?? 30);
// Proposed (owner to confirm): the small institution's queries may be at most 25 % or 2 ms slower with the large one.
export const NEIGHBOUR_THRESHOLD = { ratio: 1.25, absoluteMs: 2 };

const large = seedId('institution:bench-large');
const small = seedId('institution:bench-small');
const smallUser = seedId('user:bench-small:0');
const smallManager = seedId('user:bench-small:1');
const largeUser = seedId('user:bench-large:0');

const sql = `
begin;
${benchSet()}
select app.sync_permissions('[{"module":"bench","release":"bench","permissions":[{"key":"bench.view","scopable":true,"sensitive":false,"defaults":{}}]}]');
create table public.bench_records (institution_id uuid not null, id uuid not null default gen_random_uuid(), owner_id uuid, branch_id uuid,
  offering_id uuid, created_by uuid, title text, created_at timestamptz not null default now(), primary key (institution_id, id));
create index bench_records_owner_idx on public.bench_records (institution_id, owner_id);
create index bench_records_branch_idx on public.bench_records (institution_id, branch_id);
alter table public.bench_records enable row level security;
grant select on public.bench_records to authenticated;
select app.create_visibility_policy('public.bench_records', 'bench.view');

-- Roles: everyone "own"; one manager per institution with "branch"; give them to every member.
insert into public.role_permissions (institution_id, role_id, permission_key, scope)
select r.institution_id, r.id, 'bench.view', case r.template_key when 'caller' then 'own' when 'branch_manager' then 'branch' end
  from public.roles r where r.institution_id in ('${large}', '${small}') and r.template_key in ('caller', 'branch_manager');
insert into public.role_assignments (institution_id, user_id, role_id)
select m.institution_id, m.user_id, r.id from public.institution_members m
  join public.roles r on r.institution_id = m.institution_id and r.template_key = case when m.user_id in ('${smallManager}') then 'branch_manager' else 'caller' end
 where m.institution_id in ('${large}', '${small}');
select app.flush_access_queue('${large}', 100000);
select app.flush_access_queue('${small}', 100000);

-- Rows: spread over the institution's people and branches.
insert into public.bench_records (institution_id, owner_id, branch_id, created_by, title)
select '${large}', m.user_id, m.branch_id, m.user_id, 'Record ' || g
  from generate_series(1, ${LARGE_ROWS}) g
  join lateral (select user_id, branch_id from public.institution_members where institution_id = '${large}' order by user_id offset (g % 200) limit 1) m on true;
insert into public.bench_records (institution_id, owner_id, branch_id, created_by, title)
select '${small}', m.user_id, m.branch_id, m.user_id, 'Record ' || g
  from generate_series(1, ${SMALL_ROWS}) g
  join lateral (select user_id, branch_id from public.institution_members where institution_id = '${small}' order by user_id offset (g % 5) limit 1) m on true;
analyze public.bench_records;

create temp table results (k text primary key, v numeric);
grant all on results to authenticated;
create function pg_temp.time_query(p_sql text, p_runs integer) returns numeric language plpgsql as $$
declare t0 timestamptz; best numeric := null; d numeric; i integer;
begin
  execute p_sql;  -- warm-up
  for i in 1..p_runs loop
    t0 := clock_timestamp();
    execute p_sql;
    d := extract(epoch from clock_timestamp() - t0) * 1000;
    best := least(coalesce(best, d), d);
  end loop;
  return round(best, 3);
end $$;
grant execute on function pg_temp.time_query(text, integer) to authenticated;
create function pg_temp.claims(p_user uuid) returns text language sql as $$
  select ((public.custom_access_token_hook(jsonb_build_object('user_id', p_user, 'claims', jsonb_build_object('sub', p_user, 'role', 'authenticated')))) -> 'claims')::text
$$;
grant execute on function pg_temp.claims(uuid) to authenticated;

-- The list query a screen runs: newest 50 visible records, and the count.
\\set list 'select id, title from public.bench_records order by created_at desc, id limit 50'
\\set count 'select count(*) from public.bench_records'

-- Owner (no RLS) baseline for the small institution.
insert into results select 'small_owner_list_ms', pg_temp.time_query('select id, title from public.bench_records where institution_id = ''${small}'' order by created_at desc, id limit 50', ${RUNS});

select set_config('request.jwt.claims', pg_temp.claims('${smallUser}'), true);
set local role authenticated;
insert into results select 'small_own_list_with_large_ms', pg_temp.time_query(:'list', ${RUNS});
insert into results select 'small_own_count_with_large_ms', pg_temp.time_query(:'count', ${RUNS});
reset role;
select set_config('request.jwt.claims', pg_temp.claims('${smallManager}'), true);
set local role authenticated;
insert into results select 'small_branch_count_with_large_ms', pg_temp.time_query(:'count', ${RUNS});
reset role;
select set_config('request.jwt.claims', pg_temp.claims('${largeUser}'), true);
set local role authenticated;
insert into results select 'large_own_list_ms', pg_temp.time_query(:'list', ${RUNS});
insert into results select 'large_own_count_ms', pg_temp.time_query(:'count', ${RUNS});
-- 1000 calls with a different record each (so nothing is computed once); ms for 1000 calls = µs per call.
insert into results select 'can_per_call_us', pg_temp.time_query('select count(*) filter (where app.can(''bench.view'', jsonb_build_object(''owner_id'', ''${largeUser}'', ''branch_id'', null, ''created_by'', ''${largeUser}'', ''n'', g))) from generate_series(1, 1000) g', 5);
reset role;
insert into results select 'rebuild_one_large_user_ms', pg_temp.time_query('select app.rebuild_user_access(''${large}'', ''${largeUser}'')', 10);

-- Without the large institution's rows: the same small-institution queries.
delete from public.bench_records where institution_id = '${large}';
analyze public.bench_records;
select set_config('request.jwt.claims', pg_temp.claims('${smallUser}'), true);
set local role authenticated;
insert into results select 'small_own_list_alone_ms', pg_temp.time_query(:'list', ${RUNS});
insert into results select 'small_own_count_alone_ms', pg_temp.time_query(:'count', ${RUNS});
reset role;
select set_config('request.jwt.claims', pg_temp.claims('${smallManager}'), true);
set local role authenticated;
insert into results select 'small_branch_count_alone_ms', pg_temp.time_query(:'count', ${RUNS});
reset role;
select json_object_agg(k, v) from results;
rollback;
`;

const raw = execFileSync('psql', [DB_URL, '-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1'], { input: sql, encoding: 'utf8', maxBuffer: 64 << 20 });
const result = JSON.parse(raw.trim().split('\n').filter((l) => l.startsWith('{')).at(-1));
const report = { at: new Date().toISOString(), rows: { large: LARGE_ROWS, small: SMALL_ROWS }, runs: RUNS, results: result }; // i18n-exempt: developer tool
mkdirSync('bench-results', { recursive: true });
writeFileSync('bench-results/latest.json', `${JSON.stringify(report, null, 2)}\n`);
console.log(JSON.stringify(report.results, null, 2));

const baselineArg = process.argv.indexOf('--baseline');
if (baselineArg > 0 && existsSync(process.argv[baselineArg + 1])) {
  const base = JSON.parse(readFileSync(process.argv[baselineArg + 1], 'utf8')).results;
  for (const [k, v] of Object.entries(result)) {
    if (base[k]) console.log(`${k}: ${base[k]} → ${v} (${(((v - base[k]) / base[k]) * 100).toFixed(1)} %)`);
  }
}

// Noisy neighbour: the small institution must not get noticeably slower because a large one shares the database.
const failures = [];
for (const q of ['small_own_list', 'small_own_count', 'small_branch_count']) {
  const withLarge = result[`${q}_with_large_ms`];
  const alone = result[`${q}_alone_ms`];
  if (withLarge > alone * NEIGHBOUR_THRESHOLD.ratio && withLarge - alone > NEIGHBOUR_THRESHOLD.absoluteMs) {
    failures.push(`${q}: ${withLarge} ms with the large institution vs ${alone} ms alone`);
  }
}
if (failures.length) {
  for (const f of failures) console.error(f);
  console.error('Benchmark: the large institution slows the small one beyond the threshold.');
  process.exit(1);
}
console.log('Benchmark passed: the large institution does not slow the small one beyond the threshold.');
