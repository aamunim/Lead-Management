// Benchmark harness (0A.20-T4, Ch 2.7 #4, Ch 47.12 #6): a large and a small institution side by side, with a synthetic
// lead-sized table under the same RLS rule as real record tables (app.create_visibility_policy over user_access).
// Measures, inside one transaction that is rolled back:
//   - the small institution's list query with and without the large institution's rows (noisy neighbour),
//   - the RLS + user_access overhead (same query as the table owner, without RLS),
//   - can() per call, and rebuilding one person's access in the large institution.
// Writes bench-results/latest.json. With --baseline <file> it prints the change against an earlier run (report only;
// With --fail-on-slowdown as well (CI, 0A.20-T5, D41) it fails when a measured path got slower than the threshold.
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
// Agreed threshold (D40): slower by more than 25 % AND more than 2 ms (0.05 ms for per-call µs figures) fails.
export const NEIGHBOUR_THRESHOLD = { ratio: 1.25, absoluteMs: 2 };
const absoluteFor = (key) => (key.endsWith('_us') ? 50 : NEIGHBOUR_THRESHOLD.absoluteMs);

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

-- Machine speed (no tables, no RLS): later runs on a faster or slower CI machine are scaled by this.
insert into results select 'calibration_ms', pg_temp.time_query('select sum(g::numeric * g) from generate_series(1, 200000) g', ${RUNS});

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

-- Custom fields (0B.06): 20 fields on every small-institution record, two of them filterable (with their partial
-- indexes); the list filtered on both must stay within CUSTOM_FIELD_LIST_MS. Set up as the database owner (no user).
select set_config('request.jwt.claims', '', true);
insert into public.custom_field_definitions (institution_id, id, entity, key, label, type, options, filterable)
select '${small}', md5('bench-cf-' || g)::uuid, 'lead', 'bench_f' || g, '{"en":"F","bn":"F"}',
       case g when 1 then 'gpa' when 2 then 'select' else 'text' end,
       case g when 2 then '{"choices":[{"key":"morning","label":{"en":"M","bn":"M"}},{"key":"day","label":{"en":"D","bn":"D"}}]}'::jsonb else '{}' end,
       g <= 2
  from generate_series(1, 20) g;
insert into public.custom_field_values (institution_id, field_id, entity, record_id, value_text, value_num)
select '${small}', md5('bench-cf-' || g)::uuid, 'lead', r.id,
       case when g = 2 then (array['morning', 'day'])[1 + (abs(hashtext(r.id::text)) % 2)] when g > 2 then 'value ' || g end,
       case when g = 1 then round((abs(hashtext(r.id::text)) % 501) / 100.0, 2) end
  from public.bench_records r cross join generate_series(1, 20) g where r.institution_id = '${small}';
select app.custom_field_index_sync('${small}', md5('bench-cf-1')::uuid), app.custom_field_index_sync('${small}', md5('bench-cf-2')::uuid);
analyze public.custom_field_values;
select set_config('request.jwt.claims', pg_temp.claims('${smallManager}'), true);
set local role authenticated;
insert into results select 'small_custom_field_filter_list_ms', pg_temp.time_query('select r.id, r.title from public.bench_records r
  where r.id in (select v.record_id from public.custom_field_values v where v.institution_id = ''${small}'' and v.field_id = ''' || md5('bench-cf-1')::uuid || ''' and v.value_num >= 4)
    and r.id in (select v.record_id from public.custom_field_values v where v.institution_id = ''${small}'' and v.field_id = ''' || md5('bench-cf-2')::uuid || ''' and v.value_text = ''day'')
  order by r.created_at desc, r.id limit 50', ${RUNS});
reset role;

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

const failures = [];
const baselineArg = process.argv.indexOf('--baseline');
if (baselineArg > 0 && existsSync(process.argv[baselineArg + 1])) {
  const base = JSON.parse(readFileSync(process.argv[baselineArg + 1], 'utf8')).results;
  // CI machines differ in speed: scale this run to the baseline machine with the calibration figure.
  const speed = base.calibration_ms && result.calibration_ms ? base.calibration_ms / result.calibration_ms : null;
  console.log(speed ? `Machine speed vs baseline: ×${speed.toFixed(2)} (figures below are scaled)` : 'No calibration in the baseline: report only.');
  for (const [k, raw] of Object.entries(result)) {
    if (!base[k] || k === 'calibration_ms') continue;
    const v = speed ? Math.round(raw * speed * 1000) / 1000 : raw;
    console.log(`${k}: ${base[k]} → ${v} (${(((v - base[k]) / base[k]) * 100).toFixed(1)} %)`);
    if (speed && process.argv.includes('--fail-on-slowdown') && v > base[k] * NEIGHBOUR_THRESHOLD.ratio && v - base[k] > absoluteFor(k)) {
      failures.push(`${k}: slower than the last main / nightly run (${base[k]} → ${v}, scaled to the baseline machine)`);
    }
  }
} else if (baselineArg > 0) {
  console.log('No baseline yet (first run on main makes it): slow-down check skipped.');
}

// Custom fields (0B.06, Ch 14.12 row 5): a list filtered on two custom fields stays quick (Proposed target).
export const CUSTOM_FIELD_LIST_MS = 50;
if (result.small_custom_field_filter_list_ms > CUSTOM_FIELD_LIST_MS) {
  failures.push(`small_custom_field_filter_list: ${result.small_custom_field_filter_list_ms} ms (target ${CUSTOM_FIELD_LIST_MS} ms)`);
}

// Noisy neighbour: the small institution must not get noticeably slower because a large one shares the database.
for (const q of ['small_own_list', 'small_own_count', 'small_branch_count']) {
  const withLarge = result[`${q}_with_large_ms`];
  const alone = result[`${q}_alone_ms`];
  if (withLarge > alone * NEIGHBOUR_THRESHOLD.ratio && withLarge - alone > NEIGHBOUR_THRESHOLD.absoluteMs) {
    failures.push(`${q}: ${withLarge} ms with the large institution vs ${alone} ms alone`);
  }
}
if (failures.length) {
  for (const f of failures) console.error(f);
  console.error('Benchmark failed: slower than the agreed threshold (25 % and 2 ms).');
  process.exit(1);
}
console.log('Benchmark passed: no slow-down beyond the threshold (noisy neighbour and against the baseline).');
