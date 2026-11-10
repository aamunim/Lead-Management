import { Text, type TextProps } from 'react-native';

import { useLanguageState } from '@/lib/language';
import { fontFamilyFor } from '@/i18n/language';

// Text in the current UI language's font (0A.10). Bangla uses Noto Sans Bengali on Android and web, so conjuncts and
// vowel signs render the same everywhere (Ch 13.8). Use this instead of react-native's Text in screens.
export function AppText({ style, ...props }: TextProps) {
  const { language } = useLanguageState();
  const fontFamily = fontFamilyFor(language);
  return <Text {...props} style={fontFamily ? [{ fontFamily }, style] : style} />;
}
