// Unit tests for 0A.10: language resolution, the translation completeness check and the hard-coded UI string lint.
import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { ERRORS } from '../../supabase/functions/_shared/errors.ts';
import { fontFamilyFor, isLanguage, resolveLanguage } from '../../src/i18n/language.ts';
import { checkErrorContract, compareLocales, readLocales } from '../check-translations.mjs';
import { checkSource } from '../check-ui-strings.mjs';

const rules = (source, file = 'src/app/x.tsx') => checkSource(file, source).map((f) => f.rule);

describe('language resolution (user → institution → English)', () => {
  it('uses the person\'s choice first', () => {
    assert.equal(resolveLanguage({ choice: 'bn', institutionDefault: 'en' }), 'bn');
  });
  it('falls back to the institution default, then English', () => {
    assert.equal(resolveLanguage({ choice: null, institutionDefault: 'bn' }), 'bn');
    assert.equal(resolveLanguage({}), 'en');
  });
  it('ignores unsupported values', () => {
    assert.equal(resolveLanguage({ choice: 'fr', institutionDefault: 'xx' }), 'en');
    assert.equal(isLanguage('BN'), false);
  });
  it('Bangla gets the Bangla font', () => {
    assert.equal(fontFamilyFor('bn'), 'NotoSansBengali');
    assert.equal(fontFamilyFor('en'), undefined);
  });
});

describe('translation completeness check', () => {
  const good = { en: { common: { a: 'Hi {{name}}', b: { c: 'Save' } } }, bn: { common: { a: 'হ্যালো {{name}}', b: { c: 'সংরক্ষণ' } } } };
  it('passes when both languages have every key', () => {
    assert.deepEqual(compareLocales(good), []);
  });
  it('fails on a key present only in en', () => {
    const locales = structuredClone(good);
    locales.en.common.only_en = 'Only English';
    assert.match(compareLocales(locales).join('\n'), /\[missing_key\] bn\/common: "only_en"/);
  });
  it('fails on a namespace that exists in one language only', () => {
    const locales = structuredClone(good);
    locales.bn.reports = { title: 'রিপোর্ট' };
    assert.match(compareLocales(locales).join('\n'), /\[missing_namespace\] en\/reports\.json/);
  });
  it('fails on empty values and different placeholders', () => {
    const locales = structuredClone(good);
    locales.bn.common.b.c = ' ';
    locales.bn.common.a = 'হ্যালো {{person}}';
    const out = compareLocales(locales).join('\n');
    assert.match(out, /\[empty\] bn\/common: "b\.c"/);
    assert.match(out, /\[placeholders\] common: "a"/);
  });
  it('fails on renamable terms in translations (they come from labels)', () => {
    const locales = structuredClone(good);
    locales.en.common.b.c = 'Add student';
    locales.bn.common.b.c = 'শিক্ষার্থী যোগ করুন';
    const out = compareLocales(locales).join('\n');
    assert.match(out, /\[renamable_term\] en\/common/);
    assert.match(out, /\[renamable_term\] bn\/common/);
  });
  it('fails when an error message key of the contract is not translated', () => {
    const out = checkErrorContract({ en: { errors: { unknown: 'x', actions: { retry: 'y' } } } }, ERRORS).join('\n');
    assert.match(out, /"not_signed_in" \(code not_signed_in\)/);
    assert.match(out, /"actions\.sign_in"/);
  });
  it('the real locale files are complete and cover the error contract', () => {
    const locales = readLocales();
    assert.deepEqual([...compareLocales(locales), ...checkErrorContract(locales, ERRORS)], []);
  });
});

describe('hard-coded UI string lint', () => {
  it('accepts translated text', () => {
    assert.deepEqual(rules(`export const A = () => <Text title={t('x')}>{t('home.subtitle')}{name}{' '}{count}</Text>;`), []);
  });
  it('blocks JSX text', () => {
    assert.deepEqual(rules('export const A = () => <Text>Save</Text>;'), ['jsx_text']);
    assert.deepEqual(rules('export const A = () => <Text>সংরক্ষণ</Text>;'), ['jsx_text']);
  });
  it('allows JSX text without letters (punctuation, numbers)', () => {
    assert.deepEqual(rules('export const A = () => <Text>{a} · 3</Text>;'), []);
  });
  it('blocks literals and templates in JSX children', () => {
    assert.deepEqual(rules(`export const A = () => <Text>{'Save'}</Text>;`), ['jsx_literal']);
    assert.deepEqual(rules('export const A = () => <Text>{`Hello ${name}`}</Text>;'), ['jsx_literal']);
    assert.deepEqual(rules(`export const A = () => <Text>{ok ? 'Yes' : t('no')}</Text>;`), ['jsx_literal']);
  });
  it('blocks literals in visible props', () => {
    assert.deepEqual(rules('export const A = () => <Button title="Save" />;'), ['visible_prop']);
    assert.deepEqual(rules(`export const A = () => <TextInput placeholder={'Name'} />;`), ['visible_prop']);
    assert.deepEqual(rules('export const A = () => <Pressable accessibilityLabel="Close" />;'), ['visible_prop']);
  });
  it('allows non-visible props such as testID and style values', () => {
    assert.deepEqual(rules('export const A = () => <View testID="home-root" pointerEvents="none" />;'), []);
  });
  it('blocks navigation titles and alerts', () => {
    assert.deepEqual(rules(`export const A = () => <Stack.Screen options={{ title: 'Leads' }} />;`), ['visible_option']);
    assert.deepEqual(rules(`Alert.alert('Deleted', t('x'));`, 'src/lib/x.ts'), ['alert_literal']);
  });
  it('blocks renamable terms anywhere in code', () => {
    assert.deepEqual(rules(`const key = 'Student';`, 'src/lib/x.ts'), ['renamable_term']);
    assert.deepEqual(rules(`const key = 'নতুন শিক্ষার্থী';`, 'src/lib/x.ts'), ['renamable_term']);
  });
  it('blocks toLocaleString and Intl outside the format library (0A.11)', () => {
    assert.deepEqual(rules('const s = amount.toLocaleString();', 'src/lib/x.ts'), ['raw_locale_format']);
    assert.deepEqual(rules('const f = new Intl.NumberFormat("en-IN");', 'src/lib/x.ts'), ['raw_locale_format']);
    assert.deepEqual(rules('const f = new Intl.DateTimeFormat("en-US");', 'src/lib/format.ts'), []);
  });
  it('blocks the phone clock outside server-time (0A.11)', () => {
    assert.deepEqual(rules('const now = Date.now();', 'src/lib/x.ts'), ['phone_clock']);
    assert.deepEqual(rules('const now = new Date();', 'src/lib/x.ts'), ['phone_clock']);
    assert.deepEqual(rules('const d = new Date(value);', 'src/lib/x.ts'), []);
    assert.deepEqual(rules('const now = Date.now();', 'src/lib/server-time.ts'), []);
  });
  it('honours a reasoned exemption on the line, or for a developer-only file', () => {
    assert.deepEqual(rules('// i18n-exempt: brand name, never translated\nexport const A = () => <Text>Leadora</Text>;'), []);
    assert.deepEqual(rules('// i18n-exempt-file: developer tool\nexport const A = () => <Text>Sign in</Text>;'), []);
    assert.deepEqual(rules('// i18n-exempt:\nexport const A = () => <Text>Sign in</Text>;'), ['jsx_text']);
  });
});
