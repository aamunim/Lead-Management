import { useCallback, useEffect, useState } from 'react';

import { callWithSessionRetry, type ErrorInfo } from './errors';
import type { Text } from './packs';
import { supabase } from './supabase';

// Modules and limits (0B.05). The server decides everything (allowed by the plan or the platform, switched on by the
// institution, industry, dependencies; limits with 80 % / 100 %); the app only shows it.
export type ModuleState = {
  key: string; label_key: string | null; always_on: boolean; depends_on: string[]; built_in: string | null;
  in_industry: boolean; allowed: boolean; switched_on: boolean; enabled: boolean;
};
export type LimitLevel = 'ok' | 'warning' | 'full' | 'blocked';
export type LimitsStatus = {
  plan: { key: string; version: number; name: Text; expires_at: string | null; modules: string[] } | null;
  metrics: { metric: string; level: LimitLevel; used: number | null; limit: number | null }[];
};
type Result<T> = { data: T | null; error: ErrorInfo | null };

const rpc = <T>(where: string, fn: string, args?: Record<string, unknown>): Promise<Result<T>> =>
  callWithSessionRetry<T>(where, async () => {
    const { data, error } = await supabase.rpc(fn, args);
    return { data: data as T | null, error };
  });

export const fetchModules = () => rpc<ModuleState[]>('modules.get', 'modules_get');
export const setModule = (key: string, enabled: boolean, confirm: boolean) =>
  rpc<{ impact: { needs: string[]; stops: string[] }; applied: boolean }>('modules.set', 'module_set', { p_key: key, p_enabled: enabled, p_confirm: confirm });
export const fetchLimits = () => rpc<LimitsStatus>('limits.status', 'limits_status');

/** Which modules work for the active institution (menus hide the others). null while loading. */
export function useModulesEnabled(): { enabled: (key: string) => boolean; loaded: boolean; reload: () => void } {
  const [mods, setMods] = useState<ModuleState[] | null>(null);
  const reload = useCallback(() => {
    void fetchModules().then((r) => setMods(r.data ?? []));
  }, []);
  useEffect(reload, [reload]);
  return { enabled: (key) => !!mods?.find((m) => m.key === key)?.enabled, loaded: mods !== null, reload };
}
