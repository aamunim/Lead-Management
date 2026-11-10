#!/usr/bin/env bash
# Cross-tenant leak test (0A.05): probes every tenant table and every RPC as members of institution B and checks
# that nothing of institution A is visible. Needs the local database with migrations and the 0A.03 seed.
# Everything runs in a rolled-back transaction.
set -euo pipefail
DB_URL="${DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 <<'SQL'
begin;
\i supabase/tests/leak/leak_functions.sql
create schema leak_fixtures;
\i supabase/tests/leak/fixtures/all.sql
\i supabase/tests/leak/allowlist.sql
select leak.report();
rollback;
SQL
