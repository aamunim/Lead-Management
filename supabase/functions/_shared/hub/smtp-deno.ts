// The TLS socket for the SMTP adapter (Deno only): implicit TLS, a 15-second limit per reply.
import type { SmtpSocket } from './smtp.ts';

export async function openSmtp(host: string, port: number): Promise<SmtpSocket> {
  const conn = await Deno.connectTls({ hostname: host, port });
  const enc = new TextEncoder();
  const dec = new TextDecoder();
  let buffer = '';
  async function line(): Promise<string> {
    const deadline = Date.now() + 15_000;
    while (!buffer.includes('\r\n')) {
      if (Date.now() > deadline) throw new Error('SMTP timeout');
      const chunk = new Uint8Array(4096);
      const n = await conn.read(chunk);
      if (n === null) throw new Error('SMTP connection closed');
      buffer += dec.decode(chunk.subarray(0, n));
    }
    const i = buffer.indexOf('\r\n');
    const out = buffer.slice(0, i);
    buffer = buffer.slice(i + 2);
    return out;
  }
  return {
    write: async (text) => {
      await conn.write(enc.encode(text));
    },
    read: async () => {
      // Multi-line replies ("250-…") end with a line whose fourth character is a space.
      const lines = [await line()];
      while (lines[lines.length - 1][3] === '-') lines.push(await line());
      return lines.join('\n');
    },
    close: async () => conn.close(),
  };
}
