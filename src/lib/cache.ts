import AsyncStorage from '@react-native-async-storage/async-storage';

import { cacheKey, clearCaches, mayWriteKey, type CacheScope, type ClearEvent } from './cache-core';

// The app's cache namespace (0A.14-T2). Use cached(scope, …) for every stored piece of institution or user data;
// register in-memory stores with onCacheClear(). session.ts calls clearAppCaches() on sign-out, switch, access change
// and user change, so nothing of the previous institution or user stays on screen or in storage.
export { cacheKey, type CacheScope, type ClearEvent };

const clearers = new Set<(event: ClearEvent) => void | Promise<void>>();

export function onCacheClear(clear: (event: ClearEvent) => void | Promise<void>): () => void {
  clearers.add(clear);
  return () => clearers.delete(clear);
}

export async function clearAppCaches(event: ClearEvent): Promise<number> {
  try {
    return await clearCaches(AsyncStorage, clearers, event);
  } catch {
    // Storage errors must never keep the user from signing out; memory clearers still run.
    for (const clear of clearers) await clear(event);
    return 0;
  }
}

export async function readCache<T>(key: string): Promise<T | null> {
  try {
    const raw = await AsyncStorage.getItem(key);
    return raw ? (JSON.parse(raw) as T) : null;
  } catch {
    return null;
  }
}

// Who is signed in now (set by session.ts on every auth change): late writes for anyone else are dropped.
let owner: CacheScope = { userId: null, institutionId: null };
export function setCacheOwner(scope: CacheScope): void {
  owner = scope;
}

export async function writeCache(key: string, value: unknown): Promise<void> {
  if (!mayWriteKey(key, owner)) return;
  try {
    await AsyncStorage.setItem(key, JSON.stringify(value));
  } catch {
    // a cache is a convenience only
  }
}

export async function removeCache(key: string): Promise<void> {
  await AsyncStorage.removeItem(key).catch(() => undefined);
}
