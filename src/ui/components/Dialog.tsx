import { createContext, useCallback, useContext, useRef, useState, type ReactNode } from 'react';
import { Modal, StyleSheet, View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';

import { useTheme } from '../theme';

import { Button } from './Button';

type ConfirmOptions = { title: string; message?: string; confirmLabel?: string; cancelLabel?: string; danger?: boolean };
const DialogContext = createContext<((options: ConfirmOptions) => Promise<boolean>) | null>(null);

// Confirmation dialog (0A.13): `const confirm = useConfirm(); if (await confirm({ title, danger: true })) …`.
// Android Back and a tap outside cancel it.
export function DialogProvider({ children }: { children: ReactNode }) {
  const { colors, radius, space } = useTheme();
  const { t } = useTranslation('ui');
  const [options, setOptions] = useState<ConfirmOptions | null>(null);
  const resolver = useRef<((ok: boolean) => void) | null>(null);

  const confirm = useCallback((next: ConfirmOptions) => new Promise<boolean>((resolve) => {
    resolver.current?.(false);
    resolver.current = resolve;
    setOptions(next);
  }), []);
  const close = (ok: boolean) => {
    resolver.current?.(ok);
    resolver.current = null;
    setOptions(null);
  };

  return (
    <DialogContext.Provider value={confirm}>
      {children}
      <Modal visible={options !== null} transparent animationType="fade" onRequestClose={() => close(false)}>
        <View style={[styles.backdrop, { backgroundColor: `${colors.scrim}73` }]} accessibilityViewIsModal>
          <View style={[styles.dialog, { backgroundColor: colors.surfaceContainerHigh, borderRadius: radius.xl, padding: space.xl, gap: space.md }]}
            accessibilityRole="alert" testID="confirm-dialog">
            <AppText variant="title">{options?.title}</AppText>
            {options?.message ? <AppText style={{ color: colors.onSurfaceVariant }}>{options.message}</AppText> : null}
            <View style={[styles.actions, { gap: space.sm }]}>
              <Button variant="text" label={options?.cancelLabel ?? t('actions.cancel')} onPress={() => close(false)} testID="confirm-cancel" />
              <Button variant={options?.danger ? 'danger' : 'filled'} label={options?.confirmLabel ?? t('actions.confirm')}
                onPress={() => close(true)} testID="confirm-ok" />
            </View>
          </View>
        </View>
      </Modal>
    </DialogContext.Provider>
  );
}

export function useConfirm() {
  const confirm = useContext(DialogContext);
  if (!confirm) throw new Error('useConfirm() outside DialogProvider');
  return confirm;
}

const styles = StyleSheet.create({
  backdrop: { flex: 1, justifyContent: 'center', padding: 24 },
  dialog: { maxWidth: 440, width: '100%', alignSelf: 'center' },
  actions: { flexDirection: 'row', justifyContent: 'flex-end', flexWrap: 'wrap' },
});
