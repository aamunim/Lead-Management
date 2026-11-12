import { router } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { PhoneInput } from '@/components/fields/inputs';
import { useTranslation } from '@/i18n';
import { useErrorText } from '@/i18n/errors';
import {
  emptyAnswers, fetchOpenIndustries, newRequestKey, platformCreateInstitution, type OpenIndustry, type SignupAnswers,
} from '@/lib/signup';
import { Section } from '@/ui/admin/parts';
import { Button, ErrorState, Skeleton, TextField, useSnackbar } from '@/ui/components';
import { usePanel } from '@/ui/panel/PanelContext';
import { PanelShell } from '@/ui/panel/PanelShell';
import { InfoStep, PreviewStep, StepCount, TypesStep, infoValid } from '@/ui/signup/WizardSteps';
import { useTheme } from '@/ui/theme';

// Master Admin → Create institution (0B.09-T9, Proposed; Ch 6.2): the same wizard as self sign-up; the trial starts at
// once and the Super Admin is invited by email (an existing login is attached at once, D25; a new one joins when that
// email first signs in).
type Step = 'types' | 'info' | 'admin' | 'preview';
const STEPS: Step[] = ['types', 'info', 'admin', 'preview'];

export default function PanelInstitutionNew() {
  const { t } = useTranslation('panel');
  const { t: tw } = useTranslation('shell');
  const { space } = useTheme();
  const { state } = usePanel();
  const snackbar = useSnackbar();
  const errorText = useErrorText();
  const [industry, setIndustry] = useState<OpenIndustry | null>(null);
  const [error, setError] = useState<unknown>(null);
  const [step, setStep] = useState<Step>('types');
  const [answers, setAnswers] = useState<SignupAnswers>(emptyAnswers);
  const [busy, setBusy] = useState(false);
  const [requestKey] = useState(newRequestKey);

  const load = useCallback(async () => {
    setError(null);
    const r = await fetchOpenIndustries();
    if (r.error) return setError(r.error);
    setIndustry(r.data?.[0] ?? null);
  }, []);
  useEffect(() => {
    if (state.status === 'ready') void load();
  }, [state.status, load]);

  const index = STEPS.indexOf(step);
  const admin = answers.super_admin;
  const canNext = step === 'types' ? answers.profiles.length > 0 : step === 'info' ? infoValid(answers)
    : step === 'admin' ? /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(admin.email.trim()) : true;
  const setAdmin = (k: keyof SignupAnswers['super_admin']) => (v: string | null) =>
    setAnswers({ ...answers, super_admin: { ...admin, [k]: v ?? '' } });

  const create = async () => {
    setBusy(true);
    const r = await platformCreateInstitution({ ...answers, super_admin: { ...admin, email: admin.email.trim().toLowerCase() } }, requestKey);
    setBusy(false);
    if (r.error || !r.data) return snackbar.show({ text: r.error ? errorText(r.error).message : '' });
    snackbar.show({ text: r.data.attached ? t('create.attached') : t('create.invited', { email: admin.email.trim() }) });
    router.replace(`/panel/institution/${r.data.institution_id}`);
  };

  return (
    <PanelShell permission="platform.institutions_create" title={t('create.title')} testID="panel-institution-new">
      <AppText>{t('create.intro')}</AppText>
      {error ? <ErrorState error={error} onRetry={() => void load()} /> : !industry ? <Skeleton lines={6} /> : (
        <>
          <StepCount step={index + 1} total={STEPS.length} />
          {step === 'types' ? <TypesStep industry={industry} answers={answers} onChange={setAnswers} /> : null}
          {step === 'info' ? <InfoStep answers={answers} onChange={setAnswers} /> : null}
          {step === 'admin' ? (
            <Section title={tw('signup.adminTitle')} testID="create-admin">
              <AppText variant="caption">{t('create.adminHelp')}</AppText>
              <TextField label={tw('signup.adminEmail')} kind="email" required value={admin.email} onChangeText={setAdmin('email')} testID="create-admin-email" />
              <TextField label={tw('signup.adminName')} kind="name" value={admin.display_name} onChangeText={setAdmin('display_name')} maxLength={120}
                testID="create-admin-name" />
              <PhoneInput label={tw('signup.adminPhone')} value={admin.phone} onChange={setAdmin('phone')} errorText={tw('signup.phoneInvalid')}
                testID="create-admin-phone" />
            </Section>
          ) : null}
          {step === 'preview' ? <PreviewStep answers={answers} onChange={setAnswers} /> : null}
          <View style={{ flexDirection: 'row', gap: space.md, flexWrap: 'wrap' }}>
            <Button variant="text" icon="arrow-back" label={tw('signup.back')} onPress={() => (index > 0 ? setStep(STEPS[index - 1]) : router.back())}
              testID="wizard-back" />
            {step === 'preview' ? (
              <Button icon="check" label={t('create.submit')} loading={busy} onPress={() => void create()} testID="create-submit" />
            ) : (
              <Button icon="arrow-forward" label={tw('signup.next')} disabled={!canNext} onPress={() => setStep(STEPS[index + 1])} testID="wizard-next" />
            )}
          </View>
        </>
      )}
    </PanelShell>
  );
}
