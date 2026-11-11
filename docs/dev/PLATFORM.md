# Master Admin panel and platform roles (0B.02)

Roadmap 0B.02; plan Ch 5.1–5.3, 5.14, 5.17; Ch 11.15; Ch 10.2; Ch 1.5, 1.7, 1.8. Decisions D4, D21, D37.
Migration `20261112100000_platform.sql`; seed `supabase/seeds/0B02_platform.sql`; tests
`supabase/tests/0B02_platform_test.sql`, `scripts/ui/panel.web.test.mjs`; CLI `scripts/platform/create-master-admin.mjs`.

## Separate from institutions

- Platform users are rows of `platform_members` (the roadmap's `platform_users`): role `master_admin`, `support`,
  `billing` or `developer`, `status`, personal `extra_permissions`. Institution roles live in `roles` /
  `role_assignments`. A platform permission (kind `platform`) can never be granted to an institution role (foreign key
  on kind + RPC check), and an institution Super Admin's `*` never covers platform permissions. Tested both ways.
- Platform checks: `app.is_platform_admin()` and `app.is_platform(permission)`. **Both need a two-step (aal2)
  session**: a platform user signed in with only a password has no platform right at all. The panel refuses earlier
  with `mfa_required`.
- Platform tables (`platform_members`, `platform_role_permissions`, `platform_invites`, `platform_login_devices`,
  `platform_alerts`, `platform_audit_log`) are never readable by institution users.

## Permission keys

Keys are two-part (`module.action`), so the roadmap's names map to:

| Roadmap | Key | Master Admin | Support | Billing | Developer |
|---|---|---|---|---|---|
| panel read access | `platform.view` | ✓ | ✓ | ✓ | |
| `platform.institutions.*` | `platform.institutions` | ✓ | | | |
| `platform.support.enter` | `platform.support_access` | ✓ | personal extra right | | |
| `platform.billing.*` | `platform.billing` | ✓ | | ✓ | |
| `platform.integrations.manage` | `platform.integrations` | ✓ | | | |
| `platform.profiles.manage` | `platform.profiles` | ✓ | | | |
| `platform.users.manage` | `platform.users` | ✓ | | | |
| `platform.developer.view` | `platform.developer` | ✓ | | | ✓ |
| — | `platform.product_settings`, `platform.extensions`, `platform.labels_lock` | ✓ | | | |

The rights per role (least privilege, 0B.02-T5) were approved by the owner (D43);
they live in `platform_role_permissions` (data, not code).

## Sign-in, devices and alerts

- `/panel/sign-in` is its own page (not the staff sign-in). Password, then always the second step: the code from an
  authenticator app (TOTP, Supabase Auth MFA), or the first time setting one up (the key is shown; the person adds it
  to Google / Microsoft Authenticator). Hosted Supabase: TOTP must be enabled in Authentication → MFA (on by default).
- After the second step the panel calls `platform_session_start(device id)`: it accepts a pending invite, records the
  device (`platform_login_devices`), and for a device the person never used before (not their first) writes a
  `new_device` alert to the person and to every Master Admin (`platform_alerts`, shown on the dashboard; email when
  the email adapters exist, 0B.14). The device id is random per browser / phone (`panel_device_id`).

## Platform users

`/panel/users` (`platform.users`): list (role, last seen, second step set up or not), invite by email (one person per
account; the invite becomes a membership at that person's first two-step panel sign-in — they need an account; until
the email adapters exist new accounts come from the CLI), change role, setup rights, deactivate (ends their sessions).
Guards: only a Master Admin makes or changes a Master Admin; nobody changes themselves; the last Master Admin stays.

First Master Admin, command line only:
`DB_URL=… ADMIN_EMAIL=… ADMIN_PASSWORD=… node scripts/platform/create-master-admin.mjs`.
On staging / production without a local setup: put the password in the environment secret `MASTER_ADMIN_PASSWORD`
(14+ characters), then Actions → **create-master-admin** → choose the environment and type the email. The person
opens the panel from "Platform staff" on the app's sign-in page (or `/panel/sign-in` on the web) and sets up an
authenticator app at the first sign-in.

## Audit

Every platform write goes through `app.platform_audit(action, institution, target, before, after, reason)`: actor,
optional institution, before / after with secret-looking keys redacted at any depth (`app.redact_secrets`), IP and
user agent from the request. The table is append-only. The institution-facing view of support visits comes in 0B.09.

## Panel shell

Menu (Ch 5.3, approved, D43): Dashboard, Institutions (0B.07), Groups (1.19), Profiles and packs (built in 0B.03, see `PROFILES.md`), Providers
(0B.11), Announcements (1.33), Requests (0B.07), Developer inbox (1.18), Platform users. Each item needs its right;
pages built later say when they arrive. Every institution will get the tabs Overview, Messaging, Notifications,
Payments, Integrations, Domain, Plan and billing, Words, Audit (filled by later milestones).

## Product name (0B.02-T9, D37)

The product name lives in one product setting, `app_name` (default "Leadora"), read with `product_config()` by the
panel; the app's store name, Android package and deep-link scheme are in `config/product.json` / `app.json`.
**Proposed naming criteria** for the final name: neutral (not tied to education), short, easy to say and write in
Bangla and English, `.com` / `.com.bd` and the Play Store name free, no trademark conflict. **The name, Android package
and deep-link scheme must be fixed before the first store build** (Ch 1.7 row 3): changing the package later means a
new app in the store.
