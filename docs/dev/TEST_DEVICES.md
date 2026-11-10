# Test phones and the manual pre-release pass (0A.14-T9, Ch 47.11, 47.12 #8)

Automated tests (unit, SQL, e2e, Playwright on the web, Maestro flows) catch most problems. Before every store
release, the owner or a tester also does one **manual pass on real phones**, because low-end phones, small screens
and large fonts break things that emulators hide.

## The three test phones (to buy / borrow; owner to confirm models)

| Role | What it must be | Why |
|---|---|---|
| Low-end | Android, 2–3 GB RAM, Android 10–12, slow storage (e.g. a Symphony / Walton / older Samsung A0x) | Most callers use such phones; lists, start-up time and memory |
| Mid-range | Android, 4–6 GB RAM, recent Android | The common good case; fingerprint for app lock |
| Small screen | 5–5.5 inch, 720 px wide or less | Keyboard covering fields, long Bangla words, tab bar |

Plus one browser check on a laptop (web app) at 1280 px and a tablet or tablet emulator in landscape.

## Manual pass (about 20 minutes per phone)

1. **Large font on** (Android Settings → Display → Font size: largest) and **Bangla** UI; go through: sign-in, Home,
   More, Profile, the component gallery (developer builds) and the newest screens of the release. Nothing cut,
   nothing overlapping, all buttons reachable.
2. **Dark mode** on, then off again from Profile — the app must not restart.
3. **Keyboard:** open the long form (gallery → Forms); type in the last field; Save and the field stay visible.
4. **Slow network:** Developer options → network throttling or a weak signal; screens show skeletons, errors offer
   Retry, nothing hangs forever; switch to airplane mode → "No internet" strip; back → "✓ Back online".
5. **Security:** turn on app lock; send the app to the background > 30 s; it locks; unlock with PIN and with
   fingerprint; sign out → sign in again: no old data, no lock.
6. **Back button:** sheets and dialogs close first; on Home it asks before leaving.
7. Note the phone, Android version, app version and any problem in the release PR.

The Maestro flows in `.maestro/` automate parts 3, 5 and 6 on a connected phone or emulator:
`maestro test .maestro/` (needs a preview build; see `ENVIRONMENTS_AND_RELEASES.md`).
