// Structured logger (0A.06-T4, Ch 3.7): one JSON line per event, always tagged with institution, user and request id,
// always redacted. Used by Edge Functions; the app has its own tiny wrapper (src/lib/logger.ts) over the same redaction.
import { redact } from './redact.ts';

export type LogContext = {
  function: string;
  request_id: string;
  institution_id?: string | null;
  user_id?: string | null;
};

export type Logger = {
  info(event: string, data?: Record<string, unknown>): void;
  warn(event: string, data?: Record<string, unknown>): void;
  error(event: string, data?: Record<string, unknown>): void;
  with(extra: Partial<LogContext>): Logger;
  /** Every secret read during this request is registered here and removed from all later log lines. */
  registerSecret(value: string): void;
};

export function createLogger(
  context: LogContext,
  sink: (line: string) => void = console.log,
  knownSecrets: Set<string> = new Set(),
): Logger {
  const write = (level: string, event: string, data?: Record<string, unknown>) =>
    sink(JSON.stringify({
      ts: new Date().toISOString(),
      level,
      event,
      function: context.function,
      request_id: context.request_id,
      institution_id: context.institution_id ?? null,
      user_id: context.user_id ?? null,
      ...(data ? { data: redact(data, 0, knownSecrets) } : {}),
    }));
  return {
    info: (event, data) => write('info', event, data),
    warn: (event, data) => write('warn', event, data),
    error: (event, data) => write('error', event, data),
    with: (extra) => createLogger({ ...context, ...extra }, sink, knownSecrets),
    registerSecret: (value) => {
      if (value) knownSecrets.add(value);
    },
  };
}
