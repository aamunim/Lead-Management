import { router } from 'expo-router';
import { useState, type ReactNode } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { appLockAvailable, disableAppLock, enableAppLock, isValidPin, useAppLock } from '@/lib/app-lock';
import { useAuthState } from '@/lib/auth-state';
import { useActiveInstitution } from '@/lib/institution';
import { signOut, signOutOtherDevices } from '@/lib/session';
import { BottomSheet, Button, Screen, TextField, useConfirm, useSnackbar } from '@/ui/components';
import { AppHeader } from '@/ui/shell/AppHeader';
import { AppearancePicker, LanguagePicker } from '@/ui/shell/Pickers';
import { useTheme } from '@/ui/theme';

// Profile (0A.14-T4/T7): language and appearance (applied at once, no restart), app lock, sign out here or on all
// other devices. Signing out wipes every cached piece of user and institution data on this device.
export default function ProfileScreen() {
  const { t } = useTranslation('shell');
  const { colors } = useTheme();
  const auth = useAuthState();
  const institution = useActiveInstitution();
  const confirm = useConfirm();
  const snackbar = useSnackbar();
  const lock = useAppLock();
  const [pinSheet, setPinSheet] = useState(false);
  const email = auth.status === 'signedIn' ? auth.email ?? '' : '';

  const signOutHere = async () => {
    if (await confirm({ title: t('profile.signOutTitle'), message: t('profile.signOutBody'), confirmLabel: t('profile.signOut'), danger: true })) {
      await signOut();
      router.replace('/sign-in');
    }
  };
  const signOutOthers = async () => {
    if (await confirm({ title: t('profile.signOutOthersTitle'), message: t('profile.signOutOthersBody'), confirmLabel: t('profile.signOutOthers'), danger: true })) {
      await signOutOtherDevices();
      snackbar.show({ text: t('profile.signOutOthersDone') });
    }
  };

  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <AppHeader back />
      <Screen title={t('profile.title')} testID="profile">
        <AppText testID="profile-account">{t('profile.account', { email })}</AppText>
        {institution ? <AppText style={{ color: colors.onSurfaceVariant }}>{t('profile.institution', { name: institution.name })}</AppText> : null}

        <Section title={t('profile.language')}><LanguagePicker /></Section>
        <Section title={t('profile.appearance')}><AppearancePicker /></Section>

        <Section title={t('profile.security')}>
          {appLockAvailable ? (
            <>
              <AppText testID="profile-applock-state">{lock.enabled ? t('profile.appLockOn') : t('profile.appLockOff')}</AppText>
              <Button variant="tonal" icon={lock.enabled ? 'lock-open' : 'lock'} label={`${t('profile.appLock')}: ${lock.enabled ? t('profile.turnOff') : t('profile.turnOn')}`}
                onPress={() => (lock.enabled ? void disableAppLock() : setPinSheet(true))} testID="profile-applock" />
            </>
          ) : (
            <AppText style={{ color: colors.onSurfaceVariant }} testID="profile-applock-state">{t('profile.appLockUnavailable')}</AppText>
          )}
          <Button variant="outlined" icon="devices" label={t('profile.signOutOthers')} onPress={() => void signOutOthers()} testID="profile-signout-others" />
          <Button variant="danger" icon="logout" label={t('profile.signOut')} onPress={() => void signOutHere()} testID="profile-signout" />
        </Section>
      </Screen>
      <PinSetup visible={pinSheet} onClose={() => setPinSheet(false)} />
    </View>
  );
}

function Section({ title, children }: { title: string; children: ReactNode }) {
  const { colors, space } = useTheme();
  return (
    <View style={{ gap: space.md, paddingTop: space.lg, borderTopWidth: 1, borderTopColor: colors.outlineVariant }}>
      <AppText variant="titleSmall" accessibilityRole="header">{title}</AppText>
      {children}
    </View>
  );
}

function PinSetup({ visible, onClose }: { visible: boolean; onClose: () => void }) {
  const { t } = useTranslation('shell');
  const { t: tUi } = useTranslation('ui');
  const [pin, setPin] = useState('');
  const [again, setAgain] = useState('');
  const [error, setError] = useState<string | null>(null);
  const digits = (v: string) => v.replace(/[^0-9]/g, '').slice(0, 6);
  const save = async () => {
    if (!isValidPin(pin)) return setError(t('lock.setPin'));
    if (pin !== again) return setError(t('lock.mismatch'));
    await enableAppLock(pin);
    setPin('');
    setAgain('');
    setError(null);
    onClose();
  };
  return (
    <BottomSheet visible={visible} onClose={onClose} title={t('profile.appLock')} testID="pin-setup"
      footer={<Button label={tUi('actions.save')} onPress={() => void save()} fullWidth testID="pin-save" />}>
      <TextField label={t('lock.setPin')} kind="password" value={pin} onChangeText={(v) => setPin(digits(v))} testID="pin-new" />
      <TextField label={t('lock.confirmPin')} kind="password" value={again} onChangeText={(v) => setAgain(digits(v))} error={error}
        last onDone={() => void save()} testID="pin-again" />
    </BottomSheet>
  );
}
