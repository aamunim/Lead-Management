import Constants from 'expo-constants';
import { Link } from 'expo-router';
import { StyleSheet, View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';

// Placeholder home (real home screens come later). The product name comes from app config; every other word
// from translations.
export default function HomeScreen() {
  const { t } = useTranslation();
  const productName = Constants.expoConfig?.name ?? '';
  return (
    <View style={styles.container} testID="placeholder-root">
      <AppText style={styles.title}>{productName}</AppText>
      <AppText style={styles.subtitle} testID="home-subtitle">{t('home.subtitle')}</AppText>
      <Link href="/language" style={styles.link} testID="open-language">
        <AppText style={styles.linkText}>{t('home.openLanguage')}</AppText>
      </Link>
      <Link href="/samples" style={styles.link} testID="open-samples">
        <AppText style={styles.linkText}>{t('home.openSamples')}</AppText>
      </Link>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: 16, gap: 12 },
  title: { fontSize: 20, fontWeight: '600' },
  subtitle: { fontSize: 16, textAlign: 'center' },
  link: { minHeight: 48, paddingVertical: 12, paddingHorizontal: 16 },
  linkText: { fontSize: 16, textDecorationLine: 'underline' },
});
