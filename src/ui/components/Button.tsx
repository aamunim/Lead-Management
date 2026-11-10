import { MaterialIcons } from '@expo/vector-icons';
import type { ComponentProps } from 'react';
import { ActivityIndicator, Pressable, StyleSheet, View } from 'react-native';

import { AppText } from '@/components/AppText';

import { useTheme } from '../theme';

export type IconName = ComponentProps<typeof MaterialIcons>['name'];
type Variant = 'filled' | 'tonal' | 'outlined' | 'text' | 'danger';

export type ButtonProps = {
  label: string;
  onPress: () => void;
  variant?: Variant;
  icon?: IconName;
  loading?: boolean;
  disabled?: boolean;
  accessibilityHint?: string;
  fullWidth?: boolean;
  testID?: string;
};

// Button (0A.13): at least 48 dp tall and wide (Ch 47.8), label read by screen readers, busy state while loading
// (a loading button cannot be pressed twice — the first line of double-submit protection, Ch 47.4).
export function Button({ label, onPress, variant = 'filled', icon, loading, disabled, accessibilityHint, fullWidth, testID }: ButtonProps) {
  const { colors, radius, touch, space } = useTheme();
  const palette = {
    filled: { bg: colors.primary, fg: colors.onPrimary, border: colors.primary },
    tonal: { bg: colors.primaryContainer, fg: colors.onPrimaryContainer, border: colors.primaryContainer },
    outlined: { bg: 'transparent', fg: colors.primary, border: colors.outline },
    text: { bg: 'transparent', fg: colors.primary, border: 'transparent' },
    danger: { bg: colors.error, fg: colors.onError, border: colors.error },
  }[variant];
  const inactive = disabled || loading;
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={label}
      accessibilityHint={accessibilityHint}
      accessibilityState={{ disabled: !!disabled, busy: !!loading }}
      disabled={inactive}
      onPress={onPress}
      testID={testID}
      style={({ pressed }) => [
        styles.base,
        { minHeight: touch, minWidth: touch, borderRadius: radius.full, paddingHorizontal: space.xl, backgroundColor: palette.bg,
          borderColor: palette.border, opacity: disabled ? 0.45 : pressed ? 0.85 : 1 },
        fullWidth && styles.full,
      ]}
    >
      <View style={[styles.row, { gap: space.sm }]}>
        {loading ? <ActivityIndicator color={palette.fg} /> : icon ? <MaterialIcons name={icon} size={20} color={palette.fg} /> : null}
        <AppText variant="label" style={{ color: palette.fg, textAlign: 'center' }}>{label}</AppText>
      </View>
    </Pressable>
  );
}

// Icon-only button: `label` is required — it is what a screen reader says (Ch 47.8; the lint also checks it).
export function IconButton({ icon, label, onPress, variant = 'standard', disabled, testID, color }: {
  icon: IconName; label: string; onPress: () => void; variant?: 'standard' | 'tonal' | 'filled'; disabled?: boolean;
  testID?: string; color?: string;
}) {
  const { colors, touch, radius } = useTheme();
  const bg = variant === 'filled' ? colors.primary : variant === 'tonal' ? colors.primaryContainer : 'transparent';
  const fg = color ?? (variant === 'filled' ? colors.onPrimary : variant === 'tonal' ? colors.onPrimaryContainer : colors.onSurfaceVariant);
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={label}
      accessibilityState={{ disabled: !!disabled }}
      disabled={disabled}
      onPress={onPress}
      hitSlop={4}
      testID={testID}
      style={({ pressed }) => [styles.icon, { width: touch, height: touch, borderRadius: radius.full, backgroundColor: bg,
        opacity: disabled ? 0.45 : pressed ? 0.7 : 1 }]}
    >
      <MaterialIcons name={icon} size={24} color={fg} />
    </Pressable>
  );
}

const styles = StyleSheet.create({
  base: { alignItems: 'center', justifyContent: 'center', borderWidth: 1, paddingVertical: 10 },
  row: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', flexShrink: 1 },
  full: { alignSelf: 'stretch' },
  icon: { alignItems: 'center', justifyContent: 'center' },
});
