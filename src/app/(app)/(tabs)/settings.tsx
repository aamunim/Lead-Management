import { useTranslation } from '@/i18n';
import { EmptyState, Screen } from '@/ui/components';

// Settings placeholder: institution settings screens come in 0B / 1B (they need permissions, 0A.16–0A.17).
export default function SettingsTab() {
  const { t } = useTranslation('shell');
  return (
    <Screen title={t('settings.title')} testID="settings">
      <EmptyState icon="tune" title={t('settings.soon')} />
    </Screen>
  );
}
