// API client wrapper (0A.14-T3). Pure: unit-tested in Node with a fake fetch (scripts/tests/shell.test.mjs).
// Wraps the fetch that the Supabase client uses for every call:
// - sends the app version (min_app_version check) and the idempotency key of writes (x-idempotency-key);
// - time limit per attempt, tuned for slow 3G; retries with back-off only when repeating is safe
//   (GET / HEAD, or a write that carries an idempotency key) and only for network errors, timeouts and 502/503/504;
// - "upgrade_required" → onUpgradeRequired() (the blocking screen);
// - "session_refresh_required" (access changed, R15) → refresh the session once and repeat with the new token;
// - reports x-settings-version so settings and labels refresh without a restart.

export type ApiOptions = {
  fetch: typeof fetch;
  appVersion: string;
  timeoutMs?: number;
  retries?: number;
  backoffMs?: (attempt: number) => number;
  sleep?: (ms: number) => Promise<void>;
  onUpgradeRequired?: () => void;
  refreshSession?: () => Promise<string | null>;
  reportSettingsVersion?: (header: string | null) => void;
};

export const SLOW_3G_TIMEOUT_MS = 20_000;
const RETRY_STATUS = new Set([502, 503, 504]);

function idempotencyKeyOf(body: unknown): string | null {
  if (typeof body !== 'string' || !body.includes('p_idempotency_key')) return null;
  try {
    const parsed = JSON.parse(body) as { p_idempotency_key?: unknown };
    return typeof parsed.p_idempotency_key === 'string' ? parsed.p_idempotency_key : null;
  } catch {
    return null;
  }
}

async function errorMessage(response: Response): Promise<string | null> {
  if (response.ok) return null;
  try {
    const body = (await response.clone().json()) as { message?: unknown };
    return typeof body.message === 'string' ? body.message : null;
  } catch {
    return null;
  }
}

export function createApiFetch(options: ApiOptions): typeof fetch {
  const timeoutMs = options.timeoutMs ?? SLOW_3G_TIMEOUT_MS;
  const retries = options.retries ?? 2;
  const backoff = options.backoffMs ?? ((attempt: number) => [1000, 3000, 6000][attempt] ?? 6000);
  const sleep = options.sleep ?? ((ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms)));

  const attempt = async (input: RequestInfo | URL, init: RequestInit, headers: Headers): Promise<Response> => {
    const controller = new AbortController();
    const outer = init.signal;
    const onAbort = () => controller.abort(outer?.reason);
    if (outer) {
      if (outer.aborted) controller.abort(outer.reason);
      else outer.addEventListener('abort', onAbort);
    }
    const timer = setTimeout(() => {
      const timeout = new Error('timeout'); // Hermes has no DOMException; the error contract maps this to "timeout"
      timeout.name = 'TimeoutError';
      controller.abort(timeout);
    }, timeoutMs);
    try {
      return await options.fetch(input, { ...init, headers, signal: controller.signal });
    } finally {
      clearTimeout(timer);
      outer?.removeEventListener('abort', onAbort);
    }
  };

  return async (input, init = {}) => {
    const headers = new Headers(init.headers);
    headers.set('x-app-version', options.appVersion);
    const key = idempotencyKeyOf(init.body);
    if (key) headers.set('x-idempotency-key', key);
    const method = (init.method ?? 'GET').toUpperCase();
    const safe = method === 'GET' || method === 'HEAD' || key !== null;

    let refreshed = false;
    for (let n = 0; ; n += 1) {
      let response: Response;
      try {
        response = await attempt(input, init, headers);
      } catch (error) {
        if (init.signal?.aborted) throw error; // the caller cancelled
        if (safe && n < retries) {
          await sleep(backoff(n));
          continue;
        }
        throw error;
      }
      options.reportSettingsVersion?.(response.headers.get('x-settings-version'));
      if (RETRY_STATUS.has(response.status) && safe && n < retries) {
        await sleep(backoff(n));
        continue;
      }
      const message = await errorMessage(response);
      if (message === 'upgrade_required') options.onUpgradeRequired?.();
      if (message === 'session_refresh_required' && !refreshed && options.refreshSession) {
        refreshed = true;
        const token = await options.refreshSession();
        if (token) {
          headers.set('Authorization', `Bearer ${token}`);
          n -= 1; // the repeat after a refresh is not a network retry
          continue;
        }
      }
      return response;
    }
  };
}
