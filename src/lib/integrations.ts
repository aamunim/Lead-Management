import { callWithSessionRetry, type ErrorInfo } from './errors';
import type { Text } from './packs';
import { supabase } from './supabase';

// Integration hub core (0B.11; Ch 42): the provider catalog, connections per institution and the platform's own
// gateways, write-only secrets (hints only), rotation dates, live tests, who pays, and the integration audit.
// Everything here is the Master Admin's (D4, platform.integrations + two-step sign-in); the institution sees status only.
export type Provider = {
  key: string; kind: string; name: Text; settings_schema: JsonSchema; secret_fields: string[]; docs_url: string | null;
  capabilities: string[]; adapter_version: string | null; status: 'active' | 'beta' | 'planned' | 'retired';
};
export type JsonSchema = { type?: string | string[]; properties?: Record<string, JsonSchema>; required?: string[]; enum?: string[];
  default?: unknown; minimum?: number; maximum?: number; maxLength?: number; pattern?: string };
export type ConnectionError = { code: string; responsibility: 'platform' | 'institution' | 'provider'; at: string; detail: string | null };
export type SecretInfo = { field: string; hint: string | null; since: string | null; age_days: number | null; next_from: string | null };
export type Connection = {
  id: string; kind: string; provider: string; provider_name: Text; label: string; mode: 'sandbox' | 'live'; status: 'active' | 'disabled';
  priority: number; live_test_passed_at: string | null; last_success_at: string | null; last_error: ConnectionError | null; adapter_ready: boolean;
  settings?: Record<string, unknown>; secrets?: SecretInfo[]; secret_fields?: string[];
};
export type AuditRow = { action: string; at: string; by: string | null; detail: Record<string, unknown> };
type Result<T> = { data: T | null; error: ErrorInfo | null };

const rpc = <T>(where: string, fn: string, args?: Record<string, unknown>): Promise<Result<T>> =>
  callWithSessionRetry<T>(where, async () => {
    const { data, error } = await supabase.rpc(fn, args);
    return { data: data as T | null, error };
  });

export const fetchProviders = () =>
  rpc<{ providers: Provider[]; platform_connections: Connection[]; error_kinds: Record<string, string> }>('integrations.providers', 'platform_providers');
export const fetchIntegrations = (institutionId: string) =>
  rpc<{ connections: Connection[]; payers: Record<string, 'direct' | 'platform'>; audit: AuditRow[] }>('integrations.institution', 'platform_integrations',
    { p_institution: institutionId });
export const saveConnection = (institutionId: string | null, id: string | null, data: { provider: string; label: string; mode: string; priority: number;
  settings: Record<string, unknown> }) =>
  rpc<Connection>('integrations.save', 'platform_connection_save', { p_institution: institutionId, p_id: id, p_data: data });
export const setConnectionSecret = (institutionId: string | null, connectionId: string, field: string, value: string, validFrom: string | null) =>
  rpc<{ field: string; hint: string; valid_from: string }>('integrations.secret', 'connection_secret_set',
    { p_institution: institutionId, p_connection: connectionId, p_field: field, p_value: value, p_valid_from: validFrom });
export const markLiveTest = (institutionId: string | null, connectionId: string, passed: boolean, note: string | null) =>
  rpc<Connection>('integrations.liveTest', 'connection_live_test_mark', { p_institution: institutionId, p_connection: connectionId, p_passed: passed, p_note: note });
export const setConnectionActive = (institutionId: string | null, connectionId: string, active: boolean, reason: string | null) =>
  rpc<Connection>('integrations.status', 'connection_set_status', { p_institution: institutionId, p_connection: connectionId, p_active: active, p_reason: reason });
export const setPayer = (institutionId: string, kind: string, payer: 'direct' | 'platform') =>
  rpc<{ kind: string; payer: string }>('integrations.payer', 'institution_payer_set', { p_institution: institutionId, p_kind: kind, p_payer: payer });
export const fetchOwnIntegrations = () =>
  rpc<{ connections: Connection[]; payers: Record<string, 'direct' | 'platform'> }>('integrations.own', 'integrations_status');

/** Fields of a provider's settings form, from its JSON schema (strings, numbers, yes / no, choices). */
export type SettingsField = { key: string; kind: 'text' | 'number' | 'boolean' | 'choice'; required: boolean; choices?: string[]; schema: JsonSchema };
export function settingsFields(schema: JsonSchema): SettingsField[] {
  return Object.entries(schema.properties ?? {}).map(([key, s]) => ({
    key, schema: s, required: (schema.required ?? []).includes(key),
    kind: s.enum ? 'choice' : s.type === 'integer' || s.type === 'number' ? 'number' : s.type === 'boolean' ? 'boolean' : 'text',
    choices: s.enum,
  }));
}
