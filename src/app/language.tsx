import { useState } from 'react';

import { AppText } from '@/components/AppText';
import { ChoiceList, Screen } from '@/ui/components';
import { useTheme } from '@/ui/theme';
import { useTranslation } from '@/i18n';
import { SUPPORTED_LANGUAGES, type Language } from '@/i18n/language';
import { useErrorText } from '@/i18n/errors';
import { describeError } from '@/lib/errors';
import { chooseLanguage, useLanguageState } from '@/lib/language';

type Feedback = { kind: 'saved' | 'savedOnDevice' } | { kind: 'error'; text: string } | null;

// Language screen (0A.10): the sample screen of the owner checkpoint. Switching changes every word at once,
// without a reload. Language names are always shown in their own language (English / বাংলা).
export default function LanguageScreen() {
  const { t } = useTranslation('language');
  const errorText = useErrorText();
  const { colors } = useTheme();
  const { language, choice, institutionDefault, signedIn } = useLanguageState();
  const [feedback, setFeedback] = useState<Feedback>(null);

  const pick = async (next: Language | null) => {
    setFeedback(null);
    const result = await chooseLanguage(next);
    if (result.error) {
      setFeedback({ kind: 'error', text: errorText(describeError(result.error, 'language.choose')).message });
    } else {
      setFeedback({ kind: result.savedOnServer ? 'saved' : 'savedOnDevice' });
    }
  };

  const options: { value: Language | null; label: string }[] = SUPPORTED_LANGUAGES.map((value) => ({
    value,
    label: t(`names.${value}`),
  }));
  if (signedIn && institutionDefault) {
    options.push({ value: null, label: t('followInstitution', { language: t(`names.${institutionDefault}`) }) });
  }

  return (
    <Screen title={t('title')} intro={t('description')} testID="language">
      <AppText testID="language-current">{t('current', { language: t(`names.${language}`) })}</AppText>
      <ChoiceList
        accessibilityLabel={t('title')}
        selected={choice ?? (institutionDefault ? null : language)}
        onSelect={(value) => void pick(value)}
        choices={options.map((option) => ({ value: option.value, label: option.label, testID: `language-option-${option.value ?? 'institution'}` }))}
      />
      {feedback && (
        <AppText testID="language-feedback" style={feedback.kind === 'error' ? { color: colors.error } : undefined}>
          {feedback.kind === 'error' ? feedback.text : t(feedback.kind)}
        </AppText>
      )}
    </Screen>
  );
}
