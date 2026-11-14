// SMTP email adapter (0B.14-T1): Gmail app password, cPanel mail. Implicit TLS on port 465 only — Supabase Edge
// Functions do not allow outgoing connections on ports 25 and 587. A small SMTP client over an abstract connection, so
// the conversation is unit-tested without a network; the Edge Function opens the TLS socket (smtp-deno.ts).
import type { ConnectionContext, EmailAdapter, HealthResult, OutboundMessage, SendResult } from './adapters.ts';

export interface SmtpSocket {
  write(line: string): Promise<void>;
  /** The next complete reply (multi-line replies joined), e.g. "250 OK". */
  read(): Promise<string>;
  close(): Promise<void>;
}
export type SmtpOpener = (host: string, port: number) => Promise<SmtpSocket>;

class SmtpError extends Error {
  code: number;
  constructor(code: number, message: string) {
    super(message);
    this.code = code;
  }
}

async function expect(sock: SmtpSocket, ok: number[]): Promise<string> {
  const reply = await sock.read();
  const code = Number(reply.slice(0, 3));
  if (!ok.includes(code)) throw new SmtpError(code, reply.slice(0, 200));
  return reply;
}
async function cmd(sock: SmtpSocket, line: string, ok: number[]): Promise<string> {
  await sock.write(`${line}\r\n`);
  return expect(sock, ok);
}

const b64 = (text: string) => btoa(String.fromCharCode(...new TextEncoder().encode(text)));
/** A header value with non-ASCII text (Bangla names, subjects) as RFC 2047 encoded words. */
export function encodeHeader(value: string): string {
  const clean = value.replace(/[\r\n]+/g, ' ');
  return /^[\x20-\x7e]*$/.test(clean) ? clean : `=?UTF-8?B?${b64(clean)}?=`;
}
const address = /^[^\s@<>"]+@[^\s@<>"]+\.[^\s@<>"]+$/;

export function buildMessage(from: { name?: string | null; email: string }, to: string, subject: string, body: string, replyTo: string | null,
  messageId: string, date = new Date()): string {
  const fromHeader = from.name ? `${encodeHeader(from.name)} <${from.email}>` : from.email;
  const lines = [
    `From: ${fromHeader}`, `To: <${to}>`, `Subject: ${encodeHeader(subject)}`, `Date: ${date.toUTCString()}`,
    `Message-ID: <${messageId}@${from.email.split('@')[1]}>`, 'MIME-Version: 1.0', 'Content-Type: text/plain; charset=UTF-8',
    'Content-Transfer-Encoding: base64', ...(replyTo ? [`Reply-To: <${replyTo}>`] : []), '',
    ...(b64(body).match(/.{1,76}/g) ?? ['']),
  ];
  // Dot-stuffing is not needed for base64 bodies; headers never start with a dot.
  return `${lines.join('\r\n')}\r\n.`;
}

export function mapSmtpError(code: number, text: string): string {
  if (code === 535 || code === 534 || code === 530) return 'auth_failed';
  if (code === 550 || code === 553 || code === 501) return /sender|from|relay/i.test(text) ? 'sender_not_approved' : 'invalid_recipient';
  if (code === 552 || code === 452) return 'rate_limited';
  if (code === 421 || code >= 400 && code < 500) return 'provider_down';
  return 'adapter_error';
}

export function smtpAdapter(open: SmtpOpener): EmailAdapter {
  async function session<T>(conn: ConnectionContext, work: (sock: SmtpSocket) => Promise<T>): Promise<T> {
    const host = String(conn.settings.host ?? '');
    const sock = await open(host, Number(conn.settings.port ?? 465));
    try {
      await expect(sock, [220]);
      await cmd(sock, `EHLO ${host.includes('.') ? 'leadora.app' : 'localhost'}`, [250]);
      const user = String(conn.settings.username ?? conn.settings.from_email ?? '');
      await cmd(sock, 'AUTH LOGIN', [334]);
      await cmd(sock, b64(user), [334]);
      await cmd(sock, b64(conn.secrets.password ?? ''), [235]);
      const out = await work(sock);
      await cmd(sock, 'QUIT', [221]).catch(() => '');
      return out;
    } finally {
      await sock.close().catch(() => undefined);
    }
  }
  return {
    kind: 'email',
    version: 'smtp-1',
    async send(conn: ConnectionContext, msg: OutboundMessage): Promise<SendResult> {
      if (!conn.secrets.password) return { ok: false, errorCode: 'auth_failed', detail: 'no password set' };
      const fromEmail = msg.sender?.from_email ?? String(conn.settings.from_email ?? '');
      if (!address.test(fromEmail) || !address.test(msg.recipient)) return { ok: false, errorCode: 'invalid_recipient', detail: 'address' };
      try {
        return await session(conn, async (sock) => {
          await cmd(sock, `MAIL FROM:<${fromEmail}>`, [250]);
          await cmd(sock, `RCPT TO:<${msg.recipient}>`, [250, 251]);
          await cmd(sock, 'DATA', [354]);
          const reply = await cmd(sock, buildMessage({ name: msg.sender?.from_name ?? (conn.settings.from_name as string | undefined), email: fromEmail },
            msg.recipient, msg.subject ?? '', msg.body, msg.sender?.reply_to ?? (conn.settings.reply_to as string | undefined) ?? null, msg.id), [250]);
          return { ok: true as const, providerMessageId: reply.slice(4, 100).trim() || null };
        });
      } catch (e) {
        if (e instanceof SmtpError) return { ok: false, errorCode: mapSmtpError(e.code, e.message), detail: e.message };
        return { ok: false, errorCode: 'provider_down', detail: String((e as Error)?.message ?? e).slice(0, 200) };
      }
    },
    async health(conn: ConnectionContext): Promise<HealthResult> {
      if (!conn.secrets.password) return { ok: false, errorCode: 'auth_failed', detail: 'no password set' };
      try {
        await session(conn, async () => null);
        return { ok: true };
      } catch (e) {
        if (e instanceof SmtpError) return { ok: false, errorCode: mapSmtpError(e.code, e.message), detail: e.message };
        return { ok: false, errorCode: 'provider_down', detail: String((e as Error)?.message ?? e).slice(0, 200) };
      }
    },
    // SMTP has no status callbacks; bounces come back to the sender's mailbox.
    verifyWebhook: async () => false,
    parseStatus: () => null,
  };
}
