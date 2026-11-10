import AsyncStorage from '@react-native-async-storage/async-storage';
import { useSyncExternalStore } from 'react';

import i18n from '@/i18n';
import { FALLBACK_LANGUAGE, isLanguage, resolveLanguage, type Language } from '@/i18n/language';

import { currentClaims } from './session';
import { onSettingsVersion } from './settings-version';
import { supabase } from './supabase';

// UI language store (0A.10-T2/T3).
// - Signed in: the server is the source of truth (profiles.preferred_language → institution default_language → en).
// - Before sign-in: the last language used on this device, else English.
// Switching calls i18n.changeLanguage(): every screen using useTranslation() re-renders at once, no restart.

type State = { language: Language; choice: Language | null; institutionDefault: Language | null; signedIn: boolean };

const DEVICE_KEY = 'ui_language';
let state: State = { language: FALLBACK_LANGUAGE, choice: null, institutionDefault: null, signedIn: false };
const subscribers = new Set<() => void>();

function publish(next: State) {
  state = next;
  for (const notify of subscribers) notify();
}

async function apply(next: State) {
  if (i18n.language !== next.language) await i18n.changeLanguage(next.language);
  publish(next);
  try {
    await AsyncStorage.setItem(DEVICE_KEY, next.language);
  } catch {
    // the device copy is a convenience only
  }
}

/** First paint: the language last used on this device (or English). Call once at start-up. */
export async function initLanguage(): Promise<void> {
  try {
    const saved = await AsyncStorage.getItem(DEVICE_KEY);
    if (isLanguage(saved)) await apply({ ...state, language: saved });
  } catch {
    // ignore
  }
  await syncLanguage();
}

/** Asks the server which language applies to the signed-in person in the active institution. */
export async function syncLanguage(): Promise<void> {
  const claims = await currentClaims();
  if (!claims.sub) {
    publish({ ...state, signedIn: false, institutionDefault: null });
    return;
  }
  const { data, error } = await supabase.rpc('my_language');
  if (error) return; // keep the current language; never flip the UI on a failed call
  const result = data as { choice: unknown; institution_default: unknown; language: unknown };
  const choice = isLanguage(result.choice) ? result.choice : null;
  const institutionDefault = isLanguage(result.institution_default) ? result.institution_default : null;
  await apply({ language: resolveLanguage({ choice, institutionDefault }), choice, institutionDefault, signedIn: true });
}

/**
 * The person picks a language (or null = follow the institution). Signed in: stored on the server, so it follows
 * them to every device. Not signed in: stored on this device only.
 */
export async function chooseLanguage(choice: Language | null): Promise<{ savedOnServer: boolean; error?: unknown }> {
  if (!state.signedIn) {
    await apply({ ...state, choice, language: resolveLanguage({ choice, institutionDefault: null }) });
    return { savedOnServer: false };
  }
  const previous = state;
  // Switch at once (optimistic); the server confirms or we switch back.
  await apply({ ...state, choice, language: resolveLanguage({ choice, institutionDefault: state.institutionDefault }) });
  const { data, error } = await supabase.rpc('set_my_language', { p_language: choice });
  if (error) {
    await apply(previous);
    return { savedOnServer: false, error };
  }
  const language = (data as { language: unknown }).language;
  if (isLanguage(language) && language !== state.language) await apply({ ...state, language });
  return { savedOnServer: true };
}

export function useLanguageState(): State {
  return useSyncExternalStore(
    (notify) => {
      subscribers.add(notify);
      return () => subscribers.delete(notify);
    },
    () => state,
  );
}

let lastSettingsVersion = 0;

// Sign-in, institution switch (new token) → ask again. Sign-out keeps the current language on screen.
supabase.auth.onAuthStateChange((event) => {
  lastSettingsVersion = 0; // versions are per institution
  if (event === 'SIGNED_IN' || event === 'TOKEN_REFRESHED' || event === 'USER_UPDATED') {
    setTimeout(() => void syncLanguage().catch(() => undefined), 0);
  } else if (event === 'SIGNED_OUT') {
    publish({ ...state, signedIn: false, choice: null, institutionDefault: null });
  }
});

// The institution changed its default_language (settings_version rose) → follow it if the person has no choice.
onSettingsVersion((version) => {
  const rose = version > lastSettingsVersion;
  lastSettingsVersion = Math.max(lastSettingsVersion, version);
  if (rose && state.signedIn && state.choice === null) void syncLanguage().catch(() => undefined);
});
