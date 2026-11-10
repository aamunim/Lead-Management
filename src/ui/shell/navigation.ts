import { router, useFocusEffect, useGlobalSearchParams } from 'expo-router';
import { useCallback, useEffect, useRef } from 'react';
import { BackHandler, Platform } from 'react-native';

import { useTranslation } from '@/i18n';
import { useAuthState } from '@/lib/auth-state';
import { switchInstitution } from '@/lib/session';

import { useConfirm } from '../components/Dialog';

/**
 * Android Back on Home (0A.14-T5, Ch 47.6): ask before leaving the app. Sheets and dialogs are Modals, which close
 * first on Back (onRequestClose) before this handler is reached.
 */
export function useConfirmExitOnBack() {
  const confirm = useConfirm();
  const { t } = useTranslation('shell');
  useFocusEffect(useCallback(() => {
    if (Platform.OS !== 'android') return undefined;
    const sub = BackHandler.addEventListener('hardwareBackPress', () => {
      void confirm({ title: t('exit.title'), confirmLabel: t('exit.confirm') }).then((leave) => {
        if (leave) BackHandler.exitApp();
      });
      return true;
    });
    return () => sub.remove();
  }, [confirm, t]));
}

/**
 * Deep links that belong to another institution (D25, Ch 47.6): leadora://…?institution=<id> switches to that
 * institution first (the server checks membership), then the target screen opens. A full switcher UI comes in 1B.
 */
export function useInstitutionDeepLink() {
  const params = useGlobalSearchParams<{ institution?: string }>();
  const auth = useAuthState();
  const handled = useRef<string | null>(null);
  const target = typeof params.institution === 'string' ? params.institution : null;
  const active = auth.status === 'signedIn' ? auth.claims.active_institution_id ?? null : null;
  useEffect(() => {
    if (!target || auth.status !== 'signedIn' || handled.current === target) return;
    handled.current = target;
    const done = () => router.setParams({ institution: undefined });
    if (target === active) {
      done();
      return;
    }
    void switchInstitution(target).then(done).catch(done);
  }, [target, active, auth.status]);
}
