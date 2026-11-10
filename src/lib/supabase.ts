import AsyncStorage from '@react-native-async-storage/async-storage';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';

// One Supabase client for the whole app (0A.03).
// URL and publishable key are public values per environment, provided through EXPO_PUBLIC_* variables
// (see .env.example). Never put a service-role / secret key in the app.
const url = process.env.EXPO_PUBLIC_SUPABASE_URL ?? '';
const key = process.env.EXPO_PUBLIC_SUPABASE_KEY ?? '';

export const isSupabaseConfigured = url.length > 0 && key.length > 0;

export const supabase: SupabaseClient = createClient(url || 'http://localhost', key || 'missing-key', {
  auth: {
    storage: AsyncStorage,
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: false,
  },
});
