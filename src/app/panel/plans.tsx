import { useCallback, useEffect, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { useErrorText } from '@/i18n/errors';
import { useLanguageState } from '@/lib/language';
import { pick } from '@/lib/packs';
import { fetchPlans, savePlan, type PlanRow } from '@/lib/platform-institutions';
import { Badge, Row } from '@/ui/admin/parts';
import { BottomSheet, Button, ErrorState, Skeleton, TextField, useSnackbar } from '@/ui/components';
import { usePanel } from '@/ui/panel/PanelContext';
import { PanelShell } from '@/ui/panel/PanelShell';

// Plans catalog (0B.05-T5, T13; D22, D30, D31, D32): each plan's modules, limits, prices (also per type) and trial
// length are data. Saving makes a new version; institutions keep their version until they change plan. All numbers
// are placeholders until the owner sets them.
type Form = { key: string; en: string; bn: string; trial: string; modules: string; limits: string; prices: string; notes: string };

export default function PanelPlans() {
  const { t } = useTranslation('panel');
  const { language } = useLanguageState();
  const { state } = usePanel();
  const snackbar = useSnackbar();
  const errorText = useErrorText();
  const [plans, setPlans] = useState<PlanRow[] | null>(null);
  const [error, setError] = useState<unknown>(null);
  const [form, setForm] = useState<Form | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setError(null);
    const r = await fetchPlans();
    if (r.error) setError(r.error);
    else setPlans(r.data?.plans ?? []);
  }, []);
  useEffect(() => {
    if (state.status === 'ready') void load();
  }, [state.status, load]);

  const latest = Array.from(new Map((plans ?? []).map((p) => [p.key, p])).values());
  const open = (p: PlanRow) => setForm({ key: p.key, en: p.name.en, bn: p.name.bn, trial: p.trial_days?.toString() ?? '',
    modules: p.modules.join(', '), limits: JSON.stringify(p.limits, null, 2), prices: JSON.stringify(p.prices, null, 2), notes: '' });
  const parse = (text: string) => {
    try {
      return JSON.parse(text) as Record<string, unknown>;
    } catch {
      return null;
    }
  };
  const save = async () => {
    if (!form) return;
    const limits = parse(form.limits);
    const prices = parse(form.prices);
    if (!limits || !prices) return snackbar.show({ text: t('plan.jsonInvalid') });
    setBusy(true);
    const r = await savePlan(form.key, { en: form.en, bn: form.bn }, form.modules.split(',').map((m) => m.trim()).filter(Boolean),
      limits, prices, form.trial ? Number(form.trial) : null, form.notes.trim() || null);
    setBusy(false);
    if (r.error) return snackbar.show({ text: errorText(r.error).message });
    snackbar.show({ text: t('plans.saved', { version: r.data }) });
    setForm(null);
    void load();
  };

  return (
    <PanelShell permission="platform.plans" title={t('plans.title')} testID="panel-plans">
      <AppText>{t('plans.intro')}</AppText>
      {error ? <ErrorState error={error} onRetry={() => void load()} /> : !plans ? <Skeleton lines={6} /> : (
        <View style={{ gap: 8 }}>
          {latest.map((p) => (
            <Row key={p.key} icon="workspace-premium" title={pick(p.name, language)} testID={`plan-${p.key}`} onPress={() => open(p)}
              subtitle={t('plans.line', { version: p.version, count: plans.filter((x) => x.key === p.key).reduce((n, x) => n + x.institutions, 0) })}
              badge={p.for_new ? <Badge label={t('plans.forNew')} tone="primary" /> : undefined} />
          ))}
        </View>
      )}
      {form ? (
        <BottomSheet visible onClose={() => setForm(null)} title={form.key} testID="plan-sheet"
          footer={<Button label={t('plans.saveNew')} loading={busy} fullWidth onPress={() => void save()} testID="plan-sheet-save" />}>
          <TextField label={t('profiles.nameEn')} value={form.en} onChangeText={(v) => setForm((f) => f && { ...f, en: v })} testID="plan-name-en" />
          <TextField label={t('profiles.nameBn')} value={form.bn} onChangeText={(v) => setForm((f) => f && { ...f, bn: v })} testID="plan-name-bn" />
          <TextField label={t('plans.trialDays')} kind="number" value={form.trial} onChangeText={(v) => setForm((f) => f && { ...f, trial: v })} testID="plan-trial" />
          <TextField label={t('plans.modules')} kind="multiline" value={form.modules} onChangeText={(v) => setForm((f) => f && { ...f, modules: v })} testID="plan-modules" />
          <TextField label={t('plans.limits')} kind="multiline" value={form.limits} onChangeText={(v) => setForm((f) => f && { ...f, limits: v })}
            help={t('plans.limitsHelp')} testID="plan-limits" />
          <TextField label={t('plans.prices')} kind="multiline" value={form.prices} onChangeText={(v) => setForm((f) => f && { ...f, prices: v })}
            help={t('plans.pricesHelp')} testID="plan-prices" />
          <TextField label={t('profiles.notes')} kind="multiline" value={form.notes} onChangeText={(v) => setForm((f) => f && { ...f, notes: v })} testID="plan-notes" />
        </BottomSheet>
      ) : null}
    </PanelShell>
  );
}
