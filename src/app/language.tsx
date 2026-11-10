import { useState } from 'react';
import { Pressable, StyleSheet, View } from 'react-native';

import { AppText } from '@/components/AppText';
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
    <View style={styles.container}>
      <AppText style={styles.title} accessibilityRole="header" testID="language-title">{t('title')}</AppText>
      <AppText style={styles.description}>{t('description')}</AppText>
      <AppText testID="language-current">{t('current', { language: t(`names.${language}`) })}</AppText>
      {options.map((option) => {
        const selected = option.value === choice || (option.value === language && choice === null && !institutionDefault);
        return (
          <Pressable
            key={option.value ?? 'institution'}
            accessibilityRole="radio"
            accessibilityState={{ selected }}
            style={[styles.option, selected && styles.selected]}
            onPress={() => void pick(option.value)}
            testID={`language-option-${option.value ?? 'institution'}`}
          >
            <AppText style={styles.optionText}>{option.label}</AppText>
          </Pressable>
        );
      })}
      {feedback && (
        <AppText testID="language-feedback" style={feedback.kind === 'error' ? styles.error : undefined}>
          {feedback.kind === 'error' ? feedback.text : t(feedback.kind)}
        </AppText>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, padding: 16, gap: 12, justifyContent: 'center', maxWidth: 560, width: '100%', alignSelf: 'center' },
  title: { fontSize: 22, fontWeight: '600' },
  description: { fontSize: 16 },
  option: { minHeight: 48, borderWidth: 1, borderColor: '#999', borderRadius: 8, padding: 12, justifyContent: 'center' },
  selected: { borderWidth: 2, borderColor: '#1b6ef3' },
  optionText: { fontSize: 16 },
  error: { color: '#b00020' },
});
