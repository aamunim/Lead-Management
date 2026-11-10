// App side of the error contract (0A.06-T5). Every failed call becomes { code, messageKey, action } so screens can
// show a translated error with the right next step — never a silent empty list (principle 10).
import { toErrorInfo, type ErrorInfo } from '../../supabase/functions/_shared/errors.ts';
import { logger } from './logger';
import { refreshAfterAccessChange } from './session';

export type { ErrorInfo };

/** Normalises any error, logs it (tagged + redacted) and returns what the screen should show. */
export function describeError(error: unknown, where: string): ErrorInfo {
  const info = toErrorInfo(error);
  void logger.error('call.failed', { where, code: info.code, error });
  return info;
}

/**
 * Runs a call; on "session_refresh_required" refreshes the session once and retries (access changed, 0A.17).
 * Any other failure is returned as ErrorInfo for the screen's error state.
 */
export async function callWithSessionRetry<T>(
  where: string,
  call: () => Promise<{ data: T | null; error: unknown }>,
): Promise<{ data: T | null; error: ErrorInfo | null }> {
  let result = await call();
  if (result.error && toErrorInfo(result.error).action === 'refresh_session') {
    await refreshAfterAccessChange();
    result = await call();
  }
  if (result.error) return { data: null, error: describeError(result.error, where) };
  return { data: result.data, error: null };
}
