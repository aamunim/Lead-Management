// Language rules (0A.10). Pure: no React Native imports, so unit tests run it in Node.
// Resolution is the same as the server's app.resolve_language: user choice → institution default → English.

export const SUPPORTED_LANGUAGES = ['en', 'bn'] as const;
export type Language = (typeof SUPPORTED_LANGUAGES)[number];
export const FALLBACK_LANGUAGE: Language = 'en';

export function isLanguage(value: unknown): value is Language {
  return typeof value === 'string' && (SUPPORTED_LANGUAGES as readonly string[]).includes(value);
}

export function resolveLanguage(input: { choice?: unknown; institutionDefault?: unknown }): Language {
  if (isLanguage(input.choice)) return input.choice;
  if (isLanguage(input.institutionDefault)) return input.institutionDefault;
  return FALLBACK_LANGUAGE;
}

/** Font family per language. Bangla needs a Bangla-capable font on every platform (Ch 13.8). */
export const BANGLA_FONT_FAMILY = 'NotoSansBengali';
export function fontFamilyFor(language: Language): string | undefined {
  return language === 'bn' ? BANGLA_FONT_FAMILY : undefined;
}
