import { NotoSansBengali_400Regular, NotoSansBengali_600SemiBold } from '@expo-google-fonts/noto-sans-bengali';
import { useFonts } from 'expo-font';
import { DarkTheme, DefaultTheme, Stack, ThemeProvider } from 'expo-router';
import { useEffect } from 'react';
import { useColorScheme } from 'react-native';

import '@/i18n';
import { BANGLA_FONT_FAMILY } from '@/i18n/language';
import { loadLabels } from '@/lib/labels';
import { initLanguage } from '@/lib/language';
import { initLocale } from '@/lib/locale';

// Root layout. Translations are ready on the first render (bundled); the language is resolved right after
// (device copy first, then the server). The rest of the shell (labels, theme) arrives in 0A.12–0A.14.
export default function RootLayout() {
  const colorScheme = useColorScheme();
  const [fontsLoaded, fontError] = useFonts([
    {
      fontFamily: BANGLA_FONT_FAMILY,
      fontDefinitions: [
        { path: NotoSansBengali_400Regular, weight: 400 },
        { path: NotoSansBengali_600SemiBold, weight: 600 },
      ],
    },
  ]);

  useEffect(() => {
    void initLanguage().catch(() => undefined);
    void initLocale().catch(() => undefined);
    void loadLabels().catch(() => undefined);
  }, []);

  // Wait for the Bangla font so the first Bangla screen never flashes in a fallback font (an error still renders).
  if (!fontsLoaded && !fontError) return null;

  return (
    <ThemeProvider value={colorScheme === 'dark' ? DarkTheme : DefaultTheme}>
      <Stack screenOptions={{ headerShown: false }} />
    </ThemeProvider>
  );
}
