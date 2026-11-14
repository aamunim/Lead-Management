// Hub adapter interfaces (0B.12-T2; Ch 42.2). Versioned per kind; an adapter never sees another connection's settings
// or keys, and never decides routing, retries or billing (the worker and the database do). Runtime-independent: the
// Edge Functions use these from Deno, the unit tests from Node.

export const ADAPTER_INTERFACE_VERSION = 1;

/** Settings and keys of the one connection being used (keys read for this call only, never logged). */
export type ConnectionContext = {
  id: string;
  owner: 'institution' | 'platform';
  provider: string;
  sandbox: boolean;
  settings: Record<string, unknown>;
  secrets: Record<string, string | null>;
};

export type OutboundMessage = { id: string; channel: 'sms' | 'email'; recipient: string; body: string; subject?: string };

/** errorCode is one of integration_error_kinds (whose side the failure is on, I10). */
export type SendResult = { ok: true; providerMessageId: string | null } | { ok: false; errorCode: string; detail?: string };
export type HealthResult = { ok: true; balance?: number } | { ok: false; errorCode: string; detail?: string };
export type StatusReport = { providerMessageId: string; status: 'delivered' | 'undelivered' | 'other'; eventKey: string };

export interface SmsAdapter {
  kind: 'sms';
  version: string;
  send(conn: ConnectionContext, msg: OutboundMessage, fetchFn: typeof fetch): Promise<SendResult>;
  health(conn: ConnectionContext, fetchFn: typeof fetch): Promise<HealthResult>;
  /** Callback: true only if this request was signed with this connection's own secret. */
  verifyWebhook(conn: ConnectionContext, headers: Headers, rawBody: string): Promise<boolean>;
  parseStatus(rawBody: string): StatusReport | null;
}

export interface EmailAdapter {
  kind: 'email';
  version: string;
  send(conn: ConnectionContext, msg: OutboundMessage, fetchFn: typeof fetch): Promise<SendResult>;
  health(conn: ConnectionContext, fetchFn: typeof fetch): Promise<HealthResult>;
  verifyWebhook(conn: ConnectionContext, headers: Headers, rawBody: string): Promise<boolean>;
  parseStatus(rawBody: string): StatusReport | null;
}

/** Declared now, built with online payments (Block 2). */
export interface PaymentAdapter {
  kind: 'payment';
  version: string;
  createCheckout(conn: ConnectionContext, input: { amount: string; currency: string; reference: string }, fetchFn: typeof fetch):
    Promise<{ ok: true; url: string; sessionId: string } | { ok: false; errorCode: string; detail?: string }>;
  verifyWebhook(conn: ConnectionContext, headers: Headers, rawBody: string): Promise<boolean>;
}

export type Adapter = SmsAdapter | EmailAdapter;

/** HMAC-SHA256 of the raw body with the connection's webhook secret, hex; compared in constant time. */
export async function hmacHex(secret: string, body: string): Promise<string> {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(body)));
  return Array.from(sig, (b) => b.toString(16).padStart(2, '0')).join('');
}
export function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
