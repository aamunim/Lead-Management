import AsyncStorage from '@react-native-async-storage/async-storage';
import { useSyncExternalStore } from 'react';
import { AppState } from 'react-native';

import { currentClaims, onInstitutionChange } from './session';
import { onSettingsVersion } from './settings-version';
import { supabase } from './supabase';

// Settings store (0A.08-T5): loaded once after sign-in, cached per user + institution (memory + AsyncStorage),
// cleared on sign-out / user change / institution switch, and refreshed when the server's settings_version rises
// (x-settings-version on any response) or when the app returns to the foreground.

type Snapshot = {
  userId: string | null;
  institutionId: string | null;
  version: number;
  values: Record<string, unknown>;
  loadedAt: number;
};

const empty: Snapshot = { userId: null, institutionId: null, version: 0, values: {}, loadedAt: 0 };
let snapshot: Snapshot = empty;
let loading: Promise<void> | null = null;
const subscribers = new Set<() => void>();
const storageKey = (userId: string, institutionId: string) => `settings:${userId}:${institutionId}`;

function publish(next: Snapshot) {
  snapshot = next;
  for (const notify of subscribers) notify();
}

/** Loads (or reloads) the active institution's resolved settings. Shows the cached copy first, then refreshes. */
export async function loadSettings(force = false): Promise<void> {
  if (loading && !force) return loading;
  loading = (async () => {
    const claims = await currentClaims();
    const userId = claims.sub ?? null;
    const institutionId = claims.active_institution_id ?? null;
    if (!userId || !institutionId) {
      publish(empty);
      return;
    }
    if (snapshot.userId !== userId || snapshot.institutionId !== institutionId) {
      try {
        const cached = await AsyncStorage.getItem(storageKey(userId, institutionId));
        if (cached) publish(JSON.parse(cached) as Snapshot);
      } catch {
        // cache is a convenience only
      }
    }
    const { data, error } = await supabase.rpc('settings_get_all');
    if (error) throw error;
    const result = data as { settings_version: number; values: Record<string, unknown> };
    const next: Snapshot = { userId, institutionId, version: result.settings_version, values: result.values, loadedAt: Date.now() };
    publish(next);
    try {
      await AsyncStorage.setItem(storageKey(userId, institutionId), JSON.stringify(next));
    } catch {
      // ignore
    }
  })().finally(() => {
    loading = null;
  });
  return loading;
}

export function getSetting<T = unknown>(key: string, fallback?: T): T {
  return (key in snapshot.values ? snapshot.values[key] : fallback) as T;
}

export function settingsVersion(): number {
  return snapshot.version;
}

/** React hook: re-renders when the setting changes. */
export function useSetting<T = unknown>(key: string, fallback?: T): T {
  return useSyncExternalStore(
    (notify) => {
      subscribers.add(notify);
      return () => subscribers.delete(notify);
    },
    () => getSetting<T>(key, fallback),
  );
}

// A newer version reported by any response → reload once.
onSettingsVersion((version) => {
  if (snapshot.institutionId && version > snapshot.version) void loadSettings(true).catch(() => undefined);
});

// Institution switch / sign-out → forget this user's settings in memory.
onInstitutionChange(() => publish(empty));

// Back to the foreground after a while → refresh.
AppState.addEventListener('change', (state) => {
  if (state === 'active' && snapshot.institutionId && Date.now() - snapshot.loadedAt > 5 * 60_000) {
    void loadSettings(true).catch(() => undefined);
  }
});
