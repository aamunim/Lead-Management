import { Redirect, router } from 'expo-router';
import { useEffect, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { fetchApprovalQueue, type QueueRow } from '@/lib/lifecycle';
import { approveEdit, fetchEditRequests, type EditRequest } from '@/lib/support';
import { fetchPlatformAlerts, type PlatformAlert } from '@/lib/platform';
import { useFormat } from '@/lib/locale';
import { Badge, Row } from '@/ui/admin/parts';
import { Button, Skeleton } from '@/ui/components';
import { PANEL_MENU } from '@/ui/panel/menu';
import { usePanel } from '@/ui/panel/PanelContext';
import { PanelShell } from '@/ui/panel/PanelShell';

// Panel dashboard (0B.02, 0B.07): institutions waiting for approval (with duplicate / trial warnings) and alerts for this
// platform user (new devices). Figures and charts arrive with 1.33.
export default function PanelDashboard() {
  const { t } = useTranslation('panel');
  const format = useFormat();
  const { state, can } = usePanel();
  const [alerts, setAlerts] = useState<PlatformAlert[] | null>(null);
  const [queue, setQueue] = useState<QueueRow[] | null>(null);
  const [edits, setEdits] = useState<EditRequest[]>([]);
  const loadEdits = () => void fetchEditRequests().then(({ data }) => setEdits(data ?? []));
  useEffect(() => {
    if (state.status !== 'ready') return;
    void fetchPlatformAlerts().then(({ data }) => setAlerts(data ?? []));
    if (can('platform.view')) void fetchApprovalQueue().then(({ data }) => setQueue(data ?? []));
    if (state.session.platform_role === 'master_admin') loadEdits();
  }, [state.status, can]);
  // A role without the dashboard (Developer) starts on its first page.
  if (state.status === 'ready' && !can('platform.view')) {
    const first = PANEL_MENU.find((i) => can(i.permission));
    if (first) return <Redirect href={first.href} />;
  }
  return (
    <PanelShell permission="platform.view" title={t('dashboard.title')} testID="panel-dashboard">
      {edits.length ? (
        <View style={{ gap: 8 }} testID="panel-edit-requests">
          <AppText variant="titleSmall">{t('dashboard.editRequests')}</AppText>
          {edits.map((e) => (
            <Row key={e.id} icon="edit-note" title={`${e.institution} · ${e.by}`} subtitle={e.edit_reason} testID={`edit-request-${e.id}`}
              badge={<Button variant="tonal" label={t('dashboard.approveEdit')} onPress={() => void approveEdit(e.id).then(loadEdits)} testID={`edit-approve-${e.id}`} />} />
          ))}
        </View>
      ) : null}
      <AppText variant="titleSmall">{t('dashboard.approvals')}</AppText>
      {!queue ? <Skeleton lines={2} /> : queue.length === 0 ? <AppText testID="panel-no-approvals">{t('dashboard.noApprovals')}</AppText> : (
        <View style={{ gap: 8 }} testID="panel-approvals">
          {queue.map((q) => (
            <Row key={q.id} icon="pending-actions" title={q.name} subtitle={t('dashboard.signedUp', { date: format.dateTime(q.created_at) })}
              testID={`approval-${q.slug}`} onPress={() => router.push(`/panel/institution/${q.id}`)}
              badge={q.duplicates.length ? <Badge label={t('dashboard.possibleDuplicate')} tone="warning" />
                : q.trial.flagged ? <Badge label={t('dashboard.manyTrials')} tone="warning" /> : undefined} />
          ))}
        </View>
      )}
      <AppText variant="titleSmall">{t('dashboard.alerts')}</AppText>
      {!alerts ? <Skeleton lines={2} /> : alerts.length === 0 ? <AppText testID="panel-no-alerts">{t('dashboard.noAlerts')}</AppText> : (
        <View style={{ gap: 8 }} testID="panel-alerts">
          {alerts.map((a) => (
            a.kind === 'email_paused' ? (
              <Row key={a.id} icon="unsubscribe" title={t('dashboard.emailPausedAlert', { name: a.payload.name ?? '', bounced: a.payload.bounced ?? '',
                complained: a.payload.complained ?? '', sent: a.payload.sent ?? '' })}
                subtitle={format.dateTime(a.created_at)} onPress={() => router.push(`/panel/institution/${a.payload.institution_id}`)}
                testID={`panel-alert-${a.kind}`} />
            ) :             a.kind === 'balance_low' || a.kind === 'contract_failed' ? (
              <Row key={a.id} icon={a.kind === 'balance_low' ? 'account-balance-wallet' : 'rule'}
                title={a.kind === 'balance_low' ? t('dashboard.balanceAlert', { label: a.payload.label ?? '', name: a.payload.name ? ` · ${a.payload.name}` : '',
                  balance: a.payload.balance ?? '' }) : t('dashboard.contractAlert', { provider: a.payload.provider ?? '' })}
                subtitle={format.dateTime(a.created_at)} onPress={a.payload.institution_id ? () => router.push(`/panel/institution/${a.payload.institution_id}`)
                  : () => router.push('/panel/providers')} testID={`panel-alert-${a.kind}`} />
            ) :             a.kind === 'circuit_open' ? (
              <Row key={a.id} icon="power-off" title={t('dashboard.circuitAlert', { label: a.payload.label ?? '', name: a.payload.name ? ` · ${a.payload.name}` : '',
                code: a.payload.code ?? '' })}
                subtitle={format.dateTime(a.created_at)} onPress={a.payload.institution_id ? () => router.push(`/panel/institution/${a.payload.institution_id}`)
                  : () => router.push('/panel/providers')} testID={`panel-alert-${a.kind}`} />
            ) :             a.kind === 'key_rotation_due' ? (
              <Row key={a.id} icon="key" title={t('dashboard.keyAlert', { hint: a.payload.hint ?? '', name: a.payload.name ? ` · ${a.payload.name}` : '',
                date: a.payload.since ? format.dateTime(a.payload.since) : '' })}
                subtitle={format.dateTime(a.created_at)} onPress={a.payload.institution_id ? () => router.push(`/panel/institution/${a.payload.institution_id}`)
                  : () => router.push('/panel/providers')} testID={`panel-alert-${a.kind}`} />
            ) : a.kind === 'setup_incomplete' ? (
              <Row key={a.id} icon="checklist" title={t('dashboard.setupAlert', { name: a.payload.name ?? '', done: a.payload.done ?? '', total: a.payload.total ?? '' })}
                subtitle={format.dateTime(a.created_at)} onPress={() => router.push(`/panel/institution/${a.payload.institution_id}`)}
                testID={`panel-alert-${a.kind}`} />
            ) : (
              <Row key={a.id} icon="devices" title={t('dashboard.newDeviceAlert', { email: a.payload.email ?? '', ip: a.payload.ip ?? '' })}
                subtitle={format.dateTime(a.created_at)} testID={`panel-alert-${a.kind}`} />
            )
          ))}
        </View>
      )}
    </PanelShell>
  );
}
