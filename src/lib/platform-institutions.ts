import { callWithSessionRetry, type ErrorInfo } from './errors';
import type { BnForms, LabelValue } from './labels';
import type { Text } from './packs';
import { supabase } from './supabase';

// Master Admin (0B.04-T9, T10): institutions with their industry and types, one institution's words with platform
// locks, and the product-default words. platform.view to read, platform.labels_lock to lock, platform.profiles to edit
// product defaults; the server checks every call and needs the second step.
export type PanelInstitution = {
  id: string; name: string; slug: string; status: string; industry: string; profiles: { key: string; version: number; name: Text }[];
  plan: { key: string; name: Text; expires_at: string | null } | null; users: number; last_login: string | null; problems: string[];
};
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

// Plans (0B.05): the plans catalog (platform.plans to edit) and one institution's plan, overrides and allowed modules
// (platform.billing). Every change is a new plan version or a logged change; nothing needs a release.
export type PlanRow = {
  key: string; version: number; name: Text; modules: string[]; limits: Record<string, number | null>;
  prices: Record<string, unknown>; trial_days: number | null; for_new: boolean; institutions: number; notes: string | null;
};
export type InstitutionPlan = {
  plan: { plan_key: string; plan_version: number; latest_version: number; name: Text; expires_at: string | null; billing_cycle: string;
    price_override: number | null; discount_percent: number; limit_overrides: Record<string, number | null>; plan_limits: Record<string, number | null> } | null;
  usage: { metric: string; used: number; limit: number | null; level: string }[];
  modules: { key: string; always_on: boolean; override: boolean | null; allowed: boolean; enabled: boolean }[];
  fit: { over: { metric: string; used: number; limit: number; reduce_by: number }[]; modules_lost: string[] } | null;
};
export const fetchPlans = () => rpc<{ plans: PlanRow[]; metrics: { key: string }[]; modules: { key: string }[] }>('panel.plans', 'platform_plans_list');
export const savePlan = (key: string, name: Text, modules: string[], limits: Record<string, unknown>, prices: Record<string, unknown>,
  trialDays: number | null, notes: string | null) =>
  rpc<number>('panel.planSave', 'platform_plan_save', { p_key: key, p_name: name, p_modules: modules, p_limits: limits, p_prices: prices,
    p_trial_days: trialDays, p_notes: notes });
export const fetchInstitutionPlan = (id: string, compare: string | null) =>
  rpc<InstitutionPlan>('panel.institutionPlan', 'platform_institution_plan', { p_institution: id, p_compare_plan: compare });
export const setInstitutionPlan = (id: string, v: { plan: string; expires: string | null; cycle: string; price: number | null; discount: number;
  overrides: Record<string, unknown>; reason: string | null }) =>
  rpc<unknown>('panel.institutionPlanSet', 'platform_institution_plan_set', { p_institution: id, p_plan: v.plan, p_expires_at: v.expires,
    p_billing_cycle: v.cycle, p_price_override: v.price, p_discount_percent: v.discount, p_limit_overrides: v.overrides, p_reason: v.reason });
export const allowModule = (id: string, key: string, allowed: boolean | null, reason: string | null) =>
  rpc<null>('panel.moduleAllow', 'platform_module_allow', { p_institution: id, p_key: key, p_allowed: allowed, p_reason: reason });
