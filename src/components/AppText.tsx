import { Text, type TextProps } from 'react-native';

import { useTheme } from '@/ui/theme';
import type { TypeRole } from '@/ui/tokens/type';

// Text in the current language's font and a line height that never clips Bangla vowel signs (0A.10, 0A.13-T3).
// Use this (or the components in '@/ui') instead of React Native's Text. `variant` picks a typography token.
export function AppText({ style, variant = 'body', ...props }: TextProps & { variant?: TypeRole }) {
  const { colors, type } = useTheme();
  return <Text {...props} style={[{ color: colors.onSurface }, type[variant], style]} />;
}
