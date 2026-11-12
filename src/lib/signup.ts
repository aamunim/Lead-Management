import * as Crypto from 'expo-crypto';

import { callWithSessionRetry, type ErrorInfo } from './errors';
import type { Text } from './packs';
import type { ProfilePreview } from './profiles';
import { supabase } from './supabase';

// Institution setup wizard (0B.09; Ch 6.3): the open types and a preview before sign-in, then the signed-in person
// creates the institution (pending approval) and becomes its Super Admin. The platform runs the same wizard and
// invites the Super Admin. Only the essentials: everything else is in the setup checklist afterwards (Ch 6.9 row 3).
export type OpenIndustry = { key: string; name: Text; pack_version: number; profiles: { key: string; version: number; name: Text; description: Text }[] };
export type SignupAnswers = {
  profiles: string[];
  exclude: string[];
  label_choices: Record<string, string>;
  name: string;
  short_name: string;
  eiin: string;
  institution_code: string;
  address: string;
  contact_phone: string;
  super_admin: { display_name: string; phone: string; email: string };
};
type Result<T> = { data: T | null; error: ErrorInfo | null };

export const emptyAnswers = (): SignupAnswers => ({
  profiles: [], exclude: [], label_choices: {}, name: '', short_name: '', eiin: '', institution_code: '', address: '', contact_phone: '',
  super_admin: { display_name: '', phone: '', email: '' },
});

/** Parts of the preview a person may leave out (the roles make the Super Admin, so they always stay). */
export const FIXED_AREAS = ['roles'];

const rpc = <T>(where: string, fn: string, args?: Record<string, unknown>): Promise<Result<T>> =>
  callWithSessionRetry<T>(where, async () => {
    const { data, error } = await supabase.rpc(fn, args);
    return { data: data as T | null, error };
  });

export const fetchSignupStatus = () => rpc<{ open: boolean }>('signup.status', 'signup_status');
export const fetchOpenIndustries = () => rpc<OpenIndustry[]>('signup.packs', 'list_open_packs');
export const previewSignup = (a: Pick<SignupAnswers, 'profiles' | 'exclude' | 'label_choices'>) =>
  rpc<ProfilePreview>('signup.preview', 'signup_preview', { p_profiles: a.profiles, p_exclude: a.exclude, p_label_choices: a.label_choices });

/** One key per wizard run: pressing "Create" twice (or a retry after a lost answer) gives one institution. */
export const newRequestKey = () => Crypto.randomUUID();

const payload = (a: SignupAnswers) => ({ ...a, super_admin: { ...a.super_admin } });

export const submitSignup = (a: SignupAnswers, requestKey: string) =>
  rpc<{ institution_id: string; status: string; repeated: boolean }>('signup.submit', 'institution_signup',
    { p_payload: payload(a), p_request_key: requestKey });

export const platformCreateInstitution = (a: SignupAnswers, requestKey: string) =>
  rpc<{ institution_id: string; invite_id: string; attached: boolean }>('signup.platformCreate', 'platform_institution_create',
    { p_payload: payload(a), p_request_key: requestKey });

export const fetchInstitutionInvites = (institutionId: string) =>
  rpc<{ id: string; email: string; invited_at: string; accepted_at: string | null }[]>('signup.invites', 'platform_institution_invites',
    { p_institution: institutionId });

/**
 * The login for the Super Admin (step 4): a new account, or an existing one (D25: a member of another institution
 * joins with the same login). Returns 'confirm' when the email has to be confirmed before the institution is made.
 */
export async function ensureLogin(mode: 'new' | 'existing', email: string, password: string):
  Promise<{ state: 'ready' | 'confirm' } | { error: 'exists' | 'failed' | 'weak' }> {
  const { data: current } = await supabase.auth.getSession();
  if (current.session?.user.email?.toLowerCase() === email.trim().toLowerCase()) return { state: 'ready' };
  if (mode === 'existing') {
    const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
    return error ? { error: 'failed' } : { state: 'ready' };
  }
  const { data, error } = await supabase.auth.signUp({ email: email.trim(), password });
  if (error) {
    if (/already/i.test(error.message)) return { error: 'exists' };
    if (/password/i.test(error.message)) return { error: 'weak' };
    return { error: 'failed' };
  }
  // With email confirmation on, an existing email comes back without identities (and no session).
  if (data.user && (data.user.identities?.length ?? 0) === 0) return { error: 'exists' };
  return data.session ? { state: 'ready' } : { state: 'confirm' };
}

/** After the institution is made the next token must carry it: refresh the session. */
export async function openNewInstitution(): Promise<void> {
  await supabase.auth.refreshSession();
}
