import { callWithSessionRetry, type ErrorInfo } from './errors';
import type { BnForms, LabelValue } from './labels';
import type { Text } from './packs';
import { supabase } from './supabase';

// Master Admin (0B.04-T9, T10): institutions with their industry and types, one institution's words with platform
// locks, and the product-default words. platform.view to read, platform.labels_lock to lock, platform.profiles to edit
// product defaults; the server checks every call and needs the second step.
export type PanelInstitution = { id: string; name: string; slug: string; status: string; industry: string; profiles: { key: string; version: number; name: Text }[] };
export type InstitutionLabel = { key: string; group: string; lockable: boolean; label: LabelValue & { source: string; locked?: boolean } };
export type ProductLabel = { key: string; group: string; max_length: number; en_singular: string | null; en_plural: string | null; bn_forms: BnForms | null };
type Result<T> = { data: T | null; error: ErrorInfo | null };

const rpc = <T>(where: string, fn: string, args?: Record<string, unknown>): Promise<Result<T>> =>
  callWithSessionRetry<T>(where, async () => {
    const { data, error } = await supabase.rpc(fn, args);
    return { data: data as T | null, error };
  });

export const fetchPanelInstitutions = () => rpc<PanelInstitution[]>('panel.institutions', 'platform_institutions_list');
export const fetchInstitutionLabels = (id: string) =>
  rpc<{ institution: { id: string; name: string; industry: string }; labels: InstitutionLabel[] }>('panel.labels', 'platform_institution_labels', { p_institution: id });
export const lockLabel = (institution: string, key: string, locked: boolean, reason: string | null) =>
  rpc<unknown>('panel.lock', 'label_lock', { p_institution_id: institution, p_key: key, p_locked: locked, p_reason: reason });
export const fetchProductLabels = () => rpc<ProductLabel[]>('panel.productLabels', 'platform_label_defaults');
export const saveProductLabel = (key: string, enSingular: string, enPlural: string, bnBase: string) =>
  rpc<unknown>('panel.productLabel', 'platform_label_default_set', { p_key: key, p_en_singular: enSingular, p_en_plural: enPlural, p_bn_forms: { base: bnBase } });
