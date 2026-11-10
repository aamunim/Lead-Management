// Time budget for Edge Functions (Ch 3.9 #3, lesson 3): the platform stops a function at about 150 s.
// Each outside call gets at most 75 s, and new work may start only in the first 45 s of the request.

export const LIMITS = { functionMs: 150_000, callMs: 75_000, startNewWorkMs: 45_000 } as const;

export class Budget {
  private readonly startedAt: number;
  private readonly now: () => number;
  constructor(now: () => number = Date.now) {
    this.now = now;
    this.startedAt = now();
  }
  elapsedMs(): number {
    return this.now() - this.startedAt;
  }
  /** True while new work (another queue item, another provider call) may still be started. */
  canStartNewWork(): boolean {
    return this.elapsedMs() < LIMITS.startNewWorkMs;
  }
  /** Time allowed for the next outside call: min(75 s, what is left before the hard limit with a safety margin). */
  nextCallMs(): number {
    return Math.max(0, Math.min(LIMITS.callMs, LIMITS.functionMs - 10_000 - this.elapsedMs()));
  }
}

/** Rejects with a 'timeout' error when the promise takes longer than ms. */
export function withTimeout<T>(promise: Promise<T>, ms: number): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_resolve, reject) => {
    timer = setTimeout(() => reject(new Error('timeout')), ms);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}
