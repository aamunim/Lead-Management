import { Redirect } from 'expo-router';
import { useEffect, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { fetchPlatformAlerts, type PlatformAlert } from '@/lib/platform';
import { useFormat } from '@/lib/locale';
import { Row } from '@/ui/admin/parts';
import { Skeleton } from '@/ui/components';
import { PANEL_MENU } from '@/ui/panel/menu';
import { usePanel } from '@/ui/panel/PanelContext';
import { PanelShell } from '@/ui/panel/PanelShell';

// Panel dashboard (0B.02): alerts for this platform user (new devices). Figures and charts arrive with 1.33.
export default function PanelDashboard() {
  const { t } = useTranslation('panel');
  const format = useFormat();
  const { state, can } = usePanel();
  const [alerts, setAlerts] = useState<PlatformAlert[] | null>(null);
  useEffect(() => {
    if (state.status === 'ready') void fetchPlatformAlerts().then(({ data }) => setAlerts(data ?? []));
  }, [state.status]);
  // A role without the dashboard (Developer) starts on its first page.
  if (state.status === 'ready' && !can('platform.view')) {
    const first = PANEL_MENU.find((i) => can(i.permission));
    if (first) return <Redirect href={first.href} />;
  }
  return (
    <PanelShell permission="platform.view" title={t('dashboard.title')} testID="panel-dashboard">
      <AppText variant="titleSmall">{t('dashboard.alerts')}</AppText>
      {!alerts ? <Skeleton lines={2} /> : alerts.length === 0 ? <AppText testID="panel-no-alerts">{t('dashboard.noAlerts')}</AppText> : (
        <View style={{ gap: 8 }} testID="panel-alerts">
          {alerts.map((a) => (
            <Row key={a.id} icon="devices" title={t('dashboard.newDeviceAlert', { email: a.payload.email ?? '', ip: a.payload.ip ?? '' })}
              subtitle={format.dateTime(a.created_at)} testID={`panel-alert-${a.kind}`} />
          ))}
        </View>
      )}
    </PanelShell>
  );
}
