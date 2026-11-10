import { useEffect, useState } from 'react';
import { View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { biometricsAvailable, unlockWithBiometrics, unlockWithPin } from '@/lib/app-lock';
import { setSignOutReason } from '@/lib/auth-state';
import { signOut } from '@/lib/session';

import { Button } from '../components/Button';
import { TextField } from '../components/TextField';
import { useTheme } from '../theme';

// Lock screen (0A.14-T7): covers the app until the PIN or the fingerprint is given. Nothing behind it is rendered.
export function LockScreen() {
  const { colors, space } = useTheme();
  const { t } = useTranslation('shell');
  const insets = useSafeAreaInsets();
  const [pin, setPin] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [biometrics, setBiometrics] = useState(false);

  useEffect(() => {
    void biometricsAvailable().then((ok) => {
      setBiometrics(ok);
      if (ok) void unlockWithBiometrics(t('lock.unlockPrompt'));
    });
  }, [t]);

  const submit = async () => {
    const result = await unlockWithPin(pin);
    setPin('');
    if (result === 'wrong') setError(t('lock.wrong'));
    if (result === 'locked_out') {
      setSignOutReason('locked_out');
      await signOut();
    }
  };

  return (
    <View style={{ flex: 1, justifyContent: 'center', padding: space.xl, gap: space.lg, paddingTop: insets.top + space.xl,
      backgroundColor: colors.background }} testID="lock-screen">
      <AppText variant="headline" accessibilityRole="header">{t('lock.title')}</AppText>
      <TextField label={t('lock.enterPin')} kind="password" value={pin} onChangeText={(v) => setPin(v.replace(/[^0-9]/g, '').slice(0, 6))}
        error={error} last onDone={() => void submit()} testID="lock-pin" />
      <Button label={t('lock.unlockPrompt')} onPress={() => void submit()} disabled={pin.length < 4} fullWidth testID="lock-unlock" />
      {biometrics ? <Button variant="tonal" icon="fingerprint" label={t('lock.biometrics')} fullWidth
        onPress={() => void unlockWithBiometrics(t('lock.unlockPrompt'))} /> : null}
      <Button variant="text" label={t('lock.signOutInstead')} onPress={() => void signOut()} />
    </View>
  );
}
