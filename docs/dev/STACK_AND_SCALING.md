# Stack, libraries and scaling notes

## Stack (Ch 3.2)

| Layer | Choice | Status |
|---|---|---|
| App | Expo SDK 58, React Native 0.88, expo-router (file routes in `src/app`), React Compiler, typed routes; Android + web | In place (0A.01) |
| Backend | Supabase: Postgres 17, RLS, RPC functions, pg_cron, pg_net, Storage, Realtime, Edge Functions (Deno) | Folder in place (`supabase/`); projects in 0A.02 |
| Native (Phase 3) | Kotlin Expo module `modules/call-log` | Not started (Ch 41) |
| Push | expo-notifications + FCM (`google-services.json`), sent from Postgres via pg_net to the Expo push API | 1.23 |
| Updates | EAS Update (OTA), channels `preview` / `production`; `runtimeVersion` pinned | 0A.02 |
| Web | `expo export --platform web` (single page app, `web.output = "single"`) | Builds (0A.01) |
| Files | Google Drive through an Apps Script web app, or Supabase Storage | Phase 2 (Ch 32) |
| AI | Anthropic Claude API and Google Gemini from Edge Functions | Phase 4 (Ch 40) |
| Outside services | All SMS, email, payment, AI, storage, push and domains through the integration hub | 0B.11+ (Ch 42) |

## Libraries added later (Ch 3.2) — install them only in the milestone that needs them

Always install with `npx expo install <package>` so versions match the SDK.

| Library | Used for | Milestone |
|---|---|---|
| xlsx | Excel import / export | 1.14 |
| expo-print | PDF receipts and prints | 2.07 |
| react-native-view-shot | Image capture of cards / receipts | 2.07 |
| MediaPipe face detection (web) | Passport photo and Photo Studio | 2.15, 5.05 |
| expo-audio | Voice notes | 1.09 |
| expo-notifications | Push | 1.23 |
| i18n library, Supabase JS client, test runners | Translations, backend calls, tests | 0A.02–0A.10 |

## Supabase limits to watch (Ch 3.9 #3, Ch 4)

- **Database connections** (pooler limits per plan) — keep RPCs short; no long transactions in request paths.
- **Edge Function invocations and duration** — hard limit about 150 s per call; keep outside calls ≤ 75 s and start new work only in the first 45 s; no SDK retries (lesson 3).
- **Storage size and egress** — compress images and PDFs; prefer Drive for large paper archives (Ch 32).
- **Realtime connections** — subscribe only where live updates are needed.
- **pg_cron jobs** — one scheduler loop over due institutions, not one job per institution (1.16).

Check these numbers against the current Supabase plan before each phase release, and record them in the release notes.

## Path for a very large institution (Ch 3.9 #3, Ch 4.8)

If one institution grows so large that it slows the others despite indexes and caching:

1. Measure with the benchmark (0A.20) to confirm it is size, not a missing index or a slow query.
2. Move that institution to **its own Supabase project** running the same migrations and code (possible because all logic is standard Postgres + SQL and every row carries `institution_id`).
3. Route its users by the institution's `project` setting in the Master Admin panel.

Keep Supabase-specific parts (auth hook, Edge Function glue) in a thin layer (**Proposed**, Ch 3.9 #4) so this stays possible.
