-- Benchmark gate on main (after PR #6): can() per call went from 103 to 161 µs (+56 %; the agreed limit is 25 %).
-- 0B.08 added the support-session branch and kept auth.uid() / app.auth_institution_id() inside the query, so the
-- token was parsed several times per call and the membership looked up as a filter. Now the token is read once, the
-- membership is checked once, and the query gets plain values (same rules, same results; tests unchanged).
-- Local benchmark: 249 → 120 µs per call.
create or replace function app.can_check(p_action text, p_record jsonb) returns boolean
language plpgsql stable security definer set search_path = '' as $$
-- PL/pgSQL so the plan is cached (a SQL function with a SET clause is planned again on every call; lesson 13).
declare
  v_claims      jsonb := auth.jwt();
  v_user        uuid := nullif(v_claims ->> 'sub', '')::uuid;
  v_institution uuid := nullif(v_claims ->> 'active_institution_id', '')::uuid;
begin
  -- The same rule as app.auth_institution_id(), inlined: calling that SQL helper from here plans it again on every
  -- call (lesson 13; measured 491 µs against 120 µs inlined). Allow-listed in supabase/lint/allowlist.sql.
  if v_user is null or v_institution is null then
    return false;
  end if;
  -- An open support session: every non-sensitive permission of the institution, sensitive ones never (0B.08).
  if nullif(v_claims ->> 'support_session_id', '') is not null then
    return app.support_mode() is not null
       and exists (select 1 from public.permissions p where p.key = p_action and p.kind = 'institution' and not p.sensitive);
  end if;
  -- The token must still match an active membership (access version: a changed role ends old tokens at once).
  if not exists (select 1 from public.institution_members m
                  where m.institution_id = v_institution and m.user_id = v_user and m.status = 'active'
                    and m.access_version = nullif(v_claims ->> 'access_version', '')::integer) then
    return false;
  end if;
  return exists (
    select 1 from public.user_access ua
     where ua.institution_id = v_institution and ua.user_id = v_user
       and ua.permission_key in (p_action, '*')
       and (ua.valid_to is null or ua.valid_to > now())
       and (p_record is null or (
             (ua.branch_ids is null or (p_record ->> 'branch_id')::uuid = any (ua.branch_ids)
              or (p_record ->> 'created_by')::uuid = v_user)
         and (ua.user_ids is null or (p_record ->> 'owner_id')::uuid = any (ua.user_ids)
              or (p_record ->> 'created_by')::uuid = v_user)
         and (ua.offering_ids is null or (p_record ->> 'offering_id')::uuid = any (ua.offering_ids)
              or ((p_record ->> 'offering_id') is null and (p_record ->> 'created_by')::uuid = v_user))))
       -- `*` (Super Admin) never extends to platform permissions
       and (ua.permission_key <> '*' or exists (select 1 from public.permissions p where p.key = p_action and p.kind = 'institution')));
end $$;
