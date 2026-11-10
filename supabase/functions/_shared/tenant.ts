// Deno wrapper used by every Edge Function: `Deno.serve(withTenant('name', async (req, ctx) => ...))`.
import { createClient } from 'npm:@supabase/supabase-js@2';

import { toErrorInfo } from './errors.ts';
import { errorResponseBody, resolveTenant, type TenantContext } from './tenant-core.ts';

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });

export function withTenant(name: string, handler: (req: Request, ctx: TenantContext) => Promise<Response>) {
  return async (req: Request): Promise<Response> => {
    const requestId = req.headers.get('x-request-id') ?? crypto.randomUUID();
    const url = Deno.env.get('SUPABASE_URL') ?? '';
    const key = Deno.env.get('SUPABASE_ANON_KEY') ?? Deno.env.get('SUPABASE_PUBLISHABLE_KEY') ?? '';
    const result = await resolveTenant(req.headers.get('authorization'), async (token) => {
      // The client acts AS the caller (their JWT), so RLS and current_session() run with their rights.
      const client = createClient(url, key, { global: { headers: { Authorization: `Bearer ${token}` } } });
      return await client.rpc('current_session');
    }, name, requestId);
    if (!result.ok) return json(errorResponseBody(result.error, requestId), result.error.httpStatus);
    try {
      result.context.log.info('request.start', { method: req.method });
      const response = await handler(req, result.context);
      result.context.log.info('request.end', { status: response.status, ms: result.context.budget.elapsedMs() });
      return response;
    } catch (error) {
      const info = toErrorInfo(error);
      result.context.log.error('request.failed', { code: info.code, error });
      return json(errorResponseBody(info, requestId), info.httpStatus);
    }
  };
}

export { json };
