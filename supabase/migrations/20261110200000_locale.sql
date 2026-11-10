-- 0A.11 Locale settings (Bangladesh defaults), digit / phone normalisation and institution time.
-- Plan: Ch 13.3–13.6, 13.8 #3 #4 #7, Ch 47.3/47.4/47.8. See docs/dev/LOCALE.md.
-- Rules: digits are stored in ASCII only; times are timestamptz (UTC) and shown / calculated in the institution's
-- time zone; date-only values stay `date`; nothing locale-specific is hard-coded: every value below is a setting.

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Setting definitions (0A.11-T1, T8). Areas: settings.locale (formats) and settings.office (calendar, hours).
-- ---------------------------------------------------------------------------------------------------------------------
insert into public.setting_definitions (key, scope, schema, default_value, area, description)
select key, scope, schema::jsonb, default_value::jsonb, area, description from (values
  ('time_zone', 'institution',
   '{"type":"string","pattern":"^[A-Za-z]+(/[A-Za-z0-9_+-]+){0,2}$|^UTC$"}', '"Asia/Dhaka"', 'settings.locale',
   'IANA time zone for every time shown, reminder, job and report of the institution (Ch 13.6).'),
  ('currency', 'institution',
   '{"type":"object","required":["code","symbol","decimals","symbol_position"],"additionalProperties":false,'
   || '"properties":{"code":{"type":"string","pattern":"^[A-Z]{3}$"},"symbol":{"type":"string","minLength":1,"maxLength":5},'
   || '"decimals":{"type":"integer","minimum":0,"maximum":3},"symbol_position":{"enum":["before","after"]}}}',
   '{"code":"BDT","symbol":"৳","decimals":0,"symbol_position":"before"}', 'settings.locale',
   'Currency of receipts, fees and bills. decimals = digits shown after the point; amounts are stored exactly.'),
  ('phone', 'institution',
   '{"type":"object","required":["country_code","national_prefix","national_pattern","example"],"additionalProperties":false,'
   || '"properties":{"country_code":{"type":"string","pattern":"^[1-9][0-9]{0,3}$"},"national_prefix":{"type":"string","pattern":"^[0-9]{0,2}$"},'
   || '"national_pattern":{"type":"string","minLength":2},"example":{"type":"string","pattern":"^[0-9]+$"}}}',
   '{"country_code":"880","national_prefix":"0","national_pattern":"^01[3-9][0-9]{8}$","example":"01711223344"}',
   'settings.locale', 'Phone rules for duplicate checks, calls and SMS. Stored numbers are national, ASCII digits.'),
  ('week_start', 'institution',
   '{"enum":["saturday","sunday","monday","tuesday","wednesday","thursday","friday"]}', '"saturday"', 'settings.locale',
   'First day of the week in calendars and weekly reports.'),
  ('working_days', 'institution',
   '{"type":"array","uniqueItems":true,"minItems":1,"maxItems":7,'
   || '"items":{"enum":["saturday","sunday","monday","tuesday","wednesday","thursday","friday"]}}',
   '["saturday","sunday","monday","tuesday","wednesday","thursday"]', 'settings.office',
   'Working days (default: Friday off). Holidays list and follow-up presets are built in 1A (Ch 18).'),
  ('working_hours', 'institution',
   '{"type":"object","required":["start","end"],"additionalProperties":false,'
   || '"properties":{"start":{"type":"string","pattern":"^([01][0-9]|2[0-3]):[0-5][0-9]$"},'
   || '"end":{"type":"string","pattern":"^([01][0-9]|2[0-3]):[0-5][0-9]$"}}}',
   '{"start":"09:00","end":"17:00"}', 'settings.office',
   'Office hours (key only; used by reports and escalations later, Ch 18).'),
  ('quiet_hours', 'institution',
   '{"type":"object","required":["start","end"],"additionalProperties":false,'
   || '"properties":{"start":{"type":"string","pattern":"^([01][0-9]|2[0-3]):[0-5][0-9]$"},'
   || '"end":{"type":"string","pattern":"^([01][0-9]|2[0-3]):[0-5][0-9]$"}}}',
   '{"start":"22:00","end":"08:00"}', 'settings.office',
   'No push, SMS, email or campaigns in this window (key only; sending behaviour in 1B, Ch 25).'),
  ('scorecard_day', 'institution',
   '{"enum":["saturday","sunday","monday","tuesday","wednesday","thursday","friday"]}', '"sunday"', 'settings.office',
   'Day of the weekly scorecard (Ch 39).'),
  ('bangla_digits', 'institution',
   '{"type":"object","required":["ui","receipts","public_pages"],"additionalProperties":false,'
   || '"properties":{"ui":{"type":"boolean"},"receipts":{"type":"boolean"},"public_pages":{"type":"boolean"}}}',
   '{"ui":false,"receipts":false,"public_pages":false}', 'settings.locale',
   'Show Bangla digits (০-৯) when the language is Bangla: in the app, on receipts, on public pages. Storage is ASCII.'),
  ('payment_methods', 'institution',
   '{"type":"array","minItems":1,"items":{"type":"object","required":["key","enabled"],"additionalProperties":false,'
   || '"properties":{"key":{"type":"string","pattern":"^[a-z][a-z0-9_]*$"},"enabled":{"type":"boolean"}}}}',
   '[{"key":"bkash","enabled":true},{"key":"nagad","enabled":true},{"key":"rocket","enabled":true},'
   || '{"key":"cash","enabled":true},{"key":"bank","enabled":true}]', 'settings.locale',
   'Payment methods offered on fees and receipts (Ch 35). Names are translated by key.'),
  ('address_placeholder', 'institution',
   '{"type":"object","required":["en","bn"],"additionalProperties":{"type":"string","maxLength":200}}',
   '{"en":"House, road, area, upazila / thana, district","bn":"বাসা, রোড, এলাকা, উপজেলা / থানা, জেলা"}',
   'settings.locale', 'Placeholder of address fields in forms, per language.')
) as v (key, scope, schema, default_value, area, description);

-- default_language (0A.10) belongs to the same group.
update public.setting_definitions set area = 'settings.locale' where key = 'default_language';

-- A time zone must be one Postgres knows (JSON Schema can only check its shape).
create or replace function app.setting_extra_errors(p_key text, p_value jsonb) returns text[]
language sql stable set search_path = '' as $$
  select case
    when p_key = 'time_zone' and not exists (select 1 from pg_catalog.pg_timezone_names where name = p_value #>> '{}')
      then array[format('unknown time zone %s', p_value #>> '{}')]
    when p_key in ('working_hours', 'quiet_hours') and p_value ->> 'start' = p_value ->> 'end'
      then array['start and end must differ']
    else '{}'::text[] end
$$;

create or replace function app.validate_setting_value() returns trigger
language plpgsql set search_path = '' as $$
declare
  v_errors text[] := app.setting_extra_errors(new.key, new.value);
begin
  if array_length(v_errors, 1) > 0 then
    raise exception 'setting_invalid' using errcode = 'P0422', detail = array_to_string(v_errors, '; ');
  end if;
  return new;
end $$;
create trigger app_settings_extra_validation before insert or update of value on public.app_settings
  for each row execute function app.validate_setting_value();

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. Digits and phones (0A.11-T2). Bangla (০-৯), Arabic-Indic (٠-٩) and Persian (۰-۹) digits → ASCII.
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function app.ascii_digits(p_text text) returns text
language sql immutable parallel safe set search_path = '' as $$
  select translate(p_text, '০১২৩৪৫৬৭৮৯٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹', '012345678901234567890123456789')
$$;

-- Phone rules of an institution (setting), or the product default when there is no institution.
create or replace function app.phone_rules(p_institution uuid) returns jsonb
language sql stable set search_path = '' as $$
  select case when p_institution is null
              then (select d.default_value from public.setting_definitions d where d.key = 'phone')
              else app.setting_value(p_institution, 'phone') end
$$;

-- "০১৭১১-২২৩৩৪৪", "+880 1711 223344", "008801711223344", "8801711223344" → "01711223344".
-- Returns NULL for NULL or empty input; never raises (use app.require_valid_phone to enforce the pattern).
create or replace function app.normalize_phone(p_raw text, p_institution uuid default null) returns text
language plpgsql stable set search_path = '' as $$
declare
  v_rules  jsonb := app.phone_rules(p_institution);
  v_cc     text := v_rules ->> 'country_code';
  v_prefix text := coalesce(v_rules ->> 'national_prefix', '');
  v_plus   boolean;
  v_digits text;
begin
  if p_raw is null or btrim(p_raw) = '' then
    return null;
  end if;
  v_digits := app.ascii_digits(btrim(p_raw));
  v_plus := left(v_digits, 1) = '+';
  v_digits := regexp_replace(v_digits, '[^0-9]', '', 'g');
  if v_digits = '' then
    return null;
  end if;
  if not v_plus and left(v_digits, 2) = '00' then  -- international dialling prefix 00
    v_digits := substr(v_digits, 3);
    v_plus := true;
  end if;
  if left(v_digits, length(v_cc)) = v_cc and (v_plus or length(v_digits) > length(v_cc) + 8) then
    v_digits := v_prefix || ltrim(substr(v_digits, length(v_cc) + 1), '0');
  elsif v_plus then
    return '+' || v_digits;                           -- foreign number: keep it international
  end if;
  return v_digits;
end $$;

create or replace function app.is_ascii_phone(p_value text) returns boolean
language sql immutable parallel safe set search_path = '' as $$
  select p_value is null or p_value ~ '^\+?[0-9]{3,15}$'
$$;

-- Normalises and enforces the institution's pattern (international numbers with + are accepted as they are).
create or replace function app.require_valid_phone(p_raw text, p_institution uuid default null) returns text
language plpgsql stable set search_path = '' as $$
declare
  v_phone text := app.normalize_phone(p_raw, p_institution);
begin
  if v_phone is null then
    return null;
  end if;
  if not (v_phone ~ (app.phone_rules(p_institution) ->> 'national_pattern') or v_phone ~ '^\+[1-9][0-9]{6,14}$') then
    raise exception 'phone_invalid' using errcode = 'P0422', detail = v_phone;
  end if;
  return v_phone;
end $$;

-- Amounts and other numbers typed with Bangla digits or grouping: "১,০০,০০০.৫০" → 100000.50.
create or replace function app.parse_number(p_raw text) returns numeric
language plpgsql immutable set search_path = '' as $$
declare
  v_text text;
begin
  if p_raw is null or btrim(p_raw) = '' then
    return null;
  end if;
  v_text := regexp_replace(app.ascii_digits(btrim(p_raw)), '[,\s_৳]', '', 'g');
  if v_text !~ '^-?[0-9]+(\.[0-9]+)?$' then
    raise exception 'number_invalid' using errcode = 'P0422', detail = p_raw;
  end if;
  return v_text::numeric;
end $$;

-- Reusable BEFORE trigger: normalises the phone columns named in the trigger arguments.
-- create trigger … before insert or update on <table> for each row execute function app.normalize_phone_columns('phone');
create or replace function app.normalize_phone_columns() returns trigger
language plpgsql set search_path = '' as $$
declare
  v_column text;
  v_patch  jsonb := '{}'::jsonb;
  v_inst   uuid;
  v_row    jsonb := to_jsonb(new);
begin
  v_inst := case when v_row ? 'institution_id' then (v_row ->> 'institution_id')::uuid end;
  foreach v_column in array tg_argv loop
    v_patch := v_patch || jsonb_build_object(v_column, app.normalize_phone(v_row ->> v_column, v_inst));
  end loop;
  new := jsonb_populate_record(new, v_patch);
  return new;
end $$;

grant execute on function app.ascii_digits(text), app.phone_rules(uuid), app.normalize_phone(text, uuid),
  app.is_ascii_phone(text), app.require_valid_phone(text, uuid), app.parse_number(text),
  app.setting_extra_errors(text, jsonb) to authenticated, service_role;

-- Profiles: the phone is stored normalised and ASCII-only (Supabase Auth gives "8801…").
update public.profiles set phone = app.normalize_phone(phone) where phone is not null;
create trigger profiles_normalize_phone before insert or update of phone on public.profiles
  for each row execute function app.normalize_phone_columns('phone');
alter table public.profiles add constraint profiles_phone_ascii check (app.is_ascii_phone(phone));

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. Institution time (Ch 13.6). The server clock is the truth; the phone clock is never trusted (Ch 47.7).
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function app.institution_time_zone(p_institution uuid default null) returns text
language sql stable set search_path = '' as $$
  select coalesce(
    case when coalesce(p_institution, app.auth_institution_id()) is not null
         then app.setting_value(coalesce(p_institution, app.auth_institution_id()), 'time_zone') #>> '{}' end,
    (select d.default_value #>> '{}' from public.setting_definitions d where d.key = 'time_zone'))
$$;

-- Local wall-clock time of an instant in the institution (for display and "which day is it" questions).
create or replace function app.to_institution_time(p_at timestamptz, p_institution uuid default null) returns timestamp
language sql stable set search_path = '' as $$
  select p_at at time zone app.institution_time_zone(p_institution)
$$;

create or replace function app.institution_today(p_institution uuid default null) returns date
language sql stable set search_path = '' as $$
  select (now() at time zone app.institution_time_zone(p_institution))::date
$$;

-- A local date + time in the institution → the instant (e.g. "follow up on 2026-11-11 at 10:00").
create or replace function app.from_institution_time(p_local timestamp, p_institution uuid default null) returns timestamptz
language sql stable set search_path = '' as $$
  select p_local at time zone app.institution_time_zone(p_institution)
$$;

grant execute on function app.institution_time_zone(uuid), app.to_institution_time(timestamptz, uuid),
  app.institution_today(uuid), app.from_institution_time(timestamp, uuid) to authenticated, service_role;

-- For the app: the server's clock and the active institution's local date (0A.11-T6).
create or replace function public.server_time() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'now', now(),
    'time_zone', app.institution_time_zone(app.auth_institution_id()),
    'today', app.institution_today(app.auth_institution_id()),
    'local_time', to_char(app.to_institution_time(now(), app.auth_institution_id()), 'YYYY-MM-DD"T"HH24:MI:SS'))
$$;
revoke all on function public.server_time() from public;
grant execute on function public.server_time() to authenticated, anon;

-- Product defaults of the locale and office keys, for screens shown before sign-in (the app hard-codes none).
create or replace function public.locale_defaults() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_object_agg(d.key, d.default_value), '{}'::jsonb)
  from public.setting_definitions d
  where d.scope = 'institution' and d.area in ('settings.locale', 'settings.office')
$$;
revoke all on function public.locale_defaults() from public;
grant execute on function public.locale_defaults() to authenticated, anon;

-- Both are called before sign-in too (anon cannot read setting tables): DEFINER, registered.
insert into app.definer_registry (function_name, reason, added_in, reviewer, tenant_check) values
  ('public.server_time', 'Server clock + time zone/date of app.auth_institution_id() only (product default when none); '
   || 'callable before sign-in.', '0A.11', 'architecture review 0A.11', 'filters_active_institution'),
  ('public.locale_defaults', 'Product defaults of locale/office setting definitions; no institution data; callable before '
   || 'sign-in.', '0A.11', 'architecture review 0A.11', 'not_tenant_data');
