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
# App code: institution_type may only be read in seeding code (Ch 2.7 #5).
if grep -rn --include='*.ts' --include='*.tsx' 'institution_type' src 2>/dev/null; then
  echo "LINT [institution_type] app code reads institution_type; use settings and modules instead." >&2
  exit 1
fi

# Extension boundaries (0A.09, Ch 43.4). Core migrations never reference an extension schema; extension migrations
# never change core objects (they may only insert into the registries: extensions, event_definitions, event_listeners).
bash scripts/extension-lint.sh
