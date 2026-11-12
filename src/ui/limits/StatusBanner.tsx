import { useEffect, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { fetchOwnStatus, type OwnStatus } from '@/lib/lifecycle';
import { useTheme } from '@/ui/theme';

// Institution status banner (0B.07-T4): waiting for approval, trial days left (last 7 days), read only. A suspended or
// closed institution cannot be opened at all (the server refuses), so it has no banner here.
export function StatusBanner() {
  const { t } = useTranslation('admin');
  const { colors, radius, space } = useTheme();
  const [s, setS] = useState<OwnStatus | null>(null);
  useEffect(() => {
    void fetchOwnStatus().then((r) => setS(r.data));
  }, []);
  if (!s) return null;
  const text = s.status === 'pending' ? t('lifecycle.pending')
    : s.status === 'read_only' ? t('lifecycle.readOnly')
      : s.status === 'trial' && s.days_left !== null && s.days_left <= 7 ? t('lifecycle.trialEnds', { count: s.days_left })
        : null;
  if (!text) return null;
  const strong = s.status === 'read_only';
  return (
    <View testID={`status-banner-${s.status}`} style={{ padding: space.md, borderRadius: radius.md,
      backgroundColor: strong ? colors.errorContainer : colors.warmContainer }}>
      <AppText style={{ color: strong ? colors.onErrorContainer : colors.onWarmContainer }}>{text}</AppText>
    </View>
  );
}
