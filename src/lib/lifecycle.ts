import { Platform } from 'react-native';

import { callWithSessionRetry, type ErrorInfo } from './errors';
import type { Text } from './packs';
import { supabase } from './supabase';

// Institution lifecycle (0B.07): the institution's own status (banners), full exports, and the panel's overview,
// status changes and approval queue. Every rule is enforced on the server.
export type InstitutionStatus = 'pending' | 'trial' | 'active' | 'read_only' | 'suspended' | 'closed';
export type OwnStatus = { status: InstitutionStatus; expires_at: string | null; days_left: number | null; plan: string | null };
export type ExportRow = { id: string; created_at: string; size_bytes: number; counts?: Record<string, number>; by?: string | null };
export type Overview = {
  institution: { id: string; name: string; slug: string; status: InstitutionStatus; industry: string; eiin: string | null; institution_code: string | null;
    address: string | null; contact_phone: string | null; created_at: string; created_by: string | null; approved_at: string | null; approved_by: string | null;
    closed_at: string | null; purge_after: string | null };
  problems: string[];
  profiles: { key: string; version: number; name: Text }[];
  usage: { metric: string; used: number; limit: number | null }[];
  super_admins: string[];
  last_login: string | null;
  history: { from: string | null; to: string; reason: string | null; at: string; by: string | null }[];
  duplicates: { id: string; name: string; slug: string; status: string; match: string }[];
  trial: { by_person: number; by_phone: number; limit: number; flagged: boolean };
  exports: ExportRow[];
  can_close_now: boolean;
};
export type QueueRow = { id: string; name: string; slug: string; created_at: string; duplicates: Overview['duplicates']; trial: Overview['trial'] };
type Result<T> = { data: T | null; error: ErrorInfo | null };

const rpc = <T>(where: string, fn: string, args?: Record<string, unknown>): Promise<Result<T>> =>
  callWithSessionRetry<T>(where, async () => {
    const { data, error } = await supabase.rpc(fn, args);
    return { data: data as T | null, error };
  });

export const fetchOwnStatus = () => rpc<OwnStatus | null>('lifecycle.own', 'institution_status');
export const createExport = (institution: string | null = null) =>
  rpc<{ id: string; size_bytes: number }>('lifecycle.export', 'institution_export_create', { p_institution: institution });
export const listExports = (institution: string | null = null) => rpc<ExportRow[]>('lifecycle.exports', 'institution_exports_list', { p_institution: institution });
export const getExport = (id: string, institution: string | null = null) =>
  rpc<unknown>('lifecycle.exportGet', 'institution_export_get', { p_id: id, p_institution: institution });
export const fetchOverview = (id: string) => rpc<Overview>('lifecycle.overview', 'platform_institution_overview', { p_institution: id });
export const setStatus = (id: string, status: InstitutionStatus, reason: string | null) =>
  rpc<{ status: string; purge_after: string | null }>('lifecycle.status', 'platform_institution_set_status', { p_institution: id, p_status: status, p_reason: reason });
export const fetchApprovalQueue = () => rpc<QueueRow[]>('lifecycle.queue', 'platform_approval_queue');

/** The statuses an institution may move to from its current one (same table as the server). */
export const NEXT: Record<InstitutionStatus, InstitutionStatus[]> = {
  pending: ['trial', 'active', 'suspended', 'closed'],
  trial: ['active', 'read_only', 'suspended', 'closed'],
  active: ['read_only', 'suspended', 'closed'],
  read_only: ['active', 'trial', 'suspended', 'closed'],
  suspended: ['active', 'trial', 'read_only', 'closed'],
  closed: [],
};

/** Saves an export as a JSON file (web). On a phone the export is downloaded from the web panel or the web app. */
export function saveJson(name: string, value: unknown): boolean {
  if (Platform.OS !== 'web' || typeof document === 'undefined') return false;
  const url = URL.createObjectURL(new Blob([JSON.stringify(value)], { type: 'application/json' }));
  const a = document.createElement('a');
  a.href = url;
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
  return true;
}
