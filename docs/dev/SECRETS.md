# Per-institution secrets (0A.07)

API keys, SMTP passwords, payment merchant keys and similar values of an institution are **never** in code, chat,
logs, error messages or screens. They live encrypted in **Supabase Vault**; the app sees only a hint such as `sk-l…9911`.

## Model

| Part | What it does |
|---|---|
| `public.institution_secrets` | Metadata only: `secret_ref` (e.g. `sms.primary.api_key`), `hint`, `valid_from`, `created_by`, `rotated_at`, `revoked_at`, and `vault_id` (not readable by app users). RLS: the active institution only. |
| `public.secret_set(ref, value, valid_from?, institution_id?)` | **Write-only.** Stores the value in Vault and returns `{ref, hint, valid_from}`. A future `valid_from` is a **rotation**: the current value keeps working until then. `institution_id` is accepted only from the platform Master Admin (Master Admin panel, D4); everyone else writes for the active institution. |
| `public.secret_revoke(ref, institution_id?)` | Destroys the Vault values of every version, keeps who / when for the audit trail. |
| `public.secret_read_for_service(institution_id, ref)` | The value in force (latest started `valid_from`, not revoked). **Executable only by `service_role`** (Edge Functions). |
| `public.purge_institution_secrets(institution_id)` | Closing an institution (0B.07): destroys all its secrets. `service_role` only. |

## Who may write

Until roles and permissions exist (0A.16 / 0A.17), **only the platform Master Admin** may write secrets (fail-closed;
D4 says the Master Admin sets SMS and email keys). The `integration.manage` permission will later let chosen institution
roles write keys that belong to them (e.g. their own AI key).

## In Edge Functions

```ts
Deno.serve(withTenant('sms-send', async (req, ctx) => {
  const key = await ctx.secret!('sms.primary.api_key'); // the ACTIVE institution's key only
  // ... call the provider; any log line or error that contains `key` is redacted automatically
}));
```

`ctx.secret` reads through the service role, only for the institution resolved from the caller's session, and
registers the value with the request logger: every later log line has it replaced by `[redacted-secret]`, even when a
provider echoes the key inside its error message. Error responses carry only `code`, `message_key`, `action` and
`request_id`.

## In the app

`src/components/SecretField.tsx` shows the hint and a **Replace** button (password-style input, optional "active from"
date for rotation); `src/lib/secrets.ts` has `setSecret`, `revokeSecret`, `listSecretHints`. Values are never fetched.

## Guarantees and the tests that prove them

| Guarantee | Test |
|---|---|
| Staff cannot write before permissions exist; the Master Admin can | `supabase/tests/0A07_secrets_test.sql`, `scripts/e2e/secrets.e2e.mjs` |
| `secret_set` returns only the hint; the value is encrypted in Vault | same |
| App users can read neither the value, the Vault reference, Vault itself nor the service reader | same |
| Another institution sees none of the metadata | same + leak test (A's secret value is a leak marker) |
| Rotation, revoke and purge behave as described | `0A07_secrets_test.sql` |
| No secret in logs or error bodies, even inside provider errors | `scripts/tests/edge-shared.test.mjs` |
| A service-only function can never be granted to app users | schema lint rule `definer_service_only` |
