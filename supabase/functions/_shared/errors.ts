// Error contract (0A.06-T5, principle 10): every RPC / Edge Function error has a stable code and a user-safe
// message key (translated in the app). The UI shows an error state with Retry — never an empty list.
// Codes raised by the database (docs/dev/TENANCY.md) are mapped here so the app reacts the same way everywhere.

export type ErrorAction = 'sign_in' | 'choose_institution' | 'refresh_session' | 'upgrade_app' | 'fix_input' | 'retry' | 'none';

export type ErrorInfo = { code: string; messageKey: string; httpStatus: number; action: ErrorAction };

export const ERRORS: Record<string, ErrorInfo> = {
  not_signed_in: { code: 'not_signed_in', messageKey: 'errors.not_signed_in', httpStatus: 401, action: 'sign_in' },
  no_active_institution: {
    code: 'no_active_institution', messageKey: 'errors.no_active_institution', httpStatus: 409, action: 'choose_institution',
  },
  membership_not_active: {
    code: 'membership_not_active', messageKey: 'errors.membership_not_active', httpStatus: 403, action: 'choose_institution',
  },
  session_refresh_required: {
    code: 'session_refresh_required', messageKey: 'errors.session_refresh_required', httpStatus: 409, action: 'refresh_session',
  },
  upgrade_required: { code: 'upgrade_required', messageKey: 'errors.upgrade_required', httpStatus: 426, action: 'upgrade_app' },
  setting_invalid: { code: 'setting_invalid', messageKey: 'errors.setting_invalid', httpStatus: 422, action: 'fix_input' },
  setting_unknown: { code: 'setting_unknown', messageKey: 'errors.unknown', httpStatus: 404, action: 'none' },
  not_a_member: { code: 'not_a_member', messageKey: 'errors.not_a_member', httpStatus: 403, action: 'none' },
  institution_mismatch: { code: 'institution_mismatch', messageKey: 'errors.forbidden', httpStatus: 403, action: 'none' },
  protected_column: { code: 'protected_column', messageKey: 'errors.forbidden', httpStatus: 403, action: 'none' },
  permission_denied: { code: 'permission_denied', messageKey: 'errors.forbidden', httpStatus: 403, action: 'none' },
  language_unsupported: { code: 'language_unsupported', messageKey: 'errors.language_unsupported', httpStatus: 422, action: 'fix_input' },
  extension_disabled: { code: 'extension_disabled', messageKey: 'errors.extension_disabled', httpStatus: 403, action: 'none' },
  phone_invalid: { code: 'phone_invalid', messageKey: 'errors.phone_invalid', httpStatus: 422, action: 'fix_input' },
  number_invalid: { code: 'number_invalid', messageKey: 'errors.number_invalid', httpStatus: 422, action: 'fix_input' },
  label_unknown: { code: 'label_unknown', messageKey: 'errors.unknown', httpStatus: 404, action: 'none' },
  label_invalid: { code: 'label_invalid', messageKey: 'errors.label_invalid', httpStatus: 422, action: 'fix_input' },
  label_too_long: { code: 'label_too_long', messageKey: 'errors.label_too_long', httpStatus: 422, action: 'fix_input' },
  label_locked: { code: 'label_locked', messageKey: 'errors.label_locked', httpStatus: 423, action: 'none' },
  label_not_lockable: { code: 'label_not_lockable', messageKey: 'errors.unknown', httpStatus: 422, action: 'none' },
  timeout: { code: 'timeout', messageKey: 'errors.timeout', httpStatus: 504, action: 'retry' },
  network: { code: 'network', messageKey: 'errors.network', httpStatus: 503, action: 'retry' },
  unknown: { code: 'unknown', messageKey: 'errors.unknown', httpStatus: 500, action: 'retry' },
};

/** Maps any thrown value (Postgres / PostgREST / fetch / our own) to the contract. */
export function toErrorInfo(error: unknown): ErrorInfo {
  const raw = error as { message?: string; code?: string; name?: string } | null | undefined;
  const message = (raw?.message ?? (typeof error === 'string' ? error : '')).trim();
  if (message && ERRORS[message]) return ERRORS[message];
  if (raw?.code && ERRORS[raw.code]) return ERRORS[raw.code];
  if (raw?.code === '42501' || /permission denied/i.test(message)) return ERRORS.permission_denied;
  if (raw?.name === 'AbortError' || /timed? ?out/i.test(message)) return ERRORS.timeout;
  if (/network|fetch failed|failed to fetch/i.test(message)) return ERRORS.network;
  return ERRORS.unknown;
}
