#!/usr/bin/env bash
# Fixture test for scripts/extension-lint.sh: every bad pattern is caught, the real tree passes.
set -uo pipefail
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fail=0
expect() { # expect <0|1> <label>
  local want="$1" label="$2" got
  bash scripts/extension-lint.sh "$tmp/core" "$tmp/ext" >/dev/null 2>&1; got=$?
  if [[ "$got" == "$want" ]]; then echo "ok - $label"; else echo "not ok - $label (exit $got, wanted $want)"; fail=1; fi
}
reset() { rm -rf "$tmp/core" "$tmp/ext"; mkdir -p "$tmp/core" "$tmp/ext/x/migrations"; echo "select 1;" > "$tmp/core/1_core.sql"; }
ext() { printf '%s\n' "$1" > "$tmp/ext/x/migrations/0001_x.sql"; }

reset; ext "create schema ext_x; create table ext_x.t (institution_id uuid not null);
insert into public.extensions (key) values ('x'); insert into public.event_listeners (listener_key) values ('x.y');"
expect 0 "clean extension passes"
reset; echo "select * from ext_x.t;" > "$tmp/core/2_bad.sql"; expect 1 "core referencing ext_ schema"
reset; ext "alter table public.leads add column x int;"; expect 1 "alter core table"
reset; ext "drop function if exists app.audit(uuid);"; expect 1 "drop core function"
reset; ext "update public.institutions set name = 'x';"; expect 1 "update core table"
reset; ext "delete from public.audit_log;"; expect 1 "delete from core table"
reset; ext "create trigger t after insert
  on public.leads for each row execute function ext_x.f();"; expect 1 "trigger on core table (multi-line)"
reset; ext "create policy p on public.leads using (true);"; expect 1 "policy on core table"
reset; ext "create or replace function public.setting_set() returns void language sql as 'select 1';"; expect 1 "replace core function"
reset; ext "insert into public.audit_log (action) values ('x.y');"; expect 1 "insert into non-registry core table"
reset; ext "-- alter table public.leads (comment only)
select 1;"; expect 0 "comments are ignored"
bash scripts/extension-lint.sh >/dev/null 2>&1 && echo "ok - repository passes" || { echo "not ok - repository passes"; fail=1; }
exit $fail
