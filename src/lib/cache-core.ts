// Cache namespaces (0A.14-T2, Ch 4.3, 47.9). Pure: unit-tested in Node (scripts/tests/shell.test.mjs).
// Every cached piece of institution or user data lives under a key that names its owner:
//   c|<user id>|<institution id or ->|<what…>
// so it can be wiped exactly: everything on sign-out, the previous institution's data on a switch, another user's
// data when a different person signs in. Device preferences (language, appearance) are not under `c|` and stay.

export const CACHE_PREFIX = 'c|';
export type CacheScope = { userId: string | null | undefined; institutionId: string | null | undefined };
export type ClearEvent =
  | { type: 'signOut' }
  | { type: 'institutionSwitch'; from: string | null | undefined }
  | { type: 'accessChanged'; institutionId: string | null | undefined }
  | { type: 'userChange'; userId: string };

export function cacheKey(scope: CacheScope, ...parts: string[]): string {
  const clean = (v: string) => v.replace(/\|/g, '_');
  return `${CACHE_PREFIX}${clean(scope.userId ?? 'anon')}|${clean(scope.institutionId ?? '-')}|${parts.map(clean).join('|')}`;
}

export function parseCacheKey(key: string): { userId: string; institutionId: string; rest: string } | null {
  if (!key.startsWith(CACHE_PREFIX)) return null;
  const [userId, institutionId, ...rest] = key.slice(CACHE_PREFIX.length).split('|');
  if (userId === undefined || institutionId === undefined) return null;
  return { userId, institutionId, rest: rest.join('|') };
}

/** Which stored keys an event must remove. */
export function keysToClear(keys: readonly string[], event: ClearEvent): string[] {
  return keys.filter((key) => {
    const parsed = parseCacheKey(key);
    if (!parsed) return false;
    switch (event.type) {
      case 'signOut':
        return true;
      case 'institutionSwitch':
        return parsed.institutionId === (event.from ?? '-');
      case 'accessChanged':
        return parsed.institutionId === (event.institutionId ?? '-');
      case 'userChange':
        return parsed.userId !== event.userId;
      default:
        return false;
    }
  });
}

export type KeyValueStore = {
  getAllKeys(): Promise<readonly string[]>;
  multiRemove(keys: readonly string[]): Promise<void>;
};

/** Removes the stored keys for an event and runs every in-memory clearer (screens drop what they show). */
export async function clearCaches(store: KeyValueStore, clearers: Iterable<(event: ClearEvent) => void | Promise<void>>, event: ClearEvent) {
  const keys = keysToClear(await store.getAllKeys(), event);
  if (keys.length > 0) await store.multiRemove(keys);
  for (const clear of clearers) await clear(event);
  return keys.length;
}
