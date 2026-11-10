# Lead Management Platform (working name)

A multi-institution lead and admission management platform for educational institutions in Bangladesh
(Android app + website, one codebase). "Lead Management Platform" is a working name; the final name is open (D21).

## Documents
- `docs/PLAN_BN.md` / `.docx` — the full product plan (Bangla, 53 chapters).
- `docs/DEVELOPMENT_ROADMAP.md` / `.docx` — the development roadmap (English, milestones in build order).
- `docs/dev/` — developer guide: architecture rules, scope, lessons, stack, environments and releases, progress.
- `docs/APP_FEATURES_FOR_REBUILD*` — earlier source documents (archive).

## Getting started
```bash
npm install
npm run check        # typecheck + config check
npm run web          # start the web app
npm run android      # start on an Android device / emulator
```

## Layout
```
src/app/              # routes (expo-router)
assets/               # icons and splash (placeholders until branding)
config/               # product-level config + JSON schemas (not per institution)
supabase/             # database migrations, Edge Functions, seeds, extensions
scripts/              # project scripts (config check, …)
docs/                 # plan, roadmap, developer guide
```
