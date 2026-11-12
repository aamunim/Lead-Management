import { callWithSessionRetry, type ErrorInfo } from './errors';
import { supabase } from './supabase';

// Support entry (0B.08): a platform user enters one institution with a reason and a time limit. The server puts the
// institution and the session into the token, refuses writes while read only, and logs everything for the
// institution. After starting or ending, the token is refreshed so it carries (or drops) the session.
export type SupportSession = { id: string; institution_id: string; institution_name: string; mode: 'read_only' | 'edit'; expires_at: string; edit_requested: boolean };
export type SupportLogRow = {
  id: string; by: string; reason: string; mode: string; edit_reason: string | null; started_at: string; expires_at: string; ended_at: string | null;
  writes: number; actions: { action: string; target: string; at: string }[];
};
export type EditRequest = { id: string; institution: string; by: string; reason: string; edit_reason: string; requested_at: string; expires_at: string };
export type PlatformAuditRow = { action: string; at: string; by: string | null; target: string; target_id: string | null; reason: string | null; support_session_id: string | null };
type Result<T> = { data: T | null; error: ErrorInfo | null };

const rpc = <T>(where: string, fn: string, args?: Record<string, unknown>): Promise<Result<T>> =>
  callWithSessionRetry<T>(where, async () => {
    const { data, error } = await supabase.rpc(fn, args);
    return { data: data as T | null, error };
  });

export async function startSupport(institution: string, reason: string, minutes: number): Promise<Result<{ id: string }>> {
  const r = await rpc<{ id: string }>('support.start', 'support_session_start', { p_institution: institution, p_reason: reason, p_minutes: minutes });
  if (!r.error) await supabase.auth.refreshSession();
  return r;
}
export async function endSupport(): Promise<Result<null>> {
  const r = await rpc<null>('support.end', 'support_session_end');
  await supabase.auth.refreshSession();
  return r;
}
export const currentSupport = () => rpc<SupportSession | null>('support.current', 'support_session_current');
export const requestEdit = (reason: string) => rpc<null>('support.requestEdit', 'support_edit_request', { p_reason: reason });
export const approveEdit = (id: string) => rpc<null>('support.approveEdit', 'support_edit_approve', { p_session: id });
export const fetchEditRequests = () => rpc<EditRequest[]>('support.editRequests', 'support_edit_requests');
export const fetchSupportLog = () => rpc<SupportLogRow[]>('support.log', 'support_access_log');
export const fetchInstitutionAudit = (id: string) => rpc<PlatformAuditRow[]>('support.audit', 'platform_institution_audit', { p_institution: id });

/** Does the current token carry a support session? (decoded locally; the server checks it on every call) */
export async function tokenHasSupport(): Promise<boolean> {
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;
  if (!token) return false;
  try {
    const payload = JSON.parse(atob(token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/'))) as { support_session_id?: string };
    return !!payload.support_session_id;
  } catch {
    return false;
  }
}
