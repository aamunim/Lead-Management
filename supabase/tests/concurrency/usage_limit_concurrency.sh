#!/usr/bin/env bash
# 0B.05 race test: N separate connections add a member to an institution at the same moment, as a signed-in person,
# with a users limit of L. Exactly L may succeed; the counter must equal the recount (reconciliation finds nothing).
set -euo pipefail
DB_URL="${DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
N="${N:-30}"
L=12
INST='d0000000-0000-4000-8000-0000000000d3'   # plan-standard (seeded, no members)
OWNER='77777777-7777-4777-8777-777777777777'
psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 <<SQL >/dev/null
delete from public.institution_members where institution_id = '$INST';
update public.institution_plan set limit_overrides = '{"users": $L}' where institution_id = '$INST';
insert into auth.users (id, email, aud, role) select gen_random_uuid(), 'race' || g || '@example.test', 'authenticated', 'authenticated'
  from generate_series(1, $N) g on conflict do nothing;
select app.usage_reconcile('$INST');
SQL
CLAIMS="{\"sub\":\"$OWNER\",\"role\":\"authenticated\"}"
seq "$N" | xargs -P "$N" -I{} psql "$DB_URL" -X -Atq -c "begin; select set_config('request.jwt.claims', '$CLAIMS', true);
  insert into public.institution_members (institution_id, user_id, status)
  select '$INST', id, 'active' from auth.users where email = 'race{}@example.test'; commit;" >/dev/null 2>&1 || true
members=$(psql "$DB_URL" -X -Atc "select count(*) from public.institution_members where institution_id = '$INST' and status = 'active'")
counter=$(psql "$DB_URL" -X -Atc "select app.usage_of('$INST', 'users')")
fixed=$(psql "$DB_URL" -X -Atc "select app.usage_reconcile('$INST')")
psql "$DB_URL" -X -q <<SQL >/dev/null
delete from public.institution_members where institution_id = '$INST';
delete from auth.users where email like 'race%@example.test';
update public.institution_plan set limit_overrides = '{}' where institution_id = '$INST';
select app.usage_reconcile('$INST');
SQL
if [ "$members" = "$L" ] && [ "$counter" = "$L" ] && [ "$fixed" = "0" ]; then
  echo "ok - $N parallel member adds with a limit of $L: exactly $L added, counter $counter equals the recount"
else
  echo "FAILED: members=$members counter=$counter (limit $L), reconciliation fixed $fixed counter(s)"
  exit 1
fi
