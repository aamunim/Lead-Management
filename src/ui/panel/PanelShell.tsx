import { MaterialIcons } from '@expo/vector-icons';
import { Redirect, router, usePathname } from 'expo-router';
import { useEffect, useState, type ReactNode } from 'react';
import { Pressable, ScrollView, View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { fetchProductConfig } from '@/lib/platform';
import { signOut } from '@/lib/session';
import { Button, EmptyState, Skeleton } from '@/ui/components';
import { useTheme } from '@/ui/theme';
import { MAX_CONTENT_WIDTH } from '@/ui/tokens/layout';

import { PANEL_MENU } from './menu';
import { usePanel } from './PanelContext';

// Panel shell (0B.02-T6): product name, who is signed in, the menu items this platform role may open, and the page.
// Not signed in with the second step → the panel sign-in page.
export function PanelShell({ permission, title, children, testID }: { permission: string; title: string; children: ReactNode; testID?: string }) {
  const { t } = useTranslation('panel');
  const { colors, radius, space, touch } = useTheme();
  const { state, can } = usePanel();
  const path = usePathname();
  const [product, setProduct] = useState<string>('');
  useEffect(() => {
    void fetchProductConfig().then(({ data }) => setProduct(data?.app_name ?? ''));
  }, []);

  if (state.status === 'loading') return <View style={{ flex: 1, padding: space.lg, backgroundColor: colors.background }}><Skeleton lines={3} /></View>;
  if (state.status !== 'ready') return <Redirect href="/panel/sign-in" />;
  const items = PANEL_MENU.filter((i) => can(i.permission));

  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <View style={{ backgroundColor: colors.surfaceContainer, borderBottomWidth: 1, borderBottomColor: colors.outlineVariant }}>
        <View style={{ width: '100%', maxWidth: MAX_CONTENT_WIDTH * 1.4, alignSelf: 'center', padding: space.md, gap: space.sm }}>
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: space.sm, flexWrap: 'wrap' }}>
            <MaterialIcons name="shield" size={24} color={colors.primary} />
            <AppText variant="titleSmall" style={{ flex: 1, minWidth: 160 }} testID="panel-title">{`${product} · ${t('title')}`}</AppText>
            <Button variant="text" icon="logout" label={t('signIn.signOut')} testID="panel-sign-out"
              onPress={() => void signOut().then(() => router.replace('/panel/sign-in'))} />
          </View>
          <AppText variant="caption" style={{ color: colors.onSurfaceVariant }} testID="panel-who">
            {t('dashboard.signedInAs', { email: state.session.email, role: t(`roles.${state.session.platform_role}`) })}
          </AppText>
          <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: space.xs }}>
            {items.map((i) => {
              const on = path === i.href;
              return (
                <Pressable key={i.key} accessibilityRole="link" accessibilityState={{ selected: on }} accessibilityLabel={t(`menu.${i.key}` as 'menu.dashboard')}
                  onPress={() => router.push(i.href)} testID={`panel-menu-${i.key}`}
                  style={{ minHeight: touch, flexDirection: 'row', alignItems: 'center', gap: space.xs, paddingHorizontal: space.md, borderRadius: radius.full,
                    backgroundColor: on ? colors.primaryContainer : 'transparent' }}>
                  <MaterialIcons name={i.icon} size={18} color={on ? colors.onPrimaryContainer : colors.onSurfaceVariant} />
                  <AppText variant="label" style={{ color: on ? colors.onPrimaryContainer : colors.onSurface }}>{t(`menu.${i.key}` as 'menu.dashboard')}</AppText>
                </Pressable>
              );
            })}
          </ScrollView>
        </View>
      </View>
      <ScrollView contentContainerStyle={{ width: '100%', maxWidth: MAX_CONTENT_WIDTH * 1.4, alignSelf: 'center', padding: space.lg, gap: space.md }}
        testID={testID}>
        <AppText variant="headline" accessibilityRole="header" testID={testID ? `${testID}-title` : undefined}>{title}</AppText>
        {state.session.new_device ? (
          <View style={{ padding: space.md, borderRadius: radius.md, backgroundColor: colors.warmContainer }} testID="panel-new-device">
            <AppText style={{ color: colors.onWarmContainer }}>{t('newDevice')}</AppText>
          </View>
        ) : null}
        {can(permission) ? children : <EmptyState icon="lock-outline" title={t('noAccess')} testID="panel-no-access" />}
      </ScrollView>
    </View>
  );
}
