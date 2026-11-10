import { useCallback, useMemo } from 'react';
import type { NativeScrollEvent, NativeSyntheticEvent } from 'react-native';

import { useAuthState } from './auth-state';
import { cacheKey, onCacheClear } from './cache';

// "Keep in place" (0A.14-T5, Ch 15, 47.6): a list remembers where it was, so coming back from a lead opens the list
// at the same spot. In memory only, per user + institution; cleared with the caches. Lists in 1A use:
//   const place = useKeepInPlace('leads');  <FlatList contentOffset={place.contentOffset} onScroll={place.onScroll} />
const offsets = new Map<string, number>();
onCacheClear(() => offsets.clear());

export function useKeepInPlace(listKey: string) {
  const auth = useAuthState();
  const key = auth.status === 'signedIn'
    ? cacheKey({ userId: auth.userId, institutionId: auth.claims.active_institution_id }, 'scroll', listKey)
    : null;
  const onScroll = useCallback((event: NativeSyntheticEvent<NativeScrollEvent>) => {
    if (key) offsets.set(key, event.nativeEvent.contentOffset.y);
  }, [key]);
  const contentOffset = useMemo(() => ({ x: 0, y: key ? offsets.get(key) ?? 0 : 0 }), [key]);
  return { onScroll, contentOffset, scrollEventThrottle: 100 };
}
