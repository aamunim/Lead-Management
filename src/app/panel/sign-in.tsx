import { Redirect } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import { Linking, View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { useErrorText } from '@/i18n/errors';
import { enrollAuthenticator, verifySecondStep } from '@/lib/platform';
import { signOut } from '@/lib/session';
import { supabase } from '@/lib/supabase';
import { Button, Screen, Skeleton, TextField } from '@/ui/components';
import { usePanel } from '@/ui/panel/PanelContext';
import { useTheme } from '@/ui/theme';

// Panel sign-in (0B.02-T2): its own page, not the staff sign-in. Password, then ALWAYS the second step: the code from
// an authenticator app, or — the first time — setting one up. No way around it: the server refuses every platform
// call without a two-step (aal2) session.
export default function PanelSignIn() {
  const { t } = useTranslation('panel');
  const { colors, space } = useTheme();
  const errorText = useErrorText();
  const { state, refresh } = usePanel();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [code, setCode] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [enrolment, setEnrolment] = useState<{ factorId: string; secret: string; uri: string } | null>(null);

  // Start the set-up only once: a second start would replace the key the person is already typing into their app.
  const enrolling = useRef(false);
  useEffect(() => {
    if (state.status !== 'secondStep' || state.mode !== 'enroll' || enrolment || enrolling.current) return;
    enrolling.current = true;
    void enrollAuthenticator().then((r) => {
      if ('error' in r) setError(t('signIn.wrongCode'));
      else setEnrolment(r);
    });
  }, [state, enrolment, t]);

  if (state.status === 'ready') return <Redirect href="/panel" />;

  const submitPassword = async () => {
    setBusy(true);
    setError(null);
    const { error: e } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
    setBusy(false);
    if (e) setError(t('signIn.failed'));
  };
  const submitCode = async () => {
    const factorId = state.status === 'secondStep' ? (state.factorId ?? enrolment?.factorId) : null;
    if (!factorId) return;
    setBusy(true);
    setError(null);
    const failed = await verifySecondStep(factorId, code);
    setBusy(false);
    if (failed) return setError(t('signIn.wrongCode'));
    setCode('');
    refresh();
  };

  return (
    <Screen title={t('signIn.title')} intro={t('signIn.intro')} testID="panel-sign-in">
      {state.status === 'loading' ? <Skeleton lines={2} /> : null}
      {state.status === 'signedOut' ? (
        <>
          <TextField label={t('signIn.email')} kind="email" value={email} onChangeText={setEmail} testID="panel-email" />
          <TextField label={t('signIn.password')} kind="password" value={password} onChangeText={setPassword} error={error}
            last onDone={() => void submitPassword()} testID="panel-password" />
          <Button label={t('signIn.submit')} loading={busy} fullWidth onPress={() => void submitPassword()} testID="panel-submit" />
        </>
      ) : null}
      {state.status === 'secondStep' ? (
        <View style={{ gap: space.md }} testID="panel-second-step">
          <AppText variant="titleSmall">{state.mode === 'enroll' ? t('signIn.enrollTitle') : t('signIn.step2Title')}</AppText>
          <AppText style={{ color: colors.onSurfaceVariant }}>{state.mode === 'enroll' ? t('signIn.enrollIntro') : t('signIn.step2Intro')}</AppText>
          {state.mode === 'enroll' && enrolment ? (
            <View style={{ gap: space.xs }} testID="panel-enroll">
              <AppText variant="label">{t('signIn.key')}</AppText>
              <AppText selectable testID="panel-enroll-secret" style={{ letterSpacing: 2 }}>{enrolment.secret}</AppText>
              <Button variant="text" icon="open-in-new" label={t('signIn.openApp')} onPress={() => void Linking.openURL(enrolment.uri)} />
            </View>
          ) : null}
          <TextField label={t('signIn.code')} kind="otp" value={code} onChangeText={setCode} error={error} help={t('signIn.codeHelp')} last onDone={() => void submitCode()}
            testID="panel-code" />
          <Button label={t('signIn.verify')} loading={busy} fullWidth onPress={() => void submitCode()} testID="panel-verify" />
          <Button variant="text" label={t('signIn.signOut')} onPress={() => void signOut()} testID="panel-cancel" />
        </View>
      ) : null}
      {state.status === 'denied' ? (
        <View style={{ gap: space.md }}>
          <AppText style={{ color: colors.error }} accessibilityRole="alert" testID="panel-denied">
            {state.error.code === 'permission_denied' ? t('signIn.notPlatform') : errorText(state.error).message}
          </AppText>
          <Button variant="outlined" label={t('signIn.signOut')} onPress={() => void signOut()} testID="panel-denied-sign-out" />
        </View>
      ) : null}
    </Screen>
  );
}
