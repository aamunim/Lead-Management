import { createContext, useCallback, useContext, useEffect, useRef, useState, type ReactNode } from 'react';
import { Pressable, StyleSheet, View } from 'react-native';
import { KeyboardStickyView } from 'react-native-keyboard-controller';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';

import { useTheme } from '../theme';

type Message = { id: number; text: string; actionLabel?: string; onAction?: () => void; duration?: number };
type Api = { show: (message: Omit<Message, 'id'>) => void; showUndo: (text: string, undo: () => void) => void };
const SnackbarContext = createContext<Api | null>(null);
const DEFAULT_MS = 5000;

// Snackbar with Undo (0A.13-T6, Ch 47.5): after a delete, show "Deleted · Undo" instead of asking first.
// It stays above the keyboard and the system bar, and is announced to screen readers.
export function SnackbarProvider({ children }: { children: ReactNode }) {
  const { colors, radius, space, touch } = useTheme();
  const { t } = useTranslation('ui');
  const insets = useSafeAreaInsets();
  const [message, setMessage] = useState<Message | null>(null);
  const counter = useRef(0);

  const show = useCallback((next: Omit<Message, 'id'>) => {
    counter.current += 1;
    setMessage({ ...next, id: counter.current });
  }, []);
  const showUndo = useCallback((text: string, undo: () => void) => show({ text, actionLabel: t('actions.undo'), onAction: undo }), [show, t]);

  useEffect(() => {
    if (!message) return undefined;
    const timer = setTimeout(() => setMessage((m) => (m?.id === message.id ? null : m)), message.duration ?? DEFAULT_MS);
    return () => clearTimeout(timer);
  }, [message]);

  return (
    <SnackbarContext.Provider value={{ show, showUndo }}>
      {children}
      {message ? (
        <KeyboardStickyView style={[styles.wrap, { bottom: insets.bottom + space.lg, paddingHorizontal: space.lg }]} offset={{ opened: -space.sm }}>
          <View style={[styles.bar, { backgroundColor: colors.inverseSurface, borderRadius: radius.sm, paddingLeft: space.lg, minHeight: touch }]}
            accessibilityLiveRegion="polite" accessibilityRole="alert" testID="snackbar">
            <AppText style={[styles.text, { color: colors.inverseOnSurface }]} testID="snackbar-text">{message.text}</AppText>
            {message.actionLabel ? (
              <Pressable accessibilityRole="button" accessibilityLabel={message.actionLabel} testID="snackbar-action"
                style={[styles.action, { minHeight: touch, paddingHorizontal: space.lg }]}
                onPress={() => {
                  // Clear first: the action may show a new message ("Note restored.") that must stay.
                  setMessage(null);
                  message.onAction?.();
                }}>
                <AppText variant="label" style={{ color: colors.inversePrimary }}>{message.actionLabel}</AppText>
              </Pressable>
            ) : null}
          </View>
        </KeyboardStickyView>
      ) : null}
    </SnackbarContext.Provider>
  );
}

export function useSnackbar(): Api {
  const api = useContext(SnackbarContext);
  if (!api) throw new Error('useSnackbar() outside SnackbarProvider');
  return api;
}

const styles = StyleSheet.create({
  wrap: { position: 'absolute', left: 0, right: 0, alignItems: 'center' },
  bar: { flexDirection: 'row', alignItems: 'center', maxWidth: 560, width: '100%' },
  text: { flex: 1, paddingVertical: 12 },
  action: { justifyContent: 'center' },
});
