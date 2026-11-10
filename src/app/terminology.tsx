import { Link } from 'expo-router';
import { useMemo, useState } from 'react';
import { ScrollView, StyleSheet, TextInput, View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useColors } from '@/components/theme';
import { useTranslation } from '@/i18n';
import { fontFamilyFor } from '@/i18n/language';
import labelMeta from '@/i18n/label-meta.json';
import { bundledLabels } from '@/i18n/resources';
import { searchLabels, toSearchable } from '@/lib/label-search';
import { label, useLabelEntries, type LabelEntry, type LabelForm } from '@/lib/labels';
import { useLanguageState } from '@/lib/language';
import { useFormat } from '@/lib/locale';

// Words used in this app (0A.12): the label dictionary in force, grouped, with the default underneath, a search that
// also finds default and old words, and sample sentences. Read-only here; renaming is Settings → Terminology (0B),
// through label_set. This is the screen of the owner checkpoint (review the default words).
const GROUPS = ['people', 'offering', 'conversion', 'money', 'roles', 'modules', 'documents'] as const;

/** Bundled defaults shaped like labels_get() entries, for use before sign-in. */
function bundledEntries(): Record<string, LabelEntry> {
  const out: Record<string, LabelEntry> = {};
  const walk = (en: Record<string, unknown>, bn: Record<string, unknown>, prefix: string) => {
    for (const [k, v] of Object.entries(en)) {
      const key = prefix ? `${prefix}.${k}` : k;
      const node = v as Record<string, unknown>;
      if (typeof node.singular === 'string') {
        const b = bn[k] as Record<string, string>;
        const value = { en_singular: node.singular as string, en_plural: node.plural as string,
          bn_forms: { base: b.singular, plural: b.plural, possessive: b.possessive, objective: b.objective, plural_oblique: b.plural_oblique } };
        const m = (labelMeta as Record<string, { group: string; animate: boolean; max_length: number; lockable: boolean; legacy_key: string | null }>)[key];
        out[key] = { group: m?.group ?? '', animate: m?.animate ?? false, max_length: m?.max_length ?? 0, lockable: m?.lockable ?? false,
          legacy_key: m?.legacy_key ?? null,
          resolved: { ...value, source: 'pack', locked: false }, default: value, product: null };
      } else {
        walk(node, bn[k] as Record<string, unknown>, key);
      }
    }
  };
  walk(bundledLabels.en as unknown as Record<string, unknown>, bundledLabels.bn as unknown as Record<string, unknown>, '');
  return out;
}

export default function TerminologyScreen() {
  const { t } = useTranslation('terminology');
  const { t: tCommon } = useTranslation();
  const colors = useColors();
  const format = useFormat();
  const { language } = useLanguageState();
  const { entries: loaded } = useLabelEntries();
  const [query, setQuery] = useState('');
  const entries = useMemo(() => loaded ?? bundledEntries(), [loaded]);
  const keys = useMemo(() => searchLabels(query, toSearchable(entries)), [query, entries]);
  const fontFamily = fontFamilyFor(language);
  const forms: LabelForm[] = language === 'bn' ? ['singular', 'plural', 'possessive', 'objective', 'plural_oblique'] : ['singular', 'plural'];

  const show = (key: string) => {
    const e = entries[key];
    const d = e.default;
    const defaultText = d ? (language === 'bn' ? d.bn_forms.base : `${d.en_singular} / ${d.en_plural}`) : '';
    const renamed = e.resolved.source === 'institution' || e.resolved.source === 'derived';
    return (
      <View key={key} style={[styles.row, { borderColor: colors.border }]} testID={`label-${key}`}>
        <AppText style={styles.word} testID={`label-${key}-word`}>
          {forms.map((f) => label(key, f)).filter((w, i, all) => all.indexOf(w) === i).join(' · ')}
        </AppText>
        <AppText style={[styles.meta, { color: colors.muted }]}>
          {[t('key', { value: key }), renamed ? t('default', { value: defaultText }) : null,
            renamed ? t('renamed') : null, e.resolved.locked ? t('locked') : null].filter(Boolean).join('  ·  ')}
        </AppText>
      </View>
    );
  };

  return (
    <ScrollView contentContainerStyle={styles.container} style={{ backgroundColor: colors.background }}>
      <AppText style={styles.title} accessibilityRole="header" testID="terminology-title">{t('title')}</AppText>
      <AppText style={{ color: colors.muted }}>{t('intro')}</AppText>
      <Link href="/language"><AppText style={styles.link}>{tCommon('home.openLanguage')}</AppText></Link>

      <View style={[styles.samples, { borderColor: colors.border }]} testID="terminology-samples">
        <AppText style={styles.groupTitle}>{t('samples.title')}</AppText>
        <AppText testID="sample-count">{t('samples.count', { n: format.number(25) })}</AppText>
        <AppText testID="sample-add">{t('samples.add')}</AppText>
        <AppText testID="sample-contact">{t('samples.contact')}</AppText>
        <AppText testID="sample-list">{t('samples.list')}</AppText>
        <AppText testID="sample-receipt">{t('samples.receipt')}</AppText>
      </View>

      <TextInput
        style={[styles.search, { color: colors.text, borderColor: colors.border, backgroundColor: colors.surface }, fontFamily ? { fontFamily } : null]}
        placeholder={t('search')}
        placeholderTextColor={colors.muted}
        value={query}
        onChangeText={setQuery}
        autoCapitalize="none"
        testID="terminology-search"
      />
      {keys.length === 0 ? <AppText testID="terminology-empty">{t('noResults')}</AppText> : null}
      {GROUPS.map((group) => {
        const inGroup = keys.filter((key) => entries[key].group === group);
        if (inGroup.length === 0) return null;
        return (
          <View key={group} style={styles.group}>
            <AppText style={styles.groupTitle}>{t(`groups.${group}`)}</AppText>
            {inGroup.map(show)}
          </View>
        );
      })}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { padding: 16, gap: 12, maxWidth: 720, width: '100%', alignSelf: 'center' },
  title: { fontSize: 22, fontWeight: '600' },
  link: { textDecorationLine: 'underline', paddingVertical: 8 },
  samples: { borderWidth: 1, borderRadius: 8, padding: 12, gap: 6 },
  search: { minHeight: 48, borderWidth: 1, borderRadius: 8, paddingHorizontal: 12, fontSize: 16 },
  group: { gap: 6, marginTop: 8 },
  groupTitle: { fontSize: 17, fontWeight: '600' },
  row: { borderTopWidth: 1, paddingVertical: 8, gap: 2 },
  word: { fontSize: 16 },
  meta: { fontSize: 13 },
});
