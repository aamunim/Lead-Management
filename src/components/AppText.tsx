import { Text, type TextProps } from 'react-native';

import { fontFamilyFor } from '@/i18n/language';
import { useLanguageState } from '@/lib/language';

import { useColors } from './theme';

// Text in the current UI language's font (0A.10). Bangla uses Noto Sans Bengali on Android and web, so conjuncts and
// vowel signs render the same everywhere (Ch 13.8). Use this instead of react-native's Text in screens.
export function AppText({ style, ...props }: TextProps) {
  const { language } = useLanguageState();
  const colors = useColors();
  const fontFamily = fontFamilyFor(language);
  // Bangla vowel signs (ু ৃ) need room above and below: never set a tight lineHeight on Bangla text (Ch 13.4).
  return <Text {...props} style={[{ color: colors.text }, fontFamily ? { fontFamily } : null, style]} />;
}
