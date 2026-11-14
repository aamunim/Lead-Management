import { useCallback, useEffect, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { fetchDeliveryLog, fetchUsageLedger, type DeliveryRow, type LedgerRow } from '@/lib/integrations';
import { useFormat } from '@/lib/locale';
import { Badge, Chips, Row, Section, tDynamic } from '@/ui/admin/parts';
import { ErrorState, Skeleton } from '@/ui/components';
import { usePanel } from '@/ui/panel/PanelContext';
import { PanelShell } from '@/ui/panel/PanelShell';

// Master Admin → Delivery log and ledger (0B.12-T11; Ch 42.2, Ch 25.5): every send result (recipient, time, channel,
// result, connection, fallback, provider message id, parts, cost) and the daily usage ledger per institution, provider,
// channel, category and payer — only platform-paid rows are billable (D15).
type Filter = 'all' | 'sms' | 'email';

export default function PanelDelivery() {
  const { t } = useTranslation('panel');
  const format = useFormat();
  const { state } = usePanel();
  const [channel, setChannel] = useState<Filter>('all');
  const [log, setLog] = useState<DeliveryRow[] | null>(null);
  const [ledger, setLedger] = useState<LedgerRow[] | null>(null);
  const [error, setError] = useState<unknown>(null);

  const load = useCallback(async () => {
    setError(null);
    const [l, g] = await Promise.all([fetchDeliveryLog(null, channel === 'all' ? null : channel), fetchUsageLedger(null)]);
    if (l.error || g.error) return setError(l.error ?? g.error);
    setLog(l.data ?? []);
    setLedger(g.data ?? []);
  }, [channel]);
  useEffect(() => {
    if (state.status === 'ready') void load();
  }, [state.status, load]);

  return (
    <PanelShell permission="platform.view" title={t('menu.delivery')} testID="panel-delivery">
      <AppText>{t('delivery.intro')}</AppText>
      <Chips label={t('delivery.channel')} selected={channel} onSelect={setChannel}
        choices={(['all', 'sms', 'email'] as const).map((c) => ({ value: c, label: tDynamic(`panel:delivery.channels.${c}`), testID: `delivery-channel-${c}` }))} />
      {error ? <ErrorState error={error} onRetry={() => void load()} /> : !log || !ledger ? <Skeleton lines={8} /> : (
        <>
          <Section title={t('delivery.ledger')} testID="delivery-ledger">
            {ledger.length === 0 ? <AppText variant="caption">{t('delivery.noLedger')}</AppText> : ledger.map((r) => (
              <Row key={`${r.institution_id}-${r.day}-${r.provider}-${r.channel}-${r.category}-${r.payer}`} icon="receipt-long"
                title={`${r.institution} · ${format.date(r.day)}`}
                subtitle={[tDynamic(`panel:integrations.kind.${r.channel}`), tDynamic(`panel:delivery.categories.${r.category}`), r.provider,
                  t('delivery.counts', { count: r.count, parts: r.parts, failed: r.failed_parts }), t('delivery.cost', { cost: format.number(r.cost) })].join(' · ')}
                badge={r.billable ? <Badge label={t('delivery.billable')} tone="warning" /> : <Badge label={t('delivery.direct')} />} />
            ))}
          </Section>
          <Section title={t('delivery.log')} testID="delivery-log">
            {log.length === 0 ? <AppText variant="caption" testID="delivery-empty">{t('delivery.noLog')}</AppText> : (
              <View style={{ gap: 8 }}>
                {log.map((d) => (
                  <Row key={d.id} icon={d.result === 'sent' || d.result === 'delivered' ? 'check-circle' : 'error-outline'}
                    title={`${d.institution} · ${d.recipient}`} testID={`delivery-${d.id}`}
                    subtitle={[format.dateTime(d.at), tDynamic(`panel:integrations.kind.${d.channel}`), d.connection,
                      d.fallback ? t('delivery.fallback') : null, d.sandbox ? t('delivery.sandbox') : null,
                      d.parts ? t('delivery.parts', { count: d.parts }) : null,
                      d.error ? t('integrations.lastError', { code: d.error.code, side: tDynamic(`panel:integrations.side.${d.error.responsibility ?? 'platform'}`) }) : null,
                    ].filter(Boolean).join(' · ')}
                    badge={<Badge label={tDynamic(`panel:delivery.results.${d.result}`)}
                      tone={d.result === 'sent' || d.result === 'delivered' ? 'success' : d.result === 'failed' ? 'warning' : 'error'} />} />
                ))}
              </View>
            )}
          </Section>
        </>
      )}
    </PanelShell>
  );
}
