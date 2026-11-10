import { Redirect } from 'expo-router';
import { useState } from 'react';
import { Pressable, StyleSheet, Text, TextInput, View } from 'react-native';

import { devSignInEnabled } from '@/dev/flags';
import { currentClaims, signOut, switchInstitution, type SessionClaims } from '@/lib/session';
import { isSupabaseConfigured, supabase } from '@/lib/supabase';

// DEVELOPER TOOL ONLY (0A.03-T8). Hidden unless EXPO_PUBLIC_DEV_SIGNIN=1 and not a production build.
// Its texts are developer-facing and intentionally not translated; the real login screens come in 0B (Ch 10).
const DEV_TEXT = {
  email: 'email',
  password: 'password',
  signIn: 'Sign in',
  signOut: 'Sign out',
  switchTo: 'Switch to',
  notConfigured: 'Set EXPO_PUBLIC_SUPABASE_URL and EXPO_PUBLIC_SUPABASE_KEY (see .env.example).',
};

type Institution = { id: string; name: string };

export default function DevSignIn() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [claims, setClaims] = useState<SessionClaims>({});
  const [institutions, setInstitutions] = useState<Institution[]>([]);
  const [message, setMessage] = useState('');

  if (!devSignInEnabled) return <Redirect href="/" />;

  const load = async () => {
    setClaims(await currentClaims());
    const { data, error } = await supabase.from('institutions').select('id, name').order('name');
    if (error) setMessage(error.message);
    setInstitutions(data ?? []);
  };

  const run = (action: () => Promise<unknown>) => async () => {
    setMessage('');
    try {
      await action();
      await load();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : String(error));
    }
  };

  return (
    <View style={styles.container}>
      {!isSupabaseConfigured && <Text style={styles.error}>{DEV_TEXT.notConfigured}</Text>}
      <TextInput style={styles.input} placeholder={DEV_TEXT.email} autoCapitalize="none" keyboardType="email-address"
        value={email} onChangeText={setEmail} />
      <TextInput style={styles.input} placeholder={DEV_TEXT.password} secureTextEntry value={password}
        onChangeText={setPassword} />
      <Pressable style={styles.button} onPress={run(async () => {
        const { error } = await supabase.auth.signInWithPassword({ email, password });
        if (error) throw error;
      })}>
        <Text>{DEV_TEXT.signIn}</Text>
      </Pressable>
      <Text selectable testID="dev-claims">{JSON.stringify({
        active_institution_id: claims.active_institution_id ?? null,
        access_version: claims.access_version ?? null,
        user_kind: claims.user_kind ?? null,
      })}</Text>
      {institutions.map((institution) => (
        <Pressable key={institution.id} style={styles.button} onPress={run(() => switchInstitution(institution.id))}>
          <Text>{`${DEV_TEXT.switchTo} ${institution.name}`}</Text>
        </Pressable>
      ))}
      <Pressable style={styles.button} onPress={run(signOut)}>
        <Text>{DEV_TEXT.signOut}</Text>
      </Pressable>
      {message.length > 0 && <Text style={styles.error}>{message}</Text>}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, gap: 12, padding: 16, justifyContent: 'center' },
  input: { borderWidth: 1, borderColor: '#999', borderRadius: 8, padding: 12, minHeight: 48 },
  button: { borderWidth: 1, borderColor: '#999', borderRadius: 8, padding: 12, minHeight: 48, justifyContent: 'center' },
  error: { color: '#b00020' },
});
