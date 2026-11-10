# App shell, session plumbing and phone security (0A.14)

Plan: Ch 47.6, 47.7, 47.9, 47.10, Ch 4.3, 4.5, 3.4, 13.2. Decisions D12, D13, D25.

## Routes

| Path | Who | What |
|---|---|---|
| `/` | everyone | redirects to `/home` (signed in) or `/sign-in` |
| `/sign-in` | signed out only (`Stack.Protected`) | email + password (OTP, Google, invitations come in 0B, Ch 10); neutral product name in the top bar |
| `(app)/(tabs)/home`, `more`, `settings` | signed in only | placeholders under the top bar (institution name + mark, brand stripe, profile button) and bottom tabs |
| `(app)/profile` | signed in only | language, appearance, app lock, sign out here / on all other devices |
| `/language`, `/appearance`, `/terminology`, `/samples`, `/dev/*`, `/dev-sign-in` | everyone | settings-like pages and developer tools (dev tools hidden in production) |

Over everything (root layout): the offline strip, the "Please update the app" screen, and the lock screen.

## Caches (0A.14-T2)

Every cached piece of user or institution data is stored under `cacheKey({ userId, institutionId }, …)` → `c|user|institution|…`
(`src/lib/cache-core.ts`, wired in `src/lib/cache.ts`). In-memory stores register `onCacheClear()`.

| Event | What is wiped |
|---|---|
| Sign-out (button, idle, too many wrong PINs) | every `c|` key, the session, the app lock PIN; screens drop their data |
| Institution switch | every key of the previous institution; settings, labels and the top bar reload for the new one |
| Access changed (`session_refresh_required`) | that institution's keys; reload |
| A different person signs in on the device | every key of the previous person |

Device preferences (language before sign-in, appearance, product locale defaults) are not under `c|` and stay.
**Lists in 1A/1B** (stale-while-revalidate caches) must use `cacheKey` too; `useKeepInPlace(listKey)` remembers a
list's scroll position the same way.

## API wrapper (0A.14-T3, `src/lib/api-core.ts`)

All Supabase calls pass through it: `x-app-version`, `x-idempotency-key` (taken from `p_idempotency_key`; use
`useSubmit()` for writes), 20 s per attempt (slow 3G), up to 2 retries with back-off **only** when repeating is safe
(reads, or writes with an idempotency key) and only for network errors, timeouts and 502/503/504.
`upgrade_required` → blocking screen; `session_refresh_required` → one session refresh and a repeat with the new
token; `x-settings-version` → settings and labels refresh.

## Navigation (0A.14-T5)

- Android Back: sheets and dialogs (Modals) close first; tabs go back to Home; on Home it asks "Leave the app?".
- Deep links: `…?institution=<id>` switches to that institution first (the server checks membership), then opens
  the target (`useInstitutionDeepLink`). The switcher UI comes in 1B.
- Every screen inside the app has the top bar; secondary screens (Profile) show a back arrow.

## Phone security (0A.14-T7, Ch 47.10)

- **App lock** (phone app only): 4–6 digit PIN, kept as a salted SHA-256 hash in the phone's secure store (never on
  the server), plus fingerprint when the phone has one. Locks on start and after 30 s in the background; five wrong
  PINs sign out. Turned off and forgotten on sign-out.
- **Idle sign-out:** institution setting `idle_signout_minutes` (0 = off; key name to confirm in 0B); any touch or
  key press counts as activity; the sign-in screen says why.
- **Sign out of all other devices:** Profile → revokes every other session of the account.

## Tests

`scripts/tests/shell.test.mjs` (cache rules, API wrapper with a fake fetch), `scripts/ui/shell.web.test.mjs`
(sign-in, sign-out and switch leave nothing behind, deep link, language/theme without reload, offline strip, idle
sign-out with a fake clock, upgrade screen, 320 / 768 / 1280 px, weird labels in bn/en × light/dark),
`.maestro/shell-security.yaml` (app lock, Back, sign-out on a phone). Test phones: `TEST_DEVICES.md`.
