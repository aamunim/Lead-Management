// Development-only switches. Production builds never enable them (APP_ENV=production).
import Constants from 'expo-constants';

const appEnv = (Constants.expoConfig?.extra as { appEnv?: string } | undefined)?.appEnv ?? 'development';

/** Dev sign-in (0A.03-T8): only when explicitly enabled and never in production. */
export const devSignInEnabled = process.env.EXPO_PUBLIC_DEV_SIGNIN === '1' && appEnv !== 'production';
