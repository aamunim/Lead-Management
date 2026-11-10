import { supabase } from './supabase';

// Session helpers for the tenancy rules (0A.03, docs/dev/TENANCY.md).
// The active institution always comes from the server (token claim set by the access-token hook);
// the app never sends an institution id for authorisation.

export type SessionClaims = {
  sub?: string;
  active_institution_id?: string | null;
  access_version?: number | null;
  user_kind?: 'staff' | 'portal' | 'api';
};

/** Errors the database raises with a fixed code, so the app can react (refresh, choose institution, sign in). */
export const SESSION_ERRORS = {
  notSignedIn: 'not_signed_in',
  noActiveInstitution: 'no_active_institution',
  membershipNotActive: 'membership_not_active',
  sessionRefreshRequired: 'session_refresh_required',
  notAMember: 'not_a_member',
} as const;

type CacheClearer = () => void | Promise<void>;
const cacheClearers = new Set<CacheClearer>();

/** Every client cache registers here; caches are keyed by user + institution and are cleared on switch / sign-out. */
export function onInstitutionChange(clear: CacheClearer): () => void {
  cacheClearers.add(clear);
  return () => cacheClearers.delete(clear);
}

async function clearCaches(): Promise<void> {
  for (const clear of cacheClearers) await clear();
}

export function readClaims(accessToken: string | undefined): SessionClaims {
  if (!accessToken) return {};
  try {
    const payload = accessToken.split('.')[1] ?? '';
    const json = globalThis.atob(payload.replace(/-/g, '+').replace(/_/g, '/'));
    return JSON.parse(json) as SessionClaims;
  } catch {
    return {};
  }
}

export async function currentClaims(): Promise<SessionClaims> {
  const { data } = await supabase.auth.getSession();
  return readClaims(data.session?.access_token);
}

/**
 * Switch the active institution (D25): the server checks membership and records the choice,
 * then a fresh token is fetched so the new claim is used, and all client caches are cleared.
 */
export async function switchInstitution(institutionId: string): Promise<SessionClaims> {
  const { error } = await supabase.rpc('set_active_institution', { p_institution_id: institutionId });
  if (error) throw error;
  const { data, error: refreshError } = await supabase.auth.refreshSession();
  if (refreshError) throw refreshError;
  await clearCaches();
  return readClaims(data.session?.access_token);
}

/** Refresh after the server says "session_refresh_required" (access changed, 0A.17). */
export async function refreshAfterAccessChange(): Promise<SessionClaims> {
  const { data, error } = await supabase.auth.refreshSession();
  if (error) throw error;
  await clearCaches();
  return readClaims(data.session?.access_token);
}

/** "Sign out of all other devices" (Ch 47.10): revokes every other session of this user. */
export async function signOutOtherDevices(): Promise<void> {
  const { error } = await supabase.auth.signOut({ scope: 'others' });
  if (error) throw error;
}

export async function signOut(): Promise<void> {
  await supabase.auth.signOut({ scope: 'local' });
  await clearCaches();
}
