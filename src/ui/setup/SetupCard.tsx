import { router } from 'expo-router';
import { useEffect, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { useMyAccess } from '@/lib/access';
import { fetchChecklist, type Checklist } from '@/lib/setup';
import { Button } from '@/ui/components';
import { useTheme } from '@/ui/theme';

import { ChecklistProgress } from './ChecklistView';

// Home card (0B.10-T3, placeholder until the real Home in 1B): setup progress for people with a settings permission,
// until everything available is done.
export function SetupCard() {
  const { t } = useTranslation('admin');
  const { colors, radius, space } = useTheme();
  const { access } = useMyAccess();
  const allowed = Object.keys(access?.permissions ?? {}).some((k) => k === '*' || k.startsWith('settings.'));
  const [list, setList] = useState<Checklist | null>(null);
  useEffect(() => {
    if (allowed) void fetchChecklist().then((r) => setList(r.data));
  }, [allowed]);
  if (!allowed || !list || list.percent >= 100) return null;
  return (
    <View style={{ gap: space.sm, padding: space.md, borderRadius: radius.md, backgroundColor: colors.surfaceContainerLow }} testID="home-setup-card">
      <AppText variant="titleSmall">{t('checklist.cardTitle')}</AppText>
      <ChecklistProgress list={list} />
      <Button variant="tonal" icon="checklist" label={t('checklist.open')} onPress={() => router.push('/admin/checklist')} testID="home-setup-open" />
    </View>
  );
}
