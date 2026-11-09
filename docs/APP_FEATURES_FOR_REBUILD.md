# Admission Management App: full feature brief for a new multi-institution app

> **What this is.** A brief for an AI agent or developer who will build a **new, multi-institution
> (multi-tenant)** admission management app **from scratch**. No existing data is moved into it.
>
> It lists **every feature the app must have**, how each works, the business rules that matter, what
> must be configurable per institution, and lessons learned from an earlier single-institution version.
> Read it fully before planning.
>
> **বাংলা সারাংশ:** এই ফাইলে অ্যাপের সব ফিচার, নিয়ম, সেটিং, পারমিশন আর আগের অভিজ্ঞতা লেখা আছে।
> নতুন অ্যাপটা শূন্য থেকে বানানো হবে, কোনো পুরোনো ডাটা থাকবে না।
> এতে একাধিক কলেজ/স্কুল/ইনস্টিটিউট থাকবে। প্রতিটি প্রতিষ্ঠান সেটআপ স্ক্রিন থেকে খোলা হবে, লগইনের সময় প্রতিষ্ঠান বাছাই করতে হবে, আর সব প্রতিষ্ঠান দেখাশোনা করবেন "Master Admin"।

## Contents
1. [Product in one page](#1-product-in-one-page)
2. [Goals of the new app (multi-institution)](#2-goals-of-the-new-app-multi-institution)
3. [Current tech stack and architecture](#3-current-tech-stack-and-architecture)
4. [Users, roles, permissions, "who" rules](#4-users-roles-permissions-who-rules)
5. [Auth and account lifecycle](#5-auth-and-account-lifecycle)
6. [Leads](#6-leads)
7. [Leads list, board, search, filters](#7-leads-list-board-search-filters)
8. [Lead page and peek sheet](#8-lead-page-and-peek-sheet)
9. [Pipeline stages, admit, lost, reopen](#9-pipeline-stages-admit-lost-reopen)
10. [Follow-ups (next call) and reminders](#10-follow-ups-next-call-and-reminders)
11. [Calls, call-log sync, caller card, call lock](#11-calls-call-log-sync-caller-card-call-lock)
12. [WhatsApp](#12-whatsapp)
13. [Notes, voice notes, delete and restore](#13-notes-voice-notes-delete-and-restore)
14. [Campus visits, lead score, recent/starred](#14-campus-visits-lead-score-recentstarred)
15. [Phone contacts, import/export, message templates](#15-phone-contacts-importexport-message-templates)
16. [Courses, batches, sections, fees master data](#16-courses-batches-sections-fees-master-data)
17. [Admission papers, uploads, passport photo, Photo Studio](#17-admission-papers-uploads-passport-photo-photo-studio)
18. [Google Drive files](#18-google-drive-files)
19. [Student IDs](#19-student-ids)
20. [Fee negotiation, discounts, final fee](#20-fee-negotiation-discounts-final-fee)
21. [Payments, installments, receipts, refunds, reminders](#21-payments-installments-receipts-refunds-reminders)
22. [Students tab, placement, external board flow](#22-students-tab-placement-external-board-flow)
23. [AI features (Claude / Gemini)](#23-ai-features-claude--gemini)
24. [Admission Contribution](#24-admission-contribution)
25. [Notifications and push](#25-notifications-and-push)
26. [Team activity, change log, reports](#26-team-activity-change-log-reports)
27. [Credits, leaderboard, milestones, weekly scorecard](#27-credits-leaderboard-milestones-weekly-scorecard)
28. [Alumni, referrals, public forms](#28-alumni-referrals-public-forms)
29. [Feedback chat, crashes, speed check, app versions](#29-feedback-chat-crashes-speed-check-app-versions)
30. [Home, More, Settings hub](#30-home-more-settings-hub)
31. [Website (web version)](#31-website-web-version)
32. [Native Android module](#32-native-android-module)
33. [Background jobs (pg_cron)](#33-background-jobs-pg_cron)
34. [Theming, offline, caching, speed](#34-theming-offline-caching-speed)
35. [Build, release, deploy](#35-build-release-deploy)
36. [Everything that must be configurable per institution](#36-everything-that-must-be-configurable-per-institution)
37. [Lessons learned (do not repeat these mistakes)](#37-lessons-learned-do-not-repeat-these-mistakes)
38. [Open decisions for the owner](#38-open-decisions-for-the-owner)
39. [Planning round 1: additions, decisions and proposals](#39-planning-round-1-additions-decisions-and-proposals)
40. [Fitting each institution type](#40-fitting-each-institution-type)
41. [Challenges for the Master Admin and the developer](#41-challenges-for-the-master-admin-and-the-developer)
42. [Updated build phases and open questions](#42-updated-build-phases-and-open-questions)
43. [Custom features without breaking the core database](#43-custom-features-without-breaking-the-core-database)
44. [UX and quality checklist](#44-ux-and-quality-checklist)
45. [Multi-tenant integration challenges](#45-multi-tenant-integration-challenges)

> **Note:** sections 39–45 record what was added and decided while planning. Where they conflict with an
> earlier section, **the later section wins**. Items marked **Proposed** still need the owner's approval.

---

## 1. Product in one page

The app is an **admission CRM for an education institution**. Callers and counsellors get leads (people
interested in a course), call them, log what happened, plan the next call, invite them to campus,
negotiate the fee and finally **admit** them. After admission the same app manages the **student**:
papers, fee payments, installments, receipts, student ID, section and the external-board (university)
submission steps. Managers watch team activity, reports and leaderboards. AI estimates each lead's
chance of admission, coaches the caller, and splits credit for each admission among staff.

- **Platforms:**
  - Android app: Expo / React Native, with a native module for call-log and WhatsApp sync.
  - Website: the same codebase exported for the web.
  - iOS is not targeted.
- **Language of the UI:** English labels. Bangla is used in AI output, message templates and public forms. Users are Bangladeshi.
- **Expected scale:** many institutions, each with tens of staff and thousands of leads.
- **Tabs (phone):** Home · Leads · Students · More.

## 2. Goals of the new app (multi-institution)

The owner's requirements:

1. **First screen: "Set up your institution".**
   - Institution name, address, **College Code** and **EIIN** (both optional, "if exist").
   - Then create the institution's **Super Admin** (name, email, phone, password).
2. **Login: pick the institution first** (college / institute / school), then email + password.
3. **New top role: "Master Admin".** Above every institution's Super Admin. Manages all institutions: list, approve, suspend, view usage, enter one to help (audited).
4. **Every feature in this file is per institution.** Settings, roles, courses, pipeline stages, templates, AI keys, Drive, receipts, ID series, reports and leaderboards.

### Must-haves for tenancy
- Put `institution_id` on **every** tenant table from day one, with an index that starts with it.
- **Row Level Security** must use the institution taken from the **JWT custom claim**. Do not look it up per row; that is fast and avoids extra queries.
- **Every server function must filter by institution.** The single-institution version had about 418 `SECURITY DEFINER` functions, which bypass RLS. In a multi-tenant app each one is a potential data leak.
  - Prefer `SECURITY INVOKER` plus RLS where possible.
  - Where DEFINER is needed, check the institution explicitly.
- Build an **automatic cross-tenant leak test** early. Create two institutions, call every RPC and select every table as a user of B, and assert nothing of A is visible.
- **Per-tenant uniqueness and counters:**
  - stage keys, receipt numbers, refund numbers, alumni ref codes, alumni field keys
  - student ID series, phone-duplicate checks, tag names, course names
- Settings must be per tenant, e.g. `app_settings(institution_id, key)` or typed settings tables.
- **Per-tenant integrations:** Claude/Gemini keys, Google Drive Apps Script URL and secret, iLovePDF and remove.bg accounts, receipt prefix, logo, institute details used in receipts and templates.
- **Per-tenant locale:** time zone (default `Asia/Dhaka`), currency (default ৳), phone country rules (default Bangladesh), week start (default Saturday), working days and holidays.
- **Public pages need the institution in the URL:** `/apply/<slug>`, `/refer/<code>`. Referral codes can stay globally unique.
- Storage paths and policies are prefixed by institution. Drive folders are per institution.
- Background jobs (pg_cron) must loop per institution and respect each one's time zone and settings.
- **Branding per institution:** name and logo on login, web shell, receipts and the Home top bar. The product needs a neutral app name.

## 3. Recommended tech stack and architecture

| Layer | Current choice |
|---|---|
| App | Expo SDK **58**, React Native 0.88, **expo-router** (file routes in `src/app`), React Compiler, typed routes |
| Backend | **Supabase**: Postgres, RLS, RPC functions, pg_cron, pg_net, Storage, Realtime, Edge Functions (Deno) |
| Native | Kotlin Expo module `modules/call-log` (call log, WhatsApp notification listener, caller overlay, contact groups, native crash capture) |
| Push | expo-notifications + FCM (`google-services.json`), sent from Postgres via pg_net to Expo push API |
| Updates | EAS Update (OTA), channels `preview` / `production`; runtimeVersion pinned |
| Web | `expo export --platform web` (single page), FTP to cPanel hosting |
| Files | Google Drive via an Apps Script web app (no Google login for staff) |
| AI | Anthropic Claude API (Sonnet 5.5 / Haiku 5.5) and Google Gemini (Flash) from Edge Functions |
| Other libs | xlsx (Excel), expo-print (PDF/receipts), react-native-view-shot, MediaPipe face detection (web), expo-audio (voice notes) |

**Patterns used**
- **Database:**
  - Tables are read through RLS. Most writes go through **RPCs** (SECURITY DEFINER) that check permissions.
  - Guard triggers block direct edits of important columns. Pipeline, admission and fee fields change only via RPCs, which set session flags such as `app.pipeline_action`.
  - `lead_activity` is an **append-only timeline**. Every action writes a line, and it feeds the lead's Changes, the global Change log and restore.
  - Denormalised columns on `leads` are kept by triggers so lists stay fast: fee status, paid, due, papers counts, visit status, last contact, score, course_ids, AI chance.
- **App:**
  - Settings are loaded once and cached.
  - Lists use small RPCs plus caching ("stale-while-revalidate": show last data instantly, then refresh).
- **Ask before risky actions:** dialogs warn before re-running costly AI or before deleting.

## 4. Users, roles, permissions, "who" rules

- **Seed roles:**

  | Role | Permissions | Rank |
  |---|---|---|
  | `super_admin` | `*` | 100 |
  | `admin` | | 80 |
  | `team_lead` | | 50 |
  | `caller` | | 10 |

- **Custom roles:**
  - Created by the Super Admin (Settings → Roles).
  - Each has a name, permissions, `acts_as` (caller / team_lead / admin) and optional `course_ids` (course restriction).
  - System roles can't be deleted. A role with people can't be deleted.
- **Permission keys:**

  | Area | Keys |
  |---|---|
  | Leads | `leads.view_own`, `leads.edit_own`, `leads.view_team`, `leads.edit_team`, `leads.view_all`, `leads.edit_all`, `leads.assign`, `leads.delete`, `leads.export`, `import.run` |
  | Reports | `reports.view_team`, `reports.view_all` |
  | Fees | `payments.manage`, `discounts.approve_limited`, `discounts.approve` |
  | Admin | `settings.manage` (also means "sees all courses"), `users.manage` |
  | Wildcard | `*` |

- **Teams:** `profiles.team_lead_id` links a person to their Team Lead.
- **Course restriction:**
  - A person's own `course_ids` override the role's.
  - Leads and students of other courses are hidden everywhere through restrictive RLS policies.
  - A lead with no course is seen only by admins and by the person who added it.
- **The "who" rule** is reused by many settings: `{mode: 'all'|'roles'|'users', roles: [], user_ids: []}`.
  - Admins (`settings.manage` or `*`) always pass.
  - Role pickers list every role except Super Admin.
- **"Admission Officer"** is not a role. It means anyone allowed by the Admission-flow "who" rule.
- **Developer:** a special user (by email setting) who receives everyone's feedback chats and crash reports.
  - In the new app this belongs to the **Master Admin / product owner** level, not per institution.

## 5. Auth and account lifecycle

- **First-run setup:**
  - Runs when no Super Admin exists.
  - Asks for name, email, phone, password and institution name.
  - Creates the account and makes it an active Super Admin.
  - **In the new app this becomes the per-institution setup screen.**
- **Login:**
  - Email and password, with a "remember my email" option.
  - No self-service password reset: an admin resets it.
  - The web login is a split page with the logo, show/hide password and a Caps Lock warning.
- **Sign up:**
  - Creates an **inactive** profile with role caller.
  - Users with `users.manage` get a "signup" notification and approve the person in Users.
- **App states:** loading / error / needs_setup / signed_out / pending_approval / must_change_password / active.
- **Pending screen:** check again, sign out, or delete my account. Wording differs if the account was deactivated.
- **Admin reset password** (Edge Function):
  - Sets a password, ends all of the person's sessions and can force "change password on next login".
  - Only a Super Admin can reset a Super Admin. You can't reset yourself.
  - The UI generates a password and shares it on WhatsApp.
- **Users screen:**
  - Lists pending / active / deactivated users, with search.
  - Detail screen: edit name, phone, email (immediate), role, team lead, course limits, list design.
  - "Call log sync required" (Super Admin only).
  - Actions: approve, deactivate or reactivate, reset password, view activity.
- **Profile:** edit name and phone, change email (with a confirm link), change password, photo (public bucket `avatars`).
- **Account deletion** (Google Play requirement):
  - Signed in: re-enter the password and type DELETE.
  - Signed out: sign in on the page, or send a deletion request (rate limited) for admins to handle.
  - Deletion **anonymises** the person but keeps the institution's records:
    - leads become unassigned
    - tokens, devices and chats are deleted
    - the profile becomes "Deleted user"
    - the auth email is scrambled and the account banned
  - The last Super Admin can't be deleted.
- **Privacy page:** static, with contact and site details.
- **Sign out:** unregisters push, clears caches and forgets the device.

## 6. Leads

**Fields**

| Group | Fields |
|---|---|
| Contact | name (required), phone (normalised BD mobile), alt_phone, guardian name / phone / relation, email, area |
| WhatsApp | whatsapp_number (BD or `+intl`), whatsapp_username |
| Classification | lead_type, source, campaign, referred_by |
| Pipeline | stage, rating (hot / warm / cold), score, lost_reason |
| Ownership | assigned_to, assignment_method, created_by |
| Dates and counters | next_follow_up_at, last_contacted_at, admitted_at, lost_at, closed_at, call_attempts, unreachable_at |
| Visit | visit_status / visit_at |
| Text and extra | notes, custom_fields (jsonb), import_batch_id, deleted_at (soft delete) |
| Courses and tags | interested **courses** (many), **tags** (many) |

**Rules**
- **Contact:** name is required. At least one of phone, WhatsApp number or WhatsApp username is required.
- **WhatsApp number:** if it equals phone it is cleared. Usernames are lower-cased, 3–35 characters.
- **Course:**
  - A new lead must have at least one interested course, if any course exists.
  - A lead's last course can't be removed.
  - `create_lead(row, course_ids, tag_ids)` saves everything in one transaction.
- **Source:** the original source can only be changed with `leads.edit_all`. Reassigning needs `leads.assign`; deleting needs `leads.delete`.
- **Duplicate check** (`find_leads_by_contact`):
  - Runs while typing.
  - Checks the phone against phone / alt / guardian / WhatsApp numbers of **all** leads, even ones the user can't see.
  - Shows up to 5 matches with name, stage and owner, plus "Open" (if allowed) or "Save anyway".
- **Add/Edit form:**
  - Cards: Who (pick from contacts or recent calls), Interested course, Quick details.
  - Folding sections: other contact, guardian, campaign / type / tags / notes.
  - Remembers the last source and course. "Save & next" keeps source, course and assignee.

**Assignment** (setting `assignment`)

| Option | Meaning |
|---|---|
| `enabled` | Assignment on / off |
| `visibility` | `assigned` / `everyone` |
| `admin_auto` | Admins' new leads go to a chosen user |
| `caller_self`, `team_lead_self` | Callers / team leads keep the leads they add |
| `team_lead_assign` | Team leads may assign leads |
| `handover` | Who may hand over to whom: anyone / team / managers / off |

- A trigger decides who gets a new lead.
- Admins can assign to anyone. Team leads can assign to themselves or their team.
- "Hand over" moves leads with a note and a notification.
- **Visibility:** own / team / all permissions. "Shared mode" (assignment off or visibility everyone) lets everyone see and edit all leads. The creator always sees what they added.

## 7. Leads list, board, search, filters

- **Search:**
  - Matches name, student ID, guardian, email, area, board ID and WhatsApp username.
  - 3 or more digits also match all phone numbers.
  - Closed leads are always included when searching.
  - A hint shows matches hidden by the current chip or filter, plus an "also matched in …" line.
  - The last 8 searches are kept.
- **Chips:** All, 🕘 Recent, ⭐ Starred, 🔮 AI Hot (if AI is on), 🆕 Not called. Counts are cached.
- **Added by / when:**
  - 👤 user picker (who added the lead).
  - Today / Yesterday / This week (starting Saturday) / This month / Custom.
- **Filters** (an admin chooses which show and their order):
  - next call, rating, AI chance, stage, tags, assignee (or unassigned), source, course, campaign, lead type
  - added, last contacted, admitted period, lost reason, papers, campus visit, contact type, fee / payment, batch
- **Saved filters:** private, or shared by admins.
- **Sorts:**
  - next call (default), newest / oldest, name, not contacted longest, recently contacted
  - visit date, papers missing, discount, fee, score
  - AI chance, AI "call first", AI rising, AI falling, AI lowest
  - The next-call sort can "group by time": Overdue / Today / Tomorrow / This week / Later / No call.
- **Closed leads:** hidden from the list by setting (`admission.closed_in_list`) unless a filter needs them.
- **Card designs:**
  - Per user: "New" (Material card) or "Classic". An admin can set it for everyone.
  - "Show the latest on cards" adds the last call and last note lines.
  - A stale card turns orange after N days without contact (`lead_cards.stale_days`).
  - On the card: score chip, AI chance chip, "📵 X is on a call" (call lock), Call / WhatsApp / SMS buttons (hold for SMS or a template), 👁 peek.
- **Bulk select:**
  - Long-press; "mark all matching" selects up to 2,000.
  - Actions: note, stage, tag, assign / hand over, next call, rating, fee, lost, placement, external board "received", course (admins), AI check.
  - Runs in chunks of 200; leads the user can't edit are skipped.
- **Quick menu (one or many):** rating, stage, tags, assign, follow-up, note.
- **Board view:**
  - One column per stage, using the same search, filters and sort. Columns load lazily.
  - Moving a card uses the same stage rules.
  - Setting `board`: enabled, show closed columns, who may use it.
- **Page size** is 30. "Keep in place" stops a card jumping after an edit.

## 8. Lead page and peek sheet

**Phone layout**
- Header: back, call, ⭐ star, edit.
- Round actions: Call, WhatsApp, SMS, Note, Next call.
- Cards in this order:
  1. next-call card
  2. **Pipeline** card (stage, move, admit, lost, reopen)
  3. 🔮 **AI chance** card
  4. **External board / admission flow** card
  5. **Admission credit** card
  6. **Visit** card
  7. **Fee** card
  8. **Papers** card
  9. **Files** card
  10. hand-over note
- Folds: Timeline (calls and notes, filter phone / WhatsApp), Admission, Info, Changes.
- At the bottom: + Note and + Log call.
- **Log a call** made from another phone. **Log WhatsApp** (call or message).
- **URL parameters:** `callNote` (open the add-note view from a notification), `waCall`, `dial` (call on open).
- Opening a lead records a "view" (used by Recent). Delete has an Undo toast.

**Wide / web layout:** Calls & notes, Interest, Details, Activity, Delete lead.

**Peek sheet:**
- Shows the last 5 calls, notes and voice notes in full, or all, without opening the lead.
- Actions: Open, Add note.
- Also shows the AI card for open leads.

## 9. Pipeline stages, admit, lost, reopen

**Stages**
- Fields: key, name, kind (open / won / lost / cancelled), color, order, active, course_ids (stage only for some courses).
- Per-stage rules:
  - `follow_up_days`: auto next call N days later.
  - `note_required`.
  - `ask_date` with `date_label`: the date becomes a follow-up.
- **Seed stages:** New, Contacted, Interested, Follow-up, Papers pending, Ready for admission, Admitted (won), Lost, Admission cancelled.
- **Guards:**
  - System stages can't be deleted or change kind; Admitted, Lost and Cancelled always exist.
  - A stage with leads can't be removed.
  - New stages go before the closed ones.
- **Moving:**
  - Only between open stages; a closed lead must be reopened.
  - Every move writes stage history with an optional note.

**Admit** (`mark_admitted`; who may: setting `admission.mark`)
- **Inputs:** course (active), batch (required by setting; must be in the course), section (required if the batch has sections), admission date, student ID, note.
- **Seats:** checked with a lock unless overbooking is allowed.
- **Papers check:** block / warn / allow.
- **Payment:** optional "pay now", with a minimum by setting.
- **Side effects:**
  - finishes the pending follow-up
  - locks the fee
  - assigns the student ID
  - resets the external-board flow
  - notifies officers
  - triggers AI credit

**Lost:** a reason is required, and "Other…" needs a note. Optional "♻️ Revive on date" follow-up.

**Cancel admission** (who: setting `admission.cancel`)
- A reason is required.
- Frees the seat, unlocks the fee and clears the board flow.
- Keeps the student ID, so a re-admission gets the same ID.

**Reopen:** works on lost or cancelled leads, to a chosen open stage. "Undo admission" = cancel, then reopen.

## 10. Follow-ups (next call) and reminders

- **Rules:**
  - One pending follow-up per lead, mirrored to `leads.next_follow_up_at`.
  - Statuses: pending / done / rescheduled / cancelled. Purpose `revive` for lost leads.
  - Scheduling a new one marks the old one "rescheduled".
- **Auto-done:** a reached call (any outgoing call, or any connected call) marks today's or an overdue follow-up done.
- **Presets:** In 2 hours, Tomorrow 10:00, In 3 days, Next week. They skip holidays; a holiday picked by hand shows a warning.
- **Default next call after each call result:**

  | Result | Next call |
  |---|---|
  | wrong number | none |
  | busy / no answer / call back | 2 h |
  | switched off | tomorrow |
  | connected | 3 days |

- **Home "Today" list:** due today and overdue, closed leads left out. Missed-call follow-ups first, then revive, then by time.
- **Reminders** (cron every minute):
  - early reminder N minutes before, then a repeat
  - **speed-to-lead escalation:** new lead not called in X minutes → the person, then the Team Lead after Y hours, then admins after Z hours
  - **quiet hours** (default 22:00–08:00) delay pushes; an option lets "assigned" come at once

## 11. Calls, call-log sync, caller card, call lock

**Call log** (`call_logs`)
- **Fields:** lead, user, time, outcome, duration, notes, direction, source (app / phone / whatsapp), channel (phone / whatsapp / sms), media (voice / video / message), device ids, SIM, template id, soft delete.
- **Outcomes:** connected, no_answer, busy, switched_off, wrong_number, call_back, missed, rejected, message.
- **Edits:** calls can't be edited, except adding a note once within 24 h.
- **After each call (trigger):**
  - updates last contacted and closes due follow-ups
  - counts unanswered attempts: after N (default 5) the lead is marked unreachable and gets a retry follow-up after N days
  - a missed call from a lead creates a "call back" follow-up and a notification
  - a missed call from a lost lead creates "♻️ Lost lead called you"
  - closed leads don't count attempts

**Call popup**
- Appears when the user returns to the app after calling from the list or lead page.
- Inputs: result, note, rating, next call, 🎙 voice note.
- **Auto mode:** if the call is in the phone's call log, result, duration and SIM are filled in.
- Offers to reopen a lost lead after talking to them.
- `save_phone_call` merges the popup result with the synced copy, so there are no duplicates.

**Call-log sync (Android)**
- **What the phone sends:** only a **SHA-256 hash** of each number, never the number itself. The server matches hashes to leads the user can see.
- **When it runs:** on app open and on returning to the front, plus a background worker after each call.
- **Results:**
  - outgoing ≥ N seconds → connected, otherwise no answer
  - incoming with talk time → connected, otherwise missed
- Matches a manual entry within ±10 minutes instead of saving it twice.
- **Held calls:** calls from numbers that are not leads yet are kept (default 15 days). When a lead gets that number, they appear in its history without alerts.
- **Phone lead directory:** the phone keeps hash → name / stage / course / last note / next call for up to 10k leads. It powers the offline **caller card** overlay and "add a note" notifications.
- **Sync health screen:** per phone: permission, sync on, SIM, pending count, last sync, errors. Worst first.
- **Nudges:** the Super Admin can send "turn on sync" reminders. They close automatically when sync is on.
- **"Sync required"** per person (Super Admin only): the Android app stays blocked until sync is set up.
- **Setting `call_sync`:** who, incoming, missed follow-up, connected minimum seconds, unreachable after / retry days, ask after WhatsApp, hold calls / days.

**Call lock** (setting `call_lock`)
- Stops two people calling the same lead at once.
- Options:
  - mode block or warn
  - lock length 3–60 min
  - override: none / admin / admin + team lead
  - also lock for WhatsApp; show on cards
- The phone marks answered incoming lead calls and clears the lock when the call ends.

**Double-call warning** (setting `double_call`)
- Before calling, warns if someone else contacted this lead within N minutes, e.g. "Rahim called 12 min ago. Call again?", with "read notes".
- Options: count attempts / notes / WhatsApp, include own contacts, log "call anyway".

**Reports:** talk time per person per day, and a weekday × hour heatmap.

## 12. WhatsApp

- **Opening:** WhatsApp opens by number (or the app for username-only leads), optionally with a filled template.
- **Manual log:** call or message, incoming or outgoing, voice or video.
- **Automatic log** (Android):
  - A notification listener sees WhatsApp and WhatsApp Business calls and messages from lead numbers.
  - It **never reads message text**.
  - Events sync without duplicates, skipping ones typed by hand within 15 minutes.
  - Needs Android "Notification access".
- **"Ask after WhatsApp":** after opening WhatsApp from the app, the app asks what happened.
- **WhatsApp calls screen:** today / 7 / 30 days; calls or messages. Delete your own within 24 h.
- **WhatsApp report:** shown separately in Reports and Team activity.

## 13. Notes, voice notes, delete and restore

- **Notes:**
  - Stored as one text on the lead, in stamped blocks such as "26 Oct 2026 · Rahim: …".
  - Bulk "add note" works on many leads.
  - The timeline splits the text into separate notes.
- **Voice notes:**
  - Recorded in the call popup or next to any note field. AAC 64 kbps, at most 1 hour.
  - Stored in Google Drive and linked to the call. Played with speed control.
- **Delete:**
  - admins: anything; the writer: within 24 h
  - only app-written entries, not synced calls
  - calls are soft-deleted
- **Restore:** the person who deleted can undo within 10 minutes; admins any time, from the Change log.
- **Leads:** soft-deleted with `leads.delete`. There is no restore UI yet.

## 14. Campus visits, lead score, recent/starred

**Campus visits**
- At most one planned visit per lead.
- Statuses: planned / visited / missed / cancelled. Walk-ins are allowed.
- A visit moves New or Contacted to Interested (by setting). A miss creates a next call after N days.
- Visit reminders: today from 9 am, and 1 h before.
- Home "Today's visits" card.
- Setting `campus_visit`.

**Lead score** (rule-based, 0–100; separate from AI)
- Base 30, plus points per signal: visited, visit planned, fee talk, answered, stage, referral, hot / cold.
- Minus points for: silent 7 / 30 days, 3 misses, wrong number.
- Admitted = 100; lost = 0. Reasons are stored.
- Recalculated on every change and nightly.
- Card chip: 🔥 70+, 🙂 40–69, ❄️ below 40. Points are editable in Settings.

**Recent and Starred**
- Star leads per user.
- "Recent" combines your calls, activity and opened leads.
- Home "Recent" card.

## 15. Phone contacts, import/export, message templates

**Phone contacts**
- Pick contacts (or a whole contact group) and save them as leads, with source "Phone contact", course (required), tags, rating and assignee.
- Undo within 24 h.
- Existing numbers are flagged.
- Who may use it: setting `contacts_import`.

**Import (Excel / CSV)**
- Needs `import.run`.
- Columns are mapped automatically, including Bangla aliases.
- Duplicate handling: skip / update (logs a "re-enquiry") / create.
- Assignment: none / user / round robin. Default source and course.
- Runs in chunks. Errors can be downloaded as Excel, and a template file is provided.
- Undo within 24 h.

**Export (Excel)**
- Needs `leads.export`.
- Uses the list filters and reads 1,000 rows per page.
- Each export is logged.
- Columns include contact, course, pipeline, fee, visit and admission-flow fields.

**Message templates (SMS / WhatsApp)**
- Shared (admins) or personal. Each has name, body, channel, category, courses and a use count.
- Six seed templates in Bangla.
- **Variables:** {name}, {first_name}, {course}, {batch}, {batch_start}, {fee}, {full_fee}, {discount}, {final_fee}, {paid}, {due}, {next_installment}, {next_due_date}, {visit_time}, {next_call}, {papers_missing}, {student_id}, {section}, {my_name}, {my_phone}, {institute}, {address}, {map_link}, {office_phone}, {today}.
- Missing values are flagged before sending.
- Sending logs a call-log entry and a timeline line.
- **Template report:** sends, edits, replies within 7 days, stage moves and admissions after a send.
- **Institute details** for templates and receipts: name, address, map link, office phone.

## 16. Courses, batches, sections, fees master data

- **Course:**
  - Fields: name, code (`{CODE}` in student IDs), category, duration, active, order.
  - **Fee lines:** e.g. Admission fee, Tuition; the full fee is their sum.
  - Optional **admission fee** threshold, used by the external-board flow.
- **Batch:**
  - Fields: name, start date, class time, **seat capacity**, status (open / closed / full).
  - Seats taken = admitted leads in the batch.
- **Sections** per batch: an in-use section is switched off, not deleted.
- **Fee sync:** changing fee lines re-calculates open negotiations.
- **Generic master lists** (Settings → list): lead_sources, campaigns, lost_reasons, call_results (unused, legacy), tags, lead_types, document_types (legacy duplicate of papers).

## 17. Admission papers, uploads, passport photo, Photo Studio

**Required papers**
- Fields: name, description, required, courses (or all), order.
- Per lead each paper is received or not needed, original or photocopy, with "kept at" (one shelf or file place per student) and "original returned".
- Lead counters: required, received, originals held, missing.
- Filters and sorts on these counters.
- Admit check: block / warn / allow.

**Upload rules (web)**
- Per paper: accepted type (any / image / pdf), exact picture size, KB limits. Defaults are set in settings.
- Pictures are resized and compressed in the browser.
- PDFs over the limit are compressed on the server through **iLovePDF** accounts, tried in order, with monthly counters.

**Passport photo**
- Per paper: on/off, background colour, face %.
- Browser pipeline: cut out the person (server `photo-cutout` → **remove.bg** accounts in order), find the head, auto-crop, render at the exact size.
- Editor: move, zoom, rotate, background, light.

**Photo Studio (web, officers)**
- Any photo in, face detection (MediaPipe), background removal.
- Presets come from paper sizes, shared presets (px / mm / in, dpi, face %, background, KB, format) or custom sizes.
- Output: download (JPG / PNG under a KB limit), a print sheet (4R / A4), or save to a student's photo paper.

## 18. Google Drive files

- **One Drive per institution, via an Apps Script web app.**
  - The admin deploys the script and pastes its URL and a secret.
  - Staff never sign in to Google. All access goes through Edge Functions, so the app's rules decide who sees what.
- **Folders:** `Lead Management/<Student ID Name | Name – Phone>/Papers | Voice notes`.
- **Edge functions:**
  - `drive-connect`: ping and save, create the root folder.
  - `drive-upload`: ≤ 35 MB. Checks the upload rule and compresses. Auto-ticks the paper as a received photocopy.
  - `drive-file`: streams the file; Drive links are never exposed.
  - `drive-delete`: moves to Drive trash.
  - `drive-zip`: a lead's files, ≤ 60 files / 60 MB.
- **Setting `files`:** enabled, and who sees everyone's files. By default you see the files you uploaded; admins see all.
- **UI:** Files card (list, open, delete, ZIP), camera or file upload.

## 19. Student IDs

- **Pattern tokens:** `{YYYY}`, `{YY}`, `{SESSION}` (e.g. 2027-28), `{CODE}`, `{000…}` (running number).
- **Number series:** one per year (if the pattern has a year) and per course code (if it has `{CODE}`).
- **Year source:** admission date or batch start.
- **Modes:** auto / manual / off.
- **Rules per course, batch or section:**
  - Each rule is a **pattern** or a **number range**; the most specific one wins.
  - Ranges can't overlap and hold at most 100k IDs. A full range blocks admission with a clear message.
  - "Fill section ranges" gives every section of a batch consecutive ranges.
  - An overview shows each range's usage, with a warning when two batches share a series.
- **Preview:** the next ID is shown in the Admit sheet without using it up.
- **Changes:**
  - Moving course, batch or section gives a new ID in auto mode; the old one is logged.
  - Typing an ID by hand must be unique, and is logged.
- **Renumber everyone:** admins only, with a preview.

## 20. Fee negotiation, discounts, final fee

- **Fee talk:**
  - One per lead and course. Starting it moves the lead to Interested.
  - Events: quoted, lead asked, offer, note.
- **Discounts:**
  - On one fee line or the whole fee, as an amount or a percent. A reason is required (setting).
  - Can't exceed the line, and all discounts can't exceed the full fee.
- **Approval:**
  - Within the requester's limit → approved at once.
  - Above it → approvers are notified; the **Discounts** queue shows Approve or "Not now" only to people whose limit fits.
- **Limits:** % per role (defaults: caller 0, team lead 10). `discounts.approve` or `*` = 100.
- **Expiry:** approved discounts expire after N days (cron).
- **On admission:** approved discounts become permanent; pending ones are cancelled.
- **Lead fee fields** (kept by triggers): fee status (negotiating / discount waiting / discount given / final), full, discount, final.
- **Fee lock at admission:**
  - The final fee is locked at admission.
  - **Change final fee** (officer or admin): a reason is required; 0 ≤ final ≤ full, and ≥ already paid.
  - A course change re-locks the fee.

## 21. Payments, installments, receipts, refunds, reminders

**Payments**
- **Who:** admitted students only, and people allowed by `payments.who`.
- **Methods:** from settings (Cash, bKash, Nagad, Rocket, Bank, Card). Some require a transaction ID.
- **Back-dating:** limited to N days (default 7); older needs admin. No future dates.
- Amount ≤ due.
- **Receipt number:** `<prefix>-YYYY-00001`, one series per year. Optional **college receipt number**: off / optional / required, unique.
- **Mistakes:** payments are never deleted; they are **voided** with a reason (`void_who`).

**Installments**
- Up to 24 lines that must sum to the final fee. Payments fill them earliest first.
- "Next due" is shown on the student.

**Printable receipt**
- Templates: classic / modern / minimal.
- Sizes: A4, A5, A4 with two copies (student and office), POS 80 mm.
- Options: accent colour, logo, title, header line, 0–3 signatures, amount in words, PAID / VOID stamp, chosen fields, footer.
- Settings has a live preview.
- Printed with expo-print, or an iframe on the web. Can also be shared as text.

**Refunds**
- For students no longer admitted. Amount ≤ net paid.
- Own series `RFD-YYYY-00001`.
- Net paid = payments − refunds.

**Reminders** (cron hourly from 9 am)
- To the assignee N days before and on the due day.
- After N days late: the assignee, their team lead and admins.
- Each reminder is sent once.

**Collection report**
- Collected, refunded, net, by method and by person.
- Due and late now, discounts given, recent voids.
- Visible according to report scope.

## 22. Students tab, placement, external board flow

**Students tab**
- Admitted students; on/off and "who" by setting.
- **Summary:** students, new this month, with due, due amount, overdue, collected this month, papers missing. Tap to filter.
- **Chips:** All, Mine, Due, Overdue, Paid, Papers missing, New this month, plus the board-flow chips.
- **Paid ranges:** ৳0, 1–999, 1,000+, 5,000+, 10,000+, custom, paid this week / month.
- **Sorts:** admitted newest / oldest, name, student ID, paid most / least, last paid, most due, next installment, papers missing, next call.
- **Search** also by student ID and board ID.
- The list total shows what the listed students paid.

**Placement**
- Change course, batch and section, with a seat check.
- Side effects: fee re-lock, new student ID, logged.
- **Bulk placement:** preview first (who moves, seats, new IDs, fee changes), then all-or-nothing.

**External board flow** (post-admission steps; configurable per institution)

Many colleges must register each admitted student with an affiliating university or board (for example,
National University in Bangladesh) and then record that the institution received the student. Default steps:

1. **📤 Submitted Online:** the student was submitted on the board's portal. The **board ID** (label set per
   institution, e.g. "NU Admission ID") is required and unique.
2. **🏛 Received by institution:** needs Submitted first, and **net paid ≥ the course's admission fee**
   (a default amount per institution, overridable per course).
   - The error says how much more is needed.
   - Officers are notified when a submitted student becomes "ready" (fee paid).
   - **Bulk received:** only ready students are marked; others are reported with the reason.
3. **Undo:** a reason is required; the later step must be undone before the earlier one.

- Officer Home card: not submitted / ready counts.
- Make the steps, their names, the board ID label and the money and paper conditions **configurable per
  institution**, and allow switching the whole flow off.

## 23. AI features (Claude / Gemini)

All AI runs **on the server**, in Edge Functions `ai-lead-chance` and `ai-admission-credit`, in the background.
- The app only reads saved answers, so lists stay fast.
- API keys are entered in Settings → AI and **stored only on the server**; the app sees a hint like `sk-ant-…abcd`.
- Names and phone numbers are **never sent**. People appear as codes P1, P2….

### 23.1 Chance of admission (open leads)
- **Input to the AI** (built by SQL `ai_chance_input`):
  - the lead's story: stage, age, days since contact, source, courses, area, rating, visit, fee talk, papers, previous chance
  - every event: calls (direction, answered, minutes, note), WhatsApp, notes, visits, fee offers, papers, hand-overs, next calls
  - per-person totals
  - **answer hours** (answered / not by Dhaka hour)
  - next-call stats
  - "like this before": admitted vs lost for the same course and source over the last year
  - today's date
- **Output** (JSON schema), in **Bangla**:
  - chance %, short summary, good signs, risks
  - objections (kind: fee / family / distance / time / other_college / job / doubt / documents / other, with detail)
  - 2–5 next actions with why
  - **script:** what to say, per situation, 1–3 polite lines
  - best time to call, next call in N days with why
- **Prompt rules:**
  - calibrate from history
  - notes are the strongest evidence
  - never promise discounts, scholarships or dates not in the data
  - the admin can add "what the AI should know about the college" (installments, class days…)
- **Level** from the chance: hot / warm / cold. The previous chance is kept, so the trend ▲▼ is shown.
- **Lead page card:**
  - chance, trend, summary, objection chips, numbered actions
  - best time plus "📅 set next call in N days" (creates a follow-up)
  - "💬 What to say" (hold to copy), "why" (good / risks)
  - "🔄 Look again", with a warning if already looked at today with nothing new
- **Queue (`lead_chances`):**
  - States: pending / working / done / failed.
  - It looks again automatically after a new call or note (once a day per lead).
  - "Check" is manual and always allowed.
  - Kinds: auto / manual / bulk. The daily limit counts **auto** only.
  - A lead stopped 3 times is given up. A failed credit try waits 5 minutes.
- **Daily run** at a chosen hour (Dhaka). Groups: changed since the last look / never looked at / older than N days.
- **Settings → AI:**
  - on/off, auto, daily run, daily auto limit (up to 1000)
  - **monthly budget ($)**: Claude stops when it is reached; "Check" still works
  - "who sees the chance"
  - run a group now (with count and cost first), progress, ⏹ stop
  - accuracy so far (by level: % of closed leads admitted)
- **Lists:**
  - 🔮 % chip on cards (tap: quick view sheet), AI Hot chip, AI sorts and filter
  - Home "Call these first" (my leads with a good chance)
  - web table column

### 23.2 AI admission credit
- When a lead is admitted, the AI reads the story (calls, minutes, notes, visits, fee talks, papers, hand-overs, who pressed Admitted) and **shares the admission among staff**.
- **Output:** shares (%, adding to 100, each with a reason in Bangla), the decisive moment, confidence.
- **Weighing:** real influence over clicks; work near the decision weighs most; bringing the lead earns a fair part; pressing Admitted is office work and earns a small part.
- **Lookback window:** 60 / 90 / 180 / 365 days.
- **Admins can:** re-run, or set the shares **by hand** with a reason.
- **Credits:** use these shares for "Admitted" when the feature is on.
- **"Work out past admissions"** runs once.

### 23.3 Providers, models, costs
- **Providers:** Claude and Gemini, each with its **own on/off switch** (off = never used, key never sent).
- **Per-feature mode:** `claude` | `gemini` | `gemini_then_claude` (fallback) | `compare` (both in parallel; lists use Claude's answer).
- **Answers are kept per provider** (`lead_chance_answers`, `admission_credit_answers`). One AI's answer is never deleted when the other answers. The lead page has tabs per AI.
- **Claude models:** **Haiku 5.5** (cheap: $0.10 / $0.50 per M tokens) or **Sonnet 5.5** ($2 / $10), chosen per feature.
  - Prompt caching on the system prompt.
  - Server-side refusal fallback for Sonnet; Haiku is asked plainly.
  - Structured output via JSON schema.
  - 75 s timeout, no SDK retries; a run starts new work for 45 s (the Edge Function has a 150 s limit).
- **Gemini (free tier):**
  - Flash models only; retired 1.x models are filtered out.
  - The server auto-switches to the best available model if the chosen one is gone (404).
  - Quota (429) → rest 15 min. Free-tier data may be used by Google, so the UI warns.
  - **Owner's verdict: the Gemini free tier was not useful in practice; Claude Haiku 5.5 is the cheap choice.**
- **Ledger `ai_usage_daily`:**
  - Rows are per day and feature (`chance`, `credit`, `haiku:<f>`, `gemini:<f>`).
  - The monthly budget counts Claude only, at each model's price.
- **Problem visibility:**
  - each AI's last problem is shown in Settings
  - a side note on the lead when one AI failed but the other answered
  - key status (refused / credit out)
- **Planned but not done:** the Batch API (50 % cheaper) for the daily run.

## 24. Admission Contribution

- A menu (phone More and web) built on AI admission credit.
- **Summary:** each person's share of admissions in a period.
- **Every student:** a coloured bar of who contributed.
- **Breakdowns:** by source and by course.
- **Drill-downs:** a student detail (who did what, when) and a person detail.
- **Export:** to Excel.

## 25. Notifications and push

**Inbox**
- Last 100, mark read, deep link to a lead or route.
- Unread badges on More, the Alerts tile and the web.

**Kinds** (each can be switched off by the admin; people can mute some)
- assigned, auto_assigned, follow_up, visit, speed_to_lead, outcome, signup, sync_nudge, missed_call, discount, payment
- leaderboard, scorecard, alumni, feedback, admission-flow steps, app_update
- AI, and the external board flow's "ready"

**Sending**
- `notify(user, kind, title, body, data, dedupe, urgent)`: dedupe per user, quiet hours, pushed via pg_net to the Expo push API.
- Receipts are checked every minute, and dead tokens removed.

**Push setup**
- Asks permission once and creates the Android channel `leads`.
- Registers the token with a timeout and "checks in" (the server knows the device's state).
- **Push check screen:** this phone's permission, channel and token; send a test push.
- **Push health (admins):** one row per person; Google pre-launch test devices are ignored.

**Device ownership**
- One person per phone install. Devices are forgotten on sign-out.
- Web sessions are labelled "🌐 Website" and get no push.

## 26. Team activity, change log, reports

**Team activity** (setting `activity`)
- **Sessions:** app time is counted while the app is in front and being touched, until N idle minutes. Offline queue.
- **Team list:** Today / Yesterday / This week / This month. Calls in / out / missed, talk time, WhatsApp, leads added and imported.
- **Person detail:**
  - calls and talk time, short calls, follow-ups on time or late
  - speed to first call, lost reasons
  - hourly chart
  - **gaps:** 60+ idle minutes in working hours
- **Lost section:** every move to Lost per person, with reason and note, and whether the lead is still lost.
- **Export work:** Excel or text.
- **Who sees it:** admins; team leads see their team (setting). Callers see no one.

**Change log**
- Paged global timeline with counts per kind.
- Restore deleted entries.
- Web version with Excel export.

**Reports** (setting `reports`: who, Home card, which sections)
- **Sections:** summary, funnel (pipeline now; tap a bar → those leads), visits, sources, team, WhatsApp, templates, collection, lost, call heatmap.
- **Scope:** reports run **as the viewer**, so each person counts only leads they can see. Managers can pick one person or a course.
- **Charts:** hand-built (no chart library). The web shows a dashboard grid.
- **Home card:** this month.

## 27. Credits, leaderboard, milestones, weekly scorecard

**Credits**
- **Rule sets:** points per activity with daily caps, versioned with `effective_from`.
- **Kinds:**
  - calls: call, connected, talk minute, incoming
  - WhatsApp and templates: wa_message, wa_call, template
  - notes and follow-ups: note, voice, follow-up set, follow-up on time
  - leads: lead added, imported, stage forward
  - visits and admission: visit planned / done, paper, admitted (AI share), payment (per ৳1,000)
  - app time, overdue penalty
- **Calculation:** worked out from the activity data already stored (no separate event table).
- **"retro" setting:** re-apply new rules to past days, or keep old days on the old rules.
- **Super Admin:** manual adjustments (logged); hide a person from the leaderboard.

**Leaderboard**
- Podium, own rank, streaks, levels; tap for a breakdown.
- **Winner announcement:** e.g. Friday 14:00.
- **Rank notices:** "You are now #2"; a nudge at 16:00 when close to the next rank.
- **Home:** Rank card and streak chip.

**Milestones**
- 10 levels: Starter 100 → Legend 100,000.
- **Badges** over the last 365 days: calls100, talk2h, early bird, fast responder, leads10, notes30, wa50, admit5, visits5, money50k…

**Weekly scorecard**
- Saturday–Friday week vs the previous week, per person.
- Metrics: leads, calls, connected, admissions, money, response time, missed follow-ups.
- Admins notified on Sunday.
- Phone: cards. Web: sortable table with Excel.

## 28. Alumni, referrals, public forms

**Alumni records**
- **Fields:**
  - contact: name, phone, WhatsApp, email, photo
  - study: course, batch, session, passing year, student ID
  - work and place: workplace, designation, district, upazila, address
  - other: tags, notes, owner, do-not-contact, link to the lead
  - **ref code:** 6 characters, without confusing letters
- **Custom fields:** text, long text, number, date, select, phone, email, url, yes/no; required, show in list, order.
- **Events:** notes, calls, messages.

**Screens**
- List: search, filters, select many, bulk course / batch, delete.
- Detail and edit.
- **Import:** from Students (by batch or course), from Excel / CSV (dedupe by phone), from phone contacts (groups).

**Referrals**
- An alumnus refers a friend into the **Referral inbox**.
- Inbox actions: import as a lead (course, assignee), credit to an existing lead, or reject.
- A referral can also be added from a lead page.

**Rewards**
- Created automatically when a referred lead is admitted; cancelled if the admission is cancelled.
- Amount: a default, or per course.
- Status, payment method, note.

**Public pages** (web, no login)
- `/refer/<code>`: a friend submits name, phone and course → referral inbox.
- `/apply`: a website application → a new lead (source "Website form"), or a line on an existing lead. With `?ref=` it counts as a referral.
- **Rate limits:** a number at most 3× per hour; the site at most 60 forms per 10 min.
- Each form can be switched on or off.
- Page text is in Bangla.

**Who:** view and manage, each a "who" rule.

## 29. Feedback chat, crashes, speed check, app versions

**Chat with the developer**
- One chat per person.
- **Topics:** problem / idea / question, with statuses.
- Replies, reactions, delete own within 5 min, seen ticks and typing (Realtime).
- **Attachments:** up to 3 pictures and 1 voice.
- **Three-finger tap:** screenshot → new problem report.
- **Solved topics:** files cleaned up after 90 days.
- **Developer inbox:** chats, topics, crashes.

**Crash reporting**
- JS global handler and error boundaries, plus native Android crashes.
- **Signature dedupe;** up to 20 queued offline, sent with the current screen.
- A solved crash reopens on a newer version.

**Speed check**
- Every request is timed; a test runs the usual requests.
- Shows average and slowest per request. Can send the result to the developer.

**App versions (admins)**
- Each person's phones: build, OTA update, channel, last opened.
- Flags old updates; "ask to update" sends a notification.

**OTA updates**
- **Banner:** "A new version is ready · Restart / Later". Checks on open and on returning, at most every 30 min.
- **What's new:** shown once per new entry; full list in More. Every change ships with an entry.
- **Old Play builds** without Firebase are told to reinstall from the Play Store.

## 30. Home, More, Settings hub

**Home (phone)**
- **Top bar:** logo, streak chip, 🔔, avatar.
- **Cards and banners, top to bottom:**
  1. store-update card
  2. **Today stats:** calls due, talk time, new leads, admitted, visits, money (team view for admins)
  3. rank card
  4. banners: sync nudge, sign-ups waiting, discount requests
  5. Today's visits, Today's calls, 🔮 Call these first, Recent
  6. Students summary, admission-flow card, report card
  7. quick actions
- **FAB:** "Add a lead".
- The **website** opens on Students instead.

**More**
- **Top:** profile card; tiles for Alerts, WhatsApp, Team activity / Templates, Discounts.
- **ALUMNI:** Alumni, Referral inbox.
- **REPORTS:** Reports, Admission Contribution, Leaderboard, Weekly scorecard.
- **TOOLS:** Call log sync, Phone contacts, Templates, Export my work, WhatsApp calls.
- **TEAM:** Team activity, Change log, Sync health.
- **ADMIN:** Users, Settings, Push health, App versions.
- **APP:** list design, Appearance, What's new, Version and update check.
- **HELP:** Contact developer, Speed check, Notification check.
- Sign out.

**Settings hub** (`settings.manage`)
- **ADMISSIONS:** Courses & batches, Students tab, Lead score, Alumni, Admission flow, Fee & discount (incl. payments, methods, receipt design, reminders), Admission rules, Student ID rules, Required papers, Paper types.
- **LEADS:** Pipeline stages, Credits & leaderboard, AI, Reports, Pipeline board, Campus visit, lists (sources, campaigns, lost reasons, call results, tags, lead types), Lead cards, Lead filters.
- **OFFICE:** Working days & holidays.
- **DATA:** Import, Export, Google Drive, Message templates, Phone contacts access.
- **TEAM:** Website access, Users, Roles (Super Admin), Lead assignment, Call log sync, Double-call warning, Call lock, Notifications, Team activity, Sync health.
- **Web only:** Upload rules, Photo Studio.

**`app_settings` keys** (all need to be per institution)

| Area | Keys |
|---|---|
| Team and reports | activity, reports, scorecard, credits, credit_extras, notifications, web |
| Admission and students | admission, admission_approval, students, files, upload_rules, photo_presets |
| Fees | fees (incl. payments, receipt, reminders), receipt_prefix |
| Leads | assignment, board, lead_cards, lead_filters, lead_score, campus_visit, message_templates |
| Calls and contacts | call_sync, call_lock, double_call, contacts_import |
| AI | ai_chance, ai_credit, ai_providers |
| Alumni and forms | alumni, public_forms |
| Office calendar | working_days, working_hours, quiet_hours |
| Single values | institution_name, developer_email, min_app_version, speed_to_lead_minutes, early_reminder_minutes, repeat_reminder_minutes, escalate_team_lead_hours, escalate_admin_hours |

- **Unused legacy:** max_call_attempts, call_log_lock_hours, activity_retention_days, and the `feature_flags` table.

## 31. Website (web version)

- **Same codebase** with a **WebShell**:
  - **Left menu** (narrowable, permission-based): Leads, Students, Alumni, Reports, Team activity, Change log, Admission Contribution, Leaderboard, Scorecard, Contact developer, Upload rules, Photo Studio.
  - **Top bar:** page title, **global search** (Ctrl+K or `/`), `?` for keyboard shortcuts, theme (System / Light / Dark), avatar menu (Speed check, Sign out).
- **Access:** setting `web` (who may use the website; admins always).
- **Leads / Students table:**
  - sortable columns, column chooser, density (comfortable / compact), board view, tick-many with bulk actions, Excel export
  - detail in a right-hand panel, name hover card, copy buttons
  - row ⋯ menu: payment, note, upload paper, flow steps, section, board ID, student ID, fee change, papers popup, all notes
  - KPI cards
- **Live approval toast:** officers see a badge and a note when students become ready.
- **Other web screens:** Team activity, Change log (restore, Excel), wide reports and scorecard, Photo Studio.
- **Stale build after deploy:** the page reloads by itself (chunk errors); missing assets return 404.
- **Hosting:** cPanel via FTP, deployed by a GitHub Action on push to main.

## 32. Native Android module

`modules/call-log` (Kotlin, Expo module):
- **Permissions:** READ_CALL_LOG, READ_PHONE_STATE, POST_NOTIFICATIONS, SYSTEM_ALERT_WINDOW, plus Notification access (WhatsApp).
- **Call-end receiver and worker:** captures calls about 6 s and 40 s after a call ends, plus a 15-min safety job.
- **Queue:** only BD mobile numbers, stored as SHA-256 hashes; SIM filter.
- **Lead directory:** on-phone, offline. Feeds the **caller card overlay** on the call screen (lead name, stage, last note…) and the "add a note" / "incoming lead" notifications. Deep link `leadmanagement://leads/<id>`.
- **Call lock:** device key.
- **WhatsApp listener:** WhatsApp and WhatsApp Business; never reads text.
- **Contact groups**, **native crash capture**.
- **JS API:**
  - device and permissions: getDeviceId, getPermissions
  - sync: setEnabled, getSims / setSimFilter, captureNow, getPending, removePending, recentCalls
  - directory: setLeadDirectory
  - caller card: get / setCallerCard, previewCallerCard
  - call lock: setCallLock
  - WhatsApp: getWhatsAppStatus, setWhatsAppEnabled, openNotificationAccess, getWhatsAppPending
  - contacts: getContactGroups
  - crashes: takeNativeCrashes
- **Google Play:** needs the call-log permission declaration and a Data Safety form.

## 33. Background jobs (pg_cron)

| Job | Every | Does |
|---|---|---|
| lead-notifications (`notifications_tick`) | 1 min | Pushes held by quiet hours, follow-up reminders, visit reminders, speed-to-lead escalation, cleanup (60 days) |
| push-followup | 1 min | Expo push receipts, remove dead tokens |
| fee-discounts | 15 min | Expire approved discounts |
| fee-payments | hourly | Installment reminders and late alerts |
| credit-tick / credit-level-tick | 15 min / hourly | Winners, rank notices, nudges, level-up notices |
| weekly-scorecard | hourly | Sends Sunday 9:00 |
| lead-scores-nightly | 02:10 | Recalculate scores |
| held-calls-cleanup, call-lock-clean | daily / periodic | Housekeeping |
| ai-* kicks | 2 min | Wake the AI Edge Functions when work is waiting (x-cron-secret header) |
| AI daily run | hourly check | Queue the daily AI run at the chosen hour |

**In the new app,** every job must run per institution, in that institution's time zone.

## 34. Theming, offline, caching, speed

- **Theme:**
  - Light and dark palettes; brand blue `#3557D4`; hot / warm / cold colours.
  - Material 3 tonal containers on Home, More and Alumni.
  - Phone: Appearance System / Light / Dark (restarts the app). Web: theme picker.
- **Offline:**
  - "No internet" strip, then "✓ Back online".
  - Activity, crash, call and WhatsApp queues work offline.
- **Caching:**
  - In-memory request memo with TTL.
  - Per-user AsyncStorage cache for **instant open** of Home, Leads and Students (stale-while-revalidate).
  - Cleared on sign-out or user switch.
- **Speed techniques that worked:**
  - RLS init-plans and child-policy fixes, indexes
  - one RPC for all Home numbers, a counts RPC for chips
  - page size 30, lazy board columns
  - lead page and peek loads trimmed
  - `set jit = off` on heavy report functions (JIT added about 800 ms)
- **Rule from the owner: the app must never get slower.** Measure before and after; benchmark with about 3,000 leads.

## 35. Build, release, deploy

- **App identity:**
  - A neutral product name, its own Android package and deep-link scheme.
  - `runtimeVersion` is pinned; changing it needs a new store build.
- **EAS profiles:**
  - development: dev client APK
  - preview: APK, channel `preview`
  - production: AAB, channel `production`
  - production-apk
- **GitHub Actions:**
  - `app-update.yml` (manual): choose Database + app / App only / Database only. Runs `supabase db push`, optionally `functions deploy <names>`, then `eas update --channel production`.
  - `build-android.yml`: local EAS build on GitHub runners. `google-services.json` comes from a base64 secret, and the job checks that Firebase is inside the build.
  - `deploy-web.yml`: web export plus MediaPipe assets, FTPS upload.
- **Secrets** (never in code or chat):
  - Expo token, Supabase access token, DB password, project ref
  - FTP credentials, the Firebase file, the keystore
  - AI keys (only in the app's Settings, stored server-side)
- **Release flow:** each change is one PR with a "What's new" entry. The deploy type is stated: database / Edge Functions / app update / new store build.

## 36. Everything that must be configurable per institution

Never hard-code any of these. The earlier version hard-coded them for one college, and each one had to be found later.

- **Branding:** institution name, short name, logo, colours. Used on login, web shell, Home top bar, receipts,
  tab titles, permission texts, public forms and the native WhatsApp listener label.
- **Product-level (not per institution):** app name, domain, privacy page contact, and the developer / feedback
  inbox owner (the Master Admin side).
- **External board flow:** step names, board ID label, admission-fee default, on/off.
- **Reset password format:** generic (no institution prefix), or based on the short name.
- **Locale:** defaults are for Bangladesh, but each must be a setting.
  - time zone `Asia/Dhaka`
  - currency ৳
  - phone rules (`880`, 01XXXXXXXXX)
  - week Saturday–Friday, Friday off, scorecard day Sunday
  - Bangla templates and public forms, payment methods bKash / Nagad / Rocket, address placeholders
- **Lead score:** rules must reference stage kinds or ids, not hard-coded stage keys.
- **Everything else per tenant:** settings, roles, setup, counters (receipts, refunds, student IDs), Drive
  connection, iLovePDF / remove.bg accounts, AI keys.

## 37. Lessons learned (do not repeat these mistakes)

1. **Invoker functions calling locked functions:**
   - A `SECURITY INVOKER` read function called a helper revoked from `authenticated`.
   - Result: "permission denied", and every AI card was **empty for every user**.
   - **Test every RPC as a real signed-in role**, not as the database owner.
   - Run a sweep that finds invoker functions or triggers calling functions the role can't execute.
   - Show load errors in the UI instead of rendering nothing.
2. **Queue bugs found in review:**
   - wrong daily-limit counting
   - a manual check while work was in progress being pushed to tomorrow
   - endless re-claiming of stuck items (billed every 10 min)
   - immediate retries
   - kicks that woke the server with nothing it could do
   - **Design queues with attempts, back-off, "given up", and kicks that check feasibility.**
3. **Edge Function time limit (150 s):**
   - Keep each AI call ≤ 75 s, start new work only for 45 s, and use no SDK retries.
   - Run compare-mode providers **in parallel**.
4. **Postgres JIT** made one report go from 15 ms to 900 ms. Set `jit = off` on heavy plpgsql functions.
5. **External AI providers:**
   - Model lists include **retired models**, so filter them out and self-heal on 404.
   - Free tiers have tight, unpublished quotas.
   - Record every provider problem where an admin can see it.
   - Never fall back silently without a note.
6. **Cost display:** estimates must use the **model actually chosen** (and $0 for free providers). Otherwise budgets stop work wrongly and admins are misled.
7. **Old app versions stay in the field after each update:**
   - Derive server decisions (e.g. institution, permissions) from the user's profile, not from what the client sends.
   - Keep RPC signatures backward compatible, or add new ones.
8. **Speed:**
   - Every new list badge or chip is a potential extra request per row. Batch into one RPC.
   - Denormalise counters with triggers.
   - Cache with stale-while-revalidate.
9. **Phone duplicates:** check across all leads, even invisible ones (via a DEFINER function), but only reveal name, stage and owner.
10. **Soft delete plus an append-only timeline** made "restore" and audits easy. Keep that pattern.
11. **Google Play:**
    - Call-log permission declaration and an account-deletion web path are required.
    - FCM needs `google-services.json` in the build.
    - Pre-launch test devices pollute push stats.
12. **Never commit secrets:**
    - Firebase JSON, google-services.json, .env, keystore, Apps Script secret, tokens.
    - API keys are entered by admins in the app and stored server-side; the app only sees a hint.

## 38. Open decisions for the owner

1. Can one person belong to **more than one institution**? Simplest: one email = one institution.
2. **Who may create an institution?** Self sign-up with Master Admin approval, or the Master Admin only?
3. **How to pick the institution at login:** search by name, College Code or EIIN (recommended, so the customer list stays private), or a list?
4. **AI keys and Google Drive:** each institution brings its own, or the platform's shared ones (who pays)?
5. **Product name, app name, domain:** e.g. one domain with `/<slug>`, or per-institution subdomains?
6. **Billing / subscription plans** for institutions, now or later? Keep a plan/expiry field from day one.
7. Should the **external board flow** be included from the start, and which languages should the UI support besides English and Bangla?
8. **Lead merge** (merging duplicate leads) was planned in the earlier version but never shipped. Include it?

---

## 39. Planning round 1: additions, decisions and proposals

> **বাংলা সারাংশ:** পরিকল্পনার আলোচনায় যা যোগ হয়েছে আর ঠিক হয়েছে: ইমেইল ও SMS নোটিফিকেশন,
> Google ও OTP লগইন, আর প্রতিটি কলেজের আলাদা SMS ও ইমেইল সেটআপ, যা Master Admin প্যানেল থেকে করা হবে।
> কোন নোটিফিকেশন কোন মাধ্যমে যাবে তা Master Admin ঠিক করবেন, টেমপ্লেট কলেজ লিখবে,
> আর Master Admin প্রতিটি কলেজের কাছ থেকে SMS খরচ আলাদাভাবে নেবেন।
> "Proposed" লেখা অংশগুলো এখনো মালিকের অনুমোদনের অপেক্ষায়।

**Status keys:** **Decided** = the owner approved it. **Proposed** = suggested during planning, still needs the owner's approval.

### 39.1 Owner decisions so far (Decided)

| # | Decision |
|---|---|
| D1 | The app gets **email and SMS notifications**, in addition to the in-app inbox and push. |
| D2 | Login also supports **"Sign in with Google"** and **OTP** (one-time code). |
| D3 | Each institution has its **own SMS gateway and transactional email** setup, and the setup must be easy. |
| D4 | SMS and email settings live in the **Master Admin panel**. The Master Admin sets them up **separately for each institution**. |
| D5 | The **Master Admin** decides which notification kind goes through which channel (inbox / push / email / SMS). |
| D6 | **Message template text** (SMS / WhatsApp / email) is written by each **institution**. |
| D7 | The Master Admin **charges each institution for SMS separately**, so per-institution usage and billing reports are needed. |

### 39.2 Login: Google and OTP (D2)

- **Methods:**
  - email + password (as in section 5)
  - **Sign in with Google**: one Google OAuth client for the whole product (platform level). Institutions set up nothing.
  - **OTP**: SMS code to the phone, or code to the email (Supabase Auth). *Proposed:* offer both.
- **Proposed:** each institution can switch each method on or off.
- **Access rules:**
  - A Google or OTP sign-in never grants access by itself.
  - If the email or phone matches a user the institution's admin already added → they sign in.
  - Otherwise → an **inactive "pending approval"** profile, like sign-up in section 5.
- **Institution detection:** the server finds the institution from the email or phone on the profile,
  never from what the client sends (see 37.7). *Proposed:* this relies on "one email / phone = one institution" (38.1).
- **OTP SMS** is sent through **that institution's SMS gateway** (39.3), found from the phone number.
  If the institution has none, the platform gateway is used, if the Master Admin allows it.
- **OTP safety:** codes expire after 5 minutes; limited sends per number per hour; lock after 5 wrong codes.
- **Changes to section 5:**
  - **Account deletion:** users without a password (Google / OTP) confirm with an OTP instead of their password.
  - **Admin reset password:** applies only to password users.
  - **Proposed:** OTP enables self-service "forgot password" (section 5 currently has none).

### 39.3 Per-institution SMS and transactional email (D3, D4)

Lives in **Master Admin panel → Institutions → \<institution\> → Messaging**.

**All-institutions overview**
- One row per institution: SMS status, email status (on / not set up / problem), low balance,
  this month's sends, last problem. Problems first.

**SMS setup (per institution)**
- **Provider presets** for common Bangladeshi SMS gateways (exact list to be confirmed with the owner),
  plus a **"Custom HTTP"** option: URL, method, parameters with placeholders such as `{to}`, `{message}`,
  `{sender_id}`, and how to detect success. Any gateway can be connected this way.
- Sender ID / masking.
- Bangla (Unicode, 70 characters per part) and English (160 per part). The part count and cost are shown before sending.
- **Test SMS** button; balance check where the provider supports it.
- Cost per SMS part (used for billing, 39.5).

**Email setup (per institution)**
- **SMTP** (e.g. Gmail app password, cPanel mail), or an **API provider** (e.g. Resend, Brevo, SendGrid, Mailgun, Amazon SES).
- From name, from address, reply-to.
- **Domain check** with step-by-step SPF / DKIM guidance and a "Verify" button.
- **Test email** button.
- **Platform default mail:** used when an institution has no email setup, within limits.

**Shared rules**
- **Monthly limits** per institution, set by the Master Admin.
  - When reached, bulk sends stop; OTP and urgent messages still go.
- **"Copy setup from another institution"** for institutions on the same provider.
- **Fallback per institution:** use the platform gateway, or send nothing.
- **Secrets:**
  - API keys and passwords are encrypted, stored only on the server (e.g. Supabase Vault) and writable only by the Master Admin.
  - Screens show only a hint such as `key…ab12` (see 37.12).
- **Audit:** every Master Admin change is written to an audit log.
- **Problems:** each channel's last error (wrong key, balance out, bounce) is shown in the Master Admin panel (see 37.5).
- **Delivery log:** recipient, time, channel, template, result, provider message id, cost.

**What the institution sees**
- The institution's Super Admin **does not see** keys or provider settings.
- They only see status (e.g. "SMS: on ✓") and this month's usage.

### 39.4 Email and SMS notifications (D1, D5, D6)

- **Channels per notification kind** (section 25): inbox, push, email, SMS. **Set by the Master Admin** for each institution (D5).
  Example defaults:

  | Kind | Channels |
  |---|---|
  | assigned | inbox + push |
  | speed_to_lead escalation | push, then SMS |
  | payment due / late | email + SMS |
  | weekly scorecard | email |

- **Proposed:** users may mute non-urgent channels for themselves. Kinds marked "urgent" can't be muted.
- Quiet hours (section 10) also apply to SMS. Dedupe per user and kind, as in section 25.
- **Sending pipeline:**
  - All email and SMS go through an **outbox table** with attempts, back-off and a "given up" state (see 37.2).
  - A worker (Edge Function, woken by pg_cron) runs per institution in that institution's time zone.
- **Templates (D6):**
  - Section 15 templates get a third channel: **email** (subject + body).
  - The institution writes the text; the variables are the same as in section 15.
- **Proposed: messages to leads, students and guardians:**
  - welcome after admission
  - payment receipt
  - installment due reminder
  - campus visit reminder
- **Proposed: bulk SMS campaigns** to filtered leads:
  - cost estimate before sending
  - respects `do-not-contact` and opt-out
  - Bangladesh rules for promotional SMS to be checked before building

### 39.5 SMS billing per institution (D7)

- **Usage ledger** per institution, per day and channel: SMS parts sent, failed, and cost at the gateway's per-part price.
- **Monthly statement per institution** in the Master Admin panel: totals, by kind (OTP / notification / template / bulk), export to Excel / PDF.
- The institution's Super Admin sees their own monthly usage (not the gateway's price, unless the Master Admin chooses to show it).
- *Proposed:* keep `plan`, `expires_at` and billing fields on the institution from day one (see 38.6).

### 39.6 Corrections to earlier sections (Proposed)

| # | Section | Issue | Proposal |
|---|---|---|---|
| C1 | 2, 38.1 | Login asks for the institution first. If one email = one institution, the server already knows it. | Use "one email / phone = one institution" and drop the picker. The server takes the institution from the profile (37.7). |
| C2 | 3 | The heading says "Recommended" but the table says "Current choice". | State clearly that this stack is the stack for the new app. |
| C3 | 13 | Notes are one text blob on the lead. This conflicts with the append-only timeline (37.10). | Use a separate `notes` table (one row per note) for restore, edits and reports. |
| C4 | 2 vs 28 | `/apply/<slug>` in one place, `/apply` in another. | Use `/apply/<slug>` everywhere. |
| C5 | 16, 30 | Legacy items: `call_results`, `document_types`, `feature_flags`, unused setting keys. | Leave them out of the new app. |
| C6 | 23.3 | AI model prices are written into the code. | Keep prices in config and check them at build time. |
| C7 | 3, 37 | About 418 `SECURITY DEFINER` functions in the earlier version. | `SECURITY INVOKER` + RLS by default. Any DEFINER checks the institution. The cross-tenant leak test exists from day one. |
| C8 | 32 | Google Play allows `READ_CALL_LOG` only to default dialers or approved exceptions, and a new package needs a new declaration. | Build the native module in a later phase, and confirm the Play policy first. |

### 39.7 Answers to section 38 (Proposed)

1. One email / phone = one institution.
2. Institutions sign up themselves; the Master Admin approves.
3. No institution picker at login (follows from 1).
4. AI keys and Drive: each institution brings its own. SMS and email are set up by the Master Admin (39.3).
5. One domain with `/<slug>`.
6. No billing screens yet, but `plan` / `expires_at` fields from day one. SMS billing as in 39.5.
7. External board flow in phase 2, switchable on/off. UI languages: English and Bangla.
8. Lead merge at the end of phase 1 or in phase 2.

### 39.8 Build phases (Proposed, replaced by 42.1)

| Phase | Contents |
|---|---|
| 0: Foundation | Multi-tenant schema + RLS, Master Admin panel, institution setup, login (password, **Google, OTP**), roles / permissions / users, cross-tenant leak test, **per-institution SMS and email setup (39.3)** |
| 1: Core CRM | Leads, list / board / search / filters, pipeline, follow-ups, manual call log, notes, templates (incl. email), import / export, notifications (inbox / push / **email / SMS**, outbox), web version |
| 2: Admission and students | Courses / batches, admit, papers, fees and discounts, payments and receipts, student IDs, external board flow, **receipt and installment messages to students**, **bulk SMS**, SMS billing statements |
| 3: Android native | Call-log sync, WhatsApp, caller card, call lock |
| 4: AI and team | Admission chance, admission credit, leaderboard, scorecard, team activity |
| 5: Everything else | Alumni and referrals, public forms, Google Drive, Photo Studio, feedback chat, crash reports |

### 39.9 Still open

1. Who receives email / SMS: staff only, or also leads, students and guardians?
2. Google sign-in: only users already added by an admin, or may new people sign in (pending approval)?
3. Which SMS gateways do the institutions use? (Needed for the presets.)
4. Are bulk / promotional SMS campaigns needed?
5. OTP: by SMS, by email, or both?

---

## 40. Fitting each institution type

> **বাংলা সারাংশ:** স্কুল, কলেজ, বিশ্ববিদ্যালয়, পলিটেকনিক, মাদ্রাসা, কোচিং, ট্রেনিং সেন্টার, এদের প্রত্যেকের
> ভর্তির ধরন আলাদা। তাই সেটআপের সময় প্রতিষ্ঠানের ধরন বাছাই করলে সেই ধরনের উপযোগী শব্দ, ধাপ, ফি,
> কাগজপত্র আর ফিল্ড আপনা-আপনি বসে যাবে, পরে সব বদলানো যাবে। নতুন কিছু সাধারণ ফিচারও যোগ হয়েছে:
> ভর্তি পরীক্ষা ও মেধাতালিকা, যোগ্যতার নিয়ম, মাসিক/সেমিস্টার ফি, বৃত্তি ও ছাড়ের নিয়ম, অভিভাবক ও ভাইবোন,
> শাখা (ক্যাম্পাস), আর মডিউল চালু/বন্ধ। সব অংশ **Proposed**।

### 40.1 The idea: one product, many shapes

Each institution type admits students differently. The product must fit all of them **without a separate
codebase or hard-coded branches**. The tools for that:

1. **Institution type profile** picked at setup (40.3). It **seeds** sensible defaults; everything stays editable.
2. **Terminology (labels)** per institution (40.4): "Course" can be "Class", "Program", "Department" or "Technology".
3. **Modules** switched on or off per institution (40.5).
4. **Custom fields** on leads and students, with presets per type (40.6).
5. **Generic building blocks** that cover every type's needs (40.7–40.14), instead of type-specific code.

> Rule for the developer: code checks **settings and modules**, never `institution_type`. The type is only used
> once, to seed defaults. This keeps one codebase and lets a mixed institution (e.g. school + college) work.

### 40.2 Institution types and what they need

| Type | How admission works | Main differences |
|---|---|---|
| **School** (primary / secondary) | Per class (Play–Class 10). Admission test or lottery for some classes. Session usually January–December. | The **guardian** is the main contact (the student is a child). **Monthly tuition** plus admission and session fees. Age rule per class, birth certificate. Shift (morning / day), version (Bangla / English), sibling discount, transport. |
| **College** (HSC, Degree, Honours, Masters) | HSC: class XI through the central online system, then confirmation. Degree / Honours / Masters: affiliated university (e.g. National University) merit lists. | Group (Science / Humanities / Business Studies). SSC / HSC **GPA, board, roll and registration numbers**. External board flow (section 22). Yearly or session fees. |
| **Private university** | Several intakes per year (e.g. Spring / Summer / Fall). Admission test and viva. | **Per-credit or per-semester fees**, **result-based waivers**, credit transfer, department and program. Very lead-heavy marketing. |
| **Polytechnic / technical institute** | Per technology (department), 4-year diploma, shift. | Board registration (e.g. BTEB) as the external flow, semester fees, SSC GPA rules. |
| **Madrasa** (Alia / Qawmi) | Per class level (e.g. Ebtedayee, Dakhil, Alim; Qawmi levels). | Madrasa board registration as the external flow, residential (**hostel**) fees, often separate boys' and girls' sections. |
| **English-medium school** | Per grade, admission test and interview. | O / A level board registration (e.g. Edexcel / Cambridge) as the external flow, higher monthly fees, development fees. |
| **Coaching centre** | Rolling: new batches every few weeks, quick enrolment. | **Short courses, many small batches**, monthly or package fees, high Facebook-ad lead volume, quick follow-up matters most. |
| **Training / skills institute** | Course with start dates, often online. | Certificates, short courses, installments, corporate clients (one company sends many trainees). |
| **Nursing / medical / health institute** | Session-based, merit list from a central body. | Strict eligibility (subjects, GPA), many required papers, hostel. |

### 40.3 Institution type profile (seed templates)

At institution setup the Super Admin (or Master Admin) picks one or more types. The profile seeds:

| What is seeded | Example: School | Example: Coaching centre |
|---|---|---|
| Labels (40.4) | Class, Section, Session, Roll | Course, Batch, Month, Student no. |
| Pipeline stages (section 9) | New → Contacted → Visit → Admission test → Result → Ready → Admitted / Lost | New → Called → Demo class → Enrolled / Lost |
| Required papers (section 17) | Birth certificate, previous school TC, photos, guardian NID | Photo only |
| Fee structure (40.9) | Admission fee + monthly tuition + session fee | Package fee or monthly fee |
| Lead custom fields (40.6) | Child's date of birth, previous school, desired class, shift | Current class / job, preferred time |
| External board flow (section 22) | Off | Off |
| Message templates (section 15) | Admission test date, result, monthly fee due | Demo class reminder, batch start |
| Student ID pattern (section 19) | `{YYYY}{CLASS}{000}` | `{CODE}-{000}` |
| Lead score points (section 14) | Visit and test weigh most | Demo class weighs most |

- Profiles are **versioned data** (rows in a `type_profiles` table), editable by the Master Admin, not code.
- After seeding, the institution changes anything. "Reset to profile defaults" is offered per area, with a preview.
- A **mixed institution** (e.g. school and college on one campus) picks several types; the seeds are merged, and
  courses / classes are grouped by type.

### 40.4 Terminology (labels)

- A per-institution **label dictionary**, in English and Bangla. Keys and examples:

  | Key | Default | School | University | Polytechnic |
  |---|---|---|---|---|
  | `course` | Course | Class | Program | Technology |
  | `batch` | Batch | Session | Intake | Session |
  | `section` | Section | Section | Section | Group / Shift |
  | `student_id` | Student ID | Roll / ID | Student ID | Roll |
  | `lead` | Lead | Enquiry | Applicant | Applicant |
  | `admission` | Admission | Admission | Enrolment | Admission |

- Every screen, report, export header, template variable name and notification text uses the label, never a fixed word.
- The Master Admin edits the defaults; each institution can override.

### 40.5 Modules (switch whole features on or off)

Each institution has a list of **modules**. The Master Admin decides which modules an institution may use
(for example by plan, 42.3); the institution's Super Admin turns allowed modules on or off.

| Module | Sections | Typical users |
|---|---|---|
| Core leads and follow-ups | 6–10 | everyone (always on) |
| Calls and Android call sync | 11 | institutions with a calling team |
| WhatsApp logging | 12 | most |
| Campus visits | 14 | schools, colleges, universities |
| Admission test and merit list | 40.8 | schools, universities, some colleges |
| Fees, payments, receipts | 20–21 | most |
| Student IDs | 19 | most |
| External board flow | 22 | colleges, polytechnics, madrasas, English-medium |
| Hostel and transport | 40.9 | madrasas, schools, nursing |
| AI | 23–24 | larger institutions |
| Credits and leaderboard | 27 | institutions with a calling team |
| Alumni and referrals | 28 | colleges, universities, coaching |
| Google Drive files and Photo Studio | 17–18 | institutions that collect papers online |
| Public application form | 28, 40.11 | everyone |
| Bulk SMS | 39.4 | everyone (paid per SMS) |

- A switched-off module disappears from menus, Home cards, filters, reports and settings, and its background jobs skip that institution.
- Data is kept when a module is switched off and comes back when it is switched on again.

### 40.6 Custom fields with presets

- Section 28 already has custom fields for alumni. The same **field builder** is used for **leads** and **students**.
- Field types: text, long text, number, date, select, multi-select, phone, email, URL, yes/no, **GPA** (0–5, two decimals), **file** (paper).
- Options: required, show on card, show in list / table, filterable, searchable, include in export, show on public form, order, group.
- **Presets per type** (seeded by the profile): SSC / HSC GPA, board, roll, registration number, passing year,
  previous institution, date of birth, birth certificate number, guardian NID, guardian occupation, group, shift, version.
- Custom fields can be used in **template variables**, **filters**, **eligibility rules** (40.7) and **reports**.

### 40.7 Eligibility rules

- Per course / class: minimum GPA (overall or per subject), required group, age range on a date
  (e.g. "Class 1: 6+ years on 1 January"), gender, required previous level.
- When a lead's fields don't meet a rule: a warning on the lead page and a filter "Not eligible".
  The setting chooses **warn** or **block admission**.
- Used by the public form to tell applicants early.

### 40.8 Admission test, merit list, waiting list

- **Test sessions:** date, time, venue / room, capacity, courses, fee (optional).
- Register leads to a session; **admit card** (printable, with photo and roll) and SMS / email with the details.
- Record attendance and **marks** (manual entry or Excel import), with a viva mark if needed.
- **Result and merit list** per course: by marks, with tie-break rules; selected / waiting / not selected.
- **Quota seats** (optional): e.g. staff children, siblings, freedom fighters' quota, area. Each quota has seats.
- Publish results: SMS / email to each applicant, and an optional public result page (`/result/<slug>`, roll + date of birth).
- **Waiting list:** when a selected applicant doesn't confirm by a deadline, the next on the list is offered the seat (with a notification to officers).
- Lottery mode (some schools): a recorded, auditable random draw instead of marks.

### 40.9 Fee structures for every type

Section 20–21 assume one total fee per course. Generalise to **fee heads** with a **schedule**:

| Schedule | Example |
|---|---|
| One-time | Admission fee, form fee, ID card |
| Monthly | School tuition, hostel, transport |
| Per term / semester | University semester fee |
| Per credit | Private university: credits × rate |
| Yearly / session | Session fee, development fee |
| Package | Coaching centre course package |

- Each course has fee heads with amount, schedule, due day and late fee rule.
- **Optional heads** chosen per student: hostel, transport (with route), books, uniform, lab.
- **Monthly / term invoices** are generated by a background job per institution, in its time zone.
- **Waivers and scholarships (rules):** result-based (e.g. GPA 5.00 → 50 % of tuition), sibling, staff child,
  quota, merit list rank. Rules apply automatically and need approval above limits (same as section 20).
- **Online payment** (optional module): a payment gateway such as bKash or SSLCommerz for application and
  tuition fees, set up per institution by the Master Admin, the same way as SMS (39.3).
- Due, late and installment reminders (section 21) work for every schedule.

### 40.10 Guardians, families and siblings

- A **guardian** record can link to many leads / students (siblings). Schools treat the guardian as the main contact.
- Duplicate check (section 6) also matches guardian phones, and shows "sibling of …" instead of a plain duplicate.
- Sibling discount rule (40.9) uses this link.
- One message to a guardian can cover all their children (e.g. one fee-due SMS listing each child).

### 40.11 Online application form builder

- The public `/apply/<slug>` form (section 28) becomes **configurable per institution**: which fields (including custom fields), sections, required ones, file uploads (photo, papers), Bangla / English text.
- Optional **application fee** paid online (40.9).
- On submit: a lead is created (or matched), with an SMS / email confirmation and an application number.
- Optional **applicant status page**: application number + phone → current status, test date, result, next step.

### 40.12 Academic calendar and admission windows

- Sessions / intakes with **admission open and close dates** per course.
- Outside the window, the public form shows "Admission closed" (or takes interest for the next intake).
- Reports and leaderboards can be filtered **per admission season**, so years can be compared.
- "Roll over to next session": copy courses, batches and fees to a new session in one step.

### 40.13 Branches and campuses

- An institution can have **branches** (campuses). Optional; off for most.
- `branch_id` exists on leads, students, courses, batches and users **from day one** (nullable), so it can be turned on later without a migration of every table.
- Staff can be limited to branches (like course limits in section 4). Reports and leaderboards per branch.

### 40.14 Language of the UI

- The original brief uses English labels. Many school and madrasa staff prefer **Bangla**.
- Proposed: full **English and Bangla UI**, chosen per user, with the institution's default.
- All texts in translation files from the start; labels (40.4) have both languages.
- Bangla digits optional for receipts and public pages.

---

## 41. Challenges for the Master Admin and the developer

> **বাংলা সারাংশ:** অনেক প্রতিষ্ঠান একসাথে চালাতে গেলে Master Admin (ব্যবসা ও পরিচালনা) আর ডেভেলপার
> (প্রযুক্তি) যেসব সমস্যায় পড়বেন, সেগুলো এখানে আলাদা করে লেখা। প্রতিটির পাশে কেন কঠিন, কীভাবে সামলানো
> যায়, আর কোন ধাপে করতে হবে তা দেওয়া আছে। সব অংশ **Proposed**।

### 41.1 Master Admin challenges (business and operations)

| # | Challenge | Why it is hard | How to handle it | Phase |
|---|---|---|---|---|
| M1 | **Onboarding many institutions** | Each needs setup, courses, fees, staff, SMS, training. Done by hand it does not scale. | Type profiles (40.3), a step-by-step setup checklist with progress, Excel import of courses / staff / old leads, "copy from another institution", short video guides. | 0–1 |
| M2 | **Verifying new institutions** | Self sign-up invites fake or duplicate institutions and SMS abuse. | Master Admin approval (39.7), EIIN / College Code check against duplicates, no SMS / bulk features until approved, trial limits. | 0 |
| M3 | **Every institution wants something special** | Saying yes to each one leads to custom code and a product that can't be maintained. | Only settings, labels, modules, custom fields and profiles; a request log with votes across institutions; build only what several need. | always |
| M4 | **Supporting users inside an institution** | Helping means seeing their data, which raises privacy and trust issues. | "Enter institution" only with a reason, time-limited, read-only by default, fully audited; the institution's Super Admin can see when support entered. | 0 |
| M5 | **Billing and collections** | Plans, SMS usage, renewals, unpaid accounts, invoices, possibly VAT. | Plan and expiry fields from day one, SMS usage ledger (39.5), monthly statements, reminders before expiry, a clear grace period then **read-only mode** (never delete data for non-payment). Prepaid SMS balance per institution is simpler than postpaid. | 0–2 |
| M6 | **SMS and email operations** | Gateways run out of balance, change APIs, go down; masked sender IDs usually need approval; emails land in spam. | Balance and error alerts to the Master Admin, a backup gateway per institution, delivery log, domain check (39.3), test buttons. Check sender ID rules with each gateway. | 0–1 |
| M7 | **Watching the health of all institutions** | Problems in one institution (failed SMS, sync off, AI spend) are invisible until they complain. | Master Admin dashboard: per institution activity, errors, SMS / AI spend, sync health, last login, inactive institutions; alerts. | 1 |
| M8 | **Busy season peaks** | Admission seasons overlap; many institutions are busy at the same time. | Load test before each season, rate limits per institution, queue fairness (41.2 D7), status page, no big releases during peak weeks. | 1+ |
| M9 | **Data protection and children's data** | Schools hold minors' data; leaving institutions want their data; laws may change. | Clear terms and privacy policy, export of all an institution's data, deletion after leaving (with a notice period), access logs, minimal data in AI (section 23). Check current Bangladeshi data protection rules before launch. | 0–2 |
| M10 | **Suspending or offboarding an institution** | Must stop use without losing data or breaking other institutions. | States: trial / active / read-only / suspended / closed. Full export before closing. | 0 |
| M11 | **Communicating with institutions** | Releases, downtime and new features must reach the right people. | Announcements from the Master Admin panel (in-app, email), "What's new" per release, maintenance notices. | 1 |
| M12 | **Master Admin account security** | One stolen Master Admin login exposes every institution. | Very few Master Admins, mandatory 2-factor login, separate login page, IP / device alerts, full audit, no shared accounts. | 0 |
| M13 | **One app vs. each institution's own app** | Some institutions will want their own app name and logo on Play Store. | **Both options are planned (D12):** one shared app showing each institution's branding after login, and a separate branded build (own name, icon, package, Play Store listing) from the same code as a paid option. Each branded app needs its own store listing, signing key, push setup and call-log permission declaration, so it costs more to run. | 0 (shared), 5 (branded) |

### 41.2 Developer challenges (technical)

| # | Challenge | Why it is hard | How to handle it | Phase |
|---|---|---|---|---|
| D1 | **Tenant isolation everywhere** | Not only tables: storage paths, Realtime channels, Edge Functions, cron jobs, push, client caches, exports, logs. One miss leaks data. | `institution_id` on every row, RLS from the JWT claim, INVOKER functions by default, automated **cross-tenant leak test** in CI covering tables, RPCs, storage and Realtime; client caches keyed by institution and user. | 0 |
| D2 | **Configuration explosion** | Types × modules × settings × roles create thousands of combinations to test. | Typed settings with JSON schema validation and defaults, settings versioning and migrations, seed test institutions for each type profile, tests that run the main flows on each. | 0+ |
| D3 | **Labels and two languages** | Hard-coded words creep in everywhere; Bangla text is longer and breaks layouts. | Translation files and label lookup from day one, a lint check for hard-coded UI strings, screenshot tests in both languages. | 0 |
| D4 | **Performance with many tenants** | Thousands of leads per institution × many institutions; one big tenant can slow others. | Indexes starting with `institution_id`, the speed rules in section 34, per-tenant rate limits, benchmark with large and small tenants, watch Supabase plan limits (connections, function calls, storage). Plan a path to move a very large tenant to its own project if ever needed. | 0+ |
| D5 | **Database changes for everyone at once** | One migration changes all institutions; old app versions stay installed (37.7). | Backward-compatible RPCs, expand-then-contract migrations, a minimum app version per release, staged rollout (D12). | 0+ |
| D6 | **Restoring one institution's data** | Supabase backups restore the whole database, not one tenant. | Soft delete + append-only timeline (37.10) for everyday undo; per-institution export snapshots (daily or weekly) for disasters. | 1 |
| D7 | **Background jobs per institution** | Each job must loop institutions in their own time zone and settings; one slow tenant must not block others. | A job scheduler that picks due institutions, processes in small chunks, with attempts, back-off and per-tenant fairness (37.2). | 1 |
| D8 | **Many third-party providers** | SMS gateways, email providers, payment gateways, AI, Drive all differ and fail differently. | One adapter interface per kind (send, check balance, parse result), a Custom HTTP adapter, provider errors stored and shown, test buttons, timeouts. | 0–2 |
| D9 | **Secrets per institution** | Many keys; leaks are costly. | Encrypted storage (e.g. Supabase Vault), only Edge Functions read them, never logged, rotation support, hint-only display. | 0 |
| D10 | **Login variety** | Password, Google, OTP; linking them to one profile; OTP cost and abuse; Google consent screen verification for production. | Supabase Auth with a custom hook that maps email / phone to one profile and institution; rate limits; CAPTCHA on public OTP requests; plan the Google verification early. | 0 |
| D11 | **Android permissions and Play policy** | Call-log permission needs approval; WhatsApp listener and overlays are sensitive. | Build native features in phase 3, submit the permission declaration early, keep the app usable without them. | 3 |
| D12 | **Releasing safely** | A bug ships to every institution at once. | Feature flags per institution, beta institutions first, OTA updates in channels, quick rollback. | 1+ |
| D13 | **Observability** | Errors must be traced to an institution and user. | Logs and crash reports tagged with institution and user ids, an error dashboard, alerts on spikes. | 1 |
| D14 | **Importing each institution's old data** | Every institution's Excel looks different. | Column mapping with saved mappings, Bangla aliases, preview, dry run, undo (section 15). | 1 |
| D15 | **Public pages per institution** | Forms, results, referrals need the right institution, branding and abuse protection. | `/<page>/<slug>` URLs, per-institution branding, rate limits and CAPTCHA; custom domains later. | 1–2 |
| D16 | **Costs per institution** | AI, SMS, storage and function calls must be traceable to who uses them. | Usage ledgers per institution (39.5, 23.3), budgets and limits, a monthly cost view in the Master Admin panel. | 1+ |

---

## 42. Updated build phases and open questions

### 42.1 Build phases (Proposed; replaces 39.8)

| Phase | Contents |
|---|---|
| **0: Foundation** | Multi-tenant schema with `institution_id` and nullable `branch_id`, RLS, cross-tenant leak test in CI. Master Admin panel: institutions, approval, states, support entry (audited), 2-factor login. **Type profiles for all institution types (D8), labels, modules, custom field builder.** **Branches / campuses (D9).** Institution setup wizard and checklist. Per-institution branding inside the shared app (D12). Login (password, Google, OTP). Roles, permissions, users. Per-institution SMS and email setup. English + Bangla UI framework. **Event log and extension framework (43).** **Design system with light / dark tokens (44).** **Integration hub (45.2).** |
| **1: Core CRM** | Leads (with guardians and custom fields), list / board / search / filters, pipeline, follow-ups, manual call log, notes, templates (incl. email), import / export, notifications (inbox, push, email, SMS via outbox), application form builder, academic calendar and admission windows, web version, Master Admin health dashboard and announcements. **Automation rules (43.2).** |
| **2: Admission and students** | Courses / classes, batches / sessions, **eligibility rules**, **admission test and merit list**, admit, papers, **fee heads and schedules**, waivers and scholarships, payments, receipts, invoices, **online payment (D11)**, student IDs, external board flow, student messages, bulk SMS, SMS billing statements, hostel and transport. **Custom records, webhooks and API (43.2).** |
| **3: Android native** | Call-log sync, WhatsApp, caller card, call lock. |
| **4: AI and team** | Admission chance, admission credit, leaderboard, scorecard, team activity. |
| **5: Everything else** | Alumni and referrals, Google Drive, Photo Studio, feedback chat, crash reports, applicant status page, **separate branded apps per institution (D12)**, guardian / student portal (if wanted later, D10). |

### 42.2 Institution types in the first release (Decided: D8)

**All types** in 40.2 are supported from the first release: school, college, private university, polytechnic,
madrasa, English-medium school, coaching centre, training institute, nursing / medical / health institute.

- Each type gets a **type profile** (40.3) in phase 0, built only from the generic blocks (40.4–40.14), with no type-specific code.
- Each profile gets a **seeded test institution** and runs the main flows in CI (41.2 D2).
- **Risk:** supporting every type at once makes the first release bigger. Mitigation: the blocks a type needs
  (e.g. merit list, per-credit fees) are switched off by module until they are built and tested; the profile still works for leads and follow-ups.

### 42.3 Plans and modules (Proposed)

| Plan | For | Modules |
|---|---|---|
| Starter | small coaching centres, schools | Core leads, follow-ups, templates, public form, fees and payments |
| Standard | most colleges and schools | Starter + calls, WhatsApp, visits, admission test, student IDs, board flow, reports |
| Pro | large institutions | Standard + AI, credits and leaderboard, alumni, Drive, branches |

SMS and AI usage are billed on top (39.5). Prices and exact module lists are the owner's decision.

### 42.4 Questions asked in round 2 (answered in 42.5)

1. Which institution types should the **first release** support? (Proposed in 42.2: college, school, coaching.)
2. Are **branches / campuses** needed in the first release, or later?
3. Is a **guardian / student portal** wanted (see fees, receipts, results), and when?
4. Is **online payment** (bKash, SSLCommerz or other) needed, and in which phase?
5. Should institutions be able to get **their own branded app** on Play Store?
6. Should the UI be **fully Bangla and English** (40.14), or English labels only as in the original brief?
7. Plans and pricing: are the three plans in 42.3 close to what you want?
8. Still open from 39.9: who receives email / SMS, Google sign-in for new people, which SMS gateways, bulk SMS, OTP by SMS / email / both.

### 42.5 Owner decisions, planning round 2 (Decided)

| # | Question (42.4) | Decision |
|---|---|---|
| D8 | Institution types in the first release | **All types** (see 42.2). |
| D9 | Branches / campuses in the first release | **Yes.** Branches move from phase 5 to phase 0 (40.13). |
| D10 | Guardian / student portal | **Not for now.** Kept as a possible later item. |
| D11 | Online payment | **Yes.** Set up per institution by the Master Admin, like SMS (39.3). In phase 2 with fees. |
| D12 | Own branded app per institution | **Keep both options:** the shared app with per-institution branding, and a separate branded app (paid option). |
| D13 | Full Bangla and English UI | **Yes** (40.14). Each user picks; the institution sets the default. |
| — | Plans (42.3) | Explained to the owner; **still open**. |

**Online payment details (D11, Proposed):**
- Gateways: e.g. bKash, Nagad, SSLCommerz (the list to be confirmed), with an adapter per gateway (41.2 D8).
- Set up per institution in **Master Admin panel → Institutions → \<institution\> → Payments**, with test mode, keys in the Vault, and a test payment button.
- Used for: application fee (public form), admission fee, monthly / term fees, installments.
- A successful online payment creates the payment and receipt automatically (section 21); a failed or pending one is shown with its status.
- Reconciliation: a daily check against the gateway; mismatches go to a list for the officer.
- Refunds through the gateway where supported; otherwise recorded by hand (section 21).

**Branches details (D9, Proposed):**
- Settings → Branches: name, address, phone, branch head.
- Courses, batches, staff and leads can belong to a branch; staff can be limited to branches.
- Receipts, templates and public forms can show branch details.
- Reports, leaderboards and the Master Admin dashboard can be split by branch.

### 42.6 Still open after round 2

1. Plans and pricing (42.3).
2. From 39.9: who receives email / SMS, Google sign-in for new people, which SMS gateways, bulk SMS, OTP by SMS / email / both.
3. Which online payment gateways to support first.

---

## 43. Custom features without breaking the core database

> **বাংলা সারাংশ:** কোনো প্রতিষ্ঠান বিশেষ ফিচার চাইলে মূল ডাটাবেস না বদলে পাঁচটি স্তরে তা যোগ করা যাবে:
> সেটিং, কাস্টম রেকর্ড, অটোমেশন নিয়ম, webhook/API, আর আলাদা এক্সটেনশন। মূল টেবিলে কোনো প্রতিষ্ঠানের জন্য
> আলাদা কলাম যোগ হবে না। সব অংশ **প্রস্তাবিত**; মালিক যোগ করতে বলেছেন।

### 43.1 The rule

The core database and core code are **never changed for one institution**. Custom needs are met in layers
outside the core, from the simplest to the most special.

### 43.2 Five layers

| Layer | How | Example | Code needed? |
|---|---|---|---|
| **1. Settings** | Settings, labels, modules, custom fields (section 40) | "Add a 'blood group' field to our lead form" | No |
| **2. Custom records** | The institution defines a new record type (name, fields, link to lead / student). Forms, lists, filters and export are generated automatically. | Hostel room allocation, scholarship application, library card | No |
| **3. Automation rules** | "When … if … then …" rules. Triggers: lead created, stage changed, payment received, date reached, field changed. Actions: send SMS / email / push, assign, set a field, create a follow-up, add a tag, call a webhook. | "When the stage changes and the course is BBA, SMS the guardian and create a follow-up" | No |
| **4. Webhooks and API** | Outgoing webhooks on events, and a per-institution API with scoped API keys (read / write per area), rate-limited and audited. | Connect to the institution's own ERP or accounting software | Only on the institution's side |
| **5. Extensions** | A separate small module built by our developers, switched on only for chosen institutions. | Bus GPS tracking, a special merit-list formula | Yes, outside the core |

Most requests should be met by layers 1–3 without any code.

### 43.3 Rules that keep the core safe

1. **No per-institution columns in core tables.** Custom data lives in generic tables
   (e.g. `custom_field_values`, `custom_records` with `jsonb` data), with suitable indexes (GIN / expression indexes).
2. **Extensions are isolated:**
   - their own schema (e.g. `ext_transport`) and their own migrations folder
   - they never write to core tables directly; only through versioned RPCs and events
   - switching off or removing an extension never breaks the core app
3. **Event log from day one:** every important action (lead created, stage changed, payment received …) is
   written to a `domain_events` table. Automation, webhooks and extensions listen to these events, so the core
   code does not change for them.
4. **Core schema changes are additive only** (expand, then contract later); see 41.2 D5.
5. **Limits per institution:** number of custom fields, custom record types and records, and automation runs per
   day, so one institution can't slow down the others.
6. **Security:** custom tables and extension tables also have `institution_id` and RLS; the cross-tenant leak
   test covers them; exports and backups include them.
7. **Stable contracts:** event payloads and API versions are documented and versioned, so extensions and outside
   systems don't break when the core changes.

### 43.4 How a new request is handled

1. First check whether settings, custom records or automation can do it. If yes, no code is written.
2. If **several institutions** want the same thing, build it into the core as a module for everyone.
3. If **only one institution** wants it, build it as an extension, and it can be charged separately.

### 43.5 Phases

- **Phase 0:** event log, extension framework and conventions, custom fields.
- **Phase 1:** automation rules.
- **Phase 2:** custom records, webhooks and API.
- **Later, on demand:** individual extensions.

---

## 44. UX and quality checklist

> **বাংলা সারাংশ:** ডার্ক মোড, কিবোর্ডের নিচে ফিল্ড ঢাকা না পড়া, বাংলা লেখা ঠিকভাবে দেখানো, কম দামি ফোনে
> দ্রুত চলা, ধীর নেট, লাখের নিয়মে টাকা লেখা, ফোনে নিরাপত্তা আর টেস্টিং: প্রতিটি নতুন স্ক্রিন বানানোর পর
> এই তালিকা ধরে যাচাই হবে। সব অংশ **প্রস্তাবিত**; মালিক যোগ করতে বলেছেন।

Every new screen is checked against this list before it ships. ✅ = already in the plan, ⚠️ = partly, ❌ = new.

### 44.1 Look: theme and screens

| Item | Status | What to do |
|---|---|---|
| Dark mode | ⚠️ | In section 34, but changing the theme restarts the app. **Switch without a restart.** |
| Institution brand colour | ❌ | Check automatically that the brand colour keeps text readable in both light and dark themes. |
| Large system font | ❌ | Text must not be cut off or overlap when the phone's font size is large. |
| Bangla text clipping | ❌ | Bangla vowel signs above and below (e.g. ু, ৃ) are clipped when the line height is tight. Use a Bangla-safe line height. |
| Notch, camera hole, navigation bar | ❌ | Respect safe areas; buttons never hide behind the system bars (Android edge-to-edge). |
| Small phones, tablets, landscape | ❌ | Layouts work from 5-inch phones to tablets; the web is responsive. |

### 44.2 Keyboard and input

| Item | Status | What to do |
|---|---|---|
| **Keyboard covering fields** | ❌ | The focused field scrolls above the keyboard on every screen, including bottom sheets and popups. |
| Save button | ❌ | On long forms, the Save button stays visible just above the keyboard. |
| "Next" key | ❌ | Next moves to the next field; Done on the last field saves. |
| Right keyboard type | ❌ | Number pad for phones, email keyboard for email, numeric for money. |
| **Bangla digits in numbers** | ❌ | "০১৭১১…" typed or pasted in Bangla digits becomes "01711…". +880, spaces and dashes are cleaned too. |
| Bangla search | ❌ | Searching names typed in Bangla (Avro, Gboard) works. |
| OTP autofill | ❌ | The OTP from SMS fills in automatically. |
| Dismiss keyboard | ❌ | Tapping outside or scrolling closes the keyboard. |

### 44.3 Forms

| Item | Status | What to do |
|---|---|---|
| Validation messages | ⚠️ | Plain-language messages right under the field. |
| Leaving without saving | ❌ | Back asks "Discard changes?". |
| Draft autosave | ❌ | Text is not lost when a call comes in or the app is closed. |
| **Double tap on Save** | ❌ | Never creates two leads or two payments. **Critical for money:** use idempotency keys on the server. |
| Date and time pickers | ❌ | In Bangla and English, in the institution's time zone. |

### 44.4 Loading, empty and error states

| Item | Status | What to do |
|---|---|---|
| Loading | ⚠️ | Skeletons instead of blank screens; cached data first (section 34). |
| Empty state | ❌ | "No leads yet" with an action: Add lead / Import. |
| Errors | ⚠️ | Never fail silently (37.1): say what happened and offer Retry. |
| Pull to refresh, Undo | ⚠️ | Pull to refresh on every list; Undo after deletes. |
| Long tasks | ⚠️ | Progress (%) and Cancel for import and bulk actions. |

### 44.5 Navigation

- **Android Back button:** closes an open sheet or popup first, then goes back; on Home, confirm before exiting. ❌
- **Keep position:** returning from a lead keeps the list position. ⚠️ ("Keep in place" in section 7)
- **Deep links:** a notification opens the exact lead or payment. ✅

### 44.6 Network and device (very important in Bangladesh)

- **Offline and slow networks:** offline queues exist; add timeouts and retries tuned for slow 3G. ⚠️
- **Low-end phones:** test on 2–3 GB RAM Android phones; long lists must stay smooth (virtualised lists). ❌
- **Mobile data cost:** compress images, avoid needless downloads. ❌
- **Battery:** background sync must not drain the battery. ❌
- **App size:** keep it as small as possible. ❌
- **Wrong phone clock:** all time logic uses server time. ❌

### 44.7 Accessibility

- Touch targets at least 48 dp. ❌
- Never use colour alone: hot / warm / cold also have an icon or text. ⚠️ (🔥🙂❄️ exist)
- Screen-reader labels on buttons; enough contrast between text and background. ❌
- One-hand use: callers' main actions near the bottom of the screen. ⚠️

### 44.8 Language and money

- Bangla / English switch **without a restart**. ✅ (40.14)
- **Money in the lakh format:** ১,০০,০০০ / 1,00,000, not 100,000. ❌
- Date formats and optional Bangla digits. ⚠️

### 44.9 Security on the phone

- Optional app lock with PIN or fingerprint. ❌
- Auto sign-out after inactivity (institution setting). ❌
- "Sign out of all other devices". ❌
- Caches cleared on sign-out. ✅

### 44.10 Quality process

- **Design system:** colours, fonts and spacing defined once as tokens (light / dark / brand), so dark mode and branding work on every screen. ❌
- **Automated tests:** Maestro (phone) and Playwright (web) for the main flows. ❌
- **Screenshot tests:** every screen in light / dark × Bangla / English. ⚠️ (partly in 41.2)
- **Test phone list:** one low-end, one mid-range, one small-screen phone. ❌

---

## 45. Multi-tenant integration challenges

> **বাংলা সারাংশ:** প্রতিটি প্রতিষ্ঠানের নিজস্ব SMS, ইমেইল, পেমেন্ট গেটওয়ে (SSLCommerz, bKash, Nagad ইত্যাদি),
> AI, Google Drive, পুশ, কাস্টম ডোমেইন ও SSL সার্টিফিকেট, webhook আর অন্যান্য বাইরের সার্ভিস থাকলে জটিলতা অনেক গুণ
> বাড়ে। এখানে একটি সাধারণ "ইন্টিগ্রেশন হাব" কাঠামো, প্রতিটি সার্ভিসের আলাদা চ্যালেঞ্জ আর সমাধান, আর সব
> সার্ভিসে প্রযোজ্য চ্যালেঞ্জগুলো লেখা আছে। সব অংশ **প্রস্তাবিত**।

### 45.1 Why integrations get hard in a multi-tenant app

- **Institutions × providers × environments.** 100 institutions, each with its own SMS, email, payment and AI
  setup, in sandbox and live mode, is hundreds of separate connections, each able to fail on its own.
- Every connection has its **own credentials, limits, costs, callbacks and failure modes**, and a mistake can
  send one institution's message, money or data through another institution's account.
- Providers change their APIs, prices and rules without asking, and some (especially local gateways) have
  thin documentation and no proper sandbox.
- The Master Admin sets them up (39.1 D4), but the **institution** feels the problem when something breaks.

### 45.2 Integration hub (one structure for every provider)

All outside services go through one **integration hub** instead of separate code per feature.

| Part | What it does |
|---|---|
| **Provider catalogue** | List of supported providers per kind (SMS, email, payment, AI, storage, push, …) with their settings form, docs link and capabilities (balance check, refunds, delivery reports …). |
| **Connection per institution** | `integration_connections(institution_id, kind, provider, mode sandbox/live, status, settings, priority)`. Several per kind allowed (primary + backup). |
| **Secrets** | Stored encrypted (e.g. Supabase Vault), readable only by Edge Functions, shown as a hint; rotation with a "valid from" date so the old key keeps working until the new one is tested. |
| **Adapter interface** | One adapter per provider with the same functions per kind (e.g. SMS: `send`, `balance`, `parse_status`; payment: `create`, `verify`, `refund`, `parse_callback`). A **Custom HTTP** adapter for SMS / email covers unlisted providers. |
| **Outbox and queue** | Every outgoing call is queued with attempts, back-off, "given up" (37.2) and an idempotency key. |
| **Webhook router** | Incoming callbacks use a URL that names the connection, e.g. `/hooks/<provider>/<connection_id>`; the signature is checked with **that connection's** secret before anything is trusted. |
| **Circuit breaker and failover** | After repeated failures a connection is paused and the backup is used (where allowed, e.g. SMS); the Master Admin is alerted. |
| **Health and tests** | A "Test" button per connection, a periodic health check, last success / last error, shown in the Master Admin panel (39.3). |
| **Usage and cost ledger** | Per institution, per provider, per day: count, cost, failures (39.5). |
| **Audit** | Who changed which connection and when; secrets never appear in logs. |

### 45.3 Each integration: specific challenges

| Integration | Multi-tenant challenges | How to handle them |
|---|---|---|
| **SMS gateways** | Different APIs and error formats per gateway; masked sender IDs usually need approval per institution; balance runs out; Bangla (Unicode) parts cost more; OTP must work even when bulk is blocked; delivery reports come late or never. | Adapters + Custom HTTP; sender ID status per connection; low-balance alerts; part count and cost before sending; separate priority queue for OTP; a backup gateway; mark delivery as "unknown" after a timeout. |
| **Transactional email** | **Shared sending reputation:** one institution's spam-like mail can hurt every institution on the same domain / IP; SPF / DKIM / DMARC per institution domain; bounces and complaints; replies must reach the right person. | Each institution sends from **its own domain** (verified) or from its own sub-domain of the platform; platform default mail only with low limits; process bounces / complaints per institution and pause bad senders; Reply-To set to the institution's address. |
| **Payment gateways** (e.g. SSLCommerz, bKash, Nagad, Rocket, cards) | Each institution needs **its own merchant account** (trade licence, bank account, verification), or the platform must act as an aggregator, which has legal and licensing implications; sandbox differs from live; callbacks (IPN) can be late, repeated or missing; **amount tampering** on the client; refunds differ per gateway or are not supported; fees (MDR) and settlement days differ; daily reconciliation. | Default: **each institution's own merchant account**, money settles straight to the institution; the platform never holds the money. Always **verify the payment server-to-server** before marking it paid; amount and invoice come from the server, never the client; idempotent callbacks; daily reconciliation report; refunds through the gateway where supported, otherwise recorded by hand. Legal check before any aggregator model. |
| **Login: Google and OTP** | One Google OAuth client for the whole product needs Google's app verification; branded apps (D12) need their own OAuth / app identifiers; OTP SMS cost and abuse. | Plan Google verification early; per-app OAuth settings for branded builds; OTP rate limits and CAPTCHA (41.2 D10). |
| **Push notifications** | Shared app: one Firebase / Expo project for all; branded apps: **one Firebase project and credentials per app**; tokens must be tied to institution + user + app. | Push connection per app build, token table with `institution_id` and `app_id`, receipts per app (section 25). |
| **AI (Claude / Gemini)** | Keys per institution (section 23) or platform keys; budgets per institution; provider outages; personal data must not be sent. | AI connections in the hub, per-institution budgets and usage ledger, anonymisation (section 23), failover only with a visible note (37.5). |
| **Google Drive (Apps Script)** | Each institution deploys its own script: easy to break (wrong deployment, quota limits, the Google account owner leaves the institution). | Health check and clear error messages; setup guide; option to use platform storage (Supabase Storage) instead; files listed in the database so they can be moved. |
| **PDF / photo services** (iLovePDF, remove.bg) | Monthly quotas per account; several accounts per institution (section 17). | Same hub: several connections in priority order, monthly counters, fallback to "no compression" with a warning. |
| **Custom domains and SSL certificates** | Institutions may want `admission.college.edu.bd` for public forms; each needs DNS verification and an **SSL (HTTPS) certificate** that renews automatically; certificate expiry breaks the page. | Start with platform sub-paths / sub-domains (one wildcard certificate). Custom domains later, through a host that issues and renews certificates automatically; DNS check and expiry alerts in the Master Admin panel. |
| **Outgoing webhooks** (43.2) | The institution's endpoint may be slow, down or wrong; payloads must be signed; retries must not flood them. | Signed payloads (secret per webhook), timeouts, back-off retries, auto-disable after many failures with a notice, delivery log with "resend". |
| **Incoming API** (43.2) | API keys per institution must never reach another institution's data; abuse and heavy use. | Keys scoped to one institution and to areas, rate limits, audit, key rotation. |
| **WhatsApp** | Today: opening WhatsApp and logging (section 12). An official WhatsApp Business API later would need a verified business account and approved templates **per institution**, with per-message costs. | Keep the current approach; if the official API is added, treat it as a hub connection per institution, like SMS. |
| **External boards and government portals** (e.g. National University, education boards) | Usually no public API; steps are done on the portal by hand. | Keep the manual external board flow (section 22); import results from files where possible. |
| **Accounting / ERP / school management software** | Every institution uses something different, or nothing. | Webhooks, API and Excel export (43.2); no direct integration unless several institutions use the same system. |
| **Maps and addresses** | Map links in templates; optional geocoding costs money. | Store a map link per institution / branch; no paid map API unless needed. |

### 45.4 Challenges common to every integration

| # | Challenge | How to handle it |
|---|---|---|
| I1 | **Wrong institution's account used** (e.g. College A's SMS sent from College B's gateway) | The connection is always looked up from the record's `institution_id` on the server, never from the client; tests that send through two institutions and check each used its own account. |
| I2 | **Secrets leaking** (logs, error messages, screenshots) | Vault storage, hint-only display, log scrubbing, rotation, no secrets in chat or code (37.12). |
| I3 | **Sandbox vs live mix-ups** | Mode stored per connection and shown clearly; live payment and bulk SMS blocked until a test in live mode passes; sandbox data marked. |
| I4 | **Callbacks: late, duplicated, forged** | Signature check per connection, idempotency, server-to-server verification, a "pending" state with a timeout and a reconcile job. |
| I5 | **Provider outage or API change** | Circuit breaker, backup connections, versioned adapters, a contract test per adapter run daily in sandbox. |
| I6 | **Rate limits and fairness** | Per-institution and per-provider limits in the queue, so one institution's bulk send doesn't block others' OTP. |
| I7 | **Costs and billing** | Usage ledger per institution and provider (39.5); budgets and alerts; cost shown before bulk actions. |
| I8 | **Testing without real money or SMS** | Sandbox connections, a "fake" adapter for each kind in development and CI, test institutions. |
| I9 | **Onboarding effort** | Setup wizards per provider, "copy from another institution", checklists with status, short guides; the Master Admin sees what is missing per institution. |
| I10 | **Support: who fixes it?** | Clear split: the platform fixes adapter bugs; the institution (or Master Admin on its behalf) fixes its account, balance or merchant issues with the provider; the error message says which. |
| I11 | **Data protection** | Only the data a provider needs is sent (e.g. phone and text for SMS); AI gets anonymised data; each provider listed in the privacy policy. |
| I12 | **Time zones and schedules** | Sending windows and quiet hours per institution time zone (section 10). |
| I13 | **Branded apps multiply everything** (D12) | Each branded app has its own push, OAuth, store listing and permissions; keep them in the hub as "app" connections, and charge for it. |
| I14 | **Leaving institutions** | On closing an institution, disable its connections, revoke API keys and webhooks, and delete its secrets. |

### 45.5 Phases

- **Phase 0:** integration hub (catalogue, connections, secrets, adapters, outbox, webhook router, health, ledger), SMS and email adapters, Google / OTP login.
- **Phase 1:** push per app, webhooks out, sandbox / fake adapters in CI.
- **Phase 2:** payment gateways and reconciliation, incoming API, PDF / photo services, Drive.
- **Later:** custom domains, official WhatsApp API, branded-app connections.

### 45.6 Open questions for the owner

1. Payment money: **each institution's own merchant account** (proposed), or the platform collects and pays out (needs a legal check)?
2. Which payment gateways first (e.g. SSLCommerz, bKash, Nagad)?
3. Who pays gateway and SMS fees: the institution directly, or through the platform's bill?
4. Should institutions be able to use their **own domain** for public pages, and in which phase?
