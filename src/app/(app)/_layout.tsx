import { Stack } from 'expo-router';

import { useIdleSignOut } from '@/lib/idle';
import { useInstitutionDeepLink } from '@/ui/shell/navigation';
import { useTheme } from '@/ui/theme';

// Signed-in area (0A.14): idle sign-out per institution setting, deep links that switch institution first.
export default function SignedInLayout() {
  const { colors } = useTheme();
  useIdleSignOut();
  useInstitutionDeepLink();
  return <Stack screenOptions={{ headerShown: false, contentStyle: { backgroundColor: colors.background } }} />;
}
