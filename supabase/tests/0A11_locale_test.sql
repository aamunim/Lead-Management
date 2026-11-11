-- 0A.11 tests: locale settings, digit and phone normalisation (ASCII storage), institution time near midnight.
\set ON_ERROR_STOP on
begin;
create function pg_temp.check(cond boolean, what text) returns void language plpgsql as $$
begin
  if cond is distinct from true then raise exception 'FAILED: %', what; end if;
  raise notice 'ok - %', what;
end $$;
create function pg_temp.claims_for(p_user uuid) returns jsonb language sql as $$
  select (public.custom_access_token_hook(jsonb_build_object('user_id', p_user,
          'claims', jsonb_build_object('sub', p_user, 'role', 'authenticated', 'aud', 'authenticated')))) -> 'claims'
$$;
create function pg_temp.act_as(p_claims jsonb) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', p_claims::text, true);
  perform set_config('role', 'authenticated', true);
end $$;
create function pg_temp.error_of(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return ''; exception when others then return sqlerrm; end $$;
grant execute on all functions in schema pg_temp to authenticated;

\set inst_a '''a0000000-0000-4000-8000-00000000000a'''
\set inst_b '''b0000000-0000-4000-8000-00000000000b'''
\set user_a '''11111111-1111-4111-8111-111111111111'''
\set user_b '''22222222-2222-4222-8222-222222222222'''
\set user_platform '''55555555-5555-4555-8555-555555555555'''
update public.profiles set last_active_institution_id = null where user_id in (:user_a, :user_b);
delete from public.app_settings where key in ('time_zone', 'phone', 'currency');

-- 1. Every locale key exists with the Bangladesh default (Ch 13.3).
select pg_temp.check((select count(*) from public.setting_definitions where key in ('time_zone', 'currency', 'phone',
  'week_start', 'working_days', 'working_hours', 'quiet_hours', 'scorecard_day', 'bangla_digits', 'payment_methods',
  'address_placeholder', 'default_language')) = 12, 'all locale and office keys are registered');
select pg_temp.check((select default_value from public.setting_definitions where key = 'time_zone') = '"Asia/Dhaka"', 'time zone defaults to Asia/Dhaka');
select pg_temp.check((select default_value ->> 'symbol' from public.setting_definitions where key = 'currency') = '৳', 'currency defaults to ৳');
select pg_temp.check((select default_value ->> 'country_code' from public.setting_definitions where key = 'phone') = '880', 'phone country code 880');
select pg_temp.check((select default_value from public.setting_definitions where key = 'week_start') = '"saturday"', 'week starts on Saturday');
select pg_temp.check(not ((select default_value from public.setting_definitions where key = 'working_days') ? 'friday'), 'Friday is off by default');
select pg_temp.check((select default_value from public.setting_definitions where key = 'quiet_hours') = '{"start":"22:00","end":"08:00"}', 'quiet hours 22:00–08:00');
select pg_temp.check((select default_value from public.setting_definitions where key = 'scorecard_day') = '"sunday"', 'scorecard on Sunday');
select pg_temp.check((select jsonb_agg(x ->> 'key') from public.setting_definitions, jsonb_array_elements(default_value) x
                      where key = 'payment_methods') = '["bkash","nagad","rocket","cash","bank"]', 'payment methods bKash, Nagad, Rocket, cash, bank');

-- 2. Digits and phones.
select pg_temp.check(app.ascii_digits('০১২৩৪৫৬৭৮৯') = '0123456789', 'Bangla digits become ASCII');
select pg_temp.check(app.normalize_phone('০১৭১১-২২৩৩৪৪') = '01711223344', 'normalize_phone(''০১৭১১-২২৩৩৪৪'') = 01711223344');
select pg_temp.check(app.normalize_phone('+880 1711 223344') = '01711223344', '+880 with spaces is normalised');
select pg_temp.check(app.normalize_phone('+৮৮০১৭১১২২৩৩৪৪') = '01711223344', '+880 typed in Bangla digits is normalised');
select pg_temp.check(app.normalize_phone('008801711223344') = '01711223344', '00880 prefix is normalised');
select pg_temp.check(app.normalize_phone('8801711223344') = '01711223344', '880 without + (Supabase Auth style) is normalised');
select pg_temp.check(app.normalize_phone('+880 (0)1711-223344') = '01711223344', '+880 (0) form is normalised');
select pg_temp.check(app.normalize_phone('017.11.22.33.44') = '01711223344', 'dots are removed');
select pg_temp.check(app.normalize_phone('+44 20 7946 0958') = '+442079460958', 'a foreign number stays international');
select pg_temp.check(app.normalize_phone('   ') is null and app.normalize_phone(null) is null, 'empty input gives NULL');
select pg_temp.check(app.require_valid_phone('01711223344') = '01711223344', 'a valid number passes');
select pg_temp.check(pg_temp.error_of('select app.require_valid_phone(''01211223344'')') like 'phone_invalid%', 'an invalid BD mobile number is rejected');
select pg_temp.check(pg_temp.error_of('select app.require_valid_phone(''123'')') like 'phone_invalid%', 'a too short number is rejected');
select pg_temp.check(app.parse_number('১,০০,০০০') = 100000, 'parse_number(''১,০০,০০০'') = 100000');
select pg_temp.check(app.parse_number('৳ 1,50,000.50') = 150000.50, 'currency sign, grouping and decimals are handled');
select pg_temp.check(pg_temp.error_of('select app.parse_number(''১২ক'')') like 'number_invalid%', 'text that is not a number is rejected');

-- Institution rules change the result (no code change): another country code.
select pg_temp.act_as((pg_temp.claims_for(:user_platform) || '{"aal":"aal2"}'));
select public.setting_set('phone', '{"country_code":"91","national_prefix":"0","national_pattern":"^0[6-9][0-9]{9}$","example":"09812345678"}', :inst_b);
reset role;
select pg_temp.check(app.normalize_phone('+91 98123 45678', :inst_b) = '09812345678', 'B''s own phone rules are applied (country code 91)');
select pg_temp.check(app.normalize_phone('+91 98123 45678', :inst_a) = '+919812345678', '...while A still uses 880');

-- Stored phones are ASCII: profile phone typed in Bangla digits is normalised; a non-ASCII value cannot be stored.
select pg_temp.act_as(pg_temp.claims_for(:user_a));
update public.profiles set phone = '+৮৮০ ১৭১১-২২৩৩৪৪' where user_id = :user_a;
reset role;
select pg_temp.check((select phone from public.profiles where user_id = :user_a) = '01711223344', 'a profile phone typed in Bangla is stored as ASCII');
select pg_temp.check(not exists (select 1 from public.profiles where phone !~ '^\+?[0-9]+$'), 'no stored phone has non-ASCII digits');
select pg_temp.check(pg_temp.error_of('alter table public.profiles disable trigger profiles_normalize_phone; '
  || 'update public.profiles set phone = ''০১৭১১২২৩৩৪৪'' where user_id = ''' || :user_a || '''') like '%profiles_phone_ascii%',
  'even without the trigger, the CHECK refuses non-ASCII digits');

-- 3. Settings validation beyond the schema.
select pg_temp.act_as((pg_temp.claims_for(:user_platform) || '{"aal":"aal2"}'));
select pg_temp.check(pg_temp.error_of(format('select public.setting_set(%L, %L, %L)', 'time_zone', '"Mars/Olympus"', :inst_a))
                     like 'setting_invalid%', 'an unknown time zone is rejected');
select pg_temp.check(pg_temp.error_of(format('select public.setting_set(%L, %L, %L)', 'quiet_hours', '{"start":"22:00","end":"22:00"}', :inst_a))
                     like 'setting_invalid%', 'quiet hours with the same start and end are rejected');
select pg_temp.check(pg_temp.error_of(format('select public.setting_set(%L, %L, %L)', 'working_days', '["friday","friday"]', :inst_a))
                     like 'setting_invalid%', 'duplicate working days are rejected');
reset role;

-- 4. Institution time near midnight (Ch 13.8 #4): 2026-11-10 18:30 UTC = 2026-11-11 00:30 in Dhaka (UTC+6).
select pg_temp.check(app.to_institution_time('2026-11-10 18:30:00+00', :inst_a) = '2026-11-11 00:30:00',
                     '18:30 UTC is 00:30 the next day in Dhaka');
select pg_temp.check(app.to_institution_time('2026-11-10 17:59:59+00', :inst_a)::date = '2026-11-10',
                     '17:59:59 UTC is still the same day in Dhaka');
select pg_temp.check(app.from_institution_time('2026-11-11 10:00', :inst_a) = '2026-11-11 04:00:00+00',
                     '10:00 in Dhaka is 04:00 UTC');
select pg_temp.act_as((pg_temp.claims_for(:user_platform) || '{"aal":"aal2"}'));
select public.setting_set('time_zone', '"Europe/London"', :inst_b);
reset role;
select pg_temp.check(app.to_institution_time('2026-11-10 18:30:00+00', :inst_b)::date = '2026-11-10',
                     'changing the time zone setting changes the local date (no code change)');
select pg_temp.check(app.from_institution_time('2026-07-01 10:00', :inst_b) = '2026-07-01 09:00:00+00',
                     'daylight saving time is handled by the time zone (London summer)');
select pg_temp.act_as(pg_temp.claims_for(:user_a));
select pg_temp.check((public.server_time() ->> 'time_zone') = 'Asia/Dhaka', 'server_time reports the active institution''s time zone');
select pg_temp.check((public.server_time() ->> 'today')::date = (now() at time zone 'Asia/Dhaka')::date, '...and its local date');
reset role;
select pg_temp.act_as(pg_temp.claims_for(:user_b));
select pg_temp.check((public.server_time() ->> 'time_zone') = 'Europe/London', 'B sees its own time zone');
reset role;
rollback;
