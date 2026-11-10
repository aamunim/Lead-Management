import { createInstance, type Resource, type TFunction } from 'i18next';
import { useMemo, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import i18n, { useTranslation } from '@/i18n';
import type { Language } from '@/i18n/language';
import { useLabelEntries, type LabelValue } from '@/lib/labels';
import { useFormat } from '@/lib/locale';
import { useTheme } from '@/ui/theme';

import { Chips } from './parts';

// Live preview (0A.19-T4, Ch 8.10 #4): a sample list card, a receipt header and a text message written with the
// institution's words — or with a word being edited (draft) — in the UI language or the other one. It uses a private
// copy of the translations, so nothing on the real screens changes until the word is saved.
type Draft = { key: string; value: LabelValue } | null;

function setPath(tree: Record<string, unknown>, key: string, value: unknown) {
  const parts = key.split('.');
  let node = tree;
  for (const part of parts.slice(0, -1)) node = (node[part] ??= {}) as Record<string, unknown>;
  node[parts[parts.length - 1]] = value;
}

function previewT(language: Language, draft: Draft): TFunction {
  const resources: Record<string, Record<string, unknown>> = {};
  for (const lang of ['en', 'bn'] as Language[]) {
    const labels = JSON.parse(JSON.stringify(i18n.getResourceBundle(lang, 'labels') ?? {})) as Record<string, unknown>;
    if (draft) {
      const v = draft.value;
      setPath(labels, draft.key, lang === 'en' ? { singular: v.en_singular, plural: v.en_plural }
        : { singular: v.bn_forms.base, plural: v.bn_forms.plural, possessive: v.bn_forms.possessive,
          objective: v.bn_forms.objective, plural_oblique: v.bn_forms.plural_oblique });
    }
    resources[lang] = { labels, admin: i18n.getResourceBundle(lang, 'admin') };
  }
  const instance = createInstance();
  void instance.init({ resources: resources as Resource, lng: language, fallbackLng: 'en', ns: ['admin', 'labels'], defaultNS: 'admin',
    interpolation: { escapeValue: false }, initAsync: false, returnNull: false });
  return instance.getFixedT(language, 'admin');
}

export function LabelPreview({ draft, institution, testID }: { draft: Draft; institution: string; testID?: string }) {
  const { t, i18n: active } = useTranslation('admin');
  const { t: tLanguage } = useTranslation('language');
  const { entries } = useLabelEntries(); // the institution's words reloaded → the preview follows
  const { colors, radius, space } = useTheme();
  const format = useFormat();
  const [language, setLanguage] = useState<Language>((active.language as Language) === 'bn' ? 'bn' : 'en');
  // eslint-disable-next-line react-hooks/exhaustive-deps -- entries: rebuild when the institution's words reload
  const p = useMemo(() => previewT(language, draft), [language, draft, entries]);
  const tp = p as unknown as (key: string, o?: Record<string, unknown>) => string;
  const card = { gap: space.xs, padding: space.md, borderRadius: radius.md, backgroundColor: colors.surface, borderWidth: 1, borderColor: colors.outlineVariant };
  return (
    <View style={{ gap: space.sm, padding: space.md, borderRadius: radius.lg, backgroundColor: colors.surfaceContainerLow }} testID={testID}>
      <AppText variant="titleSmall" accessibilityRole="header">{t('preview.title')}</AppText>
      <Chips label={t('preview.language')} selected={language} onSelect={setLanguage} choices={[
        { value: 'bn', label: tLanguage('names.bn'), testID: testID ? `${testID}-bn` : undefined },
        { value: 'en', label: tLanguage('names.en'), testID: testID ? `${testID}-en` : undefined },
      ]} />
      <AppText variant="caption" style={{ color: colors.onSurfaceVariant }}>{t('preview.leadCard')}</AppText>
      <View style={card} testID={testID ? `${testID}-card` : undefined}>
        <AppText variant="label">{tp('preview.newLead')}</AppText>
        <AppText>{tp('preview.name')}</AppText>
        <AppText variant="bodySmall">{tp('preview.interest')}</AppText>
        <AppText variant="bodySmall">{tp('preview.assigned')}</AppText>
        <AppText variant="caption" style={{ color: colors.onSurfaceVariant }}>{tp('preview.list')}</AppText>
      </View>
      <AppText variant="caption" style={{ color: colors.onSurfaceVariant }}>{t('preview.receipt')}</AppText>
      <View style={card} testID={testID ? `${testID}-receipt` : undefined}>
        <AppText variant="title">{tp('preview.receiptTitle')}</AppText>
        <AppText variant="bodySmall">{institution}</AppText>
        <AppText variant="bodySmall">{tp('preview.receiptClient')}</AppText>
        <AppText variant="bodySmall">{tp('preview.receiptFee', { amount: format.money(5000) })}</AppText>
      </View>
      <AppText variant="caption" style={{ color: colors.onSurfaceVariant }}>{t('preview.sms')}</AppText>
      <View style={card} testID={testID ? `${testID}-sms` : undefined}>
        <AppText variant="bodySmall">{tp('preview.smsText', { number: format.digitsText('L-1024'), institution })}</AppText>
      </View>
    </View>
  );
}
