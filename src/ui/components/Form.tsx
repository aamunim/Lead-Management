import type { ReactNode } from 'react';
import { StyleSheet, View } from 'react-native';
import { KeyboardAwareScrollView, KeyboardStickyView } from 'react-native-keyboard-controller';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';

import { useTheme } from '../theme';
import { MAX_CONTENT_WIDTH } from '../tokens/layout';

import { Button } from './Button';
import { useUnsavedChangesPrompt } from './form-hooks';

// Form screen (0A.13-T4/T5, Ch 47.3–47.4):
// - the focused field scrolls above the keyboard; scrolling or tapping outside a field closes the keyboard;
// - the Save bar sticks to the top of the keyboard, so Save is always visible on long forms;
// - Back asks before discarding unsaved changes (`dirty`);
// - Save shows a busy state and cannot be pressed twice (pair with useSubmit for the idempotency key).
export function FormScreen({ title, children, onSave, saving, dirty, saveLabel, notice, testID }: {
  title: string; children: ReactNode; onSave: () => void; saving?: boolean; dirty?: boolean; saveLabel?: string;
  notice?: string | null; testID?: string;
}) {
  const { colors, space } = useTheme();
  const { t } = useTranslation('ui');
  const insets = useSafeAreaInsets();
  useUnsavedChangesPrompt(!!dirty && !saving);
  return (
    <View style={[styles.root, { backgroundColor: colors.background }]} testID={testID}>
      <KeyboardAwareScrollView
        bottomOffset={96}
        keyboardShouldPersistTaps="handled"
        keyboardDismissMode="on-drag"
        contentContainerStyle={[styles.content, { padding: space.lg, gap: space.lg, paddingTop: insets.top + space.lg, paddingBottom: 120 }]}
      >
        <AppText variant="headline" accessibilityRole="header">{title}</AppText>
        {notice ? (
          <AppText style={{ color: colors.onSurfaceVariant }} accessibilityLiveRegion="polite" testID={testID ? `${testID}-notice` : undefined}>{notice}</AppText>
        ) : null}
        {children}
      </KeyboardAwareScrollView>
      <KeyboardStickyView offset={{ closed: 0, opened: insets.bottom }}>
        <View style={[styles.bar, { backgroundColor: colors.surfaceContainer, borderTopColor: colors.outlineVariant, padding: space.md,
          paddingBottom: insets.bottom + space.md }]}>
          <Button label={saving ? t('form.saving') : (saveLabel ?? t('actions.save'))} onPress={onSave} loading={saving}
            fullWidth testID={testID ? `${testID}-save` : undefined} />
        </View>
      </KeyboardStickyView>
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
  content: { maxWidth: MAX_CONTENT_WIDTH, width: '100%', alignSelf: 'center' },
  bar: { borderTopWidth: StyleSheet.hairlineWidth, alignItems: 'stretch' },
});
