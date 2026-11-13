# Institution setup wizard and self sign-up (0B.09)

Plan: Ch 6.1–6.4, 6.8, 6.9 rows 1, 3, 6; Ch 10.6 (first Super Admin); decisions D8, D19, D20, D25.

## The flow

1. **Public, before sign-in** (`/sign-up`, also "Set up a new institution" on the sign-in page):
   - `signup_status()`: is self sign-up open (product setting `self_signup_open`).
   - `list_open_packs()` (0B.03): the open industries and their published types. While only education is open the industry
     step is hidden and the wizard starts at the types (D20).
   - `signup_preview(profiles, exclude, label_choices)`: what the chosen types set up, per area (the 0B.04 preview with no
     institution). Product data only — **no institution is ever listed publicly** (Ch 10.10 row 5).
2. **Steps** (only the essentials, Ch 6.9 row 3): types (one or more; mixed allowed) → information (name; short name,
   EIIN, College Code, address, phone optional; logo and colours later) → Super Admin (name, mobile, email, password, or
   "I already have a login", D25; a signed-in person simply continues with their login) → preview with parts to leave out
   (the roles part always stays: it makes the Super Admin role) → create.
3. **Create:** the app makes the login with Supabase Auth (`signUp`, or `signInWithPassword` for an existing login), then
   calls `institution_signup(payload, request_key)`:
   - rate limits (Proposed): `signup_limit_per_ip_hour` (5) per network address, `signup_limit_per_person_day` (3) per
     login and per phone number;
   - creates the institution in `pending` (waiting for approval) with `industry = education`, applies the types with
     `app.apply_profiles` (0B.04), makes the person an active member with the Super Admin role and points their next
     token at it (`profiles.last_active_institution_id`);
   - records the sign-up in `institution_signups` (IP, email, phone; platform-only table) and emits
     `institution.signed_up`; the same `request_key` twice returns the same institution.
   - With email confirmation switched on, the wizard shows "Confirm your email" and finishes after the person confirms.
4. **After:** "Waiting for approval" with "Continue setup". A pending institution can be set up (writes are allowed) but
   cannot send messages; it appears in the panel's approval queue with the duplicate (EIIN / code / name + phone) and
   trial-abuse flags of 0B.07. Approval moves it to `trial`.

## No messaging before approval

`app.institution_can_message(institution)` is true only for `trial` and `active`. **The hub outbox gate (0B.12) must call
it for every SMS / bulk send.** `institution_status()` returns it as `can_message` for the app.

## Master Admin "Create institution" (Proposed)

Panel → Institutions → Create institution (`platform.institutions_create`, aal2): the same wizard without a password.
`platform_institution_create(payload, request_key)` creates the institution, starts the trial at once (approved by the
creator), and invites the Super Admin by email (`institution_invites`):

- an email that already has a confirmed login is attached at once (D25);
- otherwise the invitation becomes a membership when that email is confirmed for the first time (trigger
  `on_auth_user_confirmed` on `auth.users`; an unconfirmed email never joins).

The Overview tab lists the invitations. Sending the invitation email itself is a message and comes with the hub
(0B.12); until then the Master Admin tells the person to sign up with that email.

## CAPTCHA (Proposed)

Supabase Auth checks a CAPTCHA token on `signUp` / `signInWithPassword` when `[auth.captcha]` is switched on for the
project (hCaptcha or Cloudflare Turnstile; the secret lives in the Supabase project settings, never in the repository).
The app side (a widget passing `captchaToken`) is added when the owner picks the provider; `institution_signups.captcha_score`
is kept for it. Until then the rate limits and the approval queue are the protection.

## Owner decisions still open (Proposed)

- Self sign-up open by default, with approval (Ch 6.2).
- Rate limits: 5 per address per hour, 3 per login / phone per day.
- CAPTCHA provider.
- Master Admin creation starts the trial at once.

## Tests

- SQL `supabase/tests/0B09_signup_test.sql`: public data names no institution; pending + types + Super Admin; repeat
  tap; continue setup while pending; no messaging before approval; sees only itself; duplicate EIIN in the queue; D25;
  rate limits; closed sign-up; Master Admin creation with invite (unconfirmed email does not join; existing login attached).
- UI `scripts/ui/signup.web.test.mjs`: the full wizard in English (light) and Bangla (dark) with every step
  screenshotted, landing on Home with the "waiting for approval" banner; the panel creation with an invitation.
