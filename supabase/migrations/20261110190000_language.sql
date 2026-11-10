-- 0A.10 Language of the UI: each person picks bn / en; the institution sets a default (D13, Ch 13.2).
-- Resolution (same rule in the app, src/i18n/language.ts): user choice → institution default_language → English.
-- The person's choice is stored in profiles.preferred_language (0A.03); NULL means "follow the institution".

insert into public.setting_definitions (key, scope, schema, default_value, area, description) values
  ('default_language', 'institution', '{"type":"string","enum":["bn","en"]}', '"en"', 'settings.general',
   'UI language for members who have not chosen one (D13). Message templates follow the recipient, not this (Ch 24).');

-- The language the app should use for the signed-in person in the active institution.
create or replace function app.resolve_language(p_user uuid, p_institution uuid) returns text
language sql stable set search_path = '' as $$
  select coalesce(
    (select p.preferred_language from public.profiles p where p.user_id = p_user),
    case when p_institution is not null then app.setting_value(p_institution, 'default_language') #>> '{}' end,
    'en')
$$;
grant execute on function app.resolve_language(uuid, uuid) to authenticated;

-- Set (or clear with NULL) the signed-in person's own UI language. Own profile row only (RLS + column grant).
create or replace function public.set_my_language(p_language text) returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not_signed_in' using errcode = 'P0401';
  end if;
  if p_language is not null and p_language not in ('bn', 'en') then
    raise exception 'language_unsupported' using errcode = 'P0422', detail = p_language;
  end if;
  update public.profiles set preferred_language = p_language where user_id = v_user;
  return jsonb_build_object('choice', p_language,
                            'language', app.resolve_language(v_user, app.auth_institution_id()));
end $$;

-- What the app needs on its first screen after sign-in: the choice, the institution default and the result.
create or replace function public.my_language() returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'choice', (select p.preferred_language from public.profiles p where p.user_id = auth.uid()),
    'institution_default', case when app.auth_institution_id() is not null
                                then app.setting_value(app.auth_institution_id(), 'default_language') #>> '{}' end,
    'language', app.resolve_language(auth.uid(), app.auth_institution_id()))
$$;

revoke all on function public.set_my_language(text), public.my_language() from public, anon;
grant execute on function public.set_my_language(text), public.my_language() to authenticated;
