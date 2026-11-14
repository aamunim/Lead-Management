// Resend email adapter (0B.14-T2; owner's choice D47). Sends through the HTTPS API with the connection's own key;
// status callbacks are Svix-signed with the connection's webhook secret ("whsec_…"): delivered, bounced, complained.
import type { ConnectionContext, EmailAdapter, HealthResult, OutboundMessage, SendResult, StatusReport } from './adapters.ts';
import { safeEqual } from './adapters.ts';

const API = 'https://api.resend.com';

export function mapResendError(status: number, body: string): string {
  const b = body.toLowerCase();
  if (status === 401 || status === 403 || b.includes('api key')) return 'auth_failed';
  if (b.includes('domain') && (b.includes('not verified') || b.includes('verify'))) return 'domain_not_verified';
  if (status === 422 && b.includes('to')) return 'invalid_recipient';
  if (status === 429) return 'rate_limited';
  if (status >= 500) return 'provider_down';
  return 'adapter_error';
}

function fromHeader(msg: OutboundMessage, conn: ConnectionContext): string | null {
  const email = msg.sender?.from_email ?? (conn.settings.from_email as string | undefined);
  if (!email) return null;
  const name = (msg.sender?.from_name ?? (conn.settings.from_name as string | undefined) ?? '').replace(/["<>\r\n]/g, '').trim();
  return name ? `${name} <${email}>` : email;
}

function b64(bytes: Uint8Array): string {
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s);
}
function unb64(text: string): Uint8Array<ArrayBuffer> {
  const s = atob(text);
  const out = new Uint8Array(new ArrayBuffer(s.length));
  for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
  return out;
}

/** Svix signature check: v1,<base64 HMAC-SHA256 of "id.timestamp.body" with the secret's bytes>; timestamps within 5 minutes. */
export async function verifySvix(secret: string, headers: Headers, rawBody: string, nowSeconds = Math.floor(Date.now() / 1000)): Promise<boolean> {
  const id = headers.get('svix-id');
  const ts = headers.get('svix-timestamp');
  const sigs = headers.get('svix-signature');
  if (!id || !ts || !sigs || !/^\d+$/.test(ts) || Math.abs(nowSeconds - Number(ts)) > 300) return false;
  const keyBytes = unb64(secret.replace(/^whsec_/, ''));
  const key = await crypto.subtle.importKey('raw', keyBytes, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const mac = b64(new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`${id}.${ts}.${rawBody}`))));
  return sigs.split(' ').some((part) => {
    const [version, value] = part.split(',');
    return version === 'v1' && !!value && safeEqual(value, mac);
  });
}

export const resendAdapter: EmailAdapter = {
  kind: 'email',
  version: 'resend-1',
  async send(conn: ConnectionContext, msg: OutboundMessage, fetchFn: typeof fetch): Promise<SendResult> {
    if (!conn.secrets.api_key) return { ok: false, errorCode: 'auth_failed', detail: 'no key set' };
    const from = fromHeader(msg, conn);
    if (!from) return { ok: false, errorCode: 'domain_not_verified', detail: 'no sender address' };
    const replyTo = msg.sender?.reply_to ?? (conn.settings.reply_to as string | undefined);
    let res: Response;
    try {
      res = await fetchFn(`${API}/emails`, {
        method: 'POST',
        headers: { authorization: `Bearer ${conn.secrets.api_key}`, 'content-type': 'application/json', 'idempotency-key': msg.id },
        body: JSON.stringify({ from, to: [msg.recipient], subject: msg.subject ?? '', text: msg.body, ...(replyTo ? { reply_to: replyTo } : {}) }),
        signal: AbortSignal.timeout(15_000),
      });
    } catch (e) {
      return { ok: false, errorCode: (e as Error)?.name === 'TimeoutError' ? 'timeout' : 'provider_down', detail: String((e as Error)?.message ?? e).slice(0, 200) };
    }
    const text = await res.text();
    if (!res.ok) return { ok: false, errorCode: mapResendError(res.status, text), detail: `HTTP ${res.status}: ${text.slice(0, 200)}` };
    try {
      return { ok: true, providerMessageId: (JSON.parse(text) as { id?: string }).id ?? null };
    } catch {
      return { ok: true, providerMessageId: null };
    }
  },
  async health(conn: ConnectionContext, fetchFn: typeof fetch): Promise<HealthResult> {
    if (!conn.secrets.api_key) return { ok: false, errorCode: 'auth_failed', detail: 'no key set' };
    try {
      const res = await fetchFn(`${API}/domains`, { headers: { authorization: `Bearer ${conn.secrets.api_key}` }, signal: AbortSignal.timeout(10_000) });
      return res.ok ? { ok: true } : { ok: false, errorCode: mapResendError(res.status, await res.text()) };
    } catch (e) {
      return { ok: false, errorCode: 'provider_down', detail: String((e as Error)?.message ?? e).slice(0, 200) };
    }
  },
  async verifyWebhook(conn: ConnectionContext, headers: Headers, rawBody: string): Promise<boolean> {
    return conn.secrets.webhook_secret ? verifySvix(conn.secrets.webhook_secret, headers, rawBody) : false;
  },
  parseStatus(rawBody: string): StatusReport | null {
    try {
      const b = JSON.parse(rawBody) as { type?: string; data?: { email_id?: string }; created_at?: string };
      const id = b.data?.email_id;
      if (!id || !b.type) return null;
      const status = b.type === 'email.delivered' ? 'delivered' : b.type === 'email.bounced' ? 'bounced'
        : b.type === 'email.complained' ? 'complained' : b.type === 'email.delivery_delayed' ? 'other' : 'other';
      return { providerMessageId: id, status, eventKey: `${id}:${b.type}` };
    } catch {
      return null;
    }
  },
};
