#!/usr/bin/env bash
# Applies extension migrations (supabase/extensions/<key>/migrations/*.sql) after the core migrations (0A.09).
# Each file runs once, in its own transaction, and is recorded in app.extension_migrations with its checksum.
# An applied file that has changed stops the run: write a new migration file instead.
# Uses $DB_URL (default: local Supabase). Run after `supabase db reset` and after every core deploy.
set -euo pipefail
# Deploys set APPLY_TEST_EXTENSIONS=0: extensions with a TEST_ONLY file never reach staging or production.
DB_URL="${DB_URL-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
APPLY_TEST_EXTENSIONS="${APPLY_TEST_EXTENSIONS:-1}"
shopt -s nullglob
applied=0
for dir in supabase/extensions/*/; do
  key="$(basename "$dir")"
  if [[ -f "$dir/TEST_ONLY" && "$APPLY_TEST_EXTENSIONS" != "1" ]]; then
    echo "Skipping test-only extension $key"
    continue
  fi
  if [[ -z "$DB_URL" ]]; then
    echo "DB_URL is empty but extension $key has migrations to check. Set the SUPABASE_DB_URL secret." >&2
    exit 1
  fi
  for f in "$dir"migrations/*.sql; do
    name="$(basename "$f")"
    sum="$(sha256sum "$f" | cut -d' ' -f1)"
    if [[ ! "$key" =~ ^[a-z][a-z0-9_]*$ || ! "$name" =~ ^[0-9]{4}_[a-z0-9_]+\.sql$ ]]; then
      echo "Bad extension or file name: $key/$name (expected <key>/migrations/0001_name.sql)" >&2
      exit 1
    fi
    have="$(psql "$DB_URL" -X -A -t -v ON_ERROR_STOP=1 \
      -c "select checksum from app.extension_migrations where extension_key = '$key' and filename = '$name'")"
    if [[ -n "$have" ]]; then
      if [[ "$have" != "$sum" ]]; then
        echo "Extension migration $key/$name was changed after it was applied. Add a new file instead." >&2
        exit 1
      fi
      continue
    fi
    echo "Applying extension migration $key/$name"
    psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 --single-transaction \
      -f "$f" \
      -c "insert into app.extension_migrations (extension_key, filename, checksum) values ('$key', '$name', '$sum')"
    applied=$((applied + 1))
  done
done
echo "Extension migrations applied: $applied"
