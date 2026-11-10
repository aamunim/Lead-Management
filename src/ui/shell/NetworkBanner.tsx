import { useNetworkState } from 'expo-network';
import { useEffect, useRef, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';

import { useTheme } from '../theme';

// Offline strip (0A.14-T6, Ch 47.7): "No internet" while offline, then "✓ Back online" for a few seconds.
// Offline queues for calls and notes come in 1B; until then the strip says changes are not saved.
export function NetworkBanner() {
  const { colors, space } = useTheme();
  const { t } = useTranslation('shell');
  const network = useNetworkState();
  const offline = network.isConnected === false || network.isInternetReachable === false;
  const [backOnline, setBackOnline] = useState(false);
  const wasOffline = useRef(false);

  useEffect(() => {
    if (offline) {
      wasOffline.current = true;
      setBackOnline(false);
      return undefined;
    }
    if (!wasOffline.current) return undefined;
    wasOffline.current = false;
    setBackOnline(true);
    const timer = setTimeout(() => setBackOnline(false), 3000);
    return () => clearTimeout(timer);
  }, [offline]);

  if (!offline && !backOnline) return null;
  return (
    <View accessibilityLiveRegion="polite" accessibilityRole="alert" testID={offline ? 'network-offline' : 'network-online'}
      style={{ backgroundColor: offline ? colors.errorContainer : colors.successContainer, paddingHorizontal: space.lg,
        paddingVertical: space.sm }}>
      <AppText variant="bodySmall" style={{ color: offline ? colors.onErrorContainer : colors.onSuccessContainer, textAlign: 'center' }}>
        {offline ? t('network.offline') : t('network.online')}
      </AppText>
    </View>
  );
}
