// "Verify" button (0B.14-T4): POST {institution_id, domain} with the Master Admin's session. The caller's right is
// checked first (as the caller, platform.integrations + two-step); then DNS is read and the result stored with the
// service role — the result never comes from the client.
import { createClient } from 'npm:@supabase/supabase-js@2';

import { checkDomain } from '../_shared/hub/dns-check.ts';

const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': 'authorization, content-type, apikey, x-client-info' };

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: cors });
  const url = Deno.env.get('SUPABASE_URL') ?? '';
  const anon = Deno.env.get('SUPABASE_ANON_KEY') ?? Deno.env.get('SUPABASE_PUBLISHABLE_KEY') ?? '';
  const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? Deno.env.get('SUPABASE_SECRET_KEY') ?? '';
  const body = await req.json().catch(() => ({})) as { institution_id?: string; domain?: string };
  const caller = createClient(url, anon, { global: { headers: { Authorization: req.headers.get('authorization') ?? '' } } });
  const { data: allowed, error } = await caller.rpc('platform_email_domain_check_allowed', { p_institution: body.institution_id, p_domain: body.domain });
  if (error || !allowed) return new Response(JSON.stringify({ error: 'permission_denied' }), { status: 403, headers: { ...cors, 'content-type': 'application/json' } });
  const d = allowed as { domain: string; provider: string | null; dkim_selector: string };
  const result = await checkDomain(d.domain, d.provider, d.dkim_selector, (name) => Deno.resolveDns(name, 'TXT'));
  const admin = createClient(url, service, { auth: { persistSession: false } });
  const { data: status } = await admin.rpc('hub_email_domain_result', { p_institution: body.institution_id, p_domain: d.domain, p_result: result });
  return new Response(JSON.stringify({ status, result }), { headers: { ...cors, 'content-type': 'application/json' } });
});
