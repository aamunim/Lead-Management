import { callWithSessionRetry, describeError, type ErrorInfo } from './errors';
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
  route?: 'transactional' | 'promotional' | 'all'; masking?: { type?: string; status?: string } | null; circuit_open?: boolean;
  balance_exhausted?: boolean; last_balance?: number | null; balance_checked_at?: string | null;
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
  rpc<{ connections: Connection[]; payers: Record<string, 'direct' | 'platform'>; fallback?: Record<string, boolean>; audit: AuditRow[] }>('integrations.institution', 'platform_integrations',
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
export type SettingsField = { key: string; kind: 'text' | 'number' | 'boolean' | 'choice' | 'json'; required: boolean; choices?: string[]; schema: JsonSchema };
export function settingsFields(schema: JsonSchema): SettingsField[] {
  return Object.entries(schema.properties ?? {}).map(([key, s]) => ({
    key, schema: s, required: (schema.required ?? []).includes(key),
    kind: s.enum ? 'choice' : s.type === 'integer' || s.type === 'number' ? 'number' : s.type === 'boolean' ? 'boolean' : s.type === 'object' ? 'json' : 'text',
    choices: s.enum,
  }));
}

// Hub runtime (0B.12): the panel's delivery log, usage ledger and the Test button.
export type DeliveryRow = {
  id: string; institution_id: string; institution: string; recipient: string; channel: string; category: string; template_key: string | null;
  result: 'sent' | 'failed' | 'given_up' | 'delivered' | 'undelivered' | 'unknown'; at: string; connection: string | null; fallback: boolean;
  sandbox: boolean; provider_message_id: string | null; parts: number | null; cost: number | null; error: { code: string; responsibility?: string } | null;
};
export type LedgerRow = {
  institution_id: string; institution: string; day: string; provider: string; channel: string; category: string; payer: 'direct' | 'platform';
  count: number; parts: number; failed_parts: number; cost: number; billable: boolean;
};
export const fetchDeliveryLog = (institutionId: string | null, channel: string | null) =>
  rpc<DeliveryRow[]>('integrations.deliveryLog', 'platform_delivery_log', { p_institution: institutionId, p_channel: channel, p_result: null, p_limit: 100 });
export const fetchUsageLedger = (institutionId: string | null) =>
  rpc<LedgerRow[]>('integrations.ledger', 'platform_usage_ledger', { p_institution: institutionId, p_from: null, p_to: null });
export const sendConnectionTest = (institutionId: string, connectionId: string, recipient: string, body: string | null) =>
  rpc<{ id: string; status: string }>('integrations.test', 'platform_connection_test',
    { p_institution: institutionId, p_connection: connectionId, p_recipient: recipient, p_body: body });
export const makePrimary = (institutionId: string | null, connectionId: string) =>
  rpc<{ primary: string; previous: string | null }>('integrations.primary', 'connection_make_primary', { p_institution: institutionId, p_connection: connectionId });
export const setPlatformFallback = (institutionId: string, kind: string, on: boolean) =>
  rpc<{ kind: string; platform_fallback: boolean }>('integrations.fallback', 'institution_platform_fallback_set',
    { p_institution: institutionId, p_kind: kind, p_on: on });

// Email (0B.14): sending domains with their DNS records, the check result, a paused sender, the reputation.
export type DnsRecord = { type: string; name: string; value: string; check: 'spf' | 'dkim' | 'dmarc'; note: string };
export type DomainCheck = { ok: boolean; found: string[]; problem: string | null };
export type EmailDomain = {
  domain: string; provider: string | null; status: 'pending' | 'verified' | 'failed'; dkim_selector: string; checked_at: string | null;
  verified_at: string | null; expected: DnsRecord[]; last_check: { spf?: DomainCheck; dkim?: DomainCheck; dmarc?: DomainCheck } | null;
};
export type EmailState = {
  domains: EmailDomain[]; paused: { at: string; reason: string } | null;
  reputation: { sent: number; delivered: number; bounced: number; complained: number };
  platform_sender: { from_name: string | null; from_email: string | null; reply_to: string | null } | null;
};
export const fetchEmail = (institutionId: string) => rpc<EmailState>('integrations.email', 'platform_email', { p_institution: institutionId });
export const addEmailDomain = (institutionId: string, domain: string, provider: 'resend' | 'smtp', selector: string | null) =>
  rpc<EmailState>('integrations.emailDomain', 'platform_email_domain_add', { p_institution: institutionId, p_domain: domain, p_provider: provider, p_selector: selector });
export const resumeEmail = (institutionId: string, reason: string) =>
  rpc<EmailState>('integrations.emailResume', 'platform_email_resume', { p_institution: institutionId, p_reason: reason });
/** The Verify button: the email-domain-check function reads DNS on the server and stores the result. */
export async function verifyEmailDomain(institutionId: string, domain: string): Promise<{ data: { status: string } | null; error: ErrorInfo | null }> {
  const { data, error } = await supabase.functions.invoke('email-domain-check', { body: { institution_id: institutionId, domain } });
  return error ? { data: null, error: describeError(error, 'integrations.emailVerify') } : { data: data as { status: string }, error: null };
}
