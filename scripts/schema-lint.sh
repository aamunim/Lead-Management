#!/usr/bin/env bash
# Schema lint (0A.04): checks the migrated database against the tenancy and naming rules.
# Uses $DB_URL (default: local Supabase). Nothing is changed: everything runs in a rolled-back transaction.
set -euo pipefail
DB_URL="${DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 <<'SQL'
begin;
\i supabase/lint/lint_functions.sql
\i supabase/lint/allowlist.sql
select lint.report();
rollback;
SQL
# Code follows settings and modules, never the type: only the profile applier reads the type column (Ch 7.2, 0B.03-T11).
node scripts/profiles/lint-institution-type.mjs

# Extension boundaries (0A.09, Ch 43.4). Core migrations never reference an extension schema; extension migrations
# never change core objects (they may only insert into the registries: extensions, event_definitions, event_listeners).
bash scripts/extension-lint.sh
