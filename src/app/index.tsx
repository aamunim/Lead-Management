import { Redirect } from 'expo-router';

import { useAuthState } from '@/lib/auth-state';

// Entry: signed in → Home; otherwise → sign-in (0A.14).
export default function Index() {
  const auth = useAuthState();
  if (auth.status === 'loading') return null;
  return <Redirect href={auth.status === 'signedIn' ? '/home' : '/sign-in'} />;
}
