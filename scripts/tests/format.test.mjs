// Unit tests for 0A.11 formatting (src/lib/format.ts): lakh grouping, money, digits, phones, time zones, calendars.
import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import bnFormat from '../../src/i18n/locales/bn/format.json' with { type: 'json' };
import enFormat from '../../src/i18n/locales/en/format.json' with { type: 'json' };
import {
  addDays, cleanNumberTyping, cleanPhoneTyping, formatDate, formatDateTime, formatMoney, formatNumber, formatTime,
  groupLakh, isValidPhone, localDateOf, monthGrid, normalizePhone, parseNumberInput, toAsciiDigits, toBanglaDigits,
  weekdayOrder, zonedParts, zonedToEpoch,
} from '../../src/lib/format.ts';

const BDT = { code: 'BDT', symbol: '৳', decimals: 0, symbol_position: 'before' };
const BD_PHONE = { country_code: '880', national_prefix: '0', national_pattern: '^01[3-9][0-9]{8}$', example: '01711223344' };
const words = (f) => ({ ...f.words, hour12: f.grammar.hour12, dayPeriods: f.grammar.dayPeriods });
const EN = words(enFormat);
const BN = words(bnFormat);

describe('lakh grouping and numbers', () => {
  it('100000 → 1,00,000 and ১,০০,০০০ (never 100,000)', () => {
    assert.equal(formatNumber(100000), '1,00,000');
    assert.equal(formatNumber(100000, { digits: 'bangla' }), '১,০০,০০০');
  });
  it('groups crores and small numbers correctly', () => {
    assert.equal(groupLakh('1234567'), '12,34,567');
    assert.equal(groupLakh('123456789'), '12,34,56,789');
    assert.equal(formatNumber(999), '999');
    assert.equal(formatNumber(1000), '1,000');
    assert.equal(formatNumber(-1500000), '-15,00,000');
  });
  it('rounds exactly, without floating point errors', () => {
    assert.equal(formatNumber('1.005', { decimals: 2 }), '1.01');
    assert.equal(formatNumber('99999.995', { decimals: 2 }), '1,00,000.00');
    assert.equal(formatNumber('0.1', { decimals: 0 }), '0');
    assert.equal(formatNumber('-0.4', { decimals: 0 }), '0');
  });
  it('money uses the currency setting (symbol, position, decimals)', () => {
    assert.equal(formatMoney(150000, BDT), '৳1,50,000');
    assert.equal(formatMoney(150000, BDT, 'bangla'), '৳১,৫০,০০০');
    assert.equal(formatMoney('-2500.5', { ...BDT, decimals: 2, symbol_position: 'after' }), '-2,500.50 ৳');
    assert.equal(formatMoney(1234.5, { code: 'USD', symbol: '$', decimals: 2, symbol_position: 'before' }), '$1,234.50');
  });
  it('bad input gives an empty string, never "NaN"', () => {
    assert.equal(formatNumber('abc'), '');
    assert.equal(formatMoney(Number.NaN, BDT), '');
  });
});

describe('digits and number input', () => {
  it('converts Bangla (and Arabic-Indic) digits both ways', () => {
    assert.equal(toAsciiDigits('০১২৩৪৫৬৭৮৯ ٣'), '0123456789 3');
    assert.equal(toBanglaDigits('2026-11-10'), '২০২৬-১১-১০');
  });
  it('parses typed amounts like the server', () => {
    assert.equal(parseNumberInput('১,০০,০০০'), '100000');
    assert.equal(parseNumberInput('৳ 1,50,000.50'), '150000.50');
    assert.equal(parseNumberInput('0042'), '42');
    assert.equal(parseNumberInput('১২ক'), null);
    assert.equal(parseNumberInput(''), null);
  });
  it('cleans while typing: Bangla digits become ASCII at once', () => {
    assert.equal(cleanNumberTyping('১২৩.৪.৫'), '123.45');
    assert.equal(cleanNumberTyping('১২৩.৪', false), '1234');
    assert.equal(cleanNumberTyping('5-5'), '55');
  });
});

describe('phones', () => {
  it('normalize ০১৭১১-২২৩৩৪৪ → 01711223344', () => {
    assert.equal(normalizePhone('০১৭১১-২২৩৩৪৪', BD_PHONE), '01711223344');
  });
  it('normalises +880 / 00880 / 880 forms', () => {
    for (const raw of ['+8801711223344', '+880 1711-223344', '008801711223344', '8801711223344', '+৮৮০১৭১১২২৩৩৪৪', '+880 (0)1711 223344']) {
      assert.equal(normalizePhone(raw, BD_PHONE), '01711223344', raw);
    }
  });
  it('keeps foreign numbers international and empty input null', () => {
    assert.equal(normalizePhone('+44 20 7946 0958', BD_PHONE), '+442079460958');
    assert.equal(normalizePhone('  ', BD_PHONE), null);
  });
  it('validates with the institution pattern', () => {
    assert.equal(isValidPhone('01711223344', BD_PHONE), true);
    assert.equal(isValidPhone('01211223344', BD_PHONE), false);
    assert.equal(isValidPhone('+442079460958', BD_PHONE), true);
  });
  it('typing a phone in Bangla gives ASCII at once', () => {
    assert.equal(cleanPhoneTyping('০১৭১১-২২৩'), '01711-223');
  });
});

describe('time zones (Asia/Dhaka and near midnight)', () => {
  const TZ = 'Asia/Dhaka';
  it('18:30 UTC lands on the next local date in Dhaka', () => {
    assert.equal(localDateOf(Date.parse('2026-11-10T18:30:00Z'), TZ), '2026-11-11');
    assert.equal(localDateOf(Date.parse('2026-11-10T17:59:59Z'), TZ), '2026-11-10');
  });
  it('local wall-clock parts and back again', () => {
    const p = zonedParts(Date.parse('2026-11-10T18:30:00Z'), TZ);
    assert.deepEqual([p.year, p.month, p.day, p.hour, p.minute, p.weekday], [2026, 11, 11, 0, 30, 3]);
    assert.equal(new Date(zonedToEpoch({ year: 2026, month: 11, day: 11, hour: 10, minute: 0 }, TZ)).toISOString(), '2026-11-11T04:00:00.000Z');
  });
  it('handles daylight saving time in other zones', () => {
    assert.equal(new Date(zonedToEpoch({ year: 2026, month: 7, day: 1, hour: 10 }, 'Europe/London')).toISOString(), '2026-07-01T09:00:00.000Z');
    assert.equal(new Date(zonedToEpoch({ year: 2026, month: 1, day: 1, hour: 10 }, 'Europe/London')).toISOString(), '2026-01-01T10:00:00.000Z');
  });
  it('a date-only value is never shifted by a time zone', () => {
    assert.equal(formatDate('2026-11-11', EN), '11 November 2026');
    assert.equal(addDays('2026-12-31', 1), '2027-01-01');
    assert.equal(formatDate('2026-02-30', EN), '');
  });
});

describe('dates and times in both languages', () => {
  it('formats dates in English and Bangla', () => {
    assert.equal(formatDate('2026-11-11', EN, 'ascii', 'short'), '11 Nov 2026');
    assert.equal(formatDate('2026-11-11', BN, 'bangla'), '১১ নভেম্বর ২০২৬');
    assert.equal(formatDate('2026-11-11', BN, 'ascii'), '11 নভেম্বর 2026');
  });
  it('formats times with AM/PM in English and day periods in Bangla', () => {
    assert.equal(formatTime(15, 5, EN, 'ascii', enFormat.grammar.periodFirst), '3:05 PM');
    assert.equal(formatTime(0, 30, EN, 'ascii', enFormat.grammar.periodFirst), '12:30 AM');
    assert.equal(formatTime(15, 5, BN, 'bangla', bnFormat.grammar.periodFirst), 'বিকাল ৩:০৫');
    assert.equal(formatTime(5, 0, BN, 'ascii', bnFormat.grammar.periodFirst), 'ভোর 5:00');
    assert.equal(formatTime(21, 0, BN, 'ascii', bnFormat.grammar.periodFirst), 'রাত 9:00');
  });
  it('an instant near midnight is shown on the Dhaka date', () => {
    assert.equal(formatDateTime('2026-11-10T18:30:00Z', 'Asia/Dhaka', EN, { periodFirst: enFormat.grammar.periodFirst }), '11 Nov 2026, 12:30 AM');
    assert.equal(formatDateTime('2026-11-10T18:30:00Z', 'Asia/Dhaka', BN, { digits: 'bangla', periodFirst: bnFormat.grammar.periodFirst }), '১১ নভে ২০২৬, রাত ১২:৩০');
  });
});

describe('calendars', () => {
  it('weeks start on the institution\'s week start', () => {
    assert.deepEqual(weekdayOrder('saturday'), [6, 0, 1, 2, 3, 4, 5]);
    assert.deepEqual(weekdayOrder('sunday'), [0, 1, 2, 3, 4, 5, 6]);
  });
  it('builds a month grid (November 2026 starts on a Sunday)', () => {
    const grid = monthGrid(2026, 11, 'saturday');
    assert.deepEqual(grid[0], [null, '2026-11-01', '2026-11-02', '2026-11-03', '2026-11-04', '2026-11-05', '2026-11-06']);
    assert.equal(grid.flat().filter(Boolean).length, 30);
    assert.ok(grid.every((week) => week.length === 7));
  });
});
