// Translating the error contract (0A.06 messageKey → errors namespace). Server keys are dynamic strings, so they are
// looked up here in one place; `npm run check:i18n` proves every messageKey and action exists in every language.
import type { ErrorInfo } from '../../supabase/functions/_shared/errors.ts';

import { useTranslation } from './index';

export function errorKeys(info: Pick<ErrorInfo, 'messageKey' | 'action'>): { message: string; action: string | null } {
  return {
    message: info.messageKey.replace(/^errors\./, ''),
    action: info.action === 'none' ? null : `actions.${info.action}`,
  };
}

/** Returns a function that turns an ErrorInfo into translated text for the current language. */
export function useErrorText() {
  const { t } = useTranslation('errors');
  const lookup = t as unknown as (key: string) => string; // keys verified by scripts/check-translations.mjs
  return (info: Pick<ErrorInfo, 'messageKey' | 'action'>) => {
    const keys = errorKeys(info);
    return { message: lookup(keys.message), action: keys.action ? lookup(keys.action) : null };
  };
}
