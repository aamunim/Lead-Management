import { router } from 'expo-router';
import { useEffect, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { useMyAccess } from '@/lib/access';
import { fetchLimits, type LimitsStatus } from '@/lib/modules';
import { tDynamic } from '@/ui/admin/parts';
import { Button } from '@/ui/components';
import { useTheme } from '@/ui/theme';

// Limit banner (0B.05-T8, Ch 9.5): a limit at 80 % or more is shown on Home. People who can see the plan get the
// numbers and "Upgrade"; everyone else is told to tell their Admin. The server blocks at 100 % on its own.
export function LimitBanner() {
  const { t } = useTranslation('admin');
  const { colors, radius, space } = useTheme();
  const { can } = useMyAccess();
  const [status, setStatus] = useState<LimitsStatus | null>(null);
  useEffect(() => {
    void fetchLimits().then((r) => setStatus(r.data));
  }, []);
  const hot = (status?.metrics ?? []).filter((m) => m.level !== 'ok');
  if (!hot.length) return null;
  const blocked = hot.some((m) => m.level === 'blocked' || m.level === 'full');
  const billing = can('billing.view');
  return (
    <View testID="limit-banner" style={{ gap: space.sm, padding: space.md, borderRadius: radius.md,
      backgroundColor: blocked ? colors.errorContainer : colors.warmContainer }}>
      <AppText variant="titleSmall" style={{ color: blocked ? colors.onErrorContainer : colors.onWarmContainer }}>
        {blocked ? t('limits.fullTitle') : t('limits.warningTitle')}
      </AppText>
      {hot.map((m) => (
        <AppText key={m.metric} style={{ color: blocked ? colors.onErrorContainer : colors.onWarmContainer }} testID={`limit-${m.metric}`}>
          {billing && m.limit !== null
            ? t('limits.line', { name: tDynamic(`admin:limits.metrics.${m.metric}`), used: m.used ?? 0, limit: m.limit })
            : tDynamic(`admin:limits.metrics.${m.metric}`)}
        </AppText>
      ))}
      {billing ? <Button variant="tonal" icon="upgrade" label={t('limits.upgrade')} onPress={() => router.push('/admin/plan')} testID="limit-upgrade" />
        : <AppText variant="caption" style={{ color: blocked ? colors.onErrorContainer : colors.onWarmContainer }}>{t('limits.tellAdmin')}</AppText>}
    </View>
  );
}
