// Email domain check (0B.14-T4): SPF, DKIM and DMARC from the TXT records DNS returns. Pure functions, so they are
// unit-tested; the email-domain-check Edge Function does the lookups.
export type RecordCheck = { ok: boolean; found: string[]; problem: string | null };

const join = (r: string[] | string) => (Array.isArray(r) ? r.join('') : r);

/** Exactly one "v=spf1" record; for Resend it must include amazonses.com; "+all" is refused. */
export function checkSpf(txt: (string[] | string)[], provider: string | null): RecordCheck {
  const found = txt.map(join).filter((t) => /^v=spf1\b/i.test(t.trim()));
  if (found.length === 0) return { ok: false, found, problem: 'no SPF record' };
  if (found.length > 1) return { ok: false, found, problem: 'more than one SPF record (merge them into one)' };
  const spf = found[0].toLowerCase();
  if (/(^|\s)\+?all(\s|$)/.test(spf) && !/[~-]all/.test(spf)) return { ok: false, found, problem: '"+all" lets anyone send as you' };
  if (provider === 'resend' && !spf.includes('include:amazonses.com')) return { ok: false, found, problem: 'add include:amazonses.com' };
  return { ok: true, found, problem: null };
}

/** A DKIM key at <selector>._domainkey.<domain>: "p=" with a non-empty key. */
export function checkDkim(txt: (string[] | string)[]): RecordCheck {
  const found = txt.map(join).filter((t) => /(^|;)\s*p=/i.test(t));
  if (found.length === 0) return { ok: false, found, problem: 'no DKIM key at this name' };
  const key = found[0].match(/(?:^|;)\s*p=([^;]*)/i)?.[1]?.trim() ?? '';
  if (!key) return { ok: false, found, problem: 'the DKIM key is empty (revoked)' };
  if (!/^[A-Za-z0-9+/=]{100,}$/.test(key.replace(/\s+/g, ''))) return { ok: false, found, problem: 'the DKIM key does not look complete' };
  return { ok: true, found, problem: null };
}

/** DMARC at _dmarc.<domain>: "v=DMARC1" with a policy. Recommended, not required for "verified". */
export function checkDmarc(txt: (string[] | string)[]): RecordCheck {
  const found = txt.map(join).filter((t) => /^v=DMARC1\b/i.test(t.trim()));
  if (found.length === 0) return { ok: false, found, problem: 'no DMARC record (recommended)' };
  if (!/;\s*p=(none|quarantine|reject)\b/i.test(found[0])) return { ok: false, found, problem: 'DMARC needs a policy p=none, quarantine or reject' };
  return { ok: true, found, problem: null };
}

export async function checkDomain(domain: string, provider: string | null, selector: string,
  lookup: (name: string) => Promise<(string[] | string)[]>) {
  const safe = (name: string) => lookup(name).catch(() => []);
  const [root, dkim, dmarc] = await Promise.all([safe(domain), safe(`${selector}._domainkey.${domain}`), safe(`_dmarc.${domain}`)]);
  return { spf: checkSpf(root, provider), dkim: checkDkim(dkim), dmarc: checkDmarc(dmarc) };
}
