# Environments, secrets and releases (milestone 0A.02)

## Environments

| Environment | Supabase project | EAS build profile / OTA channel | Website | Used for |
|---|---|---|---|---|
| development | local (`supabase start`) or a dev project | `development` (dev client APK) / channel `development` | `npm run web` | Day-to-day development |
| staging | staging project | `preview` (APK) / channel `preview` | staging site | Testing with seed data, pilot institutions' first look |
| production | production project | `production` (AAB) and `production-apk` (APK) / channel `production` | production site | Real institutions |

`APP_ENV` (set by the EAS profile or the workflow) tells the app which environment it runs in.
The Supabase URL and anon key per environment are added in 0A.03 (public values, read from `extra`).

## Secrets (never in the repository, never in chat)

Create two GitHub **environments**, `staging` and `production`, and add these secrets to each.
Protect `production` with required reviewers.

| Secret | Used by | Where to get it |
|---|---|---|
| `SUPABASE_ACCESS_TOKEN` | app-update | Supabase account → Access tokens |
| `SUPABASE_PROJECT_REF` | app-update | Supabase project settings |
| `SUPABASE_DB_PASSWORD` | app-update | Set when the project is created |
| `EXPO_TOKEN` | app-update, build-android | Expo account → Access tokens |
| `GOOGLE_SERVICES_JSON_BASE64` | build-android | Firebase project → Android app → `google-services.json`, then `base64 -w0 google-services.json` |
| `FTP_HOST`, `FTP_USER`, `FTP_PASSWORD`, `FTP_REMOTE_DIR` | deploy-web | Hosting control panel |
| Android keystore | build-android (EAS credentials) | Managed by EAS credentials; back it up offline |

Later secrets (Apps Script secret, provider keys) are **not** GitHub secrets: institution and provider keys are
entered in the app / Master Admin panel and stored in the Supabase Vault (0A.07, 0B.11).

## Workflows

| Workflow | Trigger | What it does |
|---|---|---|
| `ci.yml` | every PR and push to `main` | Typecheck, config check, unit tests, web build; migrations applied to a fresh database; secret scan and "migration PR must declare a database deploy" (both approved, D27). Later milestones add the schema lint, DEFINER audit, RPC-as-role tests, leak test, role matrix, i18n lint and screenshot tests. |
| `app-update.yml` | manual | Database + app / App only / Database only to staging or production: `supabase db push`, optional `functions deploy`, then `eas update` on the channel. |
| `build-android.yml` | manual | Local EAS build on the runner for a chosen profile; writes `google-services.json` from the secret; fails if Firebase is missing from the config or the built package; uploads the APK / AAB as an artifact. Brand inputs prepare branded apps (D12, Phase 5). |
| `deploy-web.yml` | manual | Web export and FTPS upload: new assets first, `index.html` last. **Proposed:** move to atomic hosting with automatic custom-domain SSL in 1B. |

Set `checks`, `database` and `secret-scan` as **required status checks** on `main` (repository settings → branch protection).

## Release rules

1. **Choose the right deploy type.** A PR that changes migrations must tick "Database"; choosing "App only" when the database changed breaks the app.
2. **Staging first.** Run migrations on staging with seed data before production; check the app on staging.
3. **OTA cannot ship native changes.** If native code or `runtimeVersion` changed, make a store build. A wrong `runtimeVersion` makes old builds crash on new JS.
4. **Backward-compatible RPCs** (lesson 7); raise the minimum app version only when unavoidable (1.18).
5. **Staged rollout:** per-institution feature flags and beta institutions come in 1.18; until then release to staging first.
6. **No big releases in admission peak weeks.** Small fixes only, through a hotfix (flag off or a small OTA).
7. **Every user-visible change has a "What's new" entry in English and Bangla** (PR template).
8. **Language review before each release (0A.10-T6, Ch 13.8 #8).** If `src/i18n/locales/` changed since the last release, the owner or a native Bangla reader reads the changed Bangla texts (`git diff <last-release-tag> -- src/i18n/locales/bn`) on a phone, checks them against `docs/dev/GLOSSARY.md`, and confirms in the release PR. A release does not go to production without that confirmation.

## Release calendar

- Expo SDK / React Native upgrades change `runtimeVersion` and need a new store build: schedule them at fixed times of the year, **never during admission season**.
- Run a load test before each admission season (Ch 44, 48).

## Runbook: a secret has leaked

1. **Rotate it at once** at the provider (Supabase, Expo, Firebase, hosting, payment or SMS provider).
2. Update the GitHub environment secret (or the Vault entry for provider keys).
3. Remove it from the repository history if it was committed, and force everyone to re-clone.
4. Check provider logs for use of the old key; tell affected institutions if their data or money could be affected.
5. Write an incident entry in `docs/dev/LESSONS.md`.
