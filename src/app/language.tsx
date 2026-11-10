import { useTranslation } from '@/i18n';
import { Screen } from '@/ui/components';
import { LanguagePicker } from '@/ui/shell/Pickers';

// Language screen (0A.10): bn / en, applied at once without a restart.
export default function LanguageScreen() {
  const { t } = useTranslation('language');
  return (
    <Screen title={t('title')} intro={t('description')} testID="language">
      <LanguagePicker />
    </Screen>
  );
}
