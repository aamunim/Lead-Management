# Locale: time zone, money, numbers, dates, phones (0A.11)

Plan: Ch 13.3–13.6, 13.8 #3 #4 #7, Ch 47.7/47.8. Migration `20261110200000_locale.sql`. Tests:
`supabase/tests/0A11_locale_test.sql`, `scripts/tests/format.test.mjs`, `scripts/e2e/locale.e2e.mjs`,
`scripts/ui/locale.web.test.mjs`.

## Rules

1. **No locale value in code.** Time zone, currency, phone rules, week start, working days and the rest are settings
   (below). Changing one for an institution changes its formatting with no code change.
2. **Digits are stored in ASCII.** Phones, amounts and numbers typed with Bangla digits are converted on input
   (client) **and** again on the server. Bangla digits are only a display choice.
3. **Times are `timestamptz`** (UTC) and shown / calculated in the institution's time zone. **Date-only values are
   `date`** (birthday, instalment date) and are never shifted by a time zone.
4. **Money and numbers use lakh grouping**: 1,00,000 / ১,০০,০০০, never 100,000.
5. **"Now" comes from the server clock** (`serverNow()`), never the phone clock, which is often wrong.

The UI lint (`npm run check:i18n`) enforces 4 and 5 in app code: `toLocaleString` / `Intl.*` only inside
`src/lib/format.ts`; `Date.now()` / `new Date()` only inside `src/lib/server-time.ts` (a device-only measurement such
as a cache's age may be exempted with `// i18n-exempt: <reason>`). The schema lint enforces 2 for phone columns.

## Settings (Bangladesh defaults; owner confirms the list)

| Key | Default | Area |
|---|---|---|
| `time_zone` | `Asia/Dhaka` (must be a zone Postgres knows) | settings.locale |
| `currency` | `{code: BDT, symbol: ৳, decimals: 0, symbol_position: before}` → ৳1,00,000 | settings.locale |
| `phone` | country code `880`, national prefix `0`, pattern `^01[3-9][0-9]{8}$`, example `01711223344` | settings.locale |
| `week_start` | Saturday | settings.locale |
| `working_days` | Saturday–Thursday (Friday off) | settings.office |
| `working_hours` | 09:00–17:00 (key only; used later, Ch 18) | settings.office |
| `quiet_hours` | 22:00–08:00 (key only; sending behaviour in 1B, Ch 25) | settings.office |
| `scorecard_day` | Sunday | settings.office |
| `default_language` | English (0A.10) | settings.locale |
| `bangla_digits` | off for app, receipts and public pages | settings.locale |
| `payment_methods` | bKash, Nagad, Rocket, cash, bank (names translated by key) | settings.locale |
| `address_placeholder` | per language, Bangladeshi address pattern | settings.locale |

The holiday list, the Settings → OFFICE screen and follow-up presets that skip holidays are built in **1A (Ch 18)**;
quiet-hours sending in **1B (Ch 25)**. Only the keys exist now (0A.11-T8). The group name of these keys in the
settings screens is confirmed with the Appendix A owner in 0B.

## Server helpers

| Function | Does |
|---|---|
| `app.ascii_digits(text)` | Bangla / Arabic-Indic / Persian digits → ASCII |
| `app.normalize_phone(raw, institution)` | `"০১৭১১-২২৩৩৪৪"`, `"+880 1711 223344"`, `"008801711223344"`, `"8801711223344"` → `01711223344`; foreign numbers stay `+…`; never raises |
| `app.require_valid_phone(raw, institution)` | normalises and raises `phone_invalid` if the pattern does not match |
| `app.parse_number(raw)` | `"১,০০,০০০"` → 100000; raises `number_invalid` |
| `app.normalize_phone_columns('col', …)` | reusable BEFORE trigger for tables with phone columns |
| `app.is_ascii_phone(value)` | for the CHECK constraint every phone column must have (schema lint rule `phone_ascii`) |
| `app.institution_time_zone(inst)`, `app.to_institution_time(ts, inst)`, `app.from_institution_time(local, inst)`, `app.institution_today(inst)` | time in the institution |
| `public.server_time()` | server clock, the active institution's time zone and local date (callable before sign-in) |
| `public.locale_defaults()` | product defaults of the locale keys, for screens before sign-in |

**Every RPC that accepts a phone or a number** calls `app.require_valid_phone` / `app.normalize_phone` /
`app.parse_number` on it, even though the app has already normalised it (Ch 13.8 #3). New phone columns get the
trigger and the CHECK (the lint fails without the CHECK).

## App

- `src/lib/format.ts`: pure library (lakh grouping, money, digits, phones, time zones, date/time text, calendars).
- `useFormat(place?)` from `src/lib/locale.ts`: formatters bound to the language and the institution's settings:
  `money`, `number`, `date` (date-only), `time`, `dateTime` (instant in the institution's zone), `digitsText`.
  `place` is `ui`, `receipts` or `public_pages` (which `bangla_digits` switch applies).
- Fields: `PhoneInput`, `AmountInput` (`src/components/fields/inputs.tsx`); `DateField` (date-only),
  `DateTimeField` (instant) (`src/components/fields/pickers.tsx`). JS pickers: same on Android and web, bn/en,
  week starts on `week_start`, "today" from the server clock in the institution's zone.
- Words (months, weekdays, day periods) come from the `format` translation namespace; a language's `grammar`
  subtree (12-hour clock, day periods ভোর / সকাল / দুপুর / বিকাল / সন্ধ্যা / রাত, word order) may differ per language.
- `serverNow()` (`src/lib/server-time.ts`): phone clock + offset measured with `server_time()` at start-up, sign-in
  and when the app returns to the foreground.

## Spike: Bangla sorting and dual-script search (0A.11-T7) — decision

Measured on the local Postgres 17 (Supabase image):

- The database collation is ICU `en_US`; ICU collations `bn-x-icu`, `bn-BD-x-icu` exist.
- Sample sort, default vs `bn-x-icu`: `কক্ষ কত কংস কা কঁাচা …` vs `কংস কঁাচা কক্ষ কত কা …`. **ICU Bangla puts ং / ঁ
  before conjuncts, as Bangla dictionaries do; the default does not.** Latin names sort before Bangla in the default
  and after it in `bn-x-icu`.
- Numeric collation (`bn-u-kn`) sorts ২ before ১০.
- `pg_trgm`, `unaccent` and `fuzzystrmatch` are available; trigram similarity does **not** match across scripts
  (rahim ↔ রহিম).

**Decision (proposed; confirm in 1A before name columns exist):**
1. Sort person and offering names with `collate "bn-x-icu"` when the viewer's language is Bangla, the default
   otherwise. Sorting is a query choice; the column keeps the default collation, and an index with
   `collate "bn-x-icu"` is added only where a long list needs it.
2. Dual-script search: store a generated `search_latin` (transliteration of Bangla names to Latin) next to the name
   and index both with `pg_trgm`; a search matches either. The transliteration function is written and benchmarked
   in 1A (Ch 13.8 #7).

## Fixed in this milestone

`app.pre_request()` (0A.08) read product settings as the caller, so **every anonymous API call failed** (401
"permission denied"). It is now SECURITY DEFINER (registered) and an e2e test calls the API anonymously.
