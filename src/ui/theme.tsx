import AsyncStorage from '@react-native-async-storage/async-storage';
import { DarkTheme, DefaultTheme, ThemeProvider as NavigationThemeProvider } from 'expo-router';
import * as SystemUI from 'expo-system-ui';
import { createContext, useContext, useEffect, useMemo, useSyncExternalStore, type ReactNode } from 'react';
import { useColorScheme, useWindowDimensions } from 'react-native';

import { useLanguageState } from '@/lib/language';
import { useSetting } from '@/lib/settings';

import { colorRoles, DEFAULT_BRAND, type ColorRoles } from './tokens/color';
import { radius, space, TOUCH } from './tokens/layout';
import { typeScale, type TextStyleToken, type TypeRole } from './tokens/type';

// Theme (0A.13-T1): light / dark / brand tokens for every screen. The appearance (System / Light / Dark) switches
// instantly, without a restart (the old app restarted, Ch 47.2). The institution's brand colour comes from the
// branding settings (0B, Ch 6); until then the platform blue. Colours are checked for contrast (tokens/color.ts).

export type Appearance = 'system' | 'light' | 'dark';
type Overrides = { appearance: Appearance; brand: string | null; fontScale: number | null };

const STORAGE_KEY = 'appearance';
let overrides: Overrides = { appearance: 'system', brand: null, fontScale: null };
const subscribers = new Set<() => void>();
const publish = (next: Overrides) => {
  overrides = next;
  for (const notify of subscribers) notify();
};

export async function initAppearance(): Promise<void> {
  try {
    const saved = await AsyncStorage.getItem(STORAGE_KEY);
    if (saved === 'light' || saved === 'dark' || saved === 'system') publish({ ...overrides, appearance: saved });
  } catch {
    // a device preference only
  }
}

export async function setAppearance(appearance: Appearance): Promise<void> {
  publish({ ...overrides, appearance });
  try {
    await AsyncStorage.setItem(STORAGE_KEY, appearance);
  } catch {
    // ignore
  }
}

/** Developer previews only (component gallery, screenshot tests): another brand colour or font size. */
export function setThemePreview(preview: { brand?: string | null; fontScale?: number | null }): void {
  publish({ ...overrides, ...preview });
}

export type Theme = {
  mode: 'light' | 'dark';
  appearance: Appearance;
  colors: ColorRoles;
  type: Record<TypeRole, TextStyleToken>;
  space: typeof space;
  radius: typeof radius;
  touch: number;
  fontScale: number;
};

const ThemeContext = createContext<Theme | null>(null);

export function ThemeProvider({ children }: { children: ReactNode }) {
  const current = useSyncExternalStore(
    (notify) => {
      subscribers.add(notify);
      return () => subscribers.delete(notify);
    },
    () => overrides,
  );
  const system = useColorScheme();
  const { fontScale: deviceFontScale } = useWindowDimensions();
  const { language } = useLanguageState();
  const institutionBrand = useSetting<string>('brand_color', DEFAULT_BRAND);
  const mode = current.appearance === 'system' ? (system === 'dark' ? 'dark' : 'light') : current.appearance;
  const fontScale = current.fontScale ?? deviceFontScale ?? 1;
  const brand = current.brand ?? institutionBrand;

  const theme = useMemo<Theme>(() => ({
    mode, appearance: current.appearance, colors: colorRoles(brand, mode), type: typeScale(language, fontScale),
    space, radius, touch: TOUCH, fontScale,
  }), [mode, current.appearance, brand, language, fontScale]);

  useEffect(() => {
    void SystemUI.setBackgroundColorAsync(theme.colors.background).catch(() => undefined);
  }, [theme.colors.background]);

  const base = mode === 'dark' ? DarkTheme : DefaultTheme;
  const navigationTheme = useMemo(() => ({
    ...base,
    colors: { ...base.colors, primary: theme.colors.primary, background: theme.colors.background, card: theme.colors.surface,
      text: theme.colors.onSurface, border: theme.colors.outlineVariant, notification: theme.colors.error },
  }), [base, theme]);

  return (
    <ThemeContext.Provider value={theme}>
      <NavigationThemeProvider value={navigationTheme}>{children}</NavigationThemeProvider>
    </ThemeContext.Provider>
  );
}

export function useTheme(): Theme {
  const theme = useContext(ThemeContext);
  if (!theme) throw new Error('useTheme() outside ThemeProvider');
  return theme;
}
