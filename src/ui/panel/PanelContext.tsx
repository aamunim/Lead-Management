import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from 'react';

import { useAuthState } from '@/lib/auth-state';
import type { ErrorInfo } from '@/lib/errors';
import { secondStepState, startPlatformSession, type PlatformSession } from '@/lib/platform';

// Panel access (0B.02): signed in → second step done (aal2) → a platform user (platform_session_start). Anything
// short of that shows the panel sign-in page. The server checks aal2 and the right on every call anyway.
export type PanelState =
  | { status: 'loading' }
  | { status: 'signedOut' }
  | { status: 'secondStep'; mode: 'verify' | 'enroll'; factorId: string | null }
  | { status: 'denied'; error: ErrorInfo }
  | { status: 'ready'; session: PlatformSession };

const Ctx = createContext<{ state: PanelState; refresh: () => void; can: (permission: string) => boolean } | null>(null);

export function PanelProvider({ children }: { children: ReactNode }) {
  const auth = useAuthState();
  const [state, setState] = useState<PanelState>({ status: 'loading' });
  const [attempt, setAttempt] = useState(0);
  const userId = auth.status === 'signedIn' ? auth.userId : null;

  useEffect(() => {
    let alive = true;
    if (auth.status === 'loading') return undefined;
    if (!userId) {
      setState({ status: 'signedOut' });
      return undefined;
    }
    void (async () => {
      const step = await secondStepState();
      if (!alive) return;
      if (step.state !== 'done') return setState({ status: 'secondStep', mode: step.state, factorId: step.factorId });
      const { data, error } = await startPlatformSession();
      if (!alive) return;
      if (error || !data) setState({ status: 'denied', error: error ?? { code: 'permission_denied', messageKey: 'errors.forbidden', httpStatus: 403, action: 'none' } });
      else setState({ status: 'ready', session: data });
    })();
    return () => {
      alive = false;
    };
  }, [auth.status, userId, attempt]);

  const refresh = useCallback(() => setAttempt((n) => n + 1), []);
  const can = useCallback((permission: string) => state.status === 'ready'
    && (state.session.platform_role === 'master_admin' || state.session.permissions.includes(permission)), [state]);
  return <Ctx.Provider value={{ state, refresh, can }}>{children}</Ctx.Provider>;
}

export function usePanel() {
  const value = useContext(Ctx);
  if (!value) throw new Error('usePanel outside PanelProvider'); // i18n-exempt: developer error
  return value;
}
