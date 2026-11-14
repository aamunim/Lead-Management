# Transactional email (0B.14)

Plan: Ch 42.5, 42.10 row 6; Ch 5.6; Ch 25.4; decisions D1, D3, D4, D47 (Resend as the first API provider).

## Adapters

- **SMTP** (`smtp-1`): Gmail app password, cPanel mail.
  - Implicit TLS on **port 465 only**: Supabase Edge Functions block outgoing ports 25 and 587.
  - A small SMTP client (`_shared/hub/smtp.ts`) over a TLS socket (`smtp-deno.ts`).
  - Bangla names and subjects are encoded (RFC 2047); the body is UTF-8 base64.
  - Errors are mapped by side: 535 → auth (institution), 550 → recipient, 4xx → provider.
  - No status callbacks: bounces return to the sender's mailbox.
- **Resend** (`resend-1`, D47): HTTPS API with the connection's own key and an idempotency key per message.
  - Status callbacks (`email.delivered` / `bounced` / `complained`) arrive through the 0B.12 router.
  - They are verified with the connection's Svix secret (`whsec_…`), and timestamps older than 5 minutes are refused.
- Other providers (Brevo, SendGrid, Mailgun, Amazon SES) follow the same interface when needed.

## Sender identity

- **An institution's own connection:** its `from_name`, `from_email` and `reply_to` settings.
- **The platform default mail:** sends *as the institution*, never as another:
  - from: the institution's verified domain (`no-reply@<domain>`), or its own address `<slug>@<platform_mail_domain>`;
  - name: the institution's name;
  - reply-to: its Super Admin.
  - Without a sender address the platform mail is not used for that institution.
- **Platform mail limit:** `platform_mail_daily_limit` (Proposed 50) emails per institution per day.

## Domain check

- Panel → Institution → Integrations → Email → add a domain (Resend or SMTP). The three DNS records to add are shown step by step:
  - SPF (`include:amazonses.com` for Resend);
  - DKIM at `<selector>._domainkey.<domain>`;
  - DMARC at `_dmarc.<domain>` (recommended).
- One domain belongs to one institution, so reputation is never shared.
- **Verify** calls the Edge Function `email-domain-check`:
  - it asks the database first whether the caller may (Master Admin, two-step);
  - it reads DNS on the server (`_shared/hub/dns-check.ts`);
  - it stores the result with the service role. The client never sends the result.
  - SPF + DKIM make the domain verified.

## Reputation and pausing

- `email_reputation` counts sent, delivered, bounced and complained per institution and local day. A callback counts only for the institution of the message it matches, even on the shared platform mail.
- Pausing: at least 50 emails in 7 days with ≥ `email_bounce_pause_percent` (5 %) bounces or ≥ `email_complaint_pause_percent` (0.3 %) complaints pauses that institution's email.
  - Sign-in codes still go.
  - Master Admins are alerted.
  - Resume (a reason is required) is in the Email section. Everything is audited.

## Platform mail templates

- `platform_email_templates` (bn / en): `institution.approved`, `institution.suspended`, `invite.super_admin`, `otp.code`.
- Placeholders: `{{var}}`, and `{{label:key}}` / `{{label:key:plural}}` for the institution's own words (label system).
- Wired now:
  - the Super Admin invitation (0B.09) mails the invitee;
  - approval / suspension (0B.07) mails the Super Admins in their language.
- A mail that cannot be queued never blocks the action that caused it; it is audited instead.

## Deploying

- Functions: `hub-worker hub-webhook email-domain-check` (app-update workflow).
- Resend: one connection per institution or the platform gateway (Panel → Providers). Key and webhook secret in the connection's write-only keys. Resend's webhook URL is `…/functions/v1/hub-webhook/<connection id>`.
- Set `platform_mail_domain` once the platform's own sending domain is verified.

## Tests

- SQL `supabase/tests/0B14_email_test.sql` (16 checks).
- Unit `scripts/tests/email-adapters.test.mjs` (Resend, Svix, SMTP conversation, DNS checker).
- UI `scripts/ui/email.web.test.mjs`.
- Leak fixture for `email_domains`.
