import { useCallback, useEffect, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { useErrorText } from '@/i18n/errors';
import { loadLabels } from '@/lib/labels';
import { useLanguageState } from '@/lib/language';
import { pick } from '@/lib/packs';
import {
  applyProfiles, describeValue, fetchProfileState, previewProfiles, resetArea,
  type PreviewArea, type ProfilePreview, type ProfileState, type ResetItem,
} from '@/lib/profiles';
import { loadSettings } from '@/lib/settings';
import { Badge, CheckRow, Chips, Row, Section, permissionLabel, tDynamic } from '@/ui/admin/parts';
import { BottomSheet, Button, ErrorState, Screen, Skeleton, TextField, useConfirm, useSnackbar } from '@/ui/components';
import { AppHeader } from '@/ui/shell/AppHeader';
import { useTheme } from '@/ui/theme';

// Settings → Institution type (0B.04-T5, T6, T7; Ch 6.6, Ch 7.6): the types in use and their versions, a newer version
// to opt into, choosing types with a preview (per area: new, changed, back to default, kept because you changed it;
// word conflicts of mixed types to choose), and "Reset to profile defaults" per area with a preview. Nothing is ever
// deleted and your own changes are kept.
export default function InstitutionTypeScreen() {
  const { t } = useTranslation('admin');
  const { language } = useLanguageState();
  const { colors, space } = useTheme();
  const snackbar = useSnackbar();
  const confirm = useConfirm();
  const errorText = useErrorText();
  const [state, setState] = useState<ProfileState | null>(null);
  const [error, setError] = useState<unknown>(null);
  const [chosen, setChosen] = useState<string[]>([]);
  const [choices, setChoices] = useState<Record<string, string>>({});
  const [preview, setPreview] = useState<ProfilePreview | null>(null);
  const [open, setOpen] = useState<string | null>(null);
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [resetting, setResetting] = useState<{ area: string; items: ResetItem[] } | null>(null);

  const load = useCallback(async () => {
    setError(null);
    const r = await fetchProfileState();
    if (r.error || !r.data) return setError(r.error);
    setState(r.data);
    setChosen(r.data.applied.map((a) => a.key));
  }, []);
  useEffect(() => {
    void load();
  }, [load]);

  const runPreview = async (types: string[], labelChoices: Record<string, string>) => {
    setBusy(true);
    const r = await previewProfiles(types, labelChoices);
    setBusy(false);
    if (r.error) return snackbar.show({ text: errorText(r.error).message });
    setPreview(r.data);
  };
  const toggle = (key: string) => {
    setPreview(null);
    setChosen((c) => (c.includes(key) ? c.filter((k) => k !== key) : [...c, key]));
  };
  const apply = async () => {
    if (!preview) return;
    const ok = await confirm({ title: t('types.applyTitle'), message: t('types.applyBody'), confirmLabel: t('types.apply') });
    if (!ok) return;
    setBusy(true);
    const r = await applyProfiles(chosen, choices, reason.trim() || null);
    setBusy(false);
    if (r.error) return snackbar.show({ text: errorText(r.error).message });
    await Promise.all([loadLabels(), loadSettings(true)]);
    snackbar.show({ text: t('types.applied') });
    setPreview(null);
    setReason('');
    void load();
  };
  const openReset = async (area: string) => {
    const r = await resetArea(area, false);
    if (r.error || !r.data) return snackbar.show({ text: r.error ? errorText(r.error).message : '' });
    setResetting({ area, items: r.data.items });
  };
  const doReset = async () => {
    if (!resetting) return;
    setBusy(true);
    const r = await resetArea(resetting.area, true);
    setBusy(false);
    if (r.error) return snackbar.show({ text: errorText(r.error).message });
    await Promise.all([loadLabels(), loadSettings(true)]);
    snackbar.show({ text: t('types.resetDone') });
    setResetting(null);
    void load();
  };

  const areaLine = (a: PreviewArea) => [a.add ? t('types.add', { count: a.add }) : null, a.change ? t('types.change', { count: a.change }) : null,
    a.remove ? t('types.remove', { count: a.remove }) : null, a.kept ? t('types.kept', { count: a.kept }) : null].filter(Boolean).join(' · ');
  const newer = state?.applied.filter((a) => a.latest_version > a.version) ?? [];

  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <AppHeader back />
      <Screen title={t('types.title')} intro={t('types.intro')} testID="institution-type">
        {error ? <ErrorState error={error} onRetry={() => void load()} testID="types-error" /> : !state ? <Skeleton lines={5} testID="types-loading" /> : (
          <>
            <Section title={t('types.current')} testID="types-current">
              {state.applied.length === 0 ? <AppText testID="types-none">{t('types.none')}</AppText> : (
                <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: space.sm }}>
                  {state.applied.map((a) => <Badge key={a.key} label={t('types.typeVersion', { name: pick(a.name, language), version: a.version })} tone="primary" testID={`type-${a.key}`} />)}
                </View>
              )}
              {newer.length ? (
                <View style={{ gap: space.sm }} testID="types-newer">
                  {newer.map((a) => <Badge key={a.key} icon="new-releases" tone="warning"
                    label={t('types.newVersion', { name: pick(a.name, language), version: a.latest_version })} />)}
                  <Button variant="tonal" label={t('types.previewNewer')} loading={busy}
                    onPress={() => void runPreview(state.applied.map((a) => a.key), choices)} testID="types-preview-newer" />
                </View>
              ) : null}
            </Section>

            <Section title={t('types.choose')} testID="types-choose">
              <AppText variant="caption">{t('types.chooseHelp')}</AppText>
              {state.available.map((p) => (
                <CheckRow key={p.key} label={pick(p.name, language)} help={pick(p.description, language)} checked={chosen.includes(p.key)}
                  onToggle={() => toggle(p.key)} testID={`types-option-${p.key}`} />
              ))}
              <Button icon="preview" label={t('types.preview')} loading={busy} disabled={chosen.length === 0}
                onPress={() => void runPreview(chosen, choices)} testID="types-preview" />
            </Section>

            {preview ? (
              <Section title={t('types.previewTitle')} testID="types-preview-result">
                <View style={{ padding: space.md, borderRadius: 12, backgroundColor: colors.warmContainer }}>
                  <AppText style={{ color: colors.onWarmContainer }}>{t('types.warning')}</AppText>
                </View>
                {preview.label_conflicts.map((c) => (
                  <View key={c.key} style={{ gap: space.xs }} testID={`types-conflict-${c.key}`}>
                    <AppText variant="label">{t('types.conflict', { key: c.key })}</AppText>
                    <Chips label={t('types.conflict', { key: c.key })} selected={choices[c.key] ?? c.chosen}
                      choices={c.options.map((o) => ({ value: o.profile, label: language === 'bn' ? o.bn : o.en_singular, testID: `types-conflict-${c.key}-${o.profile}` }))}
                      onSelect={(v) => {
                        const next = { ...choices, [c.key]: v };
                        setChoices(next);
                        void runPreview(chosen, next);
                      }} />
                  </View>
                ))}
                {preview.areas.length === 0 ? <AppText testID="types-no-change">{t('types.noChange')}</AppText> : null}
                {preview.areas.map((a) => (
                  <View key={a.area} style={{ gap: space.xs }}>
                    <Row icon={open === a.area ? 'expand-less' : 'expand-more'} title={tDynamic(`admin:types.areas.${a.area}`)}
                      subtitle={[areaLine(a), ['0B.04'].includes(a.used_from) ? null : t('types.usedFrom', { milestone: a.used_from })].filter(Boolean).join(' · ')}
                      onPress={() => setOpen(open === a.area ? null : a.area)} testID={`types-area-${a.area}`} />
                    {open === a.area ? a.items.map((i) => (
                      <AppText key={i.key} variant="caption" testID={`types-item-${a.area}-${i.key}`}>
                        {`${t(`types.action.${i.action}`)}: ${i.key} — ${describeValue(i.before, language)} → ${describeValue(i.after, language)}`}
                      </AppText>
                    )) : null}
                  </View>
                ))}
                <TextField label={t('types.reason')} kind="multiline" value={reason} onChangeText={setReason} maxLength={300} testID="types-reason" />
                <Button icon="check" label={t('types.apply')} loading={busy} onPress={() => void apply()} testID="types-apply" />
              </Section>
            ) : null}

            <Section title={t('types.resetTitle')} testID="types-reset">
              <AppText variant="caption">{t('types.resetHelp')}</AppText>
              {state.reset_areas.length === 0 ? <AppText testID="types-reset-none">{t('types.resetNone')}</AppText> : null}
              {state.reset_areas.map((r) => (
                <Row key={r.area} icon="restart-alt" title={permissionLabel(r.area)} subtitle={t('types.own', { count: r.own })}
                  onPress={() => void openReset(r.area)} testID={`types-reset-${r.area}`} />
              ))}
            </Section>
          </>
        )}
      </Screen>
      {resetting ? (
        <BottomSheet visible onClose={() => setResetting(null)} title={t('types.resetSheet', { area: permissionLabel(resetting.area) })} testID="reset-sheet"
          footer={<Button variant="danger" label={t('types.resetConfirm')} loading={busy} fullWidth onPress={() => void doReset()} testID="reset-confirm" />}>
          <AppText>{t('types.resetSheetHelp')}</AppText>
          {resetting.items.map((i) => (
            <AppText key={i.key} variant="caption" testID={`reset-item-${i.key}`}>
              {`${i.key}: ${describeValue(i.current, language)} → ${describeValue(i.default, language)}`}
            </AppText>
          ))}
        </BottomSheet>
      ) : null}
    </View>
  );
}
