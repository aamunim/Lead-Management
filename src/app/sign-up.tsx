import { router } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { PhoneInput } from '@/components/fields/inputs';
import { useTranslation } from '@/i18n';
import { useErrorText } from '@/i18n/errors';
import { useAuthState } from '@/lib/auth-state';
import { useLanguageState } from '@/lib/language';
import { pick } from '@/lib/packs';
import {
  emptyAnswers, ensureLogin, fetchOpenIndustries, fetchSignupStatus, newRequestKey, openNewInstitution, submitSignup,
  type OpenIndustry, type SignupAnswers,
} from '@/lib/signup';
import { CheckRow, Chips, Section } from '@/ui/admin/parts';
import { Button, ErrorState, Screen, Skeleton, TextField, useSnackbar } from '@/ui/components';
import { AppHeader } from '@/ui/shell/AppHeader';
import { InfoStep, PreviewStep, StepCount, TypesStep, infoValid } from '@/ui/signup/WizardSteps';
import { useTheme } from '@/ui/theme';

// "Set up your institution" (0B.09; Ch 6.3): a short public wizard. The industry step is hidden while only one
// industry is open (D20). Steps: types → information → Super Admin (a new login, or an existing one: D25) → preview
// with parts to leave out → create. The institution waits for approval; setup can continue meanwhile. No institution
// is ever listed here (Ch 10.10 row 5).
type Step = 'industry' | 'types' | 'info' | 'admin' | 'preview' | 'confirmEmail' | 'done';

export default function SignUpScreen() {
  const { t } = useTranslation('shell');
  const { language } = useLanguageState();
  const { colors, space } = useTheme();
  const auth = useAuthState();
  const snackbar = useSnackbar();
  const errorText = useErrorText();
  const [open, setOpen] = useState<boolean | null>(null);
  const [industries, setIndustries] = useState<OpenIndustry[] | null>(null);
  const [industry, setIndustry] = useState<string | null>(null);
  const [error, setError] = useState<unknown>(null);
  const [step, setStep] = useState<Step>('types');
  const [answers, setAnswers] = useState<SignupAnswers>(emptyAnswers);
  const [mode, setMode] = useState<'new' | 'existing'>('new');
  const [password, setPassword] = useState('');
  const [loginError, setLoginError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [requestKey] = useState(newRequestKey);
  const signedInEmail = auth.status === 'signedIn' ? auth.email ?? null : null;

  const load = useCallback(async () => {
    setError(null);
    const [s, p] = await Promise.all([fetchSignupStatus(), fetchOpenIndustries()]);
    if (s.error || p.error) return setError(s.error ?? p.error);
    setOpen(Boolean(s.data?.open));
    const list = p.data ?? [];
    setIndustries(list);
    // Only one industry open: the wizard starts at the types (D20).
    if (list.length === 1) setIndustry(list[0].key);
    else setStep('industry');
  }, []);
  useEffect(() => {
    void load();
  }, [load]);

  const chosen = industries?.find((i) => i.key === industry) ?? null;
  const steps: Step[] = [...(industries && industries.length > 1 ? ['industry' as Step] : []), 'types', 'info', 'admin', 'preview'];
  const index = steps.indexOf(step);
  const next = () => setStep(steps[index + 1]);
  const back = () => (index > 0 ? setStep(steps[index - 1]) : router.back());
  const email = signedInEmail ?? answers.super_admin.email.trim();
  const adminValid = answers.super_admin.display_name.trim().length > 0 && /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)
    && (signedInEmail !== null || password.length >= 8);
  const canNext = step === 'industry' ? industry !== null : step === 'types' ? answers.profiles.length > 0 : step === 'info' ? infoValid(answers)
    : step === 'admin' ? adminValid : true;

  const create = async () => {
    setBusy(true);
    setLoginError(null);
    if (!signedInEmail) {
      const login = await ensureLogin(mode, email, password);
      if ('error' in login) {
        setBusy(false);
        setLoginError(t(`signup.login.${login.error}`));
        return setStep('admin');
      }
      if (login.state === 'confirm') {
        setBusy(false);
        return setStep('confirmEmail');
      }
    }
    const r = await submitSignup({ ...answers, super_admin: { ...answers.super_admin, email } }, requestKey);
    if (r.error) {
      setBusy(false);
      return snackbar.show({ text: errorText(r.error).message });
    }
    await openNewInstitution();
    setBusy(false);
    setStep('done');
  };
  const confirmed = async () => {
    setBusy(true);
    const login = await ensureLogin('existing', email, password);
    setBusy(false);
    if ('error' in login) return snackbar.show({ text: t('signup.notConfirmed') });
    void create();
  };

  const body = () => {
    if (error) return <ErrorState error={error} onRetry={() => void load()} testID="signup-error" />;
    if (open === null || !industries) return <Skeleton lines={6} testID="signup-loading" />;
    if (!open || industries.length === 0) return <AppText testID="signup-closed">{t('signup.closed')}</AppText>;
    if (step === 'done') {
      return (
        <Section title={t('signup.doneTitle')} testID="signup-done">
          <AppText>{t('signup.doneBody', { name: answers.name.trim() })}</AppText>
          <AppText variant="caption">{t('signup.doneNoMessages')}</AppText>
          <Button icon="arrow-forward" label={t('signup.continueSetup')} onPress={() => router.replace('/home')} testID="signup-continue" />
        </Section>
      );
    }
    if (step === 'confirmEmail') {
      return (
        <Section title={t('signup.confirmTitle')} testID="signup-confirm-email">
          <AppText>{t('signup.confirmBody', { email })}</AppText>
          <Button label={t('signup.confirmedNext')} loading={busy} onPress={() => void confirmed()} testID="signup-confirmed" />
        </Section>
      );
    }
    return (
      <>
        <StepCount step={index + 1} total={steps.length} />
        {step === 'industry' ? (
          <Section title={t('signup.industryTitle')} testID="wizard-industry">
            <Chips label={t('signup.industryTitle')} selected={industry ?? ''} onSelect={(v) => setIndustry(v)}
              choices={industries.map((i) => ({ value: i.key, label: pick(i.name, language), testID: `wizard-industry-${i.key}` }))} />
          </Section>
        ) : null}
        {step === 'types' && chosen ? <TypesStep industry={chosen} answers={answers} onChange={setAnswers} /> : null}
        {step === 'info' ? <InfoStep answers={answers} onChange={setAnswers} /> : null}
        {step === 'admin' ? (
          <Section title={t('signup.adminTitle')} testID="wizard-admin">
            <AppText variant="caption">{t('signup.adminHelp')}</AppText>
            <TextField label={t('signup.adminName')} kind="name" required value={answers.super_admin.display_name} maxLength={120}
              onChangeText={(v) => setAnswers({ ...answers, super_admin: { ...answers.super_admin, display_name: v } })} testID="wizard-admin-name" />
            <PhoneInput label={t('signup.adminPhone')} value={answers.super_admin.phone} errorText={t('signup.phoneInvalid')}
              onChange={(v) => setAnswers({ ...answers, super_admin: { ...answers.super_admin, phone: v ?? '' } })} testID="wizard-admin-phone" />
            {signedInEmail ? <AppText testID="wizard-admin-signed-in">{t('signup.signedInAs', { email: signedInEmail })}</AppText> : (
              <>
                <CheckRow label={t('signup.haveLogin')} help={t('signup.haveLoginHelp')} checked={mode === 'existing'}
                  onToggle={() => setMode(mode === 'new' ? 'existing' : 'new')} testID="wizard-have-login" />
                <TextField label={t('signup.adminEmail')} kind="email" required value={answers.super_admin.email}
                  onChangeText={(v) => setAnswers({ ...answers, super_admin: { ...answers.super_admin, email: v } })} testID="wizard-admin-email" />
                <TextField label={t('signup.password')} kind="password" required value={password} onChangeText={setPassword}
                  help={mode === 'new' ? t('signup.passwordHelp') : undefined} error={loginError} testID="wizard-admin-password" />
              </>
            )}
            <AppText variant="caption">{t('signup.otherLogins')}</AppText>
          </Section>
        ) : null}
        {step === 'preview' ? <PreviewStep answers={answers} onChange={setAnswers} /> : null}
        <View style={{ flexDirection: 'row', gap: space.md, flexWrap: 'wrap' }}>
          <Button variant="text" icon="arrow-back" label={t('signup.back')} onPress={back} testID="wizard-back" />
          {step === 'preview' ? (
            <Button icon="check" label={t('signup.create')} loading={busy} onPress={() => void create()} testID="wizard-create" />
          ) : (
            <Button icon="arrow-forward" label={t('signup.next')} disabled={!canNext} onPress={next} testID="wizard-next" />
          )}
        </View>
      </>
    );
  };

  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <AppHeader signedIn={false} />
      <Screen title={t('signup.title')} intro={t('signup.intro')} testID="sign-up">
        {body()}
      </Screen>
    </View>
  );
}
