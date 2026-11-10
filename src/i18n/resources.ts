// Translation resources (0A.10-T1): one JSON file per namespace (feature) and language.
// Adding a namespace: add src/i18n/locales/<lang>/<ns>.json for EVERY language and list it here.
// `npm run check:i18n` fails on a key that exists in one language only.
import bnCommon from './locales/bn/common.json';
import bnErrors from './locales/bn/errors.json';
import bnLanguage from './locales/bn/language.json';
import enCommon from './locales/en/common.json';
import enErrors from './locales/en/errors.json';
import enLanguage from './locales/en/language.json';

export const NAMESPACES = ['common', 'language', 'errors'] as const;
export const DEFAULT_NAMESPACE = 'common';

export const resources = {
  en: { common: enCommon, language: enLanguage, errors: enErrors },
  bn: { common: bnCommon, language: bnLanguage, errors: bnErrors },
} as const;
