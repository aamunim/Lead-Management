import AsyncStorage from '@react-native-async-storage/async-storage';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import Constants from 'expo-constants';

import { reportSettingsVersion } from './settings-version';

// One Supabase client for the whole app (0A.03).
// URL and publishable key are public values per environment, provided through EXPO_PUBLIC_* variables
// (see .env.example). Never put a service-role / secret key in the app.
const url = process.env.EXPO_PUBLIC_SUPABASE_URL ?? '';
const key = process.env.EXPO_PUBLIC_SUPABASE_KEY ?? '';

export const isSupabaseConfigured = url.length > 0 && key.length > 0;

// Every request tells the server the app version (min_app_version check, 0A.08) and every response is checked for
// x-settings-version so stale settings are refreshed on the next request, without a restart.
const appVersion = Constants.expoConfig?.version ?? '0.0.0';
const fetchWithVersions: typeof fetch = async (input, init) => {
  const headers = new Headers(init?.headers);
  headers.set('x-app-version', appVersion);
  const response = await fetch(input, { ...init, headers });
  reportSettingsVersion(response.headers.get('x-settings-version'));
  return response;
};

export const supabase: SupabaseClient = createClient(url || 'http://localhost', key || 'missing-key', {
  global: { fetch: fetchWithVersions },
  auth: {
    storage: AsyncStorage,
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: false,
  },
});
