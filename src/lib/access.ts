import { useCallback, useEffect, useState } from 'react';

import { hasPermission } from './admin-core';
import { useAuthState } from './auth-state';
import { callWithSessionRetry, type ErrorInfo } from './errors';
import { supabase } from './supabase';

// The signed-in person's own access in the active institution (my_access, 0A.17), to HIDE screens and actions they
// cannot use (0A.18, Ch 4.7). It is never the real check: every RPC checks can() on the server again.
// A failed load is an error state (with Retry), never "no permissions" — that would hide screens silently.
type MyAccess = { permissions: Record<string, string[]>; flags: string[] };
type Entry = { key: string; value: MyAccess | null; error: ErrorInfo | null };

let cache: Entry = { key: '', value: null, error: null };

export function useMyAccess(): {
  loaded: boolean; error: ErrorInfo | null; retry: () => void; can: (permission: string) => boolean; access: MyAccess | null;
} {
  const auth = useAuthState();
  const institutionId = auth.status === 'signedIn' ? auth.claims.active_institution_id ?? null : null;
  const key = auth.status === 'signedIn' ? `${auth.userId}|${institutionId ?? ''}|${auth.claims.access_version ?? ''}` : '';
  const [entry, setEntry] = useState<Entry>(cache.key === key ? cache : { key, value: null, error: null });
  const [attempt, setAttempt] = useState(0);

  useEffect(() => {
    let alive = true;
    if (!key || !institutionId) {
      setEntry({ key, value: null, error: null });
      return undefined;
    }
    if (cache.key === key && cache.value) {
      setEntry(cache);
      return undefined;
    }
    setEntry({ key, value: null, error: null });
    void callWithSessionRetry<MyAccess>('access.mine', async () => {
      const { data, error } = await supabase.rpc('my_access');
      return { data: data as MyAccess | null, error };
    }).then(({ data, error }) => {
      if (!alive) return;
      const next = { key, value: error ? null : data, error };
      if (!error) cache = next;
      setEntry(next);
    });
    return () => {
      alive = false;
    };
  }, [key, institutionId, attempt]);

  const retry = useCallback(() => setAttempt((n) => n + 1), []);
  const current = entry.key === key ? entry : { key, value: null, error: null };
  return {
    loaded: current.value !== null, error: current.error, retry, access: current.value,
    can: (permission) => hasPermission(current.value?.permissions, permission),
  };
}
