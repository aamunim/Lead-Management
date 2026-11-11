import { callWithSessionRetry, type ErrorInfo } from './errors';
import { supabase } from './supabase';

// Industry packs and type profiles (0B.03): versioned data the Master Admin edits in the panel. The server checks
// platform.profiles and the second step on every call, validates before publishing and audits every write.
export type PackKind = 'pack' | 'profile';
export type Text = { en: string; bn: string };
export type PackPayload = Record<string, unknown> & { name?: Text; description?: Text };
export type IndustryRow = {
  key: string; name: Text; signup_open: boolean;
  pack: { published_version: number | null; draft_version: number | null } | null;
  profiles: { key: string; name: Text; published_version: number | null; draft_version: number | null }[];
};
export type PackVersion = {
  version: number; status: 'draft' | 'published'; payload: PackPayload; notes: string | null;
  created_at: string; created_by: string | null; published_at: string | null; published_by: string | null;
};
export type PackDetail = { kind: PackKind; key: string; industry_key: string; versions: PackVersion[] };
type Result<T> = { data: T | null; error: ErrorInfo | null };

const rpc = <T>(where: string, fn: string, args?: Record<string, unknown>): Promise<Result<T>> =>
  callWithSessionRetry<T>(where, async () => {
    const { data, error } = await supabase.rpc(fn, args);
    return { data: data as T | null, error };
  });

export const fetchPacks = () => rpc<IndustryRow[]>('packs.list', 'platform_packs_list');
export const fetchPack = (kind: PackKind, key: string) => rpc<PackDetail>('packs.get', 'platform_pack_get', { p_kind: kind, p_key: key });
export const validatePack = (kind: PackKind, key: string, payload: unknown) =>
  rpc<string[]>('packs.validate', 'platform_pack_validate', { p_kind: kind, p_key: key, p_payload: payload });
export const saveDraft = (kind: PackKind, key: string, payload: unknown, notes: string | null) =>
  rpc<number>('packs.save', 'platform_pack_save_draft', { p_kind: kind, p_key: key, p_payload: payload, p_notes: notes });
export const publishVersion = (kind: PackKind, key: string, version: number, notes: string | null) =>
  rpc<null>('packs.publish', 'platform_pack_publish', { p_kind: kind, p_key: key, p_version: version, p_notes: notes });
export const discardDraft = (kind: PackKind, key: string) => rpc<null>('packs.discard', 'platform_pack_discard_draft', { p_kind: kind, p_key: key });
export const setIndustryOpen = (key: string, open: boolean) =>
  rpc<null>('packs.open', 'platform_industry_set_open', { p_key: key, p_open: open });

/** The text in the reader's language (data rows carry both). */
export const pick = (text: Partial<Text> | null | undefined, language: string): string =>
  (language === 'bn' ? text?.bn : text?.en) ?? text?.en ?? '';

/** Parses the JSON editor text: the object, or the parse error message. */
export function parsePayload(text: string): { value: PackPayload } | { error: string } {
  try {
    const value = JSON.parse(text) as unknown;
    if (!value || typeof value !== 'object' || Array.isArray(value)) return { error: 'object' };
    return { value: value as PackPayload };
  } catch (e) {
    return { error: e instanceof Error ? e.message : String(e) };
  }
}
