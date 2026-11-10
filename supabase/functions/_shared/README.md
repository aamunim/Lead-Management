# Shared code for Edge Functions

Code used by more than one Edge Function lives here (Deno, TypeScript).

**Thin platform layer (Proposed, Ch 3.9 #4):** keep Supabase-specific parts (auth hook glue, Edge Function
request/response handling, Vault access) in small adapter modules in this folder, so that business logic stays
in plain TypeScript and SQL that would also run on another Postgres host.

Rules that apply to every function (see `docs/dev/ARCHITECTURE_RULES.md`):
- Never trust an institution id from the request; take it from the session claim / profile.
- Check permissions with `can()` before any write.
- Anything sent outside goes through the outbox (attempts, back-off, "given up", idempotency key).
- Never log secrets or full personal data; tag logs with institution and user id.
- Edge Functions have a 150 s limit: keep each outside call ≤ 75 s and start new work only in the first 45 s.
