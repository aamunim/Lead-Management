import AsyncStorage from '@react-native-async-storage/async-storage';
import * as Crypto from 'expo-crypto';
import { useNavigation, usePreventRemove } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { AppState } from 'react-native';

import { useTranslation } from '@/i18n';
import { cacheKey } from '@/lib/cache';
import { currentClaims } from '@/lib/session';

import { useConfirm } from './Dialog';

// Form behaviours (0A.13-T5, Ch 47.4).

/**
 * Draft autosave: the form's values are saved on the device while typing (debounced) and when the app goes to the
 * background, per user + institution + form; they come back after an incoming call or if the app was killed.
 * Call clear() after a successful save.
 */
export function useDraft<T>(formKey: string, value: T, restore: (draft: T) => void, delayMs = 600) {
  const [restored, setRestored] = useState(false);
  const storageKey = useRef<string | null>(null);
  const latest = useRef(value);
  latest.current = value;

  const save = useCallback(async () => {
    if (!storageKey.current) return;
    try {
      await AsyncStorage.setItem(storageKey.current, JSON.stringify(latest.current));
    } catch {
      // a draft is a convenience; never block typing
    }
  }, []);

  useEffect(() => {
    let alive = true;
    void (async () => {
      const claims = await currentClaims();
      storageKey.current = cacheKey({ userId: claims.sub, institutionId: claims.active_institution_id }, 'draft', formKey);
      try {
        const saved = await AsyncStorage.getItem(storageKey.current);
        if (alive && saved) {
          restore(JSON.parse(saved) as T);
          setRestored(true);
        }
      } catch {
        // ignore
      }
    })();
    const sub = AppState.addEventListener('change', (state) => {
      if (state !== 'active') void save();
    });
    return () => {
      alive = false;
      sub.remove();
    };
    // `restore` is read once, on mount: later renders must not re-apply an old draft.
  }, [formKey, save]);

  useEffect(() => {
    const timer = setTimeout(() => void save(), delayMs);
    return () => clearTimeout(timer);
  }, [value, delayMs, save]);

  const clear = useCallback(async () => {
    if (storageKey.current) await AsyncStorage.removeItem(storageKey.current).catch(() => undefined);
    setRestored(false);
  }, []);

  return { restored, clear };
}

/**
 * Double-submit protection: while a submit runs, more presses are ignored; every attempt carries an idempotency
 * key that stays the same across retries of the same form (a lost response then retried creates nothing twice on
 * the server, which must accept p_idempotency_key). A new key is made after a success.
 */
export function useSubmit<R>(run: (idempotencyKey: string) => Promise<R>) {
  const [submitting, setSubmitting] = useState(false);
  const inFlight = useRef(false);
  const key = useRef<string>(Crypto.randomUUID());
  const submit = useCallback(async (): Promise<R | undefined> => {
    if (inFlight.current) return undefined;
    inFlight.current = true;
    setSubmitting(true);
    try {
      const result = await run(key.current);
      key.current = Crypto.randomUUID();
      return result;
    } finally {
      inFlight.current = false;
      setSubmitting(false);
    }
  }, [run]);
  return { submit, submitting, idempotencyKey: () => key.current };
}

/** Unsaved changes: Back (button, gesture, Android back) asks "Discard changes?" while `dirty`. */
export function useUnsavedChangesPrompt(dirty: boolean) {
  const navigation = useNavigation();
  const confirm = useConfirm();
  const { t } = useTranslation('ui');
  usePreventRemove(dirty, ({ data }) => {
    void confirm({ title: t('form.unsavedTitle'), message: t('form.unsavedBody'), confirmLabel: t('actions.discard'),
      cancelLabel: t('actions.keepEditing'), danger: true }).then((discard) => {
      if (discard) navigation.dispatch(data.action);
    });
  });
}
