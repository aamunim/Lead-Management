#!/usr/bin/env bash
# 0A.08 concurrency test: N separate connections ask for the next number of the same counter at the same moment, as a
# real signed-in member of A. Every number must be distinct and the set must be exactly 1..N (no duplicates, no gaps).
set -euo pipefail
DB_URL="${DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
N="${N:-50}"
KEY="test.concurrency_$(date +%s%N)"
USER_A='11111111-1111-4111-8111-111111111111'
CLAIMS=$(psql "$DB_URL" -X -Atc "select (public.custom_access_token_hook(jsonb_build_object('user_id','$USER_A','claims',jsonb_build_object('sub','$USER_A','role','authenticated')))->'claims')::text")
SQL="begin; select set_config('request.jwt.claims', '$CLAIMS', true); set local role authenticated; select app.counter_next('$KEY'); commit;"
results=$(seq "$N" | xargs -P "$N" -I{} psql "$DB_URL" -X -Atq -c "$SQL" | grep -E '^[0-9]+$' | sort -n)
psql "$DB_URL" -X -q -c "delete from public.institution_counters where counter_key = '$KEY'" >/dev/null
expected=$(seq "$N")
if [ "$results" = "$expected" ]; then
  echo "ok - $N parallel counter_next calls produced exactly 1..$N (distinct, no gaps)"
else
  echo "FAILED: parallel counter_next results were:" $results
  exit 1
fi
