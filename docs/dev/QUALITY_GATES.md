# Quality gates of Phase 0A (0A.20)

Roadmap 0A.20; plan Ch 48.7, 48.10 #2, Ch 4.8, Ch 11.13, Ch 2.5 / 2.7, Ch 47.9 / 47.11, Ch 8.9 rule 4, Ch 50.
All run in CI (`.github/workflows/ci.yml`) on every PR and nightly; how to make them required: `ENVIRONMENTS_AND_RELEASES.md`.

## Seed generator — `npm run seed:generate -- --set matrix,bench [--apply]` (T1)

`scripts/seed/generate.mjs` prints idempotent SQL with ids derived from names (same input, same ids):
`matrix` = one institution per role-template set (college, school, coaching) with one active user per template role
holding it (`<profile>.<role>@example.test`); `bench` = a large (200 people, 10 branches) and a small (5 people)
institution. The weird-labels institution, A / B and the dual-membership user stay in `supabase/seeds/`. Tests load
the generated SQL inside a transaction; `--apply` writes it to `$DB_URL` (staging rehearsal). Type-profile seeds come
with type profiles (0B.03, D8).

## Role matrix — `npm run test:role-matrix` (T2)

`config/role-matrix.json` is the human-reviewed matrix: for every template role and every registered permission, the
expected grant (`true`, a scope, or `false`). The test fails when a permission or role has no entry, then checks in one
rolled-back transaction: (1) the template roles grant exactly that; (2) `can()` and the RLS rule (`app.row_visible`)
answer right for records inside and outside each scope — own, team, unit, branch, other branch, no branch (own /
someone else's) — for each role's real grants and for a synthetic permission per scope, plus a branch-limited and an
offering-limited assignment. 3,020 checks today. After a template or registry change: `npm run test:role-matrix --
--write`, review the diff of the JSON, commit.

## Benchmark — `npm run bench [-- --baseline file]` (T4)

`scripts/bench/run.mjs`: large (30,000 rows) and small (3,000 rows) institution side by side in a synthetic table with
the real RLS rule. Measures the small institution's list and count with and without the large one, the RLS overhead,
`can()` per call and rebuilding one person's access; writes `bench-results/latest.json` (CI artifact). Fails when the
large institution slows the small one by more than **25 % and 2 ms (D40)**, and in CI when any figure got that much
slower than the last `main` / nightly run (baseline kept in the Actions cache; `--baseline … --fail-on-slowdown`, D41).
CI machines differ in speed (the first `main` run was 30–40 % slower on every figure with the same code), so each
run also times pure CPU work (`calibration_ms`) and the comparison is scaled to the baseline machine.

## Screenshot matrix — part of `npm run test:ui` (T3)

`scripts/ui/matrix.web.test.mjs`: every screen route × light / dark × bn / en, signed in as the weird-labels
institution's Super Admin, compared with `tests/screenshots/*.png` (80 images). Dates and the change log are masked;
up to 0.5 % of pixels may differ (anti-aliasing). A new route file without an entry fails. After an intended change:
run the **screenshots-update** workflow on the branch (baselines are made on the CI runner, where they are compared),
look at the changed images in its commit. The diff runs in CI only (locally: `SCREENSHOT_DIFF=1`). Diffs: `ui-screenshots/diff/` (CI artifact).
Every PR runs the whole matrix (about 3–4 minutes); the nightly run repeats it with the benchmark.

## Other gates already in place

Leak test and self-test (0A.05), RPC-as-role SQL tests (0A.03+), DEFINER registry and invoker sweep in the schema lint
(0A.04, 0A.06), write-needs-`can()` lint (0A.17), i18n lint and missing keys (0A.10), settings schema validation
(0A.08), secret scan (0A.02).
