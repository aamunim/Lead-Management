#!/usr/bin/env bash
# Runs every SQL test in supabase/tests against the database in $DB_URL
# (default: the local Supabase database started with `supabase db start` + `supabase db reset`).
set -euo pipefail
DB_URL="${DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
status=0
for f in supabase/tests/*.sql; do
  echo "== $f"
  if ! psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 -f "$f" 2>&1 | sed -n 's/^.*NOTICE:  //p; /ERROR/p; /FAILED/p'; then
    status=1
  fi
  # psql's exit code is lost in the pipe; run again quietly to get it.
  psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 -f "$f" >/dev/null 2>&1 || status=1
done
exit $status
