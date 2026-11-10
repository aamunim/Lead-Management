import Constants from 'expo-constants';
import { Link, type Href } from 'expo-router';
import { StyleSheet, View } from 'react-native';

import { AppText } from '@/components/AppText';
import { devToolsEnabled } from '@/dev/flags';
import { useTranslation } from '@/i18n';
import { useTheme } from '@/ui/theme';

// Placeholder home (real home screens come later). The product name comes from app config; every other word
// from translations and labels.
export default function HomeScreen() {
  const { t } = useTranslation();
  const { colors, space } = useTheme();
  const productName = Constants.expoConfig?.name ?? '';
  const links: { href: Href; label: string; testID: string }[] = [
    { href: '/language', label: t('home.openLanguage'), testID: 'open-language' },
    { href: '/appearance', label: t('home.openAppearance'), testID: 'open-appearance' },
    { href: '/samples', label: t('home.openSamples'), testID: 'open-samples' },
    { href: '/terminology', label: t('home.openTerminology'), testID: 'open-terminology' },
    ...(devToolsEnabled ? [{ href: '/dev/gallery' as Href, label: t('home.openGallery'), testID: 'open-gallery' }] : []),
  ];
  return (
    <View style={[styles.container, { padding: space.lg, gap: space.md, backgroundColor: colors.background }]} testID="placeholder-root">
      <AppText variant="headline" style={styles.center}>{productName}</AppText>
      <AppText style={styles.center} testID="home-subtitle">{t('home.subtitle')}</AppText>
      {links.map((link) => (
        <Link key={link.testID} href={link.href} style={[styles.link, { paddingHorizontal: space.lg }]} testID={link.testID}>
          <AppText style={[styles.linkText, { color: colors.primary }]}>{link.label}</AppText>
        </Link>
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  center: { textAlign: 'center' },
  link: { minHeight: 48, paddingVertical: 12 },
  linkText: { textDecorationLine: 'underline' },
});
