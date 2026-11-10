import { useSyncExternalStore } from 'react';

// App-wide status flags shown by the shell (0A.14): "please update the app" blocks every screen.
let upgradeRequired = false;
const subscribers = new Set<() => void>();

export function markUpgradeRequired(): void {
  if (upgradeRequired) return;
  upgradeRequired = true;
  for (const notify of subscribers) notify();
}

export function useUpgradeRequired(): boolean {
  return useSyncExternalStore(
    (notify) => {
      subscribers.add(notify);
      return () => subscribers.delete(notify);
    },
    () => upgradeRequired,
  );
}
