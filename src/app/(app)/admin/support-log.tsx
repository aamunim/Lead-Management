import { useCallback, useEffect, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { useFormat } from '@/lib/locale';
import { fetchSupportLog, type SupportLogRow } from '@/lib/support';
import { Badge, Section, tDynamic } from '@/ui/admin/parts';
import { EmptyState, ErrorState, Screen, Skeleton } from '@/ui/components';
import { AppHeader } from '@/ui/shell/AppHeader';
import { useTheme } from '@/ui/theme';

// Settings → Support access (0B.08-T5, Ch 5.5): every time platform staff entered this institution — who, when, why,
// for how long, read only or edit, and what they did. Visible to the institution by rule (Ch 5.17 row 3).
export default function SupportLogScreen() {
  const { t } = useTranslation('admin');
  const format = useFormat();
  const { colors, space } = useTheme();
  const [rows, setRows] = useState<SupportLogRow[] | null>(null);
  const [error, setError] = useState<unknown>(null);
  const load = useCallback(async () => {
    setError(null);
    const r = await fetchSupportLog();
    if (r.error) setError(r.error);
    else setRows(r.data ?? []);
  }, []);
  useEffect(() => {
    void load();
  }, [load]);
  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <AppHeader back />
      <Screen title={t('supportLog.title')} intro={t('supportLog.intro')} testID="support-log">
        {error ? <ErrorState error={error} onRetry={() => void load()} testID="support-log-error" /> : !rows ? <Skeleton lines={4} testID="support-log-loading" />
          : rows.length === 0 ? <EmptyState icon="verified-user" title={t('supportLog.empty')} testID="support-log-empty" /> : rows.map((r) => (
            <Section key={r.id} title={t('supportLog.entry', { by: r.by, date: format.dateTime(r.started_at) })} testID={`support-entry-${r.id}`}>
              <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: space.sm }}>
                <Badge label={r.mode === 'edit' ? t('supportLog.edit') : t('supportLog.readOnly')} tone={r.mode === 'edit' ? 'error' : 'neutral'} />
                <Badge label={r.ended_at ? t('supportLog.ended', { date: format.dateTime(r.ended_at) }) : t('supportLog.until', { date: format.dateTime(r.expires_at) })} />
              </View>
              <AppText>{t('supportLog.reason', { reason: r.reason })}</AppText>
              {r.edit_reason ? <AppText>{t('supportLog.editReason', { reason: r.edit_reason })}</AppText> : null}
              <AppText variant="caption">{t('supportLog.writes', { count: r.writes })}</AppText>
              {r.actions.map((a, n) => (
                <AppText key={`${a.at}-${n}`} variant="caption">{`${format.dateTime(a.at)} · ${tDynamic(`admin:supportLog.actions.${a.action}`)}`}</AppText>
              ))}
            </Section>
          ))}
      </Screen>
    </View>
  );
}
