import { NotoSansBengali_400Regular, NotoSansBengali_600SemiBold } from '@expo-google-fonts/noto-sans-bengali';
import { useFonts } from 'expo-font';
import { Stack } from 'expo-router';
import { useEffect } from 'react';
import { KeyboardProvider } from 'react-native-keyboard-controller';

import '@/i18n';
import { BANGLA_FONT_FAMILY } from '@/i18n/language';
import { loadLabels } from '@/lib/labels';
import { initLanguage } from '@/lib/language';
import { initLocale } from '@/lib/locale';
import { DialogProvider, SnackbarProvider } from '@/ui/components';
import { initAppearance, ThemeProvider, useTheme } from '@/ui/theme';

// Root layout. Translations are ready on the first render (bundled); language, locale, labels and the appearance
// are resolved right after (device copy first, then the server). Theme and keyboard handling wrap every screen.
export default function RootLayout() {
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
    void initAppearance();
    void initLanguage().catch(() => undefined);
    void initLocale().catch(() => undefined);
    void loadLabels().catch(() => undefined);
  }, []);

  // Wait for the Bangla font so the first Bangla screen never flashes in a fallback font (an error still renders).
  if (!fontsLoaded && !fontError) return null;

  return (
    <KeyboardProvider>
      <ThemeProvider>
        <DialogProvider>
          <SnackbarProvider>
            <Screens />
          </SnackbarProvider>
        </DialogProvider>
      </ThemeProvider>
    </KeyboardProvider>
  );
}

function Screens() {
  const { colors } = useTheme();
  return <Stack screenOptions={{ headerShown: false, contentStyle: { backgroundColor: colors.background } }} />;
}
