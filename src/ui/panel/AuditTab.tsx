import { useCallback, useEffect, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { useFormat } from '@/lib/locale';
import { fetchInstitutionAudit, type PlatformAuditRow } from '@/lib/support';
import { Badge, Row } from '@/ui/admin/parts';
import { ErrorState, Skeleton } from '@/ui/components';

// Institution → Audit (0B.08-T6, Ch 5.3): every platform change and support entry for this institution, newest first.
export function AuditTab({ institutionId }: { institutionId: string }) {
  const { t } = useTranslation('panel');
  const format = useFormat();
  const [rows, setRows] = useState<PlatformAuditRow[] | null>(null);
  const [error, setError] = useState<unknown>(null);
  const load = useCallback(async () => {
    setError(null);
    const r = await fetchInstitutionAudit(institutionId);
    if (r.error) setError(r.error);
    else setRows(r.data ?? []);
  }, [institutionId]);
  useEffect(() => {
    void load();
  }, [load]);
  if (error) return <ErrorState error={error} onRetry={() => void load()} />;
  if (!rows) return <Skeleton lines={6} />;
  return (
    <View style={{ gap: 8 }} testID="audit-tab">
      {rows.length === 0 ? <AppText>{t('auditTab.empty')}</AppText> : null}
      {rows.map((r, n) => (
        <Row key={`${r.at}-${n}`} icon={r.support_session_id ? 'support-agent' : 'history'} title={r.action} testID={`audit-row-${r.action}`}
          subtitle={[format.dateTime(r.at), r.by, r.target, r.reason].filter(Boolean).join(' · ')}
          badge={r.support_session_id ? <Badge label={t('auditTab.support')} tone="warning" /> : undefined} />
      ))}
    </View>
  );
}
