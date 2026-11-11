import AsyncStorage from '@react-native-async-storage/async-storage';
import * as Crypto from 'expo-crypto';

import { callWithSessionRetry, type ErrorInfo } from './errors';
import { supabase } from './supabase';

// Master Admin panel (0B.02): two-step sign-in, the platform session (rights, new-device alert), platform users.
// The server checks every right again and needs an aal2 session for all of them.
export type PlatformRole = 'master_admin' | 'support' | 'billing' | 'developer';
export type PlatformSession = { user_id: string; email: string; platform_role: PlatformRole; new_device: boolean; permissions: string[] };
export type PlatformUser = {
  user_id: string; email: string; name: string | null; platform_role: PlatformRole; status: 'active' | 'deactivated';
  extra_permissions: string[]; last_seen: string | null; has_second_factor: boolean;
};
export type PlatformAlert = { id: string; kind: string; payload: Record<string, string>; created_at: string; read: boolean };
type Result<T> = { data: T | null; error: ErrorInfo | null };

const DEVICE_KEY = 'panel_device_id'; // device preference, not user data (stays after sign-out)

export async function deviceId(): Promise<string> {
  const existing = await AsyncStorage.getItem(DEVICE_KEY).catch(() => null);
  if (existing) return existing;
  const id = Crypto.randomUUID();
  await AsyncStorage.setItem(DEVICE_KEY, id).catch(() => undefined);
  return id;
}

const rpc = <T>(where: string, fn: string, args?: Record<string, unknown>): Promise<Result<T>> =>
  callWithSessionRetry<T>(where, async () => {
    const { data, error } = await supabase.rpc(fn, args);
    return { data: data as T | null, error };
  });

/** Where the second step stands: 'verify' (has an authenticator), 'enroll' (first time) or 'done' (aal2). */
export async function secondStepState(): Promise<{ state: 'verify' | 'enroll' | 'done'; factorId: string | null }> {
  const { data: aal } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
  if (aal?.currentLevel === 'aal2') return { state: 'done', factorId: null };
  const { data } = await supabase.auth.mfa.listFactors();
  const factor = data?.totp?.[0];
  return factor ? { state: 'verify', factorId: factor.id } : { state: 'enroll', factorId: null };
}

/** First time: creates an authenticator factor; the person adds the key to their authenticator app. */
export async function enrollAuthenticator(): Promise<{ factorId: string; secret: string; uri: string } | { error: unknown }> {
  // An unfinished earlier attempt is removed first (only one authenticator in progress).
  const { data: list } = await supabase.auth.mfa.listFactors();
  for (const f of list?.all ?? []) if (f.status !== 'verified') await supabase.auth.mfa.unenroll({ factorId: f.id });
  const { data, error } = await supabase.auth.mfa.enroll({ factorType: 'totp', friendlyName: 'Authenticator' });
  if (error || !data) return { error };
  return { factorId: data.id, secret: data.totp.secret, uri: data.totp.uri };
}

export async function verifySecondStep(factorId: string, code: string): Promise<{ error: unknown } | null> {
  const { error } = await supabase.auth.mfa.challengeAndVerify({ factorId, code: code.replace(/\s/g, '') });
  return error ? { error } : null;
}

export async function startPlatformSession(): Promise<Result<PlatformSession>> {
  return rpc<PlatformSession>('platform.session', 'platform_session_start', { p_device_fingerprint: await deviceId() });
}

export const fetchPlatformAlerts = () => rpc<PlatformAlert[]>('platform.alerts', 'platform_alerts_list');
export const fetchPlatformUsers = () =>
  rpc<{ users: PlatformUser[]; invites: { email: string; platform_role: PlatformRole; invited_at: string }[] }>('platform.users', 'platform_users_list');
export const invitePlatformUser = (email: string, role: PlatformRole) =>
  rpc<null>('platform.invite', 'platform_user_invite', { p_email: email.trim(), p_role: role });
export const updatePlatformUser = (userId: string, role: PlatformRole, status: 'active' | 'deactivated', extra: string[] | null, reason: string | null) =>
  rpc<null>('platform.user', 'platform_user_update', { p_user_id: userId, p_role: role, p_status: status, p_extra_permissions: extra, p_reason: reason });
export const cancelPlatformInvite = (email: string) => rpc<null>('platform.inviteCancel', 'platform_invite_cancel', { p_email: email });
export const fetchProductConfig = () => rpc<{ app_name: string }>('platform.product', 'product_config');
