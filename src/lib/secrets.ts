import { supabase } from './supabase';

// App-side calls for per-institution secrets (0A.07). Write-only: the app can never read a value back.

/** Sets or rotates a secret; returns only the hint. `institutionId` is used only by the Master Admin panel (D4). */
export async function setSecret(ref: string, value: string, activeFrom: string | null, institutionId?: string): Promise<string> {
  const { data, error } = await supabase.rpc('secret_set', {
    p_ref: ref,
    p_value: value,
    p_valid_from: activeFrom,
    p_institution_id: institutionId ?? null,
  });
  if (error) throw error;
  return (data as { hint: string }).hint;
}

export async function revokeSecret(ref: string, institutionId?: string): Promise<void> {
  const { error } = await supabase.rpc('secret_revoke', { p_ref: ref, p_institution_id: institutionId ?? null });
  if (error) throw error;
}

/** Hints of the active institution's secrets (metadata only; the value is never selectable). */
export async function listSecretHints() {
  const { data, error } = await supabase
    .from('institution_secrets')
    .select('secret_ref, hint, valid_from, rotated_at, revoked_at')
    .is('revoked_at', null)
    .order('secret_ref');
  if (error) throw error;
  return data;
}
