import { router } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { useErrorText } from '@/i18n/errors';
import { serverNow } from '@/lib/server-time';
import { currentSupport, endSupport, requestEdit, tokenHasSupport, type SupportSession } from '@/lib/support';
import { BottomSheet, Button, TextField, useSnackbar } from '@/ui/components';
import { useTheme } from '@/ui/theme';

// Support banner (0B.08-T2, T3): shown on every app screen while a platform user is inside an institution: read only
// or edit, the time left (mm:ss), Exit, and "Ask for edit mode" with a reason. At 00:00 the session ends by itself.
export function SupportBanner() {
  const { t } = useTranslation('shell');
  const { colors, space } = useTheme();
  const insets = useSafeAreaInsets();
  const snackbar = useSnackbar();
  const errorText = useErrorText();
  const [session, setSession] = useState<SupportSession | null>(null);
  const [now, setNow] = useState(() => serverNow());
  const [asking, setAsking] = useState(false);
  const [reason, setReason] = useState('');

  const load = useCallback(async () => {
    if (!(await tokenHasSupport())) return setSession(null);
    const r = await currentSupport();
    setSession(r.data ?? null);
  }, []);
  useEffect(() => {
    void load();
  }, [load]);
  useEffect(() => {
    if (!session) return undefined;
    const timer = setInterval(() => setNow(serverNow()), 1000);
    return () => clearInterval(timer);
  }, [session]);

  const exit = useCallback(async () => {
    await endSupport();
    setSession(null);
    router.replace('/panel');
  }, []);
  const left = session ? Math.max(0, Math.floor((new Date(session.expires_at).getTime() - now) / 1000)) : 0;
  useEffect(() => {
    if (session && left === 0) void exit();
  }, [session, left, exit]);
  if (!session) return null;

  const clock = `${String(Math.floor(left / 60)).padStart(2, '0')}:${String(left % 60).padStart(2, '0')}`;
  const ask = async () => {
    const r = await requestEdit(reason.trim());
    snackbar.show({ text: r.error ? errorText(r.error).message : t('support.editAsked') });
    if (!r.error) {
      setAsking(false);
      void load();
    }
  };
  return (
    <View testID="support-banner" accessibilityRole="alert" style={{ flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', gap: space.sm,
      paddingHorizontal: space.md, paddingTop: space.sm + insets.top, paddingBottom: space.sm, backgroundColor: session.mode === 'edit' ? colors.errorContainer : colors.warmContainer }}>
      <AppText style={{ flex: 1, minWidth: 180, color: session.mode === 'edit' ? colors.onErrorContainer : colors.onWarmContainer }} testID="support-banner-text">
        {t(session.mode === 'edit' ? 'support.bannerEdit' : 'support.bannerReadOnly', { name: session.institution_name, time: clock })}
      </AppText>
      {session.mode === 'read_only' && !session.edit_requested ? (
        <Button variant="text" label={t('support.askEdit')} onPress={() => setAsking(true)} testID="support-ask-edit" />
      ) : null}
      <Button variant="tonal" icon="logout" label={t('support.exit')} onPress={() => void exit()} testID="support-exit" />
      {asking ? (
        <BottomSheet visible onClose={() => setAsking(false)} title={t('support.askEditTitle')} testID="support-edit-sheet"
          footer={<Button label={t('support.askEdit')} fullWidth disabled={reason.trim().length < 5} onPress={() => void ask()} testID="support-edit-send" />}>
          <AppText>{t('support.askEditHelp')}</AppText>
          <TextField label={t('support.reason')} kind="multiline" value={reason} onChangeText={setReason} maxLength={500} testID="support-edit-reason" />
        </BottomSheet>
      ) : null}
    </View>
  );
}
