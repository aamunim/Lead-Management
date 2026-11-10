import { useTranslation } from '@/i18n';
import { ChoiceList, Screen } from '@/ui/components';
import { setAppearance, useTheme, type Appearance } from '@/ui/theme';

// Appearance (0A.13-T1, Ch 47.2): System / Light / Dark, applied at once without a restart; kept on this device.
export default function AppearanceScreen() {
  const { t } = useTranslation('ui');
  const { appearance } = useTheme();
  const choices: { value: Appearance; label: string; testID: string }[] = [
    { value: 'system', label: t('appearance.system'), testID: 'appearance-system' },
    { value: 'light', label: t('appearance.light'), testID: 'appearance-light' },
    { value: 'dark', label: t('appearance.dark'), testID: 'appearance-dark' },
  ];
  return (
    <Screen title={t('appearance.title')} intro={t('appearance.description')} testID="appearance">
      <ChoiceList accessibilityLabel={t('appearance.title')} choices={choices} selected={appearance} onSelect={(v) => void setAppearance(v)} />
    </Screen>
  );
}
