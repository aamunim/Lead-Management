// Mock adapters (0B.12-T12): engineering only, for unit and integration tests (the full fake-adapter set for CI comes
// with Block 1B). They never call the network. A body containing "FAIL" fails (adapter error, the platform's side),
// "BALANCE" fails as a low balance (the institution's side). Callbacks are signed with HMAC of the webhook secret.
import { hmacHex, safeEqual, type ConnectionContext, type EmailAdapter, type SmsAdapter } from './adapters.ts';

let counter = 0;
/** Every message a mock adapter "sent", with the connection that sent it (tests assert on this). */
export const mockSent: { connectionId: string; recipient: string; body: string }[] = [];

function sendLike(conn: ConnectionContext, recipient: string, body: string) {
  if (!conn.secrets.api_key) return { ok: false as const, errorCode: 'auth_failed', detail: 'no key' };
  if (body.includes('BALANCE')) return { ok: false as const, errorCode: 'balance_low', detail: 'mock balance low' };
  if (body.includes('FAIL')) return { ok: false as const, errorCode: 'adapter_error', detail: 'mock failure' };
  mockSent.push({ connectionId: conn.id, recipient, body });
  counter += 1;
  return { ok: true as const, providerMessageId: `mock-${conn.id.slice(0, 8)}-${counter}` };
}

async function verify(conn: ConnectionContext, headers: Headers, rawBody: string): Promise<boolean> {
  const secret = conn.secrets.webhook_secret;
  const given = headers.get('x-mock-signature');
  if (!secret || !given) return false;
  return safeEqual(await hmacHex(secret, rawBody), given);
}

function parse(rawBody: string) {
  try {
    const b = JSON.parse(rawBody) as { message_id?: string; status?: string; event_id?: string };
    if (!b.message_id) return null;
    const status = b.status === 'delivered' || b.status === 'undelivered' ? b.status : 'other';
    return { providerMessageId: b.message_id, status, eventKey: b.event_id ?? `${b.message_id}:${b.status}` } as const;
  } catch {
    return null;
  }
}

export const mockSms: SmsAdapter = {
  kind: 'sms', version: 'mock-1',
  send: async (conn, msg) => sendLike(conn, msg.recipient, msg.body),
  health: async (conn) => (conn.secrets.api_key ? { ok: true, balance: 1000 } : { ok: false, errorCode: 'auth_failed' }),
  verifyWebhook: verify,
  parseStatus: parse,
};

export const mockEmail: EmailAdapter = {
  kind: 'email', version: 'mock-1',
  send: async (conn, msg) => sendLike(conn, msg.recipient, msg.body),
  health: async (conn) => (conn.secrets.api_key ? { ok: true } : { ok: false, errorCode: 'auth_failed' }),
  verifyWebhook: verify,
  parseStatus: parse,
};
