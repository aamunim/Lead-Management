import * as Crypto from 'expo-crypto';
import * as LocalAuthentication from 'expo-local-authentication';
import * as SecureStore from 'expo-secure-store';
import { useSyncExternalStore } from 'react';
import { AppState, Platform } from 'react-native';

import { onCacheClear } from './cache';
import { serverNow } from './server-time';
import { supabase } from './supabase';

// Optional app lock (0A.14-T7, Ch 47.10): a 4–6 digit PIN (stored only as a salted SHA-256 hash in the phone's
// secure store, never on the server) and, if the phone has one, the fingerprint. The app locks on start and after
// LOCK_AFTER_MS in the background. Five wrong PINs sign the person out. Not offered on the web (no secure store).

export const LOCK_AFTER_MS = 30_000;
export const MAX_ATTEMPTS = 5;
type Record = { salt: string; hash: string; biometrics: boolean };
type State = { userId: string | null; enabled: boolean; locked: boolean; attempts: number };

let state: State = { userId: null, enabled: false, locked: false, attempts: 0 };
let backgroundAt: number | null = null;
const subscribers = new Set<() => void>();
const publish = (next: Partial<State>) => {
  state = { ...state, ...next };
  for (const notify of subscribers) notify();
};

export const appLockAvailable = Platform.OS !== 'web';
const storeKey = (userId: string) => `applock_${userId}`;
const hex = (bytes: Uint8Array) => Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
const hashPin = (salt: string, pin: string) => Crypto.digestStringAsync(Crypto.CryptoDigestAlgorithm.SHA256, `${salt}:${pin}`);

async function readRecord(userId: string): Promise<Record | null> {
  if (!appLockAvailable) return null;
  const raw = await SecureStore.getItemAsync(storeKey(userId)).catch(() => null);
  return raw ? (JSON.parse(raw) as Record) : null;
}

export const isValidPin = (pin: string) => /^[0-9]{4,6}$/.test(pin);

export async function biometricsAvailable(): Promise<boolean> {
  if (!appLockAvailable) return false;
  return (await LocalAuthentication.hasHardwareAsync().catch(() => false)) && (await LocalAuthentication.isEnrolledAsync().catch(() => false));
}

/** Turns the lock on with a new PIN (and the fingerprint when the phone has one). */
export async function enableAppLock(pin: string): Promise<void> {
  if (!appLockAvailable || !state.userId || !isValidPin(pin)) throw new Error('app_lock_unavailable');
  const salt = hex(Crypto.getRandomBytes(16));
  const record: Record = { salt, hash: await hashPin(salt, pin), biometrics: await biometricsAvailable() };
  await SecureStore.setItemAsync(storeKey(state.userId), JSON.stringify(record));
  publish({ enabled: true, attempts: 0 });
}

export async function disableAppLock(): Promise<void> {
  if (state.userId) await SecureStore.deleteItemAsync(storeKey(state.userId)).catch(() => undefined);
  publish({ enabled: false, locked: false, attempts: 0 });
}

/** Checks a PIN; after MAX_ATTEMPTS wrong ones the person is signed out ('locked_out'). */
export async function unlockWithPin(pin: string): Promise<'ok' | 'wrong' | 'locked_out'> {
  if (!state.userId) return 'wrong';
  const record = await readRecord(state.userId);
  if (record && (await hashPin(record.salt, pin)) === record.hash) {
    publish({ locked: false, attempts: 0 });
    return 'ok';
  }
  const attempts = state.attempts + 1;
  publish({ attempts });
  return attempts >= MAX_ATTEMPTS ? 'locked_out' : 'wrong';
}

export async function unlockWithBiometrics(prompt: string): Promise<boolean> {
  if (!state.userId || !(await readRecord(state.userId))?.biometrics) return false;
  const result = await LocalAuthentication.authenticateAsync({ promptMessage: prompt, disableDeviceFallback: true });
  if (result.success) publish({ locked: false, attempts: 0 });
  return result.success;
}

export function useAppLock(): State {
  return useSyncExternalStore(
    (notify) => {
      subscribers.add(notify);
      return () => subscribers.delete(notify);
    },
    () => state,
  );
}

async function loadFor(userId: string | null, lockNow: boolean) {
  if (!userId) {
    publish({ userId: null, enabled: false, locked: false, attempts: 0 });
    return;
  }
  const enabled = (await readRecord(userId)) !== null;
  publish({ userId, enabled, locked: enabled && lockNow, attempts: 0 });
}

// Start: lock if enabled. Sign-in: not locked (they just proved who they are). Sign-out: forget this user's PIN.
void supabase.auth.getSession().then(({ data }) => loadFor(data.session?.user.id ?? null, true));
supabase.auth.onAuthStateChange((event, session) => {
  if (event === 'SIGNED_IN') void loadFor(session?.user.id ?? null, false);
  if (event === 'SIGNED_OUT') publish({ userId: null, enabled: false, locked: false, attempts: 0 });
});
onCacheClear(async (event) => {
  if (event.type === 'signOut' && state.userId) await disableAppLock();
});

// Background for longer than LOCK_AFTER_MS → locked when the app comes back (a phone left on a desk).
AppState.addEventListener('change', (next) => {
  if (next === 'background') backgroundAt = serverNow();
  if (next === 'active' && backgroundAt !== null) {
    if (state.enabled && serverNow() - backgroundAt >= LOCK_AFTER_MS) publish({ locked: true });
    backgroundAt = null;
  }
});
