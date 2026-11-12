import { Stack } from 'expo-router';
import { View } from 'react-native';

import { useIdleSignOut } from '@/lib/idle';
import { useInstitutionDeepLink } from '@/ui/shell/navigation';
import { SupportBanner } from '@/ui/shell/SupportBanner';
import { useTheme } from '@/ui/theme';

// Signed-in area (0A.14): idle sign-out per institution setting, deep links that switch institution first; the support
// banner while a platform user is inside the institution (0B.08).
export default function SignedInLayout() {
  const { colors } = useTheme();
  useIdleSignOut();
  useInstitutionDeepLink();
  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <SupportBanner />
      <View style={{ flex: 1 }}>
        <Stack screenOptions={{ headerShown: false, contentStyle: { backgroundColor: colors.background } }} />
      </View>
    </View>
  );
}
