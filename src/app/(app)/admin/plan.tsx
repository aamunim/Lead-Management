import { useCallback, useEffect, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { useLanguageState } from '@/lib/language';
import { useFormat } from '@/lib/locale';
import { fetchLimits, fetchModules, type LimitsStatus, type ModuleState } from '@/lib/modules';
import { pick } from '@/lib/packs';
import { Badge, Section, tDynamic } from '@/ui/admin/parts';
import { ErrorState, Screen, Skeleton } from '@/ui/components';
import { moduleName } from '@/ui/limits/names';
import { AppHeader } from '@/ui/shell/AppHeader';
import { useTheme } from '@/ui/theme';

// Settings → Plan and usage (0B.05, billing.view): the plan, its end date, each limit with how much is used (80 %
// warns, 100 % blocks), and the modules the plan includes. Changing the plan is done by the platform (billing comes
// with 0B.16).
export default function PlanScreen() {
  const { t } = useTranslation('admin');
  const { language } = useLanguageState();
  const format = useFormat();
  const { colors, radius, space } = useTheme();
  const [status, setStatus] = useState<LimitsStatus | null>(null);
  const [mods, setMods] = useState<ModuleState[]>([]);
  const [error, setError] = useState<unknown>(null);

  const load = useCallback(async () => {
    setError(null);
    const [r, m] = await Promise.all([fetchLimits(), fetchModules()]);
    if (r.error) return setError(r.error);
    setStatus(r.data);
    setMods(m.data ?? []);
  }, []);
  useEffect(() => {
    void load();
  }, [load]);

  const tone = { ok: colors.primary, warning: colors.warm, full: colors.error, blocked: colors.error };
  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <AppHeader back />
      <Screen title={t('plan.title')} testID="plan">
        {error ? <ErrorState error={error} onRetry={() => void load()} testID="plan-error" /> : !status ? <Skeleton lines={8} testID="plan-loading" /> : (
          <>
            <View style={{ gap: space.xs }}>
              <AppText variant="title" testID="plan-name">{status.plan ? pick(status.plan.name, language) : ''}</AppText>
              <AppText style={{ color: colors.onSurfaceVariant }} testID="plan-expiry">
                {status.plan?.expires_at ? t('plan.expires', { date: format.date(status.plan.expires_at.slice(0, 10)) }) : t('plan.noExpiry')}
              </AppText>
              <AppText variant="caption">{t('plan.howToUpgrade')}</AppText>
            </View>
            <Section title={t('plan.usage')} testID="plan-usage">
              {status.metrics.map((m) => {
                const share = m.limit ? Math.min(1, (m.used ?? 0) / m.limit) : 0;
                return (
                  <View key={m.metric} style={{ gap: 4 }} testID={`usage-${m.metric}`}>
                    <View style={{ flexDirection: 'row', justifyContent: 'space-between', gap: space.sm, flexWrap: 'wrap' }}>
                      <AppText>{tDynamic(`admin:limits.metrics.${m.metric}`)}</AppText>
                      <AppText variant="caption">{m.limit === null ? t('plan.unlimited', { used: format.number(m.used ?? 0) })
                        : t('plan.usedOf', { used: format.number(m.used ?? 0), limit: format.number(m.limit) })}</AppText>
                    </View>
                    {m.limit !== null ? (
                      <View style={{ height: 8, borderRadius: radius.full, backgroundColor: colors.surfaceContainerHigh, overflow: 'hidden' }}
                        accessibilityRole="progressbar" accessibilityValue={{ min: 0, max: 100, now: Math.round(share * 100) }}>
                        <View style={{ width: `${share * 100}%`, height: '100%', backgroundColor: tone[m.level] }} />
                      </View>
                    ) : null}
                    {m.level !== 'ok' ? <Badge label={t(`plan.level.${m.level}`)} tone={m.level === 'warning' ? 'warning' : 'error'} /> : null}
                  </View>
                );
              })}
            </Section>
            <Section title={t('plan.modules')} testID="plan-modules">
              <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: space.sm }}>
                {mods.filter((m) => m.allowed && m.in_industry).map((m) => <Badge key={m.key} label={moduleName(m)} tone={m.enabled ? 'primary' : 'neutral'} />)}
              </View>
            </Section>
          </>
        )}
      </Screen>
    </View>
  );
}
