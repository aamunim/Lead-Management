import { useState } from 'react';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { useErrorText } from '@/i18n/errors';
import { SUPPORTED_LANGUAGES, type Language } from '@/i18n/language';
import { describeError } from '@/lib/errors';
import { chooseLanguage, useLanguageState } from '@/lib/language';

import { ChoiceList } from '../components/ChoiceList';
import { setAppearance, useTheme, type Appearance } from '../theme';

// Language and appearance choices, used on their own screens and in the profile (0A.14-T4). Both apply at once,
// without a restart. Language is saved to the profile (every device); appearance on this device.
export function LanguagePicker() {
  const { t } = useTranslation('language');
  const errorText = useErrorText();
  const { colors } = useTheme();
  const { language, choice, institutionDefault, signedIn } = useLanguageState();
  const [feedback, setFeedback] = useState<{ kind: 'saved' | 'savedOnDevice' } | { kind: 'error'; text: string } | null>(null);
  const options: { value: Language | null; label: string; testID: string }[] = SUPPORTED_LANGUAGES.map((value) => ({
    value, label: t(`names.${value}`), testID: `language-option-${value}`,
  }));
  if (signedIn && institutionDefault) {
    options.push({ value: null, label: t('followInstitution', { language: t(`names.${institutionDefault}`) }), testID: 'language-option-institution' });
  }
  const pick = async (next: Language | null) => {
    setFeedback(null);
    const result = await chooseLanguage(next);
    if (result.error) setFeedback({ kind: 'error', text: errorText(describeError(result.error, 'language.choose')).message });
    else setFeedback({ kind: result.savedOnServer ? 'saved' : 'savedOnDevice' });
  };
  return (
    <>
      <AppText testID="language-current">{t('current', { language: t(`names.${language}`) })}</AppText>
      <ChoiceList accessibilityLabel={t('title')} selected={choice ?? (institutionDefault ? null : language)}
        onSelect={(value) => void pick(value)} choices={options} />
      {feedback ? (
        <AppText testID="language-feedback" style={feedback.kind === 'error' ? { color: colors.error } : undefined}>
          {feedback.kind === 'error' ? feedback.text : t(feedback.kind)}
        </AppText>
      ) : null}
    </>
  );
}

export function AppearancePicker() {
  const { t } = useTranslation('ui');
  const { appearance } = useTheme();
  const choices: { value: Appearance; label: string; testID: string }[] = [
    { value: 'system', label: t('appearance.system'), testID: 'appearance-system' },
    { value: 'light', label: t('appearance.light'), testID: 'appearance-light' },
    { value: 'dark', label: t('appearance.dark'), testID: 'appearance-dark' },
  ];
  return <ChoiceList accessibilityLabel={t('appearance.title')} choices={choices} selected={appearance} onSelect={(v) => void setAppearance(v)} />;
}
