import { useCallback, useEffect, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { useErrorText } from '@/i18n/errors';
import { fetchIntegrations, fetchProviders, setPayer, setPlatformFallback, type AuditRow, type Connection, type Provider } from '@/lib/integrations';
import { useFormat } from '@/lib/locale';
import { CheckRow, Chips, Row, Section, tDynamic } from '@/ui/admin/parts';
import { Button, ErrorState, Skeleton, useSnackbar } from '@/ui/components';

import { ConnectionList, ConnectionSheet } from './Connections';
import { EmailSection } from './EmailSection';
import { usePanel } from './PanelContext';

// Institution → Integrations (0B.11-T5, T6, T8; Ch 5.3, Ch 42.2): every connection of the institution with mode,
// status, key hints and age, live test and last result; who pays per service (D15); the integration audit trail.
const PAYER_KINDS = ['sms', 'email'] as const;

export function IntegrationsTab({ institutionId }: { institutionId: string }) {
  const { t } = useTranslation('panel');
  const format = useFormat();
  const { can } = usePanel();
  const snackbar = useSnackbar();
  const errorText = useErrorText();
  const [data, setData] = useState<{ connections: Connection[]; payers: Record<string, string>; fallback?: Record<string, boolean>; audit: AuditRow[] } | null>(null);
  const [providers, setProviders] = useState<Provider[]>([]);
  const [error, setError] = useState<unknown>(null);
  const [editing, setEditing] = useState<Connection | 'new' | null>(null);
  const manage = can('platform.integrations');

  const load = useCallback(async () => {
    setError(null);
    const [r, p] = await Promise.all([fetchIntegrations(institutionId), fetchProviders()]);
    if (r.error) return setError(r.error);
    setData(r.data);
    setProviders(p.data?.providers ?? []);
  }, [institutionId]);
  useEffect(() => {
    void load();
  }, [load]);

  if (error) return <ErrorState error={error} onRetry={() => void load()} />;
  if (!data) return <Skeleton lines={6} />;
  return (
    <View style={{ gap: 16 }} testID="integrations-tab">
      <Section title={t('integrations.title')}
        action={manage ? <Button variant="text" icon="add" label={t('integrations.add')} onPress={() => setEditing('new')} testID="integrations-add" /> : undefined}>
        <AppText variant="caption">{t('integrations.help')}</AppText>
        {/* Status is shown even without the right to manage; settings and key hints only to those who manage. */}
        <ConnectionList connections={data.connections} onOpen={manage ? setEditing : undefined} testID="integrations-list" />
      </Section>
      <Section title={t('integrations.payers')} testID="integrations-payers">
        <AppText variant="caption">{t('integrations.payersHelp')}</AppText>
        {PAYER_KINDS.map((k) => (
          <Chips key={k} label={tDynamic(`panel:integrations.kind.${k}`)} selected={data.payers[k] ?? 'direct'}
            onSelect={async (v) => {
              if (!manage && !can('platform.billing')) return;
              const r = await setPayer(institutionId, k, v as 'direct' | 'platform');
              if (r.error) return snackbar.show({ text: errorText(r.error).message });
              void load();
            }}
            choices={(['direct', 'platform'] as const).map((p) => ({ value: p, label: `${tDynamic(`panel:integrations.kind.${k}`)}: ${tDynamic(`panel:integrations.payer.${p}`)}`,
              testID: `payer-${k}-${p}` }))} />
        ))}
      </Section>
      <EmailSection institutionId={institutionId} />
      <Section title={t('integrations.fallbackTitle')} testID="integrations-fallback">
        <AppText variant="caption">{t('integrations.fallbackHelp')}</AppText>
        {PAYER_KINDS.map((k) => (
          <CheckRow key={k} label={t('integrations.fallbackLabel', { kind: tDynamic(`panel:integrations.kind.${k}`) })}
            checked={data.fallback?.[k] ?? true} disabled={!manage && !can('platform.billing')} testID={`fallback-${k}`}
            onToggle={async () => {
              const r = await setPlatformFallback(institutionId, k, !(data.fallback?.[k] ?? true));
              if (r.error) return snackbar.show({ text: errorText(r.error).message });
              void load();
            }} />
        ))}
      </Section>
      <Section title={t('integrations.audit')} testID="integrations-audit">
        {data.audit.length === 0 ? <AppText variant="caption">{t('integrations.noAudit')}</AppText> : data.audit.map((a, i) => (
          <Row key={`${a.at}-${i}`} icon="history" title={tDynamic(`panel:integrations.actions.${a.action}`)}
            subtitle={[format.dateTime(a.at), a.by, typeof a.detail.hint === 'string' ? a.detail.hint : null].filter(Boolean).join(' · ')} />
        ))}
      </Section>
      {editing ? (
        <ConnectionSheet institutionId={institutionId} providers={providers} connection={editing === 'new' ? null : editing}
          onClose={() => setEditing(null)} onSaved={() => { setEditing(null); void load(); }} />
      ) : null}
    </View>
  );
}
