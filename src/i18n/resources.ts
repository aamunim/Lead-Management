// Translation resources (0A.10-T1): one JSON file per namespace (feature) and language.
// Adding a namespace: add src/i18n/locales/<lang>/<ns>.json for EVERY language and list it here.
// `npm run check:i18n` fails on a key that exists in one language only.
import bnCommon from './locales/bn/common.json';
import bnErrors from './locales/bn/errors.json';
import bnFormat from './locales/bn/format.json';
import bnLabels from './locales/bn/labels.json';
import bnLocale from './locales/bn/locale.json';
import bnTerminology from './locales/bn/terminology.json';
import bnUi from './locales/bn/ui.json';
import bnGallery from './locales/bn/gallery.json';
import bnShell from './locales/bn/shell.json';
import bnLanguage from './locales/bn/language.json';
import enCommon from './locales/en/common.json';
import enErrors from './locales/en/errors.json';
import enFormat from './locales/en/format.json';
import enLabels from './locales/en/labels.json';
import enLocale from './locales/en/locale.json';
import enTerminology from './locales/en/terminology.json';
import enUi from './locales/en/ui.json';
import enGallery from './locales/en/gallery.json';
import enShell from './locales/en/shell.json';
import enLanguage from './locales/en/language.json';

// `labels` = renamable words (0A.12): bundled education defaults, replaced at runtime by the institution's own labels.
export const NAMESPACES = ['common', 'language', 'errors', 'format', 'locale', 'labels', 'terminology', 'ui', 'gallery', 'shell'] as const;
export const DEFAULT_NAMESPACE = 'common';

/** The bundled default labels, to restore after sign-out. */
export const bundledLabels = { en: enLabels, bn: bnLabels } as const;

export const resources = {
  en: { common: enCommon, language: enLanguage, errors: enErrors, format: enFormat, locale: enLocale, labels: enLabels, terminology: enTerminology, ui: enUi, gallery: enGallery, shell: enShell },
  bn: { common: bnCommon, language: bnLanguage, errors: bnErrors, format: bnFormat, locale: bnLocale, labels: bnLabels, terminology: bnTerminology, ui: bnUi, gallery: bnGallery, shell: bnShell },
} as const;
