import AsyncStorage from '@react-native-async-storage/async-storage';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import Constants from 'expo-constants';

import { createApiFetch } from './api-core';
import { markUpgradeRequired } from './app-status';
import { reportSettingsVersion } from './settings-version';

// One Supabase client for the whole app (0A.03).
// URL and publishable key are public values per environment, provided through EXPO_PUBLIC_* variables
// (see .env.example). Never put a service-role / secret key in the app.
const url = process.env.EXPO_PUBLIC_SUPABASE_URL ?? '';
const key = process.env.EXPO_PUBLIC_SUPABASE_KEY ?? '';

export const isSupabaseConfigured = url.length > 0 && key.length > 0;

// Every request goes through the API wrapper (0A.14-T3, src/lib/api-core.ts): app version and idempotency headers,
// slow-3G time limits and safe retries, "upgrade required" and "session refresh required" handling, settings version.
const appVersion = Constants.expoConfig?.version ?? '0.0.0';
let client: SupabaseClient | null = null;
const apiFetch = createApiFetch({
  fetch: (input, init) => fetch(input, init),
  appVersion,
  onUpgradeRequired: markUpgradeRequired,
  reportSettingsVersion,
  refreshSession: async () => {
    const { data } = (await client?.auth.refreshSession()) ?? { data: null };
    return data?.session?.access_token ?? null;
  },
});

export const supabase: SupabaseClient = createClient(url || 'http://localhost', key || 'missing-key', {
  global: { fetch: apiFetch },
  auth: {
    storage: AsyncStorage,
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: false,
  },
});
client = supabase;
