import { NotoSansBengali_400Regular, NotoSansBengali_600SemiBold } from '@expo-google-fonts/noto-sans-bengali';
import { useFonts } from 'expo-font';
import { Stack } from 'expo-router';
import { useEffect } from 'react';
import { View } from 'react-native';
import { KeyboardProvider } from 'react-native-keyboard-controller';

import '@/i18n';
import { BANGLA_FONT_FAMILY } from '@/i18n/language';
import { useAppLock } from '@/lib/app-lock';
import { useUpgradeRequired } from '@/lib/app-status';
import { useAuthState } from '@/lib/auth-state';
import { reportActivity } from '@/lib/idle';
import { loadLabels } from '@/lib/labels';
import { initLanguage } from '@/lib/language';
import { initLocale } from '@/lib/locale';
import { loadSettings } from '@/lib/settings';
import { DialogProvider, SnackbarProvider } from '@/ui/components';
import { LockScreen } from '@/ui/shell/LockScreen';
import { NetworkBanner } from '@/ui/shell/NetworkBanner';
import { UpgradeScreen } from '@/ui/shell/UpgradeScreen';
import { initAppearance, ThemeProvider, useTheme } from '@/ui/theme';

// Root layout (0A.14). Providers, then the guards: the app group needs a session, the sign-in screen needs none.
// Over everything: the offline strip, "please update" (blocks), and the app lock (blocks; nothing renders behind it).
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
    void loadSettings().catch(() => undefined);
    void loadLabels().catch(() => undefined);
  }, []);

  // Wait for the Bangla font so the first Bangla screen never flashes in a fallback font (an error still renders).
  if (!fontsLoaded && !fontError) return null;

  return (
    <KeyboardProvider>
      <ThemeProvider>
        <DialogProvider>
          <SnackbarProvider>
            <Shell />
          </SnackbarProvider>
        </DialogProvider>
      </ThemeProvider>
    </KeyboardProvider>
  );
}

function Shell() {
  const { colors } = useTheme();
  const auth = useAuthState();
  const upgrade = useUpgradeRequired();
  const lock = useAppLock();
  if (upgrade) return <UpgradeScreen />;
  if (auth.status === 'loading') return <View style={{ flex: 1, backgroundColor: colors.background }} />;
  const signedIn = auth.status === 'signedIn';
  if (signedIn && lock.locked) return <LockScreen />;
  return (
    <View style={{ flex: 1, backgroundColor: colors.background }} onTouchStartCapture={reportActivity}>
      <NetworkBanner />
      <Stack screenOptions={{ headerShown: false, contentStyle: { backgroundColor: colors.background } }}>
        <Stack.Protected guard={signedIn}>
          <Stack.Screen name="(app)" />
        </Stack.Protected>
        <Stack.Protected guard={!signedIn}>
          <Stack.Screen name="sign-in" />
        </Stack.Protected>
      </Stack>
    </View>
  );
}
