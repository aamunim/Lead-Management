# Phase 0A demo script (0A.20-T9)

For the owner checkpoint: run it once on a phone (preview build) and once on the web, in both languages. About 15
minutes. Test users (password `password123`, test data only): `owner.admin@example.test` (Super Admin of Test College
A), `a.member@example.test` (staff of A), `both.member@example.test` (member of A and B),
`weird.member@example.test` (weird-labels institution).

## Before the demo

1. Local: `npx supabase@3.1.0 db reset`, `npm run db:extensions`, `npm run db:permissions`, then
   `psql "$DB_URL" -f scripts/demo/prepare.sql` (branches on for Test College A, two branches).
   Staging: the same seed and script (0A.20-T8 staging rehearsal).
2. Web: `npm run export:web:local` and open it; phone: the preview build pointing at the same backend.

## Script

| # | Do | You should see |
|---|---|---|
| 1 | Sign in as `both.member`. Open the institution switcher in the top bar, switch from A to B and back. | The name in the top bar changes; nothing of the other institution stays on screen (lists, words, settings). |
| 2 | Profile → language **বাংলা**, appearance **dark**; then back to English / light. | The whole app changes at once, no restart; Bangla text is not cut. |
| 3 | Sign out; sign in as `owner.admin`. Settings tab. | Users, Roles, Branches, Words, "Why can or can't…", Change log. |
| 4 | Settings → Branches: open *Mirpur campus*, change the phone, save. | Saved; the list shows the new phone. |
| 5 | Settings → Roles → New role, start from *Caller*, name it "Season caller", create; tick *General settings*; save. | Role saved; labels and help for every permission; sensitive ones marked. |
| 6 | Settings → Users → `a.member` → Give a role: *Season caller*, Where *Dhanmondi campus*, Ends: next month. Check "Resulting access", save. | The role shows "Only Dhanmondi campus" with the dates. |
| 7 | Settings → Why can or can't…: person `a.member`, permission *General settings*, record branch *Mirpur campus* → Check. Then *Dhanmondi campus*. | First: cannot — "Limited to another Branch". Second: can — "Covers everyone's records". |
| 8 | Settings → Change log → *Roles given and removed*. | "Role given" by owner.admin with the time. |
| 9 | Settings → Words: rename *Student* to "Trainee" / "Trainees" / "প্রশিক্ষণার্থী"; watch the preview in English and বাংলা; save. | Preview changes before saving; after saving every screen uses the new word in both languages. |
| 10 | On a second device signed in as `owner.admin`, refresh. | The new word there too. |
| 11 | Words → Reset all words. | Back to the defaults everywhere. |
| 12 | Sign in as `a.member`: Settings tab. | "Nothing to manage here" — a role without settings permissions sees no settings screens (the server refuses them too). |

## After the demo

`npx supabase@3.1.0 db reset` (local) or reset the staging seed. Record the result in `docs/dev/PROGRESS.md` (0A.20 owner
checkpoint).
