// i18n set-up (0A.10). Every user-visible word comes from src/i18n/locales; never hard-code UI text.
import i18n from 'i18next';
import { initReactI18next } from 'react-i18next';

import { FALLBACK_LANGUAGE, SUPPORTED_LANGUAGES } from './language';
import { DEFAULT_NAMESPACE, NAMESPACES, resources } from './resources';

void i18n.use(initReactI18next).init({
  resources,
  lng: FALLBACK_LANGUAGE,
  fallbackLng: FALLBACK_LANGUAGE,
  supportedLngs: [...SUPPORTED_LANGUAGES],
  ns: [...NAMESPACES],
  defaultNS: DEFAULT_NAMESPACE,
  initAsync: false, // resources are bundled: ready on the first render
  interpolation: { escapeValue: false }, // React already escapes
  returnNull: false,
  react: { bindI18n: 'languageChanged', useSuspense: false },
});

export default i18n;
export { useTranslation } from 'react-i18next';
