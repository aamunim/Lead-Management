// Hub worker core (0B.12-T3, T4, T8, T9): one round of the outbox worker. The database decides what is due, the order
// (OTP first, fair share), the gates, back-off, given_up and billing; this loop only sends each claimed message through
// its connections in order and reports what happened. Runtime-independent (Deno in the Edge Function, Node in tests).
import type { Adapter, ConnectionContext, OutboundMessage } from './adapters.ts';

export type ClaimedMessage = {
  institution_id: string; id: string; channel: 'sms' | 'email'; priority: string; recipient: string;
  payload: { body: string; subject?: string };
};
export type RouteConnection = {
  owner: 'institution' | 'platform'; id: string; provider: string; settings: Record<string, unknown>; sandbox: boolean; secret_fields: string[];
};
export type Route = { gate: string | null; connections: RouteConnection[] };

/** What the worker needs from the database (implemented with the service-role client, or a fake in tests). */
export interface HubStore {
  claim(worker: string, limit: number, lanes: number[]): Promise<ClaimedMessage[]>;
  route(institutionId: string, messageId: string): Promise<Route>;
  secret(institutionId: string | null, connectionId: string, field: string): Promise<string | null>;
  outcome(institutionId: string, owner: string, connectionId: string, ok: boolean, code: string | null, detail: string | null): Promise<void>;
  result(r: {
    institutionId: string; messageId: string; ok: boolean; connectionId: string | null; owner: string | null; provider: string | null;
    providerMessageId?: string | null; errorCode?: string | null; detail?: string | null; fallbackFrom?: string | null; sandbox?: boolean;
  }): Promise<string>;
}

export type RoundReport = { claimed: number; sent: number; failed: number; held: number; fallbacks: number };

async function contextFor(store: HubStore, msg: ClaimedMessage, c: RouteConnection): Promise<ConnectionContext> {
  const secrets: Record<string, string | null> = {};
  for (const f of c.secret_fields) secrets[f] = await store.secret(c.owner === 'institution' ? msg.institution_id : null, c.id, f);
  return { id: c.id, owner: c.owner, provider: c.provider, sandbox: c.sandbox, settings: c.settings, secrets };
}

/** Sends one claimed message: each connection in order until one succeeds; every failure is recorded on its connection. */
export async function sendOne(store: HubStore, adapters: Record<string, Adapter>, msg: ClaimedMessage, fetchFn: typeof fetch)
  : Promise<{ status: string; fallback: boolean }> {
  const route = await store.route(msg.institution_id, msg.id);
  if (route.gate) {
    const status = await store.result({ institutionId: msg.institution_id, messageId: msg.id, ok: false, connectionId: null, owner: null,
      provider: null, errorCode: route.gate });
    return { status, fallback: false };
  }
  let firstFailed: string | null = null;
  let last: { id: string; owner: string; provider: string; code: string; detail?: string } | null = null;
  const out: OutboundMessage = { id: msg.id, channel: msg.channel, recipient: msg.recipient, body: msg.payload.body, subject: msg.payload.subject };
  for (const c of route.connections) {
    const adapter = adapters[c.provider];
    if (!adapter || adapter.kind !== msg.channel) {
      await store.outcome(msg.institution_id, c.owner, c.id, false, 'adapter_error', 'no adapter for this provider yet');
      last = { id: c.id, owner: c.owner, provider: c.provider, code: 'adapter_error', detail: 'no adapter' };
      firstFailed ??= c.id;
      continue;
    }
    let res;
    try {
      res = await adapter.send(await contextFor(store, msg, c), out, fetchFn);
    } catch (e) {
      res = { ok: false as const, errorCode: 'adapter_error', detail: String((e as Error)?.message ?? e).slice(0, 200) };
    }
    if (res.ok) {
      await store.outcome(msg.institution_id, c.owner, c.id, true, null, null);
      const status = await store.result({ institutionId: msg.institution_id, messageId: msg.id, ok: true, connectionId: c.id, owner: c.owner,
        provider: c.provider, providerMessageId: res.providerMessageId, fallbackFrom: firstFailed, sandbox: c.sandbox });
      return { status, fallback: firstFailed !== null };
    }
    await store.outcome(msg.institution_id, c.owner, c.id, false, res.errorCode, res.detail ?? null);
    last = { id: c.id, owner: c.owner, provider: c.provider, code: res.errorCode, detail: res.detail };
    firstFailed ??= c.id;
  }
  const status = await store.result({ institutionId: msg.institution_id, messageId: msg.id, ok: false, connectionId: last?.id ?? null,
    owner: last?.owner ?? null, provider: last?.provider ?? null, errorCode: last?.code ?? 'no_connection', detail: last?.detail ?? null });
  return { status, fallback: false };
}

/**
 * One worker round: OTP lane first (never waits behind bulk), then the other lanes. Stops early when the time budget
 * is spent; what is left stays queued for the next wake-up (never re-claimed while sending).
 */
export async function runRound(store: HubStore, adapters: Record<string, Adapter>, opts: { worker: string; limit?: number; deadline?: number;
  fetchFn?: typeof fetch; now?: () => number }): Promise<RoundReport> {
  const now = opts.now ?? (() => Date.now());
  const report: RoundReport = { claimed: 0, sent: 0, failed: 0, held: 0, fallbacks: 0 };
  const fetchFn = opts.fetchFn ?? fetch;
  for (const lanes of [[1], [2, 3, 4]]) {
    if (opts.deadline && now() > opts.deadline) break;
    const batch = await store.claim(opts.worker, opts.limit ?? 50, lanes);
    report.claimed += batch.length;
    for (const msg of batch) {
      const r = await sendOne(store, adapters, msg, fetchFn);
      if (r.status === 'sent') report.sent += 1;
      else if (r.status === 'held') report.held += 1;
      else report.failed += 1;
      if (r.fallback) report.fallbacks += 1;
    }
  }
  return report;
}

/** Health round (0B.12-T9): each due connection's adapter health; results stored as last success / last error. */
export async function runHealth(store: HubStore & {
  healthDue(): Promise<(RouteConnection & { institution_id: string | null })[]>;
  healthRecord(owner: string, institutionId: string | null, connectionId: string, ok: boolean, code: string | null, detail: string | null): Promise<void>;
}, adapters: Record<string, Adapter>, fetchFn: typeof fetch = fetch): Promise<number> {
  const due = await store.healthDue();
  for (const c of due) {
    const adapter = adapters[c.provider];
    if (!adapter) continue;
    const secrets: Record<string, string | null> = {};
    for (const f of c.secret_fields) secrets[f] = await store.secret(c.institution_id, c.id, f);
    let res;
    try {
      res = await adapter.health({ id: c.id, owner: c.owner, provider: c.provider, sandbox: c.sandbox, settings: c.settings, secrets }, fetchFn);
    } catch (e) {
      res = { ok: false as const, errorCode: 'adapter_error', detail: String((e as Error)?.message ?? e).slice(0, 200) };
    }
    await store.healthRecord(c.owner, c.institution_id, c.id, res.ok, res.ok ? null : res.errorCode, res.ok ? null : res.detail ?? null);
  }
  return due.length;
}
