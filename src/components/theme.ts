import { useTheme } from '@/ui/theme';

// Compatibility for screens written before the design system (0A.10–0A.12): the same names, now taken from the
// theme tokens (light / dark / brand). New code uses useTheme() from '@/ui/theme' and the components in '@/ui'.
export function useColors() {
  const { colors } = useTheme();
  return {
    text: colors.onSurface, muted: colors.onSurfaceVariant, border: colors.outline, surface: colors.surfaceContainerLow,
    accent: colors.primary, accentText: colors.onPrimary, danger: colors.error, background: colors.background,
  };
}
export type Colors = ReturnType<typeof useColors>;
