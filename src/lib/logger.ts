// Client logger (0A.06-T4): every log / error line is tagged with the active institution and user and redacted with
// the same rules as the server. Crash collection, the error dashboard and alerts arrive in 1.18; until then lines go
// to the console (and to any sink registered with setLogSink).
import { redact } from '../../supabase/functions/_shared/redact.ts';
import { currentClaims } from './session';

type Level = 'info' | 'warn' | 'error';
type Sink = (line: Record<string, unknown>) => void;

let sink: Sink = (line) => {
  const fn = line.level === 'error' ? console.error : line.level === 'warn' ? console.warn : console.log;
  fn(JSON.stringify(line));
};

export function setLogSink(next: Sink): void {
  sink = next;
}

export async function log(level: Level, event: string, data?: Record<string, unknown>): Promise<void> {
  const claims = await currentClaims().catch(() => ({}) as Awaited<ReturnType<typeof currentClaims>>);
  sink({
    // i18n-exempt: device time on purpose (when it happened on this phone); the server adds its own time
    ts: new Date().toISOString(),
    level,
    event,
    institution_id: claims.active_institution_id ?? null,
    user_id: claims.sub ?? null,
    ...(data ? { data: redact(data) } : {}),
  });
}

export const logger = {
  info: (event: string, data?: Record<string, unknown>) => log('info', event, data),
  warn: (event: string, data?: Record<string, unknown>) => log('warn', event, data),
  error: (event: string, data?: Record<string, unknown>) => log('error', event, data),
};
