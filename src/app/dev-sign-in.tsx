import { Redirect } from 'expo-router';
import { useEffect, useState } from 'react';
import { StyleSheet, View } from 'react-native';

import { AppText } from '@/components/AppText';

import { devSignInEnabled } from '@/dev/flags';
import { currentClaims, signOut, switchInstitution, type SessionClaims } from '@/lib/session';
import { isSupabaseConfigured, supabase } from '@/lib/supabase';
import { Button, TextField } from '@/ui/components';
import { useTheme } from '@/ui/theme';

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
  const { colors, space } = useTheme();

  useEffect(() => {
    // Already signed in (e.g. coming back to this tool): show the claims and the institution list at once.
    if (devSignInEnabled) void currentClaims().then((c) => (c.sub ? load() : undefined));
    // load is recreated each render; reading it once on open is enough
  }, []);

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

  const signIn = run(async () => {
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) throw error;
  });

  return (
    <View style={[styles.container, { backgroundColor: colors.background, gap: space.md, padding: space.lg }]}>
      {!isSupabaseConfigured && <AppText style={{ color: colors.error }}>{DEV_TEXT.notConfigured}</AppText>}
      <TextField label={DEV_TEXT.email} placeholder={DEV_TEXT.email} kind="email" value={email} onChangeText={setEmail} />
      <TextField label={DEV_TEXT.password} placeholder={DEV_TEXT.password} kind="password" value={password} onChangeText={setPassword}
        last onDone={signIn} />
      <Button label={DEV_TEXT.signIn} onPress={signIn} />
      <AppText selectable testID="dev-claims">{JSON.stringify({
        active_institution_id: claims.active_institution_id ?? null,
        access_version: claims.access_version ?? null,
        user_kind: claims.user_kind ?? null,
      })}</AppText>
      {institutions.map((institution) => (
        <Button key={institution.id} variant="outlined" label={`${DEV_TEXT.switchTo} ${institution.name}`}
          onPress={run(() => switchInstitution(institution.id))} />
      ))}
      <Button variant="text" label={DEV_TEXT.signOut} onPress={run(signOut)} />
      {message.length > 0 && <AppText style={{ color: colors.error }}>{message}</AppText>}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, justifyContent: 'center', maxWidth: 560, width: '100%', alignSelf: 'center' },
});
