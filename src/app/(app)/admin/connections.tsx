import { useCallback, useEffect, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { fetchOwnIntegrations, type Connection } from '@/lib/integrations';
import { useLanguageState } from '@/lib/language';
import { useFormat } from '@/lib/locale';
import { pick } from '@/lib/packs';
import { Badge, Row, tDynamic } from '@/ui/admin/parts';
import { ErrorState, Screen, Skeleton } from '@/ui/components';
import { AppHeader } from '@/ui/shell/AppHeader';
import { useTheme } from '@/ui/theme';

// Settings → Connections (0B.11; Ch 42.2, D4): the status of the institution's SMS, email and other connections — mode,
// on / off, last success, last problem and whose side it is on (I10), and who pays. Never keys or settings: the
// Master Admin sets those up.
export default function ConnectionsScreen() {
  const { t } = useTranslation('admin');
  const { language } = useLanguageState();
  const format = useFormat();
  const { colors } = useTheme();
  const [data, setData] = useState<{ connections: Connection[]; payers: Record<string, string> } | null>(null);
  const [error, setError] = useState<unknown>(null);
  const load = useCallback(async () => {
    setError(null);
    const r = await fetchOwnIntegrations();
    if (r.error) setError(r.error);
    else setData(r.data);
  }, []);
  useEffect(() => {
    void load();
  }, [load]);

  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <AppHeader back />
      <Screen title={t('connections.title')} intro={t('connections.intro')} testID="connections">
        {error ? <ErrorState error={error} onRetry={() => void load()} /> : !data ? <Skeleton lines={4} /> : data.connections.length === 0 ? (
          <AppText testID="connections-none">{t('connections.none')}</AppText>
        ) : (
          <View style={{ gap: 8 }}>
            {data.connections.map((c) => (
              <Row key={c.id} icon={c.status === 'active' ? 'link' : 'link-off'} title={`${tDynamic(`panel:integrations.kind.${c.kind}`)} · ${pick(c.provider_name, language)}`}
                testID={`connection-${c.kind}-${c.priority}`}
                subtitle={[
                  data.payers[c.kind] === 'platform' ? t('connections.platformPays') : null,
                  c.last_success_at ? t('connections.lastSuccess', { date: format.dateTime(c.last_success_at) }) : null,
                  c.last_error ? t('connections.problem', { side: tDynamic(`panel:integrations.side.${c.last_error.responsibility}`) }) : null,
                ].filter(Boolean).join(' · ') || t('connections.noTraffic')}
                badge={<Badge label={tDynamic(`panel:integrations.mode.${c.mode}`)} tone={c.mode === 'live' ? 'success' : 'warning'} />} />
            ))}
          </View>
        )}
      </Screen>
    </View>
  );
}
