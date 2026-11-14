// DNS lookup for the Custom HTTP adapter's SSRF check (Deno only): a gateway host must not resolve to an internal
// address (0B.13-T3).
export async function resolveHost(host: string): Promise<string[]> {
  if (/^[\d.]+$/.test(host) || host.includes(':')) return [host];
  const [v4, v6] = await Promise.all([
    Deno.resolveDns(host, 'A').catch(() => [] as string[]),
    Deno.resolveDns(host, 'AAAA').catch(() => [] as string[]),
  ]);
  return [...v4, ...v6];
}
