import type { ReactNode } from 'react';
import { ScrollView, StyleSheet } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { AppText } from '@/components/AppText';

import { useTheme } from '../theme';
import { MAX_CONTENT_WIDTH } from '../tokens/layout';

// A simple scrolling screen: safe areas (notch, camera hole, gesture bar; Android edge-to-edge), readable width on
// tablets and the web, a header for screen readers. Forms use FormScreen instead.
export function Screen({ title, intro, children, testID }: { title: string; intro?: string; children: ReactNode; testID?: string }) {
  const { colors, space } = useTheme();
  const insets = useSafeAreaInsets();
  return (
    <ScrollView style={{ backgroundColor: colors.background }} keyboardShouldPersistTaps="handled" keyboardDismissMode="on-drag"
      contentContainerStyle={[styles.content, { padding: space.lg, gap: space.md, paddingTop: insets.top + space.lg,
        paddingBottom: insets.bottom + space.xxl }]} testID={testID}>
      <AppText variant="headline" accessibilityRole="header" testID={testID ? `${testID}-title` : undefined}>{title}</AppText>
      {intro ? <AppText style={{ color: colors.onSurfaceVariant }}>{intro}</AppText> : null}
      {children}
    </ScrollView>
  );
}

const styles = StyleSheet.create({ content: { maxWidth: MAX_CONTENT_WIDTH, width: '100%', alignSelf: 'center' } });
