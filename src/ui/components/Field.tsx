import type { ReactNode } from 'react';
import { StyleSheet, View } from 'react-native';

import { AppText } from '@/components/AppText';
import { fontFamilyFor } from '@/i18n/language';
import { useLanguageState } from '@/lib/language';

import { useTheme } from '../theme';

// Label above, help or error below (in plain words, right under the field, Ch 47.4). Errors are announced.
export function Field({ label, required, help, error, children, testID }: {
  label: string; required?: boolean; help?: string; error?: string | null; children: ReactNode; testID?: string;
}) {
  const { colors, space } = useTheme();
  return (
    <View style={{ gap: space.xs }} testID={testID}>
      <AppText variant="label" style={{ color: colors.onSurface }}>{required ? `${label} *` : label}</AppText>
      {children}
      {error ? (
        <AppText variant="caption" style={{ color: colors.error }} accessibilityLiveRegion="polite" accessibilityRole="alert"
          testID={testID ? `${testID}-error` : undefined}>{error}</AppText>
      ) : help ? (
        <AppText variant="caption" style={{ color: colors.onSurfaceVariant }}>{help}</AppText>
      ) : null}
    </View>
  );
}

/** Style of a text input box: theme colours, the language's font and line height, grows with the font size. */
export function useInputStyle(hasError = false) {
  const { colors, type, radius, touch, space } = useTheme();
  const { language } = useLanguageState();
  const fontFamily = fontFamilyFor(language);
  return [
    styles.input,
    { minHeight: touch, borderRadius: radius.sm, paddingHorizontal: space.md, paddingVertical: space.sm, color: colors.onSurface,
      backgroundColor: colors.surfaceContainerLow, borderColor: hasError ? colors.error : colors.outline,
      fontSize: type.body.fontSize, lineHeight: type.body.lineHeight },
    fontFamily ? { fontFamily } : null,
  ];
}

// minWidth 0: a web input has an intrinsic width and would not shrink inside a row (it overflowed at large font sizes).
const styles = StyleSheet.create({ input: { borderWidth: 1, minWidth: 0, maxWidth: '100%' } });
