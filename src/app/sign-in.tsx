import Constants from 'expo-constants';
import { Link, router } from 'expo-router';
import { useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { devSignInEnabled } from '@/dev/flags';
import { useTranslation } from '@/i18n';
import { useAuthState } from '@/lib/auth-state';
import { supabase } from '@/lib/supabase';
import { Button, Screen, TextField, useSubmit } from '@/ui/components';
import { AppHeader } from '@/ui/shell/AppHeader';
import { useTheme } from '@/ui/theme';

// Sign-in (0A.14): before sign-in only the neutral product name is shown (Ch 4.5). Email + password for now;
// OTP and Google sign-in, invitations and password reset come with the real login screens (0B, Ch 10).
export default function SignInScreen() {
  const { t } = useTranslation('shell');
  const { t: tCommon } = useTranslation();
  const { colors, space } = useTheme();
  const auth = useAuthState();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [failed, setFailed] = useState(false);
  const { submit, submitting } = useSubmit(async () => {
    setFailed(false);
    const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
    if (error) setFailed(true);
    else router.replace('/home');
  });
  const reason = auth.status === 'signedOut' ? auth.reason : undefined;
  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <AppHeader signedIn={false} />
      <Screen title={t('signIn.title')} intro={tCommon('home.subtitle')} testID="sign-in">
        {reason ? (
          <AppText style={{ color: colors.onSurfaceVariant }} accessibilityLiveRegion="polite" testID="sign-in-reason">
            {reason === 'idle' ? t('signIn.idleSignedOut') : t('lock.tooMany')}
          </AppText>
        ) : null}
        <TextField label={t('signIn.email')} kind="email" value={email} onChangeText={setEmail} testID="sign-in-email" />
        <TextField label={t('signIn.password')} kind="password" value={password} onChangeText={setPassword}
          error={failed ? t('signIn.failed') : null} last onDone={() => void submit()} testID="sign-in-password" />
        <Button label={t('signIn.submit')} onPress={() => void submit()} loading={submitting} disabled={!email || !password}
          fullWidth testID="sign-in-submit" />
        <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: space.lg }}>
          <Link href="/language" testID="sign-in-language"><AppText style={{ color: colors.primary, textDecorationLine: 'underline' }}>{t('signIn.languageLink')}</AppText></Link>
          <Link href="/panel/sign-in" testID="sign-in-panel"><AppText style={{ color: colors.onSurfaceVariant }}>{t('signIn.panelLink')}</AppText></Link>
          {devSignInEnabled ? <Link href="/dev-sign-in"><AppText style={{ color: colors.onSurfaceVariant }}>{Constants.expoConfig?.slug ?? ''}</AppText></Link> : null}
        </View>
      </Screen>
    </View>
  );
}
