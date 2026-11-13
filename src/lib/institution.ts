import { useEffect, useState } from 'react';

import { useAuthState } from './auth-state';
import { cacheKey, onCacheClear, readCache, writeCache } from './cache';
import { onSettingsVersion } from './settings-version';
import { supabase } from './supabase';

// The active institution's display data for the top bar (0A.14-T1): name and short name (0B.10 branding: the logo and
// colour are settings). Cached per user + institution for an instant first paint, cleared with the caches; read again
// after a branding change (this device) or a newer settings version (other devices).
export type InstitutionInfo = { id: string; name: string; shortName: string | null };

let memory: InstitutionInfo | null = null;
let generation = 0;
const listeners = new Set<() => void>();
const generationListeners = new Set<() => void>();

/** Reads the name and short name again (after Settings → Branding, or when another device changed them). */
export function refreshInstitutionInfo(): void {
  generation += 1;
  for (const l of generationListeners) l();
}
let seenVersion = 0;
onSettingsVersion((version) => {
  // Every response carries the version: read again only when it went up (not on the first one seen).
  if (seenVersion && version > seenVersion) refreshInstitutionInfo();
  if (version > seenVersion) seenVersion = version;
});
onCacheClear(() => {
  memory = null;
  seenVersion = 0;
  for (const l of listeners) l();
});

export function useActiveInstitution(): InstitutionInfo | null {
  const auth = useAuthState();
  const userId = auth.status === 'signedIn' ? auth.userId : null;
  const institutionId = auth.status === 'signedIn' ? auth.claims.active_institution_id ?? null : null;
  const [info, setInfo] = useState<InstitutionInfo | null>(memory?.id === institutionId ? memory : null);
  const [gen, setGen] = useState(generation);
  useEffect(() => {
    const bump = () => setGen(generation);
    generationListeners.add(bump);
    return () => {
      generationListeners.delete(bump);
    };
  }, []);

  useEffect(() => {
    const reset = () => setInfo(memory?.id === institutionId ? memory : null);
    listeners.add(reset);
    return () => {
      listeners.delete(reset);
    };
  }, [institutionId]);

  useEffect(() => {
    let alive = true;
    if (!userId || !institutionId) {
      setInfo(null);
      return undefined;
    }
    const key = cacheKey({ userId, institutionId }, 'institution');
    void (async () => {
      const cached = await readCache<InstitutionInfo>(key);
      if (alive && cached?.id === institutionId) setInfo(cached);
      const { data } = await supabase.from('institutions').select('id, name, short_name').eq('id', institutionId).maybeSingle();
      if (!alive || !data) return;
      const next = { id: data.id as string, name: data.name as string, shortName: (data.short_name as string | null) ?? null };
      memory = next;
      setInfo(next);
      await writeCache(key, next);
    })();
    return () => {
      alive = false;
    };
  }, [userId, institutionId, gen]);

  return info;
}
