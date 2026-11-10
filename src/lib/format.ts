// Formatting library (0A.11). Pure: no React Native imports, unit-tested in Node (scripts/tests/format.test.mjs).
// The ONLY place allowed to use Intl / toLocale* (enforced by scripts/check-ui-strings.mjs): every number, amount,
// date and time on screen goes through here, with the institution's settings and the words from translations.
//
// - Money and numbers use lakh grouping: 1,00,000 / ১,০০,০০০ — never 100,000 (Ch 47.8).
// - Digits are stored ASCII; Bangla digits are only a display choice (setting bangla_digits).
// - Instants are shown in the institution's time zone; date-only values ('YYYY-MM-DD') are never shifted.

export type DigitStyle = 'ascii' | 'bangla';
export type Currency = { code: string; symbol: string; decimals: number; symbol_position: 'before' | 'after' };
export type PhoneRules = { country_code: string; national_prefix: string; national_pattern: string; example: string };
export type DateWords = {
  months: string[]; // 12, January first
  monthsShort: string[];
  weekdays: string[]; // 7, Sunday first
  weekdaysShort: string[];
  dayPeriods: { from: number; label: string }[]; // hour (0–23) from which the label applies, ascending
  hour12: boolean;
};
export type Weekday = 'sunday' | 'monday' | 'tuesday' | 'wednesday' | 'thursday' | 'friday' | 'saturday';
export const WEEKDAYS: Weekday[] = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'];

// ---------------------------------------------------------------------------------------------------------------------
// Digits
// ---------------------------------------------------------------------------------------------------------------------
const BANGLA = '০১২৩৪৫৬৭৮৯';
const OTHER_DIGITS = ['০১২৩৪৫৬৭৮৯', '٠١٢٣٤٥٦٧٨٩', '۰۱۲۳۴۵۶۷۸۹'];

export function toAsciiDigits(text: string): string {
  let out = '';
  for (const ch of text) {
    let mapped = ch;
    for (const set of OTHER_DIGITS) {
      const index = set.indexOf(ch);
      if (index >= 0) mapped = String(index);
    }
    out += mapped;
  }
  return out;
}

export function toBanglaDigits(text: string): string {
  return text.replace(/[0-9]/g, (d) => BANGLA[Number(d)]);
}

export const applyDigits = (text: string, digits: DigitStyle) => (digits === 'bangla' ? toBanglaDigits(text) : text);

// ---------------------------------------------------------------------------------------------------------------------
// Numbers and money
// ---------------------------------------------------------------------------------------------------------------------

/** "1234567" → "12,34,567" (last three digits, then groups of two). */
export function groupLakh(intDigits: string): string {
  if (intDigits.length <= 3) return intDigits;
  const last3 = intDigits.slice(-3);
  let rest = intDigits.slice(0, -3);
  const groups: string[] = [];
  while (rest.length > 2) {
    groups.unshift(rest.slice(-2));
    rest = rest.slice(0, -2);
  }
  if (rest) groups.unshift(rest);
  return `${groups.join(',')},${last3}`;
}

/** Canonical decimal string ("-1234.5") from a number or numeric string; null if not a number. */
function canonical(value: number | string): string | null {
  const text = typeof value === 'number' ? (Number.isFinite(value) ? String(value) : '') : value.trim();
  if (/e/i.test(text)) return Number.isFinite(Number(text)) ? Number(text).toFixed(20).replace(/\.?0+$/, '') : null;
  return /^-?[0-9]+(\.[0-9]+)?$/.test(text) ? text : null;
}

/** Rounds a canonical decimal string to `decimals` places (half away from zero), exactly, without floating point. */
function roundDecimal(text: string, decimals: number): { negative: boolean; int: string; frac: string } {
  const negative = text.startsWith('-');
  const [intRaw, fracRaw = ''] = (negative ? text.slice(1) : text).split('.');
  const padded = (fracRaw + '0'.repeat(decimals + 1)).slice(0, decimals + 1);
  let digits = (intRaw + padded.slice(0, decimals)).replace(/^0+(?=\d)/, '') || '0';
  if (Number(padded[decimals] ?? '0') >= 5) {
    const arr = digits.split('').map(Number);
    let i = arr.length - 1;
    while (i >= 0) {
      if (arr[i] < 9) { arr[i] += 1; break; }
      arr[i] = 0;
      i -= 1;
    }
    if (i < 0) arr.unshift(1);
    digits = arr.join('');
  }
  digits = digits.padStart(decimals + 1, '0');
  const int = digits.slice(0, digits.length - decimals).replace(/^0+(?=\d)/, '');
  const frac = decimals > 0 ? digits.slice(-decimals) : '';
  const isZero = /^0+$/.test(int + frac);
  return { negative: negative && !isZero, int, frac };
}

export function formatNumber(value: number | string, options: { digits?: DigitStyle; decimals?: number } = {}): string {
  const text = canonical(value);
  if (text === null) return '';
  const decimals = options.decimals ?? Math.min((text.split('.')[1] ?? '').length, 6);
  const { negative, int, frac } = roundDecimal(text, decimals);
  const out = `${negative ? '-' : ''}${groupLakh(int)}${frac ? `.${frac}` : ''}`;
  return applyDigits(out, options.digits ?? 'ascii');
}

export function formatMoney(amount: number | string, currency: Currency, digits: DigitStyle = 'ascii'): string {
  const text = canonical(amount);
  if (text === null) return '';
  const number = formatNumber(text, { digits, decimals: currency.decimals });
  const negative = number.startsWith('-');
  const body = negative ? number.slice(1) : number;
  const signed = currency.symbol_position === 'before' ? `${currency.symbol}${body}` : `${body} ${currency.symbol}`;
  return negative ? `-${signed}` : signed;
}

/**
 * Number typed by a person ("১,০০,০০০", "৳ 1,50,000.50", "  42 ") → canonical ASCII string ("100000", "150000.50").
 * Returns null when it is not a number. Mirrors app.parse_number on the server.
 */
export function parseNumberInput(raw: string): string | null {
  const text = toAsciiDigits(raw).replace(/[\s,_৳]/g, ''); // same characters as app.parse_number
  if (!/^-?[0-9]+(\.[0-9]+)?$/.test(text)) return null;
  return text.replace(/^(-?)0+(?=\d)/, '$1');
}

/** While typing: digits converted to ASCII at once, anything but digits / one point / leading minus dropped. */
export function cleanNumberTyping(raw: string, allowDecimal = true): string {
  let text = toAsciiDigits(raw).replace(allowDecimal ? /[^0-9.-]/g : /[^0-9-]/g, '');
  text = text.replace(/(?!^)-/g, '');
  const point = text.indexOf('.');
  if (point >= 0) text = text.slice(0, point + 1) + text.slice(point + 1).replace(/\./g, '');
  return text;
}

// ---------------------------------------------------------------------------------------------------------------------
// Phones (mirror of app.normalize_phone; the server normalises again — never trust the client alone)
// ---------------------------------------------------------------------------------------------------------------------
export function normalizePhone(raw: string | null | undefined, rules: PhoneRules): string | null {
  if (raw == null || raw.trim() === '') return null;
  let digits = toAsciiDigits(raw.trim());
  let plus = digits.startsWith('+');
  digits = digits.replace(/[^0-9]/g, '');
  if (!digits) return null;
  if (!plus && digits.startsWith('00')) {
    digits = digits.slice(2);
    plus = true;
  }
  const cc = rules.country_code;
  if (digits.startsWith(cc) && (plus || digits.length > cc.length + 8)) {
    return rules.national_prefix + digits.slice(cc.length).replace(/^0+/, '');
  }
  return plus ? `+${digits}` : digits;
}

export function isValidPhone(phone: string | null, rules: PhoneRules): boolean {
  if (!phone) return false;
  return new RegExp(rules.national_pattern).test(phone) || /^\+[1-9][0-9]{6,14}$/.test(phone);
}

/** While typing a phone: Bangla digits → ASCII at once; only digits, +, spaces and dashes kept. */
export function cleanPhoneTyping(raw: string): string {
  return toAsciiDigits(raw).replace(/[^0-9+\s-]/g, '');
}

// ---------------------------------------------------------------------------------------------------------------------
// Time zones
// ---------------------------------------------------------------------------------------------------------------------
export type ZonedParts = { year: number; month: number; day: number; hour: number; minute: number; second: number; weekday: number };
const partFormatters = new Map<string, Intl.DateTimeFormat>();

function partFormatter(timeZone: string): Intl.DateTimeFormat {
  let formatter = partFormatters.get(timeZone);
  if (!formatter) {
    formatter = new Intl.DateTimeFormat('en-US', {
      timeZone, hourCycle: 'h23', year: 'numeric', month: 'numeric', day: 'numeric',
      hour: 'numeric', minute: 'numeric', second: 'numeric', weekday: 'short',
    });
    partFormatters.set(timeZone, formatter);
  }
  return formatter;
}

const WEEKDAY_SHORT_EN = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']; // Intl parsing keys, not shown to users

/** Wall-clock parts of an instant in a time zone (weekday: 0 = Sunday). */
export function zonedParts(epochMs: number, timeZone: string): ZonedParts {
  const parts: Record<string, string> = {};
  for (const p of partFormatter(timeZone).formatToParts(new Date(epochMs))) parts[p.type] = p.value;
  return {
    year: Number(parts.year), month: Number(parts.month), day: Number(parts.day),
    hour: Number(parts.hour) % 24, minute: Number(parts.minute), second: Number(parts.second),
    weekday: WEEKDAY_SHORT_EN.indexOf(parts.weekday),
  };
}

/** Local date + time in a time zone → the instant (epoch ms). Handles DST by re-checking the offset. */
export function zonedToEpoch(local: { year: number; month: number; day: number; hour?: number; minute?: number }, timeZone: string): number {
  const asUtc = Date.UTC(local.year, local.month - 1, local.day, local.hour ?? 0, local.minute ?? 0);
  const offsetAt = (epoch: number) => {
    const p = zonedParts(epoch, timeZone);
    return Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second) - Math.floor(epoch / 1000) * 1000;
  };
  let guess = asUtc - offsetAt(asUtc);
  const second = asUtc - offsetAt(guess);
  if (second !== guess) guess = second;
  return guess;
}

const pad2 = (n: number) => String(n).padStart(2, '0');

/** 'YYYY-MM-DD' of an instant in a time zone. */
export function localDateOf(epochMs: number, timeZone: string): string {
  const p = zonedParts(epochMs, timeZone);
  return `${p.year}-${pad2(p.month)}-${pad2(p.day)}`;
}

export function parseDateOnly(value: string): { year: number; month: number; day: number } | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!m) return null;
  const [year, month, day] = [Number(m[1]), Number(m[2]), Number(m[3])];
  const check = new Date(Date.UTC(year, month - 1, day));
  if (check.getUTCFullYear() !== year || check.getUTCMonth() !== month - 1 || check.getUTCDate() !== day) return null;
  return { year, month, day };
}

/** Weekday (0 = Sunday) of a date-only value, without any time zone. */
export function weekdayOfDate(value: { year: number; month: number; day: number }): number {
  return new Date(Date.UTC(value.year, value.month - 1, value.day)).getUTCDay();
}

export function addDays(value: string, days: number): string {
  const d = parseDateOnly(value);
  if (!d) return value;
  const t = new Date(Date.UTC(d.year, d.month - 1, d.day + days));
  return `${t.getUTCFullYear()}-${pad2(t.getUTCMonth() + 1)}-${pad2(t.getUTCDate())}`;
}

// ---------------------------------------------------------------------------------------------------------------------
// Dates and times as text
// ---------------------------------------------------------------------------------------------------------------------
export type DateStyle = 'long' | 'short';

/** Date-only value ('YYYY-MM-DD') → "11 November 2026" / "১১ নভেম্বর ২০২৬". Never shifted by a time zone. */
export function formatDate(value: string, words: DateWords, digits: DigitStyle = 'ascii', style: DateStyle = 'long'): string {
  const d = parseDateOnly(value);
  if (!d) return '';
  const month = (style === 'long' ? words.months : words.monthsShort)[d.month - 1];
  return applyDigits(`${d.day} ${month} ${d.year}`, digits);
}

export function dayPeriod(hour: number, words: DateWords): string {
  let label = '';
  for (const p of words.dayPeriods) if (hour >= p.from) label = p.label;
  return label || (words.dayPeriods[words.dayPeriods.length - 1]?.label ?? '');
}

/** 15:05 → "3:05 PM" (en) / "বিকাল ৩:০৫" (bn): the order comes from the words (period before or after). */
export function formatTime(hour: number, minute: number, words: DateWords, digits: DigitStyle = 'ascii', periodFirst = false): string {
  if (!words.hour12) return applyDigits(`${pad2(hour)}:${pad2(minute)}`, digits);
  const h12 = hour % 12 === 0 ? 12 : hour % 12;
  const clock = applyDigits(`${h12}:${pad2(minute)}`, digits);
  const period = dayPeriod(hour, words);
  return periodFirst ? `${period} ${clock}` : `${clock} ${period}`;
}

/** An instant shown in the institution's time zone: "11 Nov 2026, 12:30 AM". */
export function formatDateTime(
  instant: number | string, timeZone: string, words: DateWords,
  options: { digits?: DigitStyle; style?: DateStyle; periodFirst?: boolean } = {},
): string {
  const epoch = typeof instant === 'number' ? instant : Date.parse(instant);
  if (!Number.isFinite(epoch)) return '';
  const p = zonedParts(epoch, timeZone);
  const date = formatDate(`${p.year}-${pad2(p.month)}-${pad2(p.day)}`, words, options.digits, options.style ?? 'short');
  return `${date}, ${formatTime(p.hour, p.minute, words, options.digits, options.periodFirst)}`;
}

// ---------------------------------------------------------------------------------------------------------------------
// Calendars
// ---------------------------------------------------------------------------------------------------------------------

/** Weekday indexes (0 = Sunday) in display order, starting with the institution's week start. */
export function weekdayOrder(weekStart: Weekday): number[] {
  const start = WEEKDAYS.indexOf(weekStart);
  return Array.from({ length: 7 }, (_, i) => (start + i) % 7);
}

/** Month grid: weeks of 'YYYY-MM-DD' (null = blank cell), starting on the institution's week start. */
export function monthGrid(year: number, month: number, weekStart: Weekday): (string | null)[][] {
  const first = weekdayOfDate({ year, month, day: 1 });
  const lead = (first - WEEKDAYS.indexOf(weekStart) + 7) % 7;
  const daysInMonth = new Date(Date.UTC(year, month, 0)).getUTCDate();
  const cells: (string | null)[] = Array.from({ length: lead }, () => null);
  for (let day = 1; day <= daysInMonth; day += 1) cells.push(`${year}-${pad2(month)}-${pad2(day)}`);
  while (cells.length % 7 !== 0) cells.push(null);
  const weeks: (string | null)[][] = [];
  for (let i = 0; i < cells.length; i += 7) weeks.push(cells.slice(i, i + 7));
  return weeks;
}
