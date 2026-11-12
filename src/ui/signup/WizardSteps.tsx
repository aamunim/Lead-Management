import { useEffect, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { PhoneInput } from '@/components/fields/inputs';
import { useTranslation } from '@/i18n';
import { useLanguageState } from '@/lib/language';
import { pick } from '@/lib/packs';
import type { ProfilePreview } from '@/lib/profiles';
import { FIXED_AREAS, previewSignup, type OpenIndustry, type SignupAnswers } from '@/lib/signup';
import { CheckRow, Chips, Section, tDynamic } from '@/ui/admin/parts';
import { ErrorState, Skeleton, TextField } from '@/ui/components';
import { useTheme } from '@/ui/theme';

// The steps of the setup wizard (0B.09; Ch 6.3) shared by self sign-up and the Master Admin's "Create institution":
// types (one or more, mixed allowed), institution information (College Code and EIIN optional), and the preview of
// what the types set up with parts that can be left out. Only the essentials (Ch 6.9 row 3).
type Props = { answers: SignupAnswers; onChange: (next: SignupAnswers) => void };

export function StepCount({ step, total }: { step: number; total: number }) {
  const { t } = useTranslation('shell');
  const { colors } = useTheme();
  return <AppText variant="caption" style={{ color: colors.onSurfaceVariant }} testID="wizard-step">{t('signup.step', { step, total })}</AppText>;
}

export function TypesStep({ answers, onChange, industry }: Props & { industry: OpenIndustry }) {
  const { t } = useTranslation('shell');
  const { language } = useLanguageState();
  const toggle = (key: string) => onChange({ ...answers, label_choices: {},
    profiles: answers.profiles.includes(key) ? answers.profiles.filter((k) => k !== key) : [...answers.profiles, key] });
  return (
    <Section title={t('signup.typesTitle')} testID="wizard-types">
      <AppText variant="caption">{t('signup.typesHelp')}</AppText>
      {industry.profiles.map((p) => (
        <CheckRow key={p.key} label={pick(p.name, language)} help={pick(p.description, language)} checked={answers.profiles.includes(p.key)}
          onToggle={() => toggle(p.key)} testID={`wizard-type-${p.key}`} />
      ))}
    </Section>
  );
}

export function InfoStep({ answers, onChange }: Props) {
  const { t } = useTranslation('shell');
  const set = (k: keyof SignupAnswers) => (v: string) => onChange({ ...answers, [k]: v });
  return (
    <Section title={t('signup.infoTitle')} testID="wizard-info">
      <TextField label={t('signup.name')} kind="name" required value={answers.name} onChangeText={set('name')} maxLength={200} testID="wizard-name" />
      <TextField label={t('signup.shortName')} value={answers.short_name} onChangeText={set('short_name')} maxLength={40} help={t('signup.shortNameHelp')}
        testID="wizard-short-name" />
      <TextField label={t('signup.eiin')} kind="number" value={answers.eiin} onChangeText={set('eiin')} maxLength={10} help={t('signup.optional')}
        testID="wizard-eiin" />
      <TextField label={t('signup.code')} value={answers.institution_code} onChangeText={set('institution_code')} maxLength={20} help={t('signup.optional')}
        testID="wizard-code" />
      <TextField label={t('signup.address')} kind="multiline" value={answers.address} onChangeText={set('address')} maxLength={300} testID="wizard-address" />
      <PhoneInput label={t('signup.phone')} value={answers.contact_phone} onChange={(v) => onChange({ ...answers, contact_phone: v ?? '' })}
        errorText={t('signup.phoneInvalid')} testID="wizard-phone" />
      <AppText variant="caption">{t('signup.brandingLater')}</AppText>
    </Section>
  );
}

export const infoValid = (a: SignupAnswers) => a.name.trim().length >= 2 && (!a.eiin.trim() || /^[0-9]{4,10}$/.test(a.eiin.trim()))
  && (!a.institution_code.trim() || /^[0-9A-Za-z-]{2,20}$/.test(a.institution_code.trim()));

export function PreviewStep({ answers, onChange }: Props) {
  const { t } = useTranslation('shell');
  const { language } = useLanguageState();
  const { space } = useTheme();
  const [preview, setPreview] = useState<ProfilePreview | null>(null);
  const [error, setError] = useState<unknown>(null);
  const [attempt, setAttempt] = useState(0);
  // The full list of parts comes from the preview without exclusions, so a left-out part can be put back.
  const [areas, setAreas] = useState<{ area: string; add: number }[]>([]);
  const { profiles, label_choices: choices, exclude } = answers;

  useEffect(() => {
    let live = true;
    void previewSignup({ profiles, exclude: [], label_choices: choices }).then((r) => {
      if (!live) return;
      if (r.error || !r.data) return setError(r.error);
      setError(null);
      setPreview(r.data);
      setAreas(r.data.areas.map((a) => ({ area: a.area, add: a.add })));
    });
    return () => {
      live = false;
    };
  }, [profiles, choices, attempt]);

  if (error) return <ErrorState error={error} onRetry={() => setAttempt((n) => n + 1)} testID="wizard-preview-error" />;
  if (!preview) return <Skeleton lines={6} testID="wizard-preview-loading" />;
  const toggle = (area: string) => onChange({ ...answers,
    exclude: exclude.includes(area) ? exclude.filter((a) => a !== area) : [...exclude, area] });

  return (
    <Section title={t('signup.previewTitle')} testID="wizard-preview">
      <AppText variant="caption">{t('signup.previewHelp', { types: preview.profiles.map((p) => pick(p.name, language)).join(' + ') })}</AppText>
      {preview.label_conflicts.map((c) => (
        <View key={c.key} style={{ gap: space.xs }} testID={`wizard-conflict-${c.key}`}>
          <AppText variant="label">{t('signup.conflict', { key: c.key })}</AppText>
          <Chips label={t('signup.conflict', { key: c.key })} selected={choices[c.key] ?? c.chosen}
            choices={c.options.map((o) => ({ value: o.profile, label: language === 'bn' ? o.bn : o.en_singular, testID: `wizard-conflict-${c.key}-${o.profile}` }))}
            onSelect={(v) => onChange({ ...answers, label_choices: { ...choices, [c.key]: v } })} />
        </View>
      ))}
      {areas.map((a) => {
        const fixed = FIXED_AREAS.includes(a.area);
        return (
          <CheckRow key={a.area} label={tDynamic(`admin:types.areas.${a.area}`)} checked={!exclude.includes(a.area)} disabled={fixed}
            help={fixed ? t('signup.areaFixed') : t('signup.areaItems', { count: a.add })} onToggle={() => toggle(a.area)}
            testID={`wizard-area-${a.area}`} />
        );
      })}
      <AppText variant="caption">{t('signup.previewLater')}</AppText>
    </Section>
  );
}
