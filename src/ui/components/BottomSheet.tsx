import type { ReactNode } from 'react';
import { Modal, Pressable, StyleSheet, View } from 'react-native';
import { KeyboardAwareScrollView } from 'react-native-keyboard-controller';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';

import { useTheme } from '../theme';

import { IconButton } from './Button';

// Bottom sheet (0A.13-T4): its content scrolls so the focused field stays above the keyboard (Ch 47.3);
// Android Back or a tap on the dimmed area closes it; an optional footer (e.g. Save) stays visible.
export function BottomSheet({ visible, onClose, title, children, footer, testID }: {
  visible: boolean; onClose: () => void; title: string; children: ReactNode; footer?: ReactNode; testID?: string;
}) {
  const { colors, radius, space } = useTheme();
  const { t } = useTranslation('ui');
  const insets = useSafeAreaInsets();
  return (
    <Modal visible={visible} transparent animationType="slide" onRequestClose={onClose} statusBarTranslucent navigationBarTranslucent>
      <View style={styles.root}>
        <Pressable style={[StyleSheet.absoluteFill, { backgroundColor: `${colors.scrim}66` }]} onPress={onClose}
          accessibilityRole="button" accessibilityLabel={t('actions.close')} />
        <View style={[styles.sheet, { backgroundColor: colors.surfaceContainerLow, borderTopLeftRadius: radius.xl, borderTopRightRadius: radius.xl,
          paddingBottom: insets.bottom + space.md }]} accessibilityViewIsModal testID={testID}>
          <View style={[styles.handle, { backgroundColor: colors.outlineVariant }]} accessibilityLabel={t('sheet.handle')} />
          <View style={[styles.header, { paddingHorizontal: space.lg }]}>
            <AppText variant="title" style={styles.title}>{title}</AppText>
            <IconButton icon="close" label={t('actions.close')} onPress={onClose} testID={testID ? `${testID}-close` : undefined} />
          </View>
          <KeyboardAwareScrollView bottomOffset={footer ? 96 : 24} keyboardShouldPersistTaps="handled" keyboardDismissMode="on-drag"
            contentContainerStyle={{ padding: space.lg, gap: space.lg }}>
            {children}
          </KeyboardAwareScrollView>
          {footer ? <View style={{ paddingHorizontal: space.lg, paddingTop: space.sm }}>{footer}</View> : null}
        </View>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, justifyContent: 'flex-end' },
  sheet: { maxHeight: '90%', width: '100%', maxWidth: 640, alignSelf: 'center' },
  handle: { width: 32, height: 4, borderRadius: 2, alignSelf: 'center', marginTop: 12 },
  header: { flexDirection: 'row', alignItems: 'center' },
  title: { flex: 1 },
});
