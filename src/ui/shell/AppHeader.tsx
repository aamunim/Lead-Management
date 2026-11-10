import Constants from 'expo-constants';
import { router } from 'expo-router';
import { StyleSheet, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { useActiveInstitution } from '@/lib/institution';

import { IconButton } from '../components/Button';
import { useTheme } from '../theme';
import { MAX_CONTENT_WIDTH } from '../tokens/layout';

// Top bar (0A.14-T1, Ch 4.5): after sign-in the institution's name and mark (its colour; the logo comes with 0B
// branding); before sign-in the neutral product name. The brand colour is an accent stripe, never the text colour.
export function AppHeader({ signedIn = true, back = false }: { signedIn?: boolean; back?: boolean }) {
  const { colors, space, radius } = useTheme();
  const { t } = useTranslation('shell');
  const insets = useSafeAreaInsets();
  const institution = useActiveInstitution();
  const productName = Constants.expoConfig?.name ?? '';
  const title = signedIn ? (institution?.name ?? t('header.noInstitution')) : productName;
  const mark = (signedIn ? (institution?.shortName ?? institution?.name ?? '') : productName).slice(0, 3).toUpperCase();
  return (
    <View style={{ backgroundColor: colors.surfaceContainer, paddingTop: insets.top, borderBottomWidth: 3, borderBottomColor: colors.accent }}
      testID="app-header">
      <View style={[styles.row, { paddingHorizontal: space.lg, paddingVertical: space.sm, gap: space.md }]}>
        {back ? (
          <IconButton icon="arrow-back" label={t('header.back')} onPress={() => (router.canGoBack() ? router.back() : router.replace('/home'))} testID="header-back" />
        ) : null}
        <View style={[styles.mark, { backgroundColor: colors.primary, borderRadius: radius.sm }]} accessibilityElementsHidden importantForAccessibility="no">
          <AppText variant="label" style={{ color: colors.onPrimary }}>{mark}</AppText>
        </View>
        <AppText variant="titleSmall" style={styles.title} numberOfLines={2} accessibilityRole="header" testID="app-header-title">{title}</AppText>
        {signedIn && !back ? <IconButton icon="account-circle" label={t('header.profile')} onPress={() => router.push('/profile')} testID="open-profile" /> : null}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  row: { flexDirection: 'row', alignItems: 'center', maxWidth: MAX_CONTENT_WIDTH, width: '100%', alignSelf: 'center', minHeight: 56 },
  mark: { minWidth: 40, minHeight: 40, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 4 },
  title: { flex: 1 },
});
