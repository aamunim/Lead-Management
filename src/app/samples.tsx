import { Link } from 'expo-router';
import { useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Switch, View } from 'react-native';

import { AppText } from '@/components/AppText';
import { AmountInput, PhoneInput } from '@/components/fields/inputs';
import { DateField, DateTimeField } from '@/components/fields/pickers';
import { useColors } from '@/components/theme';
import { useTranslation } from '@/i18n';
import { localDateOf, WEEKDAYS, type Weekday } from '@/lib/format';
import { useLanguageState } from '@/lib/language';
import { useFormat } from '@/lib/locale';
import { serverNow } from '@/lib/server-time';

// Formatting samples (0A.11 owner checkpoint): money, numbers, dates and inputs in the current language with the
// institution's locale settings, plus the list of locale settings in force. Every word comes from translations.
const SAMPLE_INSTANT = '2026-11-10T18:30:00Z'; // just after midnight in Dhaka: shows the local date is right
const SAMPLE_DATE = '2026-11-11';
const SAMPLE_AMOUNTS = ['100000', '1234567.5', '2500'];
const SAMPLE_NUMBERS = ['100000', '12345678'];

export default function SamplesScreen() {
  const { t } = useTranslation('locale');
  const { t: tLanguage } = useTranslation('language');
  const { t: tCommon } = useTranslation();
  const colors = useColors();
  const { language } = useLanguageState();
  const [banglaPreview, setBanglaPreview] = useState(false);
  const format = useFormat('ui', language === 'bn' && banglaPreview ? 'bangla' : undefined);
  const [phone, setPhone] = useState<string | null>(null);
  const [amount, setAmount] = useState<string | null>(null);
  const [date, setDate] = useState<string | null>(SAMPLE_DATE);
  const [instant, setInstant] = useState<string | null>(null);

  const locale = format.locale;
  const weekday = (key: Weekday) => format.words.weekdays[WEEKDAYS.indexOf(key)];
  const hhmm = (value: string) => format.time(Number(value.slice(0, 2)), Number(value.slice(3, 5)));
  const today = locale ? localDateOf(serverNow(), locale.time_zone) : null;

  const settingsRows: [string, string][] = locale ? [
    [t('settings.time_zone'), locale.time_zone],
    [t('settings.currency'), `${locale.currency.symbol} (${locale.currency.code})`],
    [t('settings.phone'), t('phoneExample', { code: format.digitsText(locale.phone.country_code), example: format.digitsText(locale.phone.example) })],
    [t('settings.week_start'), weekday(locale.week_start)],
    [t('settings.working_days'), locale.working_days.map(weekday).join(', ')],
    [t('settings.working_hours'), t('range', { start: hhmm(locale.working_hours.start), end: hhmm(locale.working_hours.end) })],
    [t('settings.quiet_hours'), t('range', { start: hhmm(locale.quiet_hours.start), end: hhmm(locale.quiet_hours.end) })],
    [t('settings.scorecard_day'), weekday(locale.scorecard_day)],
    [t('settings.default_language'), tLanguage(`names.${locale.default_language}`)],
    [t('settings.bangla_digits'), (['ui', 'receipts', 'public_pages'] as const).filter((k) => locale.bangla_digits[k])
      .map((k) => t(`digitPlaces.${k}`)).join(', ') || t('digitPlaces.none')],
    [t('settings.payment_methods'), locale.payment_methods.filter((m) => m.enabled)
      .map((m) => t(`paymentMethods.${m.key}` as 'paymentMethods.cash', { defaultValue: m.key })).join(', ')],
    [t('settings.address_placeholder'), locale.address_placeholder[language] ?? ''],
  ] : [];

  return (
    <ScrollView contentContainerStyle={styles.container} style={{ backgroundColor: colors.background }}>
      <AppText variant="headline" accessibilityRole="header" testID="samples-title">{t('title')}</AppText>
      <AppText style={{ color: colors.muted }}>{t('intro')}</AppText>
      <View style={styles.row}>
        <Link href="/language" testID="samples-language"><AppText style={styles.link}>{tCommon('home.openLanguage')}</AppText></Link>
        {language === 'bn' ? (
          <Pressable accessibilityRole="switch" accessibilityState={{ checked: banglaPreview }} style={styles.toggle} onPress={() => setBanglaPreview(!banglaPreview)} testID="samples-bangla-digits">
            <Switch value={banglaPreview} onValueChange={setBanglaPreview} />
            <AppText>{t('banglaDigits.preview')}</AppText>
          </Pressable>
        ) : null}
      </View>

      <Section title={t('sections.money')}>
        {SAMPLE_AMOUNTS.map((value) => <Sample key={value} testID={`money-${value}`} text={format.money(value)} />)}
      </Section>
      <Section title={t('sections.numbers')}>
        {SAMPLE_NUMBERS.map((value) => <Sample key={value} testID={`number-${value}`} text={format.number(value)} />)}
      </Section>
      <Section title={t('sections.dates')}>
        {today ? <Sample label={t('samples.today')} testID="date-today" text={format.date(today)} /> : null}
        <Sample label={t('samples.now')} testID="date-now" text={format.dateTime(serverNow())} />
        <Sample label={t('samples.nearMidnight')} testID="date-midnight" text={format.dateTime(SAMPLE_INSTANT)} />
        <Sample label={t('samples.birthday')} testID="date-only" text={`${format.date(SAMPLE_DATE)} · ${format.date(SAMPLE_DATE, 'short')}`} />
      </Section>
      <Section title={t('sections.inputs')}>
        <PhoneInput label={t('fields.phone')} value={phone} onChange={setPhone} help={t('fields.phoneHelp')}
          errorText={t('fields.invalidPhone')} testID="input-phone" />
        <Stored value={phone} testID="input-phone-stored" />
        <AmountInput label={t('fields.amount')} value={amount} onChange={setAmount} errorText={t('fields.invalidNumber')} testID="input-amount" />
        <Stored value={amount} testID="input-amount-stored" />
        <DateField label={t('fields.date')} value={date} onChange={setDate} testID="input-date" />
        <Stored value={date} testID="input-date-stored" />
        <DateTimeField label={t('fields.dateTime')} value={instant} onChange={setInstant} testID="input-datetime" />
        <Stored value={instant} testID="input-datetime-stored" />
      </Section>
      <Section title={t('sections.settings')}>
        {settingsRows.map(([label, value]) => <Sample key={label} label={label} text={value} />)}
      </Section>
    </ScrollView>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  const colors = useColors();
  return (
    <View style={[styles.section, { borderColor: colors.border }]}>
      <AppText variant="titleSmall">{title}</AppText>
      {children}
    </View>
  );
}

function Sample({ label, text, testID }: { label?: string; text: string; testID?: string }) {
  const colors = useColors();
  return (
    <View style={styles.sample}>
      {label ? <AppText variant="caption" style={{ color: colors.muted }}>{label}</AppText> : null}
      <AppText testID={testID}>{text}</AppText>
    </View>
  );
}

function Stored({ value, testID }: { value: string | null; testID: string }) {
  const { t } = useTranslation('locale');
  const colors = useColors();
  if (!value) return null;
  // The stored value is shown as it is saved: ASCII digits (never converted for display).
  return <AppText variant="caption" style={{ color: colors.muted }} testID={testID}>{t('fields.stored', { value })}</AppText>;
}

const styles = StyleSheet.create({
  container: { padding: 16, gap: 16, maxWidth: 640, width: '100%', alignSelf: 'center' },
  row: { flexDirection: 'row', alignItems: 'center', flexWrap: 'wrap', gap: 12 },
  link: { textDecorationLine: 'underline', paddingVertical: 12 },
  toggle: { flexDirection: 'row', alignItems: 'center', gap: 8, minHeight: 48 },
  section: { borderTopWidth: 1, paddingTop: 12, gap: 10 },
  sample: { gap: 2 },
});
