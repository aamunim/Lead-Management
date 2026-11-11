import AsyncStorage from '@react-native-async-storage/async-storage';

import { clearAppCaches, onCacheClear, setCacheOwner } from './cache';
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

/** Every in-memory client cache registers here (alias of onCacheClear, kept for the stores written before 0A.14). */
export function onInstitutionChange(clear: () => void | Promise<void>): () => void {
  return onCacheClear(() => clear());
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
  const from = (await currentClaims()).active_institution_id ?? null;
  const { error } = await supabase.rpc('set_active_institution', { p_institution_id: institutionId });
  if (error) throw error;
  const { data, error: refreshError } = await supabase.auth.refreshSession();
  if (refreshError) throw refreshError;
  await clearAppCaches({ type: 'institutionSwitch', from });
  return readClaims(data.session?.access_token);
}

/** Refresh after the server says "session_refresh_required" (access changed, 0A.17). */
export async function refreshAfterAccessChange(): Promise<SessionClaims> {
  const before = (await currentClaims()).active_institution_id ?? null;
  const { data, error } = await supabase.auth.refreshSession();
  if (error) throw error;
  await clearAppCaches({ type: 'accessChanged', institutionId: before });
  return readClaims(data.session?.access_token);
}

/** "Sign out of all other devices" (Ch 47.10): revokes every other session of this user. */
export async function signOutOtherDevices(): Promise<void> {
  const { error } = await supabase.auth.signOut({ scope: 'others' });
  if (error) throw error;
}

/** Sign out on this device: the session goes and every cached piece of user / institution data is wiped (Ch 47.10). */
export async function signOut(): Promise<void> {
  setCacheOwner({ userId: null, institutionId: null }); // from now on, late answers write nothing
  await supabase.auth.signOut({ scope: 'local' }).catch(() => undefined);
  await clearAppCaches({ type: 'signOut' });
}

// The cache only accepts data of the person signed in now and their active institution (late writes are dropped).
supabase.auth.onAuthStateChange((_event, session) => {
  const claims = readClaims(session?.access_token);
  setCacheOwner({ userId: session?.user.id ?? null, institutionId: claims.active_institution_id ?? null });
});

// A different person signs in on this device → remove what the previous person left behind (Ch 47.12 #5).
const OWNER_KEY = 'cache_owner';
supabase.auth.onAuthStateChange((event, session) => {
  if (event !== 'SIGNED_IN' || !session?.user) return;
  const userId = session.user.id;
  setTimeout(() => {
    void (async () => {
      const previous = await AsyncStorage.getItem(OWNER_KEY).catch(() => null);
      if (previous !== userId) {
        await clearAppCaches({ type: 'userChange', userId });
        await AsyncStorage.setItem(OWNER_KEY, userId).catch(() => undefined);
      }
    })();
  }, 0);
});
