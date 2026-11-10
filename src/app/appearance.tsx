import { useTranslation } from '@/i18n';
import { Screen } from '@/ui/components';
import { AppearancePicker } from '@/ui/shell/Pickers';

// Appearance (0A.13-T1, Ch 47.2): System / Light / Dark, applied at once without a restart; kept on this device.
export default function AppearanceScreen() {
  const { t } = useTranslation('ui');
  return (
    <Screen title={t('appearance.title')} intro={t('appearance.description')} testID="appearance">
      <AppearancePicker />
    </Screen>
  );
}
