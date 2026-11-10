// Sample Edge Function (0A.06-T3): returns the caller's active institution, resolved by the shared middleware.
import { json, withTenant } from '../_shared/tenant.ts';

Deno.serve(withTenant('whoami', async (_req, ctx) => {
  ctx.log.info('whoami.answered');
  return json({ user_id: ctx.userId, institution_id: ctx.institutionId, request_id: ctx.requestId });
}));
