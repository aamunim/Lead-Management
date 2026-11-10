import { AppState } from 'react-native';

import { supabase } from './supabase';

// Server clock (0A.11-T6, Ch 47.7). Phones often have a wrong clock or time zone; every "now" in the app comes from
// serverNow(), which is the phone clock corrected by the offset measured against the server. This file is the only
// place allowed to read the phone clock directly (enforced by scripts/check-ui-strings.mjs).

let offsetMs = 0;
let measured = false;
let institutionTimeZone: string | null = null;
const listeners = new Set<() => void>();

/** Offset from a request: server time minus the phone time at the middle of the round trip. */
export function offsetFrom(serverIso: string, sentAt: number, receivedAt: number): number {
  return Date.parse(serverIso) - Math.round((sentAt + receivedAt) / 2);
}

export async function syncServerTime(): Promise<void> {
  const sentAt = Date.now();
  const { data, error } = await supabase.rpc('server_time');
  const receivedAt = Date.now();
  if (error || !data) return;
  const result = data as { now: string; time_zone: string };
  const next = offsetFrom(result.now, sentAt, receivedAt);
  // Keep the previous value if this round trip was very slow (the measurement is less precise than it).
  if (!measured || receivedAt - sentAt < 5000) {
    offsetMs = next;
    measured = true;
  }
  institutionTimeZone = result.time_zone;
  for (const notify of listeners) notify();
}

/** The current time in epoch ms according to the server. */
export function serverNow(): number {
  return Date.now() + offsetMs;
}

export function serverClockInfo(): { offsetMs: number; measured: boolean; timeZone: string | null } {
  return { offsetMs, measured, timeZone: institutionTimeZone };
}

export function onServerTime(listener: () => void): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

AppState.addEventListener('change', (state) => {
  if (state === 'active') void syncServerTime().catch(() => undefined);
});
supabase.auth.onAuthStateChange((event) => {
  if (event === 'SIGNED_IN' || event === 'TOKEN_REFRESHED') setTimeout(() => void syncServerTime().catch(() => undefined), 0);
});
