#!/usr/bin/env bash
# Loads the demo data into STAGING for the owner's preview (0A.20-T8/T9). Never for production.
# - The test seed (institutions A, B, weird labels; owner.admin, a.member, both.member …) and the demo branches.
# - No Master Admin test account (removed from platform_members).
# - Every demo account gets the password from the DEMO_PASSWORD secret (never the public test password).
# Safe to run again: the seed is loaded only once; the password is set every time.
set -euo pipefail
: "${DB_URL:?DB_URL is required}"
: "${DEMO_PASSWORD:?DEMO_PASSWORD secret is required}"
if [ "${#DEMO_PASSWORD}" -lt 12 ]; then echo "DEMO_PASSWORD must be at least 12 characters" >&2; exit 1; fi
psql_q() { psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 "$@"; }
loaded=$(psql_q -At -c "select count(*) from public.institutions where id = 'a0000000-0000-4000-8000-00000000000a'")
if [ "$loaded" = "0" ]; then
  for f in supabase/seeds/*.sql; do echo "Loading $f"; psql_q -f "$f"; done
else
  echo "Demo seed already loaded."
fi
psql_q -f scripts/demo/prepare.sql
psql_q -v pw="$DEMO_PASSWORD" <<'SQL'
delete from public.platform_members where user_id in (select id from auth.users where email like '%@example.test');
delete from auth.mfa_factors where user_id in (select id from auth.users where email like '%@example.test');
update auth.users set encrypted_password = extensions.crypt(:'pw', extensions.gen_salt('bf')), updated_at = now()
 where email like '%@example.test';
select app.flush_access_queue();
SQL
echo "Demo data ready on staging."
