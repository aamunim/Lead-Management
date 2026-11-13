import { useCallback, useEffect, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { fetchProviders, type Connection, type Provider } from '@/lib/integrations';
import { useLanguageState } from '@/lib/language';
import { pick } from '@/lib/packs';
import { Badge, Row, Section, tDynamic } from '@/ui/admin/parts';
import { Button, ErrorState, Skeleton } from '@/ui/components';
import { ConnectionList, ConnectionSheet } from '@/ui/panel/Connections';
import { usePanel } from '@/ui/panel/PanelContext';
import { PanelShell } from '@/ui/panel/PanelShell';

// Master Admin → Providers (0B.11-T8; Ch 5.3, Ch 42.2): the provider catalog (what each needs, whether its adapter is
// built yet) and the platform's own connections — the default SMS gateway and mail used when the platform pays (D15)
// or an institution has none. Keys are write-only; only hints are shown.
export default function PanelProviders() {
  const { t } = useTranslation('panel');
  const { language } = useLanguageState();
  const { state, can } = usePanel();
  const [data, setData] = useState<{ providers: Provider[]; platform_connections: Connection[] } | null>(null);
  const [error, setError] = useState<unknown>(null);
  const [editing, setEditing] = useState<Connection | 'new' | null>(null);

  const load = useCallback(async () => {
    setError(null);
    const r = await fetchProviders();
    if (r.error) setError(r.error);
    else setData(r.data);
  }, []);
  useEffect(() => {
    if (state.status === 'ready') void load();
  }, [state.status, load]);
  const manage = can('platform.integrations');

  return (
    <PanelShell permission="platform.view" title={t('menu.providers')} testID="panel-providers">
      <AppText>{t('providers.intro')}</AppText>
      {error ? <ErrorState error={error} onRetry={() => void load()} /> : !data ? <Skeleton lines={6} /> : (
        <>
          <Section title={t('providers.platformConnections')} testID="providers-platform"
            action={manage ? <Button variant="text" icon="add" label={t('integrations.add')} onPress={() => setEditing('new')} testID="providers-add" /> : undefined}>
            <AppText variant="caption">{t('providers.platformHelp')}</AppText>
            <ConnectionList connections={data.platform_connections} onOpen={manage ? setEditing : undefined} testID="providers-connections" />
          </Section>
          <Section title={t('providers.catalog')} testID="providers-catalog">
            <View style={{ gap: 8 }}>
              {data.providers.map((p) => (
                <Row key={p.key} icon="hub" title={pick(p.name, language)} testID={`provider-${p.key}`}
                  subtitle={[tDynamic(`panel:integrations.kind.${p.kind}`), p.secret_fields.length ? t('providers.needs', { fields: p.secret_fields.join(', ') }) : null,
                    p.adapter_version ? t('providers.adapter', { version: p.adapter_version }) : t('integrations.adapterLater')].filter(Boolean).join(' · ')}
                  badge={<Badge label={tDynamic(`panel:providers.status.${p.status}`)} tone={p.status === 'active' ? 'success' : 'neutral'} />} />
              ))}
            </View>
          </Section>
        </>
      )}
      {editing && data ? (
        <ConnectionSheet institutionId={null} providers={data.providers} connection={editing === 'new' ? null : editing}
          onClose={() => setEditing(null)} onSaved={() => { setEditing(null); void load(); }} />
      ) : null}
    </PanelShell>
  );
}
