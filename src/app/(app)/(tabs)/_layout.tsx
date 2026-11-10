import { MaterialIcons } from '@expo/vector-icons';
import type { ColorValue } from 'react-native';
import { Tabs } from 'expo-router/js-tabs';

import { useTranslation } from '@/i18n';
import { AppHeader } from '@/ui/shell/AppHeader';
import { useTheme } from '@/ui/theme';

// Bottom tabs (0A.14-T1): placeholders now; real Home, Leads and More content comes in 1A/1B (Ch 45).
// Back on another tab goes to Home first; on Home it asks before leaving (useConfirmExitOnBack).
export default function TabsLayout() {
  const { t } = useTranslation('shell');
  const { colors, type } = useTheme();
  const icon = (name: 'home' | 'menu' | 'settings') => ({ color, size }: { color: ColorValue; size: number }) =>
    <MaterialIcons name={name} color={color as string} size={size} />;
  return (
    <Tabs
      backBehavior="firstRoute"
      screenOptions={{
        header: () => <AppHeader />,
        tabBarActiveTintColor: colors.primary,
        tabBarInactiveTintColor: colors.onSurfaceVariant,
        tabBarStyle: { backgroundColor: colors.surfaceContainer, borderTopColor: colors.outlineVariant, minHeight: 64 },
        tabBarLabelStyle: type.caption,
        sceneStyle: { backgroundColor: colors.background },
      }}
    >
      <Tabs.Screen name="home" options={{ title: t('tabs.home'), tabBarIcon: icon('home'), tabBarButtonTestID: 'tab-home' }} />
      <Tabs.Screen name="more" options={{ title: t('tabs.more'), tabBarIcon: icon('menu'), tabBarButtonTestID: 'tab-more' }} />
      <Tabs.Screen name="settings" options={{ title: t('tabs.settings'), tabBarIcon: icon('settings'), tabBarButtonTestID: 'tab-settings' }} />
    </Tabs>
  );
}
