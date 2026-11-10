import { useEffect } from 'react';
import { AppState, Platform } from 'react-native';

import { setSignOutReason } from './auth-state';
import { serverNow } from './server-time';
import { signOut } from './session';
import { useSetting } from './settings';

// Idle sign-out (0A.14-T7, Ch 47.10): after the institution's `idle_signout_minutes` without a touch or key press
// (0 = never), the person is signed out and the caches are wiped; the sign-in screen says why.
let lastActivity = serverNow();
export function reportActivity(): void {
  lastActivity = serverNow();
}

export function useIdleSignOut(): void {
  const minutes = useSetting<number>('idle_signout_minutes', 0);
  useEffect(() => {
    if (!minutes || minutes <= 0) return undefined;
    reportActivity();
    const limit = minutes * 60_000;
    const check = () => {
      if (serverNow() - lastActivity >= limit) {
        setSignOutReason('idle');
        void signOut();
      }
    };
    const timer = setInterval(check, 5_000);
    const sub = AppState.addEventListener('change', (state) => {
      if (state === 'active') check();
    });
    let removeWeb: (() => void) | undefined;
    if (Platform.OS === 'web' && typeof window !== 'undefined') {
      const events = ['keydown', 'pointerdown', 'wheel'] as const;
      events.forEach((e) => window.addEventListener(e, reportActivity, { passive: true }));
      removeWeb = () => events.forEach((e) => window.removeEventListener(e, reportActivity));
    }
    return () => {
      clearInterval(timer);
      sub.remove();
      removeWeb?.();
    };
  }, [minutes]);
}
