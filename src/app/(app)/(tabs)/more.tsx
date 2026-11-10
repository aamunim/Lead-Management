import { MaterialIcons } from '@expo/vector-icons';
import { router, type Href } from 'expo-router';
import { Pressable, View } from 'react-native';

import { AppText } from '@/components/AppText';
import { devToolsEnabled } from '@/dev/flags';
import { useTranslation } from '@/i18n';
import { Screen, type IconName } from '@/ui/components';
import { useTheme } from '@/ui/theme';

// More (placeholder list; the real More menu is built in 1B, Ch 45).
export default function MoreTab() {
  const { t } = useTranslation('shell');
  const { colors, space, radius, touch } = useTheme();
  const items: { href: Href; label: string; icon: IconName; testID: string }[] = [
    { href: '/profile', label: t('more.profile'), icon: 'account-circle', testID: 'more-profile' },
    { href: '/language', label: t('more.language'), icon: 'translate', testID: 'more-language' },
    { href: '/appearance', label: t('more.appearance'), icon: 'dark-mode', testID: 'more-appearance' },
    { href: '/terminology', label: t('more.words'), icon: 'menu-book', testID: 'more-words' },
    { href: '/samples', label: t('more.samples'), icon: 'calculate', testID: 'more-samples' },
    ...(devToolsEnabled ? [{ href: '/dev/gallery' as Href, label: t('more.gallery'), icon: 'widgets' as IconName, testID: 'more-gallery' }] : []),
  ];
  return (
    <Screen title={t('more.title')} testID="more">
      <View style={{ gap: space.sm }}>
        {items.map((item) => (
          <Pressable key={item.testID} accessibilityRole="link" accessibilityLabel={item.label} onPress={() => router.push(item.href)}
            testID={item.testID}
            style={({ pressed }) => ({ minHeight: touch, flexDirection: 'row', alignItems: 'center', gap: space.md, paddingHorizontal: space.lg,
              paddingVertical: space.sm, borderRadius: radius.md, backgroundColor: pressed ? colors.surfaceContainerHigh : colors.surfaceContainerLow })}>
            <MaterialIcons name={item.icon} size={24} color={colors.onSurfaceVariant} />
            <AppText style={{ flex: 1 }}>{item.label}</AppText>
            <MaterialIcons name="chevron-right" size={24} color={colors.onSurfaceVariant} />
          </Pressable>
        ))}
      </View>
    </Screen>
  );
}
