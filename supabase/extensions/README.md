# Extensions (Ch 43)

An extension is a small, separately built module switched on only for chosen institutions. Layout:

```
supabase/extensions/<ext_name>/
  migrations/      # own migrations, applied after core
  functions/       # own Edge Functions (optional)
  README.md        # what it does, events it listens to, permissions it registers
```

Rules:
- Own Postgres schema: `ext_<name>`. Never add columns to core tables.
- Never write to core tables directly; use the versioned core RPCs and listen to `domain_events`.
- Every table has `institution_id` and RLS, and is covered by the cross-tenant leak test.
- Register its permissions in the permission registry (Ch 11) and its words as labels (Ch 8).
- Switching an extension off, or removing it, must never break the core app.
