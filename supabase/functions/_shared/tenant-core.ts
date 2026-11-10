// Tenant context for Edge Functions (0A.06-T3) — runtime-independent core, unit-tested in Node.
// The user and the active institution come ONLY from the caller's session, re-checked in the database by
// public.current_session() (membership active, access_version current). Request bodies are never trusted for this.
import { Budget } from './budget.ts';
import { ERRORS, toErrorInfo, type ErrorInfo } from './errors.ts';
import { createLogger, type Logger } from './logger.ts';

export type TenantContext = {
  userId: string;
  institutionId: string;
  accessVersion: number | null;
  userKind: string;
  requestId: string;
  log: Logger;
  budget: Budget;
};

export type SessionCheck = (accessToken: string) => Promise<{
  data: { user_id: string; institution_id: string; access_version: number | null; user_kind: string } | null;
  error: unknown;
}>;

export type TenantResult = { ok: true; context: TenantContext } | { ok: false; error: ErrorInfo; log: Logger };

export async function resolveTenant(
  authorizationHeader: string | null,
  checkSession: SessionCheck,
  functionName: string,
  requestId: string,
  sink?: (line: string) => void,
): Promise<TenantResult> {
  const budget = new Budget();
  const baseLog = createLogger({ function: functionName, request_id: requestId }, sink);
  const token = authorizationHeader?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!token) {
    baseLog.warn('auth.missing_token');
    return { ok: false, error: ERRORS.not_signed_in, log: baseLog };
  }
  const { data, error } = await checkSession(token);
  if (error || !data) {
    const info = toErrorInfo(error ?? 'not_signed_in');
    baseLog.warn('auth.session_rejected', { code: info.code });
    return { ok: false, error: info, log: baseLog };
  }
  const log = baseLog.with({ institution_id: data.institution_id, user_id: data.user_id });
  return {
    ok: true,
    context: {
      userId: data.user_id,
      institutionId: data.institution_id,
      accessVersion: data.access_version,
      userKind: data.user_kind,
      requestId,
      log,
      budget,
    },
  };
}

export function errorResponseBody(error: ErrorInfo, requestId: string) {
  return { error: { code: error.code, message_key: error.messageKey, action: error.action, request_id: requestId } };
}
