import AsyncStorage from '@react-native-async-storage/async-storage';
import { useMemo, useSyncExternalStore } from 'react';

import { useTranslation } from '@/i18n';
import type { Language } from '@/i18n/language';

import {
  applyDigits, formatDate, formatDateTime, formatMoney, formatNumber, formatTime, type Currency, type DateStyle, type DateWords,
  type DigitStyle, type PhoneRules, type Weekday,
} from './format';
import { useLanguageState } from './language';
import { onServerTime, serverClockInfo, syncServerTime } from './server-time';
import { useSetting } from './settings';
import { supabase } from './supabase';

// Locale of the active institution (0A.11): settings values (signed in) on top of the product defaults
// (locale_defaults(), cached on the device). No locale value is written in app code.

export type LocaleSettings = {
  time_zone: string;
  currency: Currency;
  phone: PhoneRules;
  week_start: Weekday;
  working_days: Weekday[];
  working_hours: { start: string; end: string };
  quiet_hours: { start: string; end: string };
  scorecard_day: Weekday;
  default_language: Language;
  bangla_digits: { ui: boolean; receipts: boolean; public_pages: boolean };
  payment_methods: { key: string; enabled: boolean }[];
  address_placeholder: Record<string, string>;
};
export const LOCALE_KEYS: (keyof LocaleSettings)[] = [
  'time_zone', 'currency', 'phone', 'week_start', 'working_days', 'working_hours', 'quiet_hours', 'scorecard_day',
  'default_language', 'bangla_digits', 'payment_methods', 'address_placeholder',
];

const CACHE_KEY = 'locale_defaults';
let defaults: Partial<LocaleSettings> = {};
let defaultsVersion = 0;
const subscribers = new Set<() => void>();

function publishDefaults(next: Partial<LocaleSettings>) {
  defaults = next;
  defaultsVersion += 1;
  for (const notify of subscribers) notify();
}

/** Loads the product defaults (cached copy first). Call once at start-up. */
export async function initLocale(): Promise<void> {
  try {
    const cached = await AsyncStorage.getItem(CACHE_KEY);
    if (cached) publishDefaults(JSON.parse(cached) as Partial<LocaleSettings>);
  } catch {
    // cache is a convenience only
  }
  const { data, error } = await supabase.rpc('locale_defaults');
  if (!error && data) {
    publishDefaults(data as Partial<LocaleSettings>);
    try {
      await AsyncStorage.setItem(CACHE_KEY, JSON.stringify(data));
    } catch {
      // ignore
    }
  }
  await syncServerTime().catch(() => undefined);
}

onServerTime(() => {
  defaultsVersion += 1;
  for (const notify of subscribers) notify();
});

const subscribe = (notify: () => void) => {
  subscribers.add(notify);
  return () => subscribers.delete(notify);
};

/** The locale settings in force (null while nothing is known yet: first start without network). */
export function useLocaleSettings(): LocaleSettings | null {
  useSyncExternalStore(subscribe, () => defaultsVersion);
  const values: Partial<LocaleSettings> = {};
  // A fixed list of keys, read in the same order on every render (rules of hooks hold).
  for (const key of LOCALE_KEYS) (values as Record<string, unknown>)[key] = useSetting(key, defaults[key]);
  const timeZone = serverClockInfo().timeZone;
  if (timeZone && !values.time_zone) values.time_zone = timeZone;
  const complete = LOCALE_KEYS.every((key) => values[key] !== undefined);
  const signature = complete ? JSON.stringify(values) : '';
  // Same values → same object, so formatters built from it are reused.
  return useMemo(() => (signature ? (JSON.parse(signature) as LocaleSettings) : null), [signature]);
}

export type Formatters = {
  ready: boolean;
  digits: DigitStyle;
  locale: LocaleSettings | null;
  money: (amount: number | string) => string;
  number: (value: number | string, decimals?: number) => string;
  /** Digits only, no grouping (years, minutes, codes): "2026" → "২০২৬" when Bangla digits are on. */
  digitsText: (text: string | number) => string;
  date: (value: string, style?: DateStyle) => string;
  time: (hour: number, minute: number) => string;
  dateTime: (instant: number | string, style?: DateStyle) => string;
  words: DateWords;
};

/**
 * Formatters bound to the current language and institution settings. `digitsFor` picks where the text is shown
 * (app UI, receipt or public page): Bangla digits only when the language is Bangla and that place is switched on.
 */
export function useFormat(place: 'ui' | 'receipts' | 'public_pages' = 'ui', digitsOverride?: DigitStyle): Formatters {
  const { language } = useLanguageState();
  const { t } = useTranslation('format');
  const locale = useLocaleSettings();
  return useMemo(() => {
    const grammar = t('grammar', { returnObjects: true }) as unknown as {
      hour12: boolean; periodFirst: boolean; dayPeriods: { from: number; label: string }[];
    };
    const words: DateWords = {
      months: t('words.months', { returnObjects: true }) as unknown as string[],
      monthsShort: t('words.monthsShort', { returnObjects: true }) as unknown as string[],
      weekdays: t('words.weekdays', { returnObjects: true }) as unknown as string[],
      weekdaysShort: t('words.weekdaysShort', { returnObjects: true }) as unknown as string[],
      dayPeriods: grammar.dayPeriods,
      hour12: grammar.hour12,
    };
    const digits: DigitStyle = digitsOverride
      ?? (language === 'bn' && locale?.bangla_digits[place] ? 'bangla' : 'ascii');
    const timeZone = locale?.time_zone ?? 'UTC';
    return {
      ready: locale !== null,
      digits,
      locale,
      words,
      money: (amount) => (locale ? formatMoney(amount, locale.currency, digits) : formatNumber(amount, { digits })),
      number: (value, decimals) => formatNumber(value, { digits, decimals }),
      digitsText: (text) => applyDigits(String(text), digits),
      date: (value, style) => formatDate(value, words, digits, style),
      time: (hour, minute) => formatTime(hour, minute, words, digits, grammar.periodFirst),
      dateTime: (instant, style) => formatDateTime(instant, timeZone, words, { digits, style, periodFirst: grammar.periodFirst }),
    };
  }, [t, language, locale, place, digitsOverride]);
}
