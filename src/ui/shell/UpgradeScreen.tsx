import { MaterialIcons } from '@expo/vector-icons';
import Constants from 'expo-constants';
import { Linking, Platform, View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';

import { Button } from '../components/Button';
import { useTheme } from '../theme';

// "Please update" (0A.14-T3): shown over everything once the server answers upgrade_required (app older than
// min_app_version). The banner variant ("update soon") comes in 1B.
export function UpgradeScreen() {
  const { colors, space } = useTheme();
  const { t } = useTranslation('shell');
  const update = () => {
    if (Platform.OS === 'web') {
      globalThis.location?.reload();
      return;
    }
    const pkg = Constants.expoConfig?.android?.package ?? '';
    void Linking.openURL(`market://details?id=${pkg}`).catch(() => Linking.openURL(`https://play.google.com/store/apps/details?id=${pkg}`));
  };
  return (
    <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', padding: space.xl, gap: space.lg, backgroundColor: colors.background }}
      testID="upgrade-required">
      <MaterialIcons name="system-update" size={56} color={colors.primary} />
      <AppText variant="headline" style={{ textAlign: 'center' }} accessibilityRole="header">{t('upgrade.title')}</AppText>
      <AppText style={{ textAlign: 'center', color: colors.onSurfaceVariant }}>{t('upgrade.body')}</AppText>
      <Button label={t('upgrade.button')} onPress={update} icon="download" />
    </View>
  );
}
