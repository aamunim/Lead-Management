import { useSyncExternalStore } from 'react';

import { readClaims, type SessionClaims } from './session';
import { supabase } from './supabase';

// Who is signed in, for the shell's route guards (0A.14). 'loading' until the stored session has been read.
export type AuthState =
  | { status: 'loading' }
  | { status: 'signedOut'; reason?: 'idle' | 'locked_out' }
  | { status: 'signedIn'; userId: string; email: string | null; claims: SessionClaims };

let state: AuthState = { status: 'loading' };
const subscribers = new Set<() => void>();
let signOutReason: 'idle' | 'locked_out' | undefined;

function publish(next: AuthState) {
  state = next;
  for (const notify of subscribers) notify();
}

/** The next sign-out shows why it happened on the sign-in screen (idle sign-out, too many wrong PINs). */
export function setSignOutReason(reason: 'idle' | 'locked_out'): void {
  signOutReason = reason;
}

function fromSession(session: { access_token: string; user: { id: string; email?: string | null } } | null) {
  if (!session) {
    publish({ status: 'signedOut', reason: signOutReason });
    signOutReason = undefined;
    return;
  }
  publish({ status: 'signedIn', userId: session.user.id, email: session.user.email ?? null, claims: readClaims(session.access_token) });
}

void supabase.auth.getSession().then(({ data }) => fromSession(data.session)).catch(() => publish({ status: 'signedOut' }));
supabase.auth.onAuthStateChange((_event, session) => fromSession(session));

export function useAuthState(): AuthState {
  return useSyncExternalStore(
    (notify) => {
      subscribers.add(notify);
      return () => subscribers.delete(notify);
    },
    () => state,
  );
}
