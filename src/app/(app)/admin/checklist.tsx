import { useCallback, useEffect, useState } from 'react';
import { View } from 'react-native';

import { AppText } from '@/components/AppText';
import { useTranslation } from '@/i18n';
import { useErrorText } from '@/i18n/errors';
import { fetchChecklist, markChecklist, type Checklist } from '@/lib/setup';
import { ErrorState, Screen, Skeleton, useSnackbar } from '@/ui/components';
import { AppHeader } from '@/ui/shell/AppHeader';
import { ChecklistView } from '@/ui/setup/ChecklistView';
import { useTheme } from '@/ui/theme';

// Settings → Setup checklist (0B.10-T1–T3, T9; Ch 6.5): what is left, who does it (you, the platform, or both) and the
// items that arrive in later phases. Items with a rule tick themselves; the others are ticked here. The merchant-account
// step is shown early: manual payment works meanwhile (Ch 6.9 row 4).
export default function ChecklistScreen() {
  const { t } = useTranslation('admin');
  const { colors, radius, space } = useTheme();
  const snackbar = useSnackbar();
  const errorText = useErrorText();
  const [list, setList] = useState<Checklist | null>(null);
  const [error, setError] = useState<unknown>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setError(null);
    const r = await fetchChecklist();
    if (r.error) setError(r.error);
    else setList(r.data);
  }, []);
  useEffect(() => {
    void load();
  }, [load]);

  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <AppHeader back />
      <Screen title={t('checklist.title')} intro={t('checklist.intro')} testID="checklist-screen">
        {error ? <ErrorState error={error} onRetry={() => void load()} /> : !list ? <Skeleton lines={8} /> : (
          <>
            {list.percent >= 100 ? (
              <View style={{ padding: space.md, borderRadius: radius.md, backgroundColor: colors.primaryContainer }} testID="checklist-complete">
                <AppText style={{ color: colors.onPrimaryContainer }}>{t('checklist.complete')}</AppText>
              </View>
            ) : null}
            <ChecklistView list={list} busy={busy} canMark={(i) => i.owner !== 'master_admin'}
              onMark={async (item, done) => {
                setBusy(true);
                const r = await markChecklist(item.key, done, null);
                setBusy(false);
                if (r.error) return snackbar.show({ text: errorText(r.error).message });
                setList(r.data);
              }} />
            <AppText variant="caption">{t('checklist.merchantNote')}</AppText>
          </>
        )}
      </Screen>
    </View>
  );
}
