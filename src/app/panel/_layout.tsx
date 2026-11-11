import { Stack } from 'expo-router';

import { PanelProvider } from '@/ui/panel/PanelContext';
import { useTheme } from '@/ui/theme';

// The Master Admin panel (0B.02): its own sign-in page and screens, separate from the staff app.
export default function PanelLayout() {
  const { colors } = useTheme();
  return (
    <PanelProvider>
      <Stack screenOptions={{ headerShown: false, contentStyle: { backgroundColor: colors.background } }} />
    </PanelProvider>
  );
}
