// Custom HTTP SMS adapter (0B.13-T3; Ch 42.4): any gateway with an HTTP API, set up by the Master Admin only.
// Safety (Proposed): HTTPS and public hosts only — internal, loopback, link-local and private addresses are refused
// (SSRF), also after DNS resolution when a resolver is given; a timeout; the key never appears in logs or errors.
import type { ConnectionContext, HealthResult, OutboundMessage, SendResult, SmsAdapter, StatusReport } from './adapters.ts';
import { hmacHex, safeEqual } from './adapters.ts';
import { smsParts } from './sms-parts.ts';

export type CustomHttpSettings = {
  send_url: string;
  method?: 'GET' | 'POST';
  body_format?: 'form' | 'json';
  /** Request parameters; values may use {to}, {message}, {sender_id}, {api_key}, {unicode}. */
  params?: Record<string, string>;
  /** The send succeeded if the response body contains this text (or matches /regex/). Default: HTTP 2xx. */
  success_match?: string;
  /** Where the provider's message id is in a JSON response, e.g. "data.message_id". */
  message_id_path?: string;
  balance_url?: string;
  balance_path?: string;
  sender_id?: string;
  /** A masked sender id is used only once approved; until then the non-masked one (0B.13-T13, D35). */
  masking?: { type: 'non_masked' | 'masked'; status?: 'applied' | 'approved' | 'rejected'; non_masked_sender_id?: string };
  timeout_ms?: number;
};

const PRIVATE_V4: [number, number][] = [
  [0x0a000000, 8], [0xac100000, 12], [0xc0a80000, 16], [0x7f000000, 8], [0xa9fe0000, 16], [0x64400000, 10], [0x00000000, 8],
  [0xe0000000, 4], [0xf0000000, 4], [0xc6120000, 15],
];

function ipv4ToInt(ip: string): number | null {
  const m = ip.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
  if (!m) return null;
  const parts = m.slice(1).map(Number);
  if (parts.some((p) => p > 255)) return null;
  return ((parts[0] << 24) >>> 0) + (parts[1] << 16) + (parts[2] << 8) + parts[3];
}

/** True for addresses that must never be called: private, loopback, link-local (cloud metadata), multicast… */
export function isBlockedAddress(host: string): boolean {
  const h = host.replace(/^\[|\]$/g, '').toLowerCase();
  const v4 = ipv4ToInt(h);
  if (v4 !== null) return PRIVATE_V4.some(([net, bits]) => (v4 >>> (32 - bits)) === (net >>> (32 - bits)));
  if (h.includes(':')) {
    return h === '::' || h === '::1' || h.startsWith('fc') || h.startsWith('fd') || h.startsWith('fe80') || h.startsWith('::ffff:')
      || h.startsWith('ff');
  }
  return h === 'localhost' || h.endsWith('.localhost') || h.endsWith('.local') || h.endsWith('.internal') || h.endsWith('.lan')
    || h === 'metadata.google.internal' || !h.includes('.');
}

/** Checks a gateway URL: https, a public host name or address, no credentials in the URL. */
export async function checkTarget(raw: string, resolve?: (host: string) => Promise<string[]>): Promise<string | null> {
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    return 'not a valid address';
  }
  if (url.protocol !== 'https:') return 'only https is allowed';
  if (url.username || url.password) return 'no credentials in the address';
  if (isBlockedAddress(url.hostname)) return 'internal or private addresses are not allowed';
  if (resolve) {
    const ips = await resolve(url.hostname).catch(() => []);
    if (ips.length === 0) return 'the host name does not resolve';
    if (ips.some(isBlockedAddress)) return 'the host resolves to an internal address';
  }
  return null;
}

function fill(template: string, values: Record<string, string>): string {
  return template.replace(/\{(to|message|sender_id|api_key|unicode)\}/g, (_, k: string) => values[k] ?? '');
}

function pick(obj: unknown, path: string): unknown {
  return path.split('.').reduce<unknown>((o, k) => (o && typeof o === 'object' ? (o as Record<string, unknown>)[k] : undefined), obj);
}

function matches(body: string, rule: string): boolean {
  const re = rule.match(/^\/(.+)\/([a-z]*)$/);
  return re ? new RegExp(re[1], re[2]).test(body) : body.includes(rule);
}

/** The sender id to use: a masked one only when approved (D35). */
export function senderFor(s: CustomHttpSettings): string {
  if (s.masking?.type === 'masked' && s.masking.status !== 'approved') return s.masking.non_masked_sender_id ?? '';
  return s.sender_id ?? '';
}

/** Maps an HTTP status / body to an error kind (whose side, I10). */
export function mapError(status: number, body: string): string {
  const b = body.toLowerCase();
  if (status === 401 || status === 403 || /invalid (api )?key|unauthori[sz]ed|authentication/.test(b)) return 'auth_failed';
  if (/balance|insufficient|credit/.test(b)) return 'balance_low';
  if (/sender|mask/.test(b)) return 'sender_not_approved';
  if (/invalid (number|recipient|mobile)/.test(b)) return 'invalid_recipient';
  if (status === 429) return 'rate_limited';
  if (status >= 500) return 'provider_down';
  return 'adapter_error';
}

async function call(s: CustomHttpSettings, url: string, values: Record<string, string>, fetchFn: typeof fetch,
  resolve?: (host: string) => Promise<string[]>): Promise<{ status: number; body: string } | { blocked: string }> {
  const target = fill(url, Object.fromEntries(Object.entries(values).map(([k, v]) => [k, encodeURIComponent(v)])));
  const problem = await checkTarget(target, resolve);
  if (problem) return { blocked: problem };
  const params = Object.fromEntries(Object.entries(s.params ?? {}).map(([k, v]) => [k, fill(v, values)]));
  const method = s.method ?? 'POST';
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), Math.min(s.timeout_ms ?? 10_000, 20_000));
  try {
    let res: Response;
    if (method === 'GET') {
      const u = new URL(target);
      for (const [k, v] of Object.entries(params)) u.searchParams.set(k, v);
      res = await fetchFn(u.toString(), { method, signal: controller.signal, redirect: 'manual' });
    } else if ((s.body_format ?? 'form') === 'json') {
      res = await fetchFn(target, { method, body: JSON.stringify(params), headers: { 'content-type': 'application/json' }, signal: controller.signal,
        redirect: 'manual' });
    } else {
      res = await fetchFn(target, { method, body: new URLSearchParams(params).toString(),
        headers: { 'content-type': 'application/x-www-form-urlencoded' }, signal: controller.signal, redirect: 'manual' });
    }
    return { status: res.status, body: (await res.text()).slice(0, 4000) };
  } finally {
    clearTimeout(timer);
  }
}

/** A detail text without the key (never logged or stored). */
function scrub(text: string, conn: ConnectionContext): string {
  let out = text;
  for (const v of Object.values(conn.secrets)) if (v && v.length >= 4) out = out.split(v).join('••••');
  return out.slice(0, 300);
}

export function customHttpAdapter(resolve?: (host: string) => Promise<string[]>): SmsAdapter {
  return {
    kind: 'sms',
    version: 'custom-http-1',
    async send(conn: ConnectionContext, msg: OutboundMessage, fetchFn: typeof fetch): Promise<SendResult> {
      const s = conn.settings as unknown as CustomHttpSettings;
      if (!conn.secrets.api_key) return { ok: false, errorCode: 'auth_failed', detail: 'no key set' };
      const values = { to: msg.recipient, message: msg.body, sender_id: senderFor(s), api_key: conn.secrets.api_key,
        unicode: smsParts(msg.body).unicode ? '1' : '0' };
      let r;
      try {
        r = await call(s, s.send_url, values, fetchFn, resolve);
      } catch (e) {
        return { ok: false, errorCode: (e as Error)?.name === 'AbortError' ? 'timeout' : 'provider_down', detail: scrub(String((e as Error)?.message ?? e), conn) };
      }
      if ('blocked' in r) return { ok: false, errorCode: 'config_invalid', detail: r.blocked };
      const ok = r.status >= 200 && r.status < 300 && (!s.success_match || matches(r.body, s.success_match));
      if (!ok) return { ok: false, errorCode: mapError(r.status, r.body), detail: scrub(`HTTP ${r.status}: ${r.body}`, conn) };
      let id: string | null = null;
      if (s.message_id_path) {
        try {
          const v = pick(JSON.parse(r.body), s.message_id_path);
          id = v === undefined || v === null ? null : String(v);
        } catch {
          id = null;
        }
      }
      return { ok: true, providerMessageId: id };
    },
    async health(conn: ConnectionContext, fetchFn: typeof fetch): Promise<HealthResult> {
      const s = conn.settings as unknown as CustomHttpSettings;
      if (!conn.secrets.api_key) return { ok: false, errorCode: 'auth_failed', detail: 'no key set' };
      if (!s.balance_url) return { ok: true };
      try {
        const r = await call({ ...s, method: 'GET', params: {} }, s.balance_url, { to: '', message: '', sender_id: '', api_key: conn.secrets.api_key,
          unicode: '0' }, fetchFn, resolve);
        if ('blocked' in r) return { ok: false, errorCode: 'config_invalid', detail: r.blocked };
        if (r.status < 200 || r.status >= 300) return { ok: false, errorCode: mapError(r.status, r.body), detail: scrub(`HTTP ${r.status}`, conn) };
        const raw = s.balance_path ? pick(JSON.parse(r.body), s.balance_path) : Number(r.body.trim());
        const balance = Number(raw);
        return Number.isFinite(balance) ? { ok: true, balance } : { ok: true };
      } catch (e) {
        return { ok: false, errorCode: 'provider_down', detail: scrub(String((e as Error)?.message ?? e), conn) };
      }
    },
    async verifyWebhook(conn: ConnectionContext, headers: Headers, rawBody: string): Promise<boolean> {
      const secret = conn.secrets.webhook_secret;
      const given = headers.get('x-signature') ?? headers.get('x-hub-signature');
      if (!secret || !given) return false;
      return safeEqual(await hmacHex(secret, rawBody), given.replace(/^sha256=/, ''));
    },
    parseStatus(rawBody: string): StatusReport | null {
      try {
        const b = JSON.parse(rawBody) as Record<string, unknown>;
        const id = b.message_id ?? b.messageId ?? b.id;
        if (id === undefined) return null;
        const st = String(b.status ?? '').toLowerCase();
        const status = /^(delivered|deliv|success)/.test(st) ? 'delivered' : /^(undeliv|failed|rejected|expired)/.test(st) ? 'undelivered' : 'other';
        return { providerMessageId: String(id), status, eventKey: `${id}:${st}` };
      } catch {
        return null;
      }
    },
  };
}
