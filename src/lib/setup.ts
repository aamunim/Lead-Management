import { callWithSessionRetry, describeError, type ErrorInfo } from './errors';
import { supabase } from './supabase';

// Setup checklist, branding and copy setup (0B.10; Ch 6.5, 5.16). The server works out items with a rule (branding
// set, a branch, a second person) from the data; the others are marked by hand. Branding shows after sign-in only.
export type ChecklistOwner = 'super_admin' | 'master_admin' | 'both';
export type ChecklistItem = {
  key: string; owner: ChecklistOwner; chapter: string; state: 'done' | 'open' | 'later'; auto: boolean; available_from: string | null;
  optional: boolean; video_url: string | null; note: string | null; completed_at: string | null; completed_by: string | null;
};
export type Checklist = { done: number; total: number; percent: number; items: ChecklistItem[] };
export type Branding = { name: string; short_name: string | null; brand_color: string; logo_path: string | null; can_edit: boolean };
export type CopyArea = { area: string; add: number; keep: number };
type Result<T> = { data: T | null; error: ErrorInfo | null };

const rpc = <T>(where: string, fn: string, args?: Record<string, unknown>): Promise<Result<T>> =>
  callWithSessionRetry<T>(where, async () => {
    const { data, error } = await supabase.rpc(fn, args);
    return { data: data as T | null, error };
  });

export const fetchChecklist = () => rpc<Checklist>('setup.checklist', 'checklist_get');
export const markChecklist = (item: string, done: boolean, note: string | null) =>
  rpc<Checklist>('setup.mark', 'checklist_mark', { p_item: item, p_done: done, p_note: note });
export const fetchPlatformChecklist = (institutionId: string) =>
  rpc<Checklist>('setup.platformChecklist', 'platform_checklist', { p_institution: institutionId });
export const markPlatformChecklist = (institutionId: string, item: string, done: boolean) =>
  rpc<Checklist>('setup.platformMark', 'platform_checklist_mark', { p_institution: institutionId, p_item: item, p_done: done });

export const fetchBranding = () => rpc<Branding>('setup.branding', 'branding_get');
export const saveBranding = (name: string, shortName: string, logo: { path: string } | 'clear' | null) =>
  rpc<Branding>('setup.brandingSave', 'branding_set', {
    p_name: name, p_short_name: shortName, p_logo_path: logo && logo !== 'clear' ? logo.path : null, p_clear_logo: logo === 'clear',
  });
export const saveBrandColor = (color: string) =>
  rpc<unknown>('setup.brandColor', 'setting_set', { p_key: 'brand_color', p_value: color });

const BUCKET = 'institution-files';

/** Puts the logo file in the institution's own folder; the server checks the folder again when it is saved. */
export async function uploadLogo(institutionId: string, file: Blob, extension: string): Promise<{ path: string } | { error: ErrorInfo }> {
  const path = `${institutionId}/branding/logo-${Math.random().toString(36).slice(2, 10)}.${extension}`;
  const { error } = await supabase.storage.from(BUCKET).upload(path, file, { contentType: file.type || `image/${extension}`, upsert: false });
  if (error) return { error: describeError(error, 'setup.logoUpload') };
  return { path };
}

const logoUrls = new Map<string, string>();
/** A short-lived link to show a logo (the bucket is private). */
export async function logoUrl(path: string): Promise<string | null> {
  const known = logoUrls.get(path);
  if (known) return known;
  const { data } = await supabase.storage.from(BUCKET).createSignedUrl(path, 60 * 60);
  if (!data?.signedUrl) return null;
  logoUrls.set(path, data.signedUrl);
  return data.signedUrl;
}

export const previewCopy = (target: string, source: string, areas: string[]) =>
  rpc<{ applied: boolean; areas: CopyArea[] }>('setup.copyPreview', 'platform_copy_setup', { p_target: target, p_source: source, p_areas: areas, p_confirm: false });
export const applyCopy = (target: string, source: string, areas: string[]) =>
  rpc<{ applied: boolean; areas: CopyArea[] }>('setup.copy', 'platform_copy_setup', { p_target: target, p_source: source, p_areas: areas, p_confirm: true });
export const COPY_AREAS = ['labels', 'settings', 'custom_fields'] as const;
