// Redaction for logs (0A.06-T4, Ch 3.7): never log secrets or full personal data.
// Shared by Edge Functions (Deno) and the app (imported with the .ts extension). No dependencies.

const SECRET_KEY = /(pass(word)?|secret|token|api[_-]?key|authorization|cookie|private[_-]?key|service[_-]?role|otp|pin)$/i;
const NATIONAL_ID_KEY = /(^|_)(nid|national_?id|birth_?cert(ificate)?(_no)?)$/i;

const JWT = /\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b/g;
const PROVIDER_KEY = /\b(sb_secret_[A-Za-z0-9_-]{8,}|sb_publishable_[A-Za-z0-9_-]{8,}|sk-[A-Za-z0-9_-]{16,}|sk_(live|test)_[A-Za-z0-9]{8,}|AIza[0-9A-Za-z_-]{20,})\b/g;
const BEARER = /\bBearer\s+[A-Za-z0-9._~+/=-]{8,}/gi;
// Bangladesh mobile numbers: 01XXXXXXXXX, 8801XXXXXXXXX, +8801XXXXXXXXX. With the country code the leading 0 is
// dropped (+880 1812-345678), so the operator part is "1[3-9]" after either "0" or "880".
const BD_PHONE = /(?<![0-9])(?:\+?880|0)(1[3-9])(\d{5})(\d{3})(?![0-9])/g;

/** Masks a phone like the app does for counsellors (D24): 017•••••234. */
export function maskPhone(text: string): string {
  return text.replace(BD_PHONE, (_m, operator: string, _middle: string, last: string) => `0${operator}•••••${last}`);
}

export function redactString(text: string): string {
  return maskPhone(
    text.replace(BEARER, 'Bearer [redacted]').replace(JWT, '[redacted-jwt]').replace(PROVIDER_KEY, '[redacted-key]'),
  );
}

/** Deep copy with secrets removed and personal numbers masked. Safe to pass anything (errors, requests, rows). */
export function redact(value: unknown, depth = 0): unknown {
  if (depth > 8) return '[truncated]';
  if (typeof value === 'string') return redactString(value);
  if (value === null || typeof value !== 'object') return value;
  if (value instanceof Error) {
    return { name: value.name, message: redactString(value.message) };
  }
  if (Array.isArray(value)) return value.map((item) => redact(item, depth + 1));
  const out: Record<string, unknown> = {};
  for (const [key, item] of Object.entries(value as Record<string, unknown>)) {
    if (SECRET_KEY.test(key)) out[key] = '[redacted]';
    else if (NATIONAL_ID_KEY.test(key)) out[key] = '[redacted-id]';
    else out[key] = redact(item, depth + 1);
  }
  return out;
}
