import { useEffect, useMemo, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { useErrorText } from '@/i18n/errors';
import { previewBnForms, resetAllLabels, resetLabel, setLabel, type BnFormsValue } from '@/lib/admin';
import { useActiveInstitution } from '@/lib/institution';
import { searchLabels, toSearchable } from '@/lib/label-search';
import { loadLabels, useLabelEntries, type LabelEntry, type LabelValue } from '@/lib/labels';
import { useLanguageState } from '@/lib/language';
import { useFormat } from '@/lib/locale';
import { LabelPreview } from '@/ui/admin/LabelPreview';
import { Badge, Row } from '@/ui/admin/parts';
import { BottomSheet, Button, Screen, Skeleton, TextField, useConfirm, useSnackbar } from '@/ui/components';
import { AppHeader } from '@/ui/shell/AppHeader';
import { useTheme } from '@/ui/theme';

// Settings → Terminology (0A.19-T3..T7, Ch 8.6 / 8.8 / 8.10 #4): every renamable word, grouped as in Ch 8.4, with a
// search that also finds default and old words; rename in English and Bangla with length limits and a live preview
// (list card, receipt header, text message) in either language; reset one word or all; locked words read-only. The
// server enforces limits and locks, audits old / new values and bumps the settings version, so other devices reload.
const GROUPS = ['people', 'offering', 'conversion', 'money', 'roles', 'modules', 'documents'] as const;
const BN_EXTRA = ['plural', 'possessive', 'objective', 'plural_oblique'] as const;

export default function TerminologyEditorScreen() {
  const { t } = useTranslation('admin');
  const { t: tTerms } = useTranslation('terminology');
  const { colors, space } = useTheme();
  const { language } = useLanguageState();
  const confirm = useConfirm();
  const snackbar = useSnackbar();
  const errorText = useErrorText();
  const institution = useActiveInstitution();
  const { entries } = useLabelEntries();
  const [query, setQuery] = useState('');
  const [editing, setEditing] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    void loadLabels();
  }, []);
  const keys = useMemo(() => (entries ? searchLabels(query, toSearchable(entries)) : []), [query, entries]);
  const renamed = entries ? Object.values(entries).some((e) => e.resolved.source === 'institution' && !e.resolved.locked) : false;
  const shown = (v: LabelValue) => (language === 'bn' ? v.bn_forms.base : `${v.en_singular} / ${v.en_plural}`);

  const resetAll = async () => {
    if (!(await confirm({ title: t('terms.resetAllTitle'), message: t('terms.resetAllBody'), confirmLabel: t('terms.resetAll'), danger: true }))) return;
    setBusy(true);
    const r = await resetAllLabels();
    if (!r.error) await loadLabels();
    setBusy(false);
    snackbar.show({ text: r.error ? errorText(r.error).message : t('terms.resetAllDone') });
  };

  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <AppHeader back />
      <Screen title={t('terms.title')} intro={t('terms.intro')} testID="terms">
        <LabelPreview draft={null} institution={institution?.name ?? ''} testID="terms-preview" />
        <Button variant="outlined" icon="restart-alt" label={t('terms.resetAll')} disabled={!renamed} loading={busy}
          onPress={() => void resetAll()} testID="terms-reset-all" />
        <TextField label={t('terms.search')} kind="search" value={query} onChangeText={setQuery} last testID="terms-search" />
        {!entries ? <Skeleton lines={6} testID="terms-loading" /> : keys.length === 0 ? <AppText testID="terms-empty">{t('terms.noResults')}</AppText> : null}
        {entries ? GROUPS.map((group) => {
          const inGroup = keys.filter((key) => entries[key].group === group);
          if (inGroup.length === 0) return null;
          return (
            <View key={group} style={{ gap: space.sm }}>
              <AppText variant="titleSmall" accessibilityRole="header">{tTerms(`groups.${group}`)}</AppText>
              {inGroup.map((key) => {
                const e = entries[key];
                const isRenamed = e.resolved.source === 'institution';
                return (
                  <Row key={key} title={shown(e.resolved)} onPress={() => setEditing(key)} testID={`term-${key}`}
                    subtitle={[t('terms.key', { value: key }), e.default && isRenamed ? t('terms.default', { value: shown(e.default) }) : null].filter(Boolean).join(' · ')}
                    badge={e.resolved.locked ? <Badge label={t('terms.locked')} icon="lock" />
                      : isRenamed ? <Badge label={t('terms.renamed')} tone="primary" /> : undefined} />
                );
              })}
            </View>
          );
        }) : null}
      </Screen>
      {editing && entries?.[editing] ? (
        <TermSheet termKey={editing} entry={entries[editing]} institution={institution?.name ?? ''} onClose={() => setEditing(null)} />
      ) : null}
    </View>
  );
}

function TermSheet({ termKey, entry, institution, onClose }: { termKey: string; entry: LabelEntry; institution: string; onClose: () => void }) {
  const { t } = useTranslation('admin');
  const { colors, space } = useTheme();
  const format = useFormat();
  const confirm = useConfirm();
  const snackbar = useSnackbar();
  const errorText = useErrorText();
  const r = entry.resolved;
  const [enSingular, setEnSingular] = useState(r.en_singular);
  const [enPlural, setEnPlural] = useState(r.en_plural);
  const [bnBase, setBnBase] = useState(r.bn_forms.base);
  // Only forms the person typed are sent as manual forms; the rest are derived by the server from the base word.
  const [overrides, setOverrides] = useState<Partial<BnFormsValue>>({});
  const [derived, setDerived] = useState<BnFormsValue>(r.bn_forms);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const max = entry.max_length;

  useEffect(() => {
    if (entry.resolved.locked || !bnBase.trim()) return undefined;
    // Base word unchanged: keep the forms in force (defaults may have hand-written irregular forms).
    if (bnBase.trim() === r.bn_forms.base && Object.keys(overrides).length === 0) {
      setDerived(r.bn_forms);
      return undefined;
    }
    const timer = setTimeout(() => {
      void previewBnForms(termKey, bnBase.trim(), overrides).then(({ data }) => {
        if (data) setDerived(data);
      });
    }, 300);
    return () => clearTimeout(timer);
  }, [termKey, bnBase, overrides, entry.resolved.locked, r.bn_forms]);

  const draft = useMemo(() => ({ key: termKey, value: { en_singular: enSingular || r.en_singular, en_plural: enPlural || r.en_plural,
    bn_forms: { ...derived, base: bnBase || derived.base } } }), [termKey, enSingular, enPlural, bnBase, derived, r]);
  const tooLong = (v: string) => (v.trim().length > max ? t('terms.tooLong', { n: format.number(max) }) : null);
  const required = (v: string) => (v.trim() ? null : t('terms.required'));
  const fieldError = (v: string) => required(v) ?? tooLong(v);

  const save = async () => {
    if ([enSingular, enPlural, bnBase, ...Object.values(overrides)].some((v) => fieldError(v ?? ''))) return setError(t('terms.limit', { n: format.number(max) }));
    setSaving(true);
    const forms = bnBase.trim() === r.bn_forms.base ? { ...r.bn_forms, ...overrides } : { base: bnBase.trim(), ...overrides };
    const res = await setLabel(termKey, enSingular.trim(), enPlural.trim(), forms);
    if (!res.error) await loadLabels();
    setSaving(false);
    if (res.error) return setError(errorText(res.error).message);
    snackbar.show({ text: t('terms.saved') });
    onClose();
  };
  const reset = async () => {
    if (!(await confirm({ title: t('terms.resetTitle', { word: r.en_singular }), confirmLabel: t('terms.reset'), danger: true }))) return;
    setSaving(true);
    const res = await resetLabel(termKey);
    if (!res.error) await loadLabels();
    setSaving(false);
    if (res.error) return setError(errorText(res.error).message);
    snackbar.show({ text: t('terms.resetDone') });
    onClose();
  };

  if (r.locked) {
    return (
      <BottomSheet visible onClose={onClose} title={`${r.en_singular} · ${r.bn_forms.base}`} testID="term-sheet">
        <Badge label={t('terms.locked')} icon="lock" />
        <AppText testID="term-locked">{t('terms.lockedBody')}</AppText>
      </BottomSheet>
    );
  }

  return (
    <BottomSheet visible onClose={onClose} title={t('terms.edit')} testID="term-sheet"
      footer={<Button label={t('terms.save')} loading={saving} fullWidth onPress={() => void save()} testID="term-save" />}>
      <AppText variant="caption" style={{ color: colors.onSurfaceVariant }}>
        {[t('terms.key', { value: termKey }), t('terms.limit', { n: format.number(max) })].join(' · ')}
      </AppText>
      <TextField label={t('terms.enSingular')} kind="text" required value={enSingular} onChangeText={setEnSingular}
        error={fieldError(enSingular)} testID="term-en-singular" />
      <TextField label={t('terms.enPlural')} kind="text" required value={enPlural} onChangeText={setEnPlural}
        error={fieldError(enPlural)} testID="term-en-plural" />
      <TextField label={t('terms.bnBase')} kind="text" required value={bnBase}
        onChangeText={(v) => { setBnBase(v); setOverrides({}); }} error={fieldError(bnBase)} testID="term-bn-base" />
      <View style={{ gap: space.sm }}>
        <AppText variant="label">{t('terms.bnMore')}</AppText>
        {BN_EXTRA.map((form) => (
          <TextField key={form} label={t(`terms.bnForms.${form}`)} kind="text" value={overrides[form] ?? derived[form] ?? ''}
            onChangeText={(v) => setOverrides((o) => ({ ...o, [form]: v }))} error={tooLong(overrides[form] ?? '')} testID={`term-bn-${form}`} />
        ))}
      </View>
      <LabelPreview draft={draft} institution={institution} testID="term-preview" />
      {error ? <AppText style={{ color: colors.error }} accessibilityRole="alert" testID="term-error">{error}</AppText> : null}
      {entry.resolved.source === 'institution'
        ? <Button variant="outlined" icon="restart-alt" label={t('terms.reset')} onPress={() => void reset()} testID="term-reset" /> : null}
    </BottomSheet>
  );
}
