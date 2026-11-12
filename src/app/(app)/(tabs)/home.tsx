import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { useAuthState } from '@/lib/auth-state';
import { EmptyState, Screen } from '@/ui/components';
import { LimitBanner } from '@/ui/limits/LimitBanner';
import { StatusBanner } from '@/ui/limits/StatusBanner';
import { SetupCard } from '@/ui/setup/SetupCard';
import { useConfirmExitOnBack } from '@/ui/shell/navigation';
import { useTheme } from '@/ui/theme';

// Home placeholder (real Home in 1B, Ch 45). Android Back here asks before leaving the app.
export default function HomeTab() {
  const { t } = useTranslation('shell');
  const { t: tCommon } = useTranslation();
  const { colors } = useTheme();
  const auth = useAuthState();
  useConfirmExitOnBack();
  const name = auth.status === 'signedIn' ? (auth.email ?? '').split('@')[0] : '';
  return (
    <Screen title={t('home.welcome', { name })} testID="home">
      <AppText style={{ color: colors.onSurfaceVariant }} testID="home-subtitle">{tCommon('home.subtitle')}</AppText>
      <StatusBanner />
      <LimitBanner />
      <SetupCard />
      <EmptyState icon="construction" title={t('home.comingSoon')} />
    </Screen>
  );
}
