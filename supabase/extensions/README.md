# Extensions (Ch 43)

An extension is a small, separately built module switched on only for chosen institutions. Read
`docs/dev/EXTENSIONS.md` first (five layers, triage rule, rules and checklist). Layout:

```
supabase/extensions/<key>/
  migrations/      # own migrations (0001_name.sql …), applied after core by scripts/apply-extensions.sh
  functions/       # own Edge Functions (optional)
  uninstall.sql    # removes it completely; the core keeps working
  README.md        # what it does, events it emits / listens to, permissions it registers
  TEST_ONLY        # only for test extensions: never applied to staging or production
```

`example/` is the reference extension used by the tests.
