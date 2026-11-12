import { useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { useErrorText } from '@/i18n/errors';
import { useLanguageState } from '@/lib/language';
import { fetchInstitutionLabels, lockLabel, type InstitutionLabel } from '@/lib/platform-institutions';
import { Badge, Chips, Row, Section, tDynamic } from '@/ui/admin/parts';
import { BottomSheet, Button, EmptyState, ErrorState, Skeleton, TextField, useSnackbar } from '@/ui/components';
import { INSTITUTION_TABS } from '@/ui/panel/menu';
import { usePanel } from '@/ui/panel/PanelContext';
import { PanelShell } from '@/ui/panel/PanelShell';
import { AuditTab } from '@/ui/panel/AuditTab';
import { IntegrationsTab } from '@/ui/panel/IntegrationsTab';
import { OverviewTab } from '@/ui/panel/OverviewTab';
import { PlanTab } from '@/ui/panel/PlanTab';

// One institution in the panel. Built now: the Labels tab (0B.04-T9; Ch 5.3, Ch 8.8) — every word of the institution
// with where it comes from, and the platform lock (with a reason) for words that must not change, such as the legal
// receipt title. A locked word is read-only in the institution's Terminology screen. Overview (0B.07) and Plan and billing
// (0B.05) too; other tabs arrive with their milestones.
type Tab = (typeof INSTITUTION_TABS)[number];

export default function PanelInstitution() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { t } = useTranslation('panel');
  const { language } = useLanguageState();
  const { state, can } = usePanel();
  const snackbar = useSnackbar();
  const errorText = useErrorText();
  const [tab, setTab] = useState<Tab>('overview');
  const [data, setData] = useState<Awaited<ReturnType<typeof fetchInstitutionLabels>>['data']>(null);
  const [error, setError] = useState<unknown>(null);
  const [locking, setLocking] = useState<InstitutionLabel | null>(null);
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setError(null);
    const r = await fetchInstitutionLabels(id);
    if (r.error) setError(r.error);
    else setData(r.data);
  }, [id]);
  useEffect(() => {
    if (state.status === 'ready') void load();
  }, [state.status, load]);

  const word = (l: InstitutionLabel) => (language === 'bn' ? l.label.bn_forms.base : l.label.en_singular);
  const save = async () => {
    if (!locking) return;
    setBusy(true);
    const r = await lockLabel(id, locking.key, !locking.label.locked, reason.trim() || null);
    setBusy(false);
    snackbar.show({ text: r.error ? errorText(r.error).message : locking.label.locked ? t('labelsTab.unlocked') : t('labelsTab.locked') });
    setLocking(null);
    setReason('');
    void load();
  };

  return (
    <PanelShell permission="platform.view" title={data?.institution.name ?? t('menu.institutions')} testID="panel-institution">
      <View testID="panel-institution-tabs">
        <Chips label={t('institutionTabs.title')} selected={tab} onSelect={setTab}
          choices={INSTITUTION_TABS.map((k) => ({ value: k, label: tDynamic(`panel:institutionTabs.${k}`), testID: `institution-tab-${k}` }))} />
      </View>
      {tab === 'overview' ? <OverviewTab institutionId={id} />
        : tab === 'audit' ? <AuditTab institutionId={id} />
        : tab === 'plan' ? <PlanTab institutionId={id} />
        : tab === 'integrations' ? <IntegrationsTab institutionId={id} />
        : tab !== 'labels' ? <EmptyState icon="construction" title={t('soon', { milestone: t('later') })} testID="institution-tab-soon" />
        : error ? <ErrorState error={error} onRetry={() => void load()} /> : !data ? <Skeleton lines={8} /> : (
          <Section title={t('labelsTab.title')} testID="institution-labels">
            <AppText variant="caption">{t('labelsTab.help')}</AppText>
            {data.labels.map((l) => (
              <Row key={l.key} icon={l.label.locked ? 'lock' : 'translate'} title={`${l.key} → ${word(l)}`} testID={`label-${l.key}`}
                subtitle={tDynamic(`panel:labelsTab.source.${l.label.source}`)}
                onPress={l.lockable && can('platform.labels_lock') ? () => setLocking(l) : undefined}
                badge={l.label.locked ? <Badge label={t('labelsTab.lockedBadge')} icon="lock" tone="warning" /> : undefined} />
            ))}
          </Section>
        )}
      {locking ? (
        <BottomSheet visible onClose={() => setLocking(null)} title={`${locking.key} → ${word(locking)}`} testID="lock-sheet"
          footer={<Button label={locking.label.locked ? t('labelsTab.unlock') : t('labelsTab.lock')} loading={busy} fullWidth onPress={() => void save()} testID="lock-save" />}>
          <AppText>{locking.label.locked ? t('labelsTab.unlockHelp') : t('labelsTab.lockHelp')}</AppText>
          <TextField label={t('labelsTab.reason')} kind="multiline" value={reason} onChangeText={setReason} maxLength={300} testID="lock-reason" />
        </BottomSheet>
      ) : null}
    </PanelShell>
  );
}
