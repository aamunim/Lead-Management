import { callWithSessionRetry, type ErrorInfo } from './errors';
import type { Text } from './packs';
import { supabase } from './supabase';

// Institution types (0B.04): which type profiles the institution uses, a preview of a change, applying it, and
// "Reset to profile defaults" per area. The server checks settings.institution_type (and the area permission for a
// reset), never deletes data and keeps the institution's own edits.
export type AppliedProfile = { key: string; version: number; name: Text; latest_version: number };
export type ProfileState = {
  industry: string;
  applied: AppliedProfile[];
  available: { key: string; version: number; name: Text; description: Text }[];
  areas: { area: string; used_from: string; items: number; modified: number }[];
  reset_areas: { area: string; own: number }[];
};
export type PreviewItem = { key: string; action: 'add' | 'change' | 'remove' | 'kept'; before: unknown; after: unknown };
export type PreviewArea = { area: string; used_from: string; add: number; change: number; remove: number; kept: number; items: PreviewItem[] };
export type LabelConflict = { key: string; chosen: string; options: { profile: string; en_singular: string; bn: string }[] };
export type ProfilePreview = { industry: string; profiles: { key: string; version: number; name: Text }[]; label_conflicts: LabelConflict[]; areas: PreviewArea[] };
export type ResetItem = { key: string; current: unknown; default: unknown };
type Result<T> = { data: T | null; error: ErrorInfo | null };

const rpc = <T>(where: string, fn: string, args?: Record<string, unknown>): Promise<Result<T>> =>
  callWithSessionRetry<T>(where, async () => {
    const { data, error } = await supabase.rpc(fn, args);
    return { data: data as T | null, error };
  });

export const fetchProfileState = () => rpc<ProfileState>('profiles.state', 'profile_state');
export const previewProfiles = (profiles: string[], choices: Record<string, string>) =>
  rpc<ProfilePreview>('profiles.preview', 'profile_change_preview', { p_profiles: profiles, p_exclude: [], p_label_choices: choices });
export const applyProfiles = (profiles: string[], choices: Record<string, string>, reason: string | null) =>
  rpc<{ profiles: string[] }>('profiles.apply', 'profile_change_apply', { p_profiles: profiles, p_exclude: [], p_label_choices: choices, p_reason: reason });
export const resetArea = (area: string, confirm: boolean) =>
  rpc<{ area: string; items: ResetItem[]; applied: boolean }>('profiles.reset', 'profile_reset', { p_area: area, p_confirm: confirm });

/** A seeded value as a short line: a word, a setting value, a stage name. */
export function describeValue(value: unknown, language: string): string {
  if (value === null || value === undefined) return '—';
  if (typeof value !== 'object') return String(value);
  const v = value as Record<string, unknown>;
  if (typeof v.en_singular === 'string') return language === 'bn' ? String((v.bn_forms as { base?: string } | undefined)?.base ?? v.bn ?? v.en_singular) : v.en_singular;
  if (v.name && typeof v.name === 'object') return String((v.name as Record<string, string>)[language] ?? (v.name as Record<string, string>).en);
  if ('value' in v) return describeValue(v.value, language);
  return JSON.stringify(value);
}
