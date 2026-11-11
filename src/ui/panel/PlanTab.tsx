import { useCallback, useEffect, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { useErrorText } from '@/i18n/errors';
import { useLanguageState } from '@/lib/language';
import { pick } from '@/lib/packs';
import { fetchInstitutionPlan, fetchPlans, setInstitutionPlan, allowModule, type InstitutionPlan, type PlanRow } from '@/lib/platform-institutions';
import { Badge, Chips, Row, Section, tDynamic } from '@/ui/admin/parts';
import { Button, ErrorState, Skeleton, TextField, useSnackbar } from '@/ui/components';

import { usePanel } from './PanelContext';

// Institution → Plan and billing (0B.05, Ch 5.7): plan, end date, cycle, price / discount and limit overrides (each
// change logged with a reason), what must be reduced before a smaller plan (fit check), usage, and modules allowed
// beyond or below the plan. Needs platform.billing.
export function PlanTab({ institutionId }: { institutionId: string }) {
  const { t } = useTranslation('panel');
  const { language } = useLanguageState();
  const { can } = usePanel();
  const snackbar = useSnackbar();
  const errorText = useErrorText();
  const [data, setData] = useState<InstitutionPlan | null>(null);
  const [plans, setPlans] = useState<PlanRow[]>([]);
  const [error, setError] = useState<unknown>(null);
  const [form, setForm] = useState({ plan: '', expires: '', cycle: 'monthly', price: '', discount: '0', overrides: '{}', reason: '' });
  const [busy, setBusy] = useState(false);

  const load = useCallback(async (compare: string | null = null) => {
    setError(null);
    const [r, p] = await Promise.all([fetchInstitutionPlan(institutionId, compare), fetchPlans()]);
    if (r.error || !r.data) return setError(r.error);
    setData(r.data);
    setPlans(p.data?.plans ?? []);
    if (!compare && r.data.plan) {
      const ip = r.data.plan;
      setForm({ plan: ip.plan_key, expires: ip.expires_at?.slice(0, 10) ?? '', cycle: ip.billing_cycle, price: ip.price_override?.toString() ?? '',
        discount: String(ip.discount_percent ?? 0), overrides: JSON.stringify(ip.limit_overrides ?? {}), reason: '' });
    }
  }, [institutionId]);
  useEffect(() => {
    void load();
  }, [load]);

  if (!can('platform.billing')) return <AppText testID="plan-no-access">{t('noAccess')}</AppText>;
  if (error) return <ErrorState error={error} onRetry={() => void load()} />;
  if (!data) return <Skeleton lines={8} />;
  const latest = Array.from(new Map(plans.map((p) => [p.key, p])).values());
  let overrides: Record<string, unknown> | null = null;
  try {
    overrides = JSON.parse(form.overrides || '{}') as Record<string, unknown>;
  } catch {
    overrides = null;
  }
  const save = async () => {
    if (!overrides) return;
    setBusy(true);
    const r = await setInstitutionPlan(institutionId, { plan: form.plan, expires: form.expires ? `${form.expires}T23:59:59Z` : null, cycle: form.cycle,
      price: form.price ? Number(form.price) : null, discount: Number(form.discount || 0), overrides, reason: form.reason.trim() || null });
    setBusy(false);
    snackbar.show({ text: r.error ? errorText(r.error).message : t('plan.saved') });
    if (!r.error) void load();
  };
  const allow = async (key: string, value: boolean | null) => {
    const r = await allowModule(institutionId, key, value, null);
    snackbar.show({ text: r.error ? errorText(r.error).message : t('plan.saved') });
    void load(form.plan !== data.plan?.plan_key ? form.plan : null);
  };

  return (
    <View style={{ gap: 16 }} testID="plan-tab">
      <Section title={t('plan.current')}>
        <AppText testID="plan-current">{data.plan ? t('plan.currentLine', { name: pick(data.plan.name, language), version: data.plan.plan_version }) : '—'}</AppText>
        {data.plan && data.plan.latest_version > data.plan.plan_version ? <Badge label={t('plan.newerVersion', { version: data.plan.latest_version })} tone="warning" /> : null}
        <Chips label={t('plan.choose')} selected={form.plan} onSelect={(v) => { setForm((f) => ({ ...f, plan: v })); void load(v); }}
          choices={latest.map((p) => ({ value: p.key, label: pick(p.name, language), testID: `plan-choice-${p.key}` }))} />
        {data.fit && (data.fit.over.length || data.fit.modules_lost.length) ? (
          <View testID="plan-fit">
            <AppText variant="label">{t('plan.fitTitle')}</AppText>
            {data.fit.over.map((o) => <AppText key={o.metric} variant="caption">{t('plan.reduce', { name: tDynamic(`admin:limits.metrics.${o.metric}`), by: o.reduce_by })}</AppText>)}
            {data.fit.modules_lost.length ? <AppText variant="caption">{t('plan.modulesLost', { names: data.fit.modules_lost.join(', ') })}</AppText> : null}
          </View>
        ) : null}
        <TextField label={t('plan.expires')} value={form.expires} onChangeText={(v) => setForm((f) => ({ ...f, expires: v }))} maxLength={10} testID="plan-expires"
          help={t('plan.expiresHelp')} />
        <Chips label={t('plan.cycle')} selected={form.cycle} onSelect={(v) => setForm((f) => ({ ...f, cycle: v }))}
          choices={['monthly', 'yearly', 'custom'].map((c) => ({ value: c, label: tDynamic(`panel:plan.cycles.${c}`), testID: `plan-cycle-${c}` }))} />
        <TextField label={t('plan.price')} kind="decimal" value={form.price} onChangeText={(v) => setForm((f) => ({ ...f, price: v }))} testID="plan-price" />
        <TextField label={t('plan.discount')} kind="decimal" value={form.discount} onChangeText={(v) => setForm((f) => ({ ...f, discount: v }))} testID="plan-discount" />
        <TextField label={t('plan.overrides')} kind="multiline" value={form.overrides} onChangeText={(v) => setForm((f) => ({ ...f, overrides: v }))}
          help={t('plan.overridesHelp')} error={overrides ? null : t('plan.jsonInvalid')} testID="plan-overrides" />
        <TextField label={t('plan.reason')} kind="multiline" value={form.reason} onChangeText={(v) => setForm((f) => ({ ...f, reason: v }))} maxLength={300} testID="plan-reason" />
        <Button label={t('plan.save')} loading={busy} disabled={!overrides || !form.plan} onPress={() => void save()} testID="plan-save" />
      </Section>
      <Section title={t('plan.usage')} testID="plan-usage">
        {data.usage.map((u) => (
          <Row key={u.metric} title={tDynamic(`admin:limits.metrics.${u.metric}`)} testID={`plan-usage-${u.metric}`}
            subtitle={u.limit === null ? t('plan.noLimit', { used: u.used }) : t('plan.usedOf', { used: u.used, limit: u.limit })}
            badge={u.level !== 'ok' ? <Badge label={tDynamic(`admin:plan.level.${u.level}`)} tone="warning" /> : undefined} />
        ))}
      </Section>
      <Section title={t('plan.modules')} testID="plan-modules">
        <AppText variant="caption">{t('plan.modulesHelp')}</AppText>
        {data.modules.filter((m) => !m.always_on).map((m) => (
          <View key={m.key} style={{ gap: 4 }}>
            <AppText>{`${m.key} · ${m.allowed ? t('plan.allowed') : t('plan.notAllowed')}${m.enabled ? ` · ${t('plan.inUse')}` : ''}`}</AppText>
            <Chips label={m.key} selected={m.override === null ? 'plan' : m.override ? 'yes' : 'no'}
              onSelect={(v) => void allow(m.key, v === 'plan' ? null : v === 'yes')}
              choices={[{ value: 'plan', label: t('plan.followPlan'), testID: `module-allow-${m.key}-plan` },
                { value: 'yes', label: t('plan.allow'), testID: `module-allow-${m.key}-yes` },
                { value: 'no', label: t('plan.disallow'), testID: `module-allow-${m.key}-no` }]} />
          </View>
        ))}
      </Section>
    </View>
  );
}
