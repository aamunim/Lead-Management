# Industry packs and type profiles (0B.03)

Plan: Ch 7 (type profiles), Ch 49 (industry packs), Ch 6.3 (wizard steps 1–2). Decisions D8, D18, D19, D20, D26.

## What they are

- **Industry** (`public.industries`): the list for the first wizard step (Ch 6.3 step 1), including "Other (general)".
  `signup_open` says which industries the sign-up wizard offers. Now only education is open (D20); while one industry is
  open the wizard hides the industry step.
- **Industry pack** (`public.industry_packs`, one row per version, key = industry key): the industry's words for the
  neutral label keys, its common pipeline, its own modules (with the milestone that builds each), custom-field presets
  and sensitive fields (Ch 49.7: never sent to AI, retention limit, view audit).
- **Type profile** (`public.type_profiles`, one row per version): what an institution of that type is seeded with —
  everything Ch 7.5 lists: words, stages, documents, fee heads, lead custom fields (preset keys), modules on / off,
  setting defaults, message templates, client-number pattern, lead-score points, lost reasons / sources / tags, report
  presets, AI words, role-template set (D26), field-rule defaults, default message recipients, and parts for blocks built
  later (`blocks`: admission test, merit list, board flow, hostel, intakes — Ch 7.8; they stay behind their modules).

The JSON schemas are `config/schemas/industry-pack.schema.json` and `config/schemas/type-profile.schema.json`; the
server keeps a copy in `public.data_schemas`.

## Versions

- A **draft** can be changed; there is at most one draft per pack / profile.
- **Publishing** validates the draft (`app.pack_payload_errors`: the schema, then the references the schema cannot
  check — registered label keys and their length limits, a won and a lost stage, unique keys, role-template set exists,
  custom fields are presets of the pack, modules belong to the pack, settings are institution settings with valid values,
  field rules name a role of the set and a known field) and freezes it. A trigger refuses any change or delete of a
  published version (`version_published`).
- Publishing writes the version's words into `label_defaults` (scope `pack` / `profile`), so the label resolution
  (profile → pack → product) uses the newest published words.
- The newest published version is the one new institutions get. A new version never changes institutions already set up
  (Ch 7.6; applying and "Reset to profile defaults" are 0B.04).

## Who can do what

| Who | What |
|---|---|
| Master Admin, or a platform user with `platform.profiles` (two-step session) | Panel → Profiles and packs: list, view, history, edit as a new version (name fields + JSON), check, save draft, publish, discard draft, open / close industries for sign-up. Every write is in the platform audit log. |
| Support / Billing / Developer (default rights) | Nothing here. |
| Institution staff | Read only published data of open industries (RLS); never write. |
| Anyone (sign-up wizard) | `list_open_packs()`: open industries with their published profiles (names and descriptions). |

RPCs: `platform_packs_list`, `platform_pack_get`, `platform_pack_validate`, `platform_pack_save_draft`,
`platform_pack_publish`, `platform_pack_discard_draft`, `platform_industry_set_open`, `list_open_packs`.

## Seed content and checks

- Version 1 of every pack and profile is in `config/packs/` (one JSON file each, reviewed with the owner) and
  `scripts/profiles/gen-seed.mjs` turns it into `supabase/migrations/20261112110100_packs_profiles_seed.sql`.
  After that migration has run on staging / production, content changes are made in the panel as new versions.
- `npm run check:profiles` validates the files (schema, references between files) and that the seed migration is up to
  date; CI adds `-- --db` to validate every pack and profile row in the database (0B.03-T10).
- Lint (0B.03-T11, Ch 7.2): `scripts/profiles/lint-institution-type.mjs` (part of `npm run lint:schema`) fails when any
  code other than the profile applier reads `institution_type`. Code follows settings and modules, never the type.

## Role templates per profile (D26)

`role_template_set` points at the role templates in `public.role_templates` (0A.16): university, polytechnic and
nursing / health use the **college** set; madrasa and English-medium use the **school** set; training uses the
**coaching** set.

## Applying profiles to an institution (0B.04)

- The **profile applier** (`supabase/migrations/20261113090000_profile_applier.sql`) is the only code that reads which
  types an institution has. `app.apply_profiles(institution, profiles[], exclude_areas[], label_choices)` stores a
  snapshot of the newest published pack + profile versions per item in `seeded_items`, completes the template roles
  and records the versions in `institution_profiles`. `institutions.industry` is always set (education today).
- **Areas** (`profile_areas`): words, settings and role templates are used now; modules (0B.05), custom fields (1.01),
  recipients (1.21), stages (1.07), lists, lead-score points, message templates, field rules, report presets, fees,
  client-number pattern, documents, later blocks and AI words are stored now and read by the block that is built later.
- **Resolution:** the institution's own value (`institution_labels`, `app_settings`) → the seeded value → the pack /
  product / definition default. Re-seeding therefore never overwrites an edit; `modified_by_institution` is kept by
  triggers on the own-value tables.
- **Mixed institutions** (Proposed merge rules): stages, number patterns and later blocks are kept per type; lists are
  joined by key (first type wins); on / off settings and modules are on when any type turns them on; lead-score points
  take the highest; a hidden field beats a masked one; different default recipients become "both"; different words for
  the same key are a **conflict** chosen in the preview (without a choice the first type wins).
- **Type change** (Settings → Institution type, `settings.institution_type`, sensitive): preview first (new, changed,
  back to default, kept because the institution changed it), then apply. Unmodified seeds of a removed type go; edited
  items, roles and data are never deleted. A second type never adds a second Super Admin role.
- **New versions** never apply by themselves; the screen shows "version N is available" and the Admin opts in after the
  preview (Ch 7.6).
- **Reset to profile defaults** (`profile_reset(area, confirm)`): per area (`settings.terminology` for the words, or a
  settings area such as `settings.fees`), preview of each own value and the default it returns to; applied only when
  confirmed; audited.
- **Master Admin:** Institutions → an institution → Labels tab (where each word comes from, lock / unlock with a reason,
  `platform.labels_lock`); Profiles and packs → Product words (the neutral product defaults, `platform.profiles`; never
  an institution's own words).
- **Test institutions:** `supabase/seeds/0B04_profile_institutions.sql` — one per profile (`profile-<key>`) and
  `profile-mixed` (school + college).

### Demo for the 0B.04 checkpoint (staging)

1. As the Super Admin of a demo institution: Settings → Institution type → tick School and College → Preview → open
   "Words" to see what changes → Apply.
2. Change a word in Settings → Terminology (for example "Class" → "Grade").
3. Institution type → untick College, tick Coaching → Preview: the changed word is listed as "kept"; Apply. The word
   stays "Grade"; the other words follow the new types.
4. Reset to profile defaults → Words → the preview shows "Grade → …"; confirm.
5. In the panel: Institutions → the demo institution → Labels → lock "doc.receipt_title" with a reason; in the app the
   word is now read-only in Terminology.

## Profile contents (approved at the 0B.03 checkpoint, D44)

The content below was approved by the owner at the 0B.03 checkpoint (D44). Generated from `config/packs/education`.

### স্কুল (School, `school`)

- **শব্দ:** lead → জিজ্ঞাসা (Enquiry), offering → শ্রেণি (Class), slot_group → সেকশন (Section), cohort → সেশন (Session), client_number → রোল (Roll)
- **স্টেজ:** নতুন → যোগাযোগ হয়েছে → ভিজিট → ভর্তি পরীক্ষা → ফলাফল → প্রস্তুত → ভর্তি হয়েছে → হারানো
- **কাগজপত্র:** জন্ম নিবন্ধন সনদ, আগের স্কুলের টিসি, পাসপোর্ট সাইজের ছবি, অভিভাবকের এনআইডির কপি, শেষ রিপোর্ট কার্ড (ঐচ্ছিক)
- **ফি:** ভর্তি ফি (একবার), মাসিক বেতন (মাসিক), সেশন ফি (প্রতি সেশন); কিস্তি: না; ছাড়/ওয়েভার: হ্যাঁ
- **রোল টেমপ্লেট:** স্কুল সেট (কলেজ সেট + প্রধান শিক্ষক, সহকারী প্রধান শিক্ষক, শ্রেণিশিক্ষক)
- **কাস্টম ফিল্ড:** জন্মতারিখ, আগের প্রতিষ্ঠান, শিফট, ভার্সন, জন্ম নিবন্ধন নম্বর, অভিভাবকের এনআইডি, অভিভাবকের পেশা
- **মডিউল চালু:** সেকশন ও সিট, অভিভাবক, ভর্তি পরীক্ষা
- **নম্বরের প্যাটার্ন:** `{YYYY}{CLASS}{000}`; **মেসেজ পাবেন:** অভিভাবক

### কলেজ (College, `college`)

- **শব্দ:** cohort → সেশন (Session), client_number → রোল (Roll)
- **স্টেজ:** নতুন → যোগাযোগ হয়েছে → ভিজিট → অনলাইনে আবেদন → নির্বাচিত → নিশ্চিত → ভর্তি হয়েছে → হারানো
- **কাগজপত্র:** এসএসসি নম্বরপত্র, এসএসসি প্রশংসাপত্র, পাসপোর্ট সাইজের ছবি, এসএসসি রেজিস্ট্রেশন কার্ড, জন্ম নিবন্ধন সনদ (ঐচ্ছিক)
- **ফি:** ভর্তি ফি (একবার), সেশন ফি (প্রতি সেশন), মাসিক বেতন (মাসিক), পরীক্ষার ফি (প্রতি সেশন); কিস্তি: না; ছাড়/ওয়েভার: হ্যাঁ
- **রোল টেমপ্লেট:** কলেজ সেট (অধ্যক্ষ = Super Admin, উপাধ্যক্ষ, Admin, শাখা ম্যানেজার, বিভাগীয় প্রধান, টিম লিড, কলার, ভর্তি কর্মকর্তা, হিসাবরক্ষক, দর্শক, গভর্নিং বডি)
- **কাস্টম ফিল্ড:** এসএসসি জিপিএ, বোর্ড, পরীক্ষার রোল, রেজিস্ট্রেশন নম্বর, পাসের বছর, আগের প্রতিষ্ঠান, বিভাগ, শিফট, ভার্সন
- **মডিউল চালু:** সেকশন ও সিট, অভিভাবক, মেধাতালিকা, বোর্ড ফ্লো, অ্যালামনাই
- **নম্বরের প্যাটার্ন:** `{YY}{GROUP}{0000}`; **মেসেজ পাবেন:** দুজনই

### প্রাইভেট বিশ্ববিদ্যালয় (Private university, `university`)

- **শব্দ:** lead → আবেদনকারী (Applicant), offering → প্রোগ্রাম (Program), cohort → ইনটেক (Intake), conversion → ভর্তি (Enrolment)
- **স্টেজ:** নতুন → কাউন্সেলিং হয়েছে → আবেদন করেছে → পরীক্ষা ও ভাইভা → অফার → ভর্তি হয়েছে → হারানো
- **কাগজপত্র:** এসএসসি নম্বরপত্র, এইচএসসি নম্বরপত্র, এসএসসি প্রশংসাপত্র, এইচএসসি প্রশংসাপত্র, পাসপোর্ট সাইজের ছবি, এনআইডি বা জন্ম নিবন্ধন
- **ফি:** ভর্তি ফি (একবার), প্রতি ক্রেডিট ফি (প্রতি ক্রেডিট), সেমিস্টার ফি (প্রতি সেমিস্টার); কিস্তি: হ্যাঁ; ছাড়/ওয়েভার: হ্যাঁ
- **রোল টেমপ্লেট:** কলেজ সেট (অধ্যক্ষ = Super Admin, উপাধ্যক্ষ, Admin, শাখা ম্যানেজার, বিভাগীয় প্রধান, টিম লিড, কলার, ভর্তি কর্মকর্তা, হিসাবরক্ষক, দর্শক, গভর্নিং বডি)
- **কাস্টম ফিল্ড:** এসএসসি জিপিএ, এইচএসসি জিপিএ, বোর্ড, পাসের বছর, আগের প্রতিষ্ঠান, বিভাগ, জন্মতারিখ
- **মডিউল চালু:** ভর্তি পরীক্ষা, অ্যালামনাই
- **নম্বরের প্যাটার্ন:** `{YY}{INTAKE}{0000}`; **মেসেজ পাবেন:** লিড / শিক্ষার্থী

### পলিটেকনিক / কারিগরি (Polytechnic / technical, `polytechnic`)

- **শব্দ:** lead → আবেদনকারী (Applicant), offering → টেকনোলজি (Technology), cohort → সেশন (Session), slot_group → গ্রুপ (Group), client_number → রোল (Roll)
- **স্টেজ:** নতুন → যোগাযোগ হয়েছে → ভিজিট → আবেদন করেছে → নির্বাচিত → ভর্তি হয়েছে → হারানো
- **কাগজপত্র:** এসএসসি নম্বরপত্র, এসএসসি প্রশংসাপত্র, পাসপোর্ট সাইজের ছবি, জন্ম নিবন্ধন সনদ (ঐচ্ছিক)
- **ফি:** ভর্তি ফি (একবার), সেমিস্টার ফি (প্রতি সেমিস্টার); কিস্তি: না; ছাড়/ওয়েভার: না
- **রোল টেমপ্লেট:** কলেজ সেট (অধ্যক্ষ = Super Admin, উপাধ্যক্ষ, Admin, শাখা ম্যানেজার, বিভাগীয় প্রধান, টিম লিড, কলার, ভর্তি কর্মকর্তা, হিসাবরক্ষক, দর্শক, গভর্নিং বডি)
- **কাস্টম ফিল্ড:** এসএসসি জিপিএ, বোর্ড, পরীক্ষার রোল, রেজিস্ট্রেশন নম্বর, পাসের বছর, শিফট, আগের প্রতিষ্ঠান
- **মডিউল চালু:** সেকশন ও সিট, অভিভাবক, মেধাতালিকা, বোর্ড ফ্লো, অ্যালামনাই
- **নম্বরের প্যাটার্ন:** `{YY}{TECH}{000}`; **মেসেজ পাবেন:** দুজনই

### মাদ্রাসা (Madrasa, `madrasa`)

- **শব্দ:** offering → শ্রেণি (Class), slot_group → সেকশন (Section), cohort → সেশন (Session), client_number → রোল (Roll)
- **স্টেজ:** নতুন → যোগাযোগ হয়েছে → ভিজিট → মৌখিক পরীক্ষা → ভর্তি হয়েছে → হারানো
- **কাগজপত্র:** জন্ম নিবন্ধন সনদ, পাসপোর্ট সাইজের ছবি, অভিভাবকের এনআইডির কপি, আগের প্রতিষ্ঠানের টিসি (ঐচ্ছিক)
- **ফি:** ভর্তি ফি (একবার), মাসিক বেতন (মাসিক), সেশন ফি (প্রতি সেশন), আবাসিক ফি (মাসিক); কিস্তি: না; ছাড়/ওয়েভার: হ্যাঁ
- **রোল টেমপ্লেট:** স্কুল সেট (কলেজ সেট + প্রধান শিক্ষক, সহকারী প্রধান শিক্ষক, শ্রেণিশিক্ষক)
- **কাস্টম ফিল্ড:** জন্মতারিখ, জন্ম নিবন্ধন নম্বর, আগের প্রতিষ্ঠান, অভিভাবকের এনআইডি, অভিভাবকের পেশা
- **মডিউল চালু:** সেকশন ও সিট, অভিভাবক, ভর্তি পরীক্ষা, বোর্ড ফ্লো, হোস্টেল ও পরিবহন
- **নম্বরের প্যাটার্ন:** `{YYYY}{CLASS}{000}`; **মেসেজ পাবেন:** অভিভাবক

### ইংলিশ-মিডিয়াম স্কুল (English-medium school, `english_medium`)

- **শব্দ:** lead → জিজ্ঞাসা (Enquiry), offering → গ্রেড (Grade), slot_group → সেকশন (Section), cohort → শিক্ষাবর্ষ (Academic year)
- **স্টেজ:** নতুন → যোগাযোগ হয়েছে → ভিজিট → পরীক্ষা ও ইন্টারভিউ → অফার → ভর্তি হয়েছে → হারানো
- **কাগজপত্র:** জন্ম নিবন্ধন সনদ, পাসপোর্ট সাইজের ছবি, শেষ রিপোর্ট কার্ড, অভিভাবকের এনআইডির কপি
- **ফি:** ভর্তি ফি (একবার), ডেভেলপমেন্ট ফি (বার্ষিক), মাসিক বেতন (মাসিক); কিস্তি: না; ছাড়/ওয়েভার: হ্যাঁ
- **রোল টেমপ্লেট:** স্কুল সেট (কলেজ সেট + প্রধান শিক্ষক, সহকারী প্রধান শিক্ষক, শ্রেণিশিক্ষক)
- **কাস্টম ফিল্ড:** জন্মতারিখ, আগের প্রতিষ্ঠান, অভিভাবকের পেশা, অভিভাবকের এনআইডি, জন্ম নিবন্ধন নম্বর
- **মডিউল চালু:** সেকশন ও সিট, অভিভাবক, ভর্তি পরীক্ষা, বোর্ড ফ্লো, অ্যালামনাই
- **নম্বরের প্যাটার্ন:** `{YYYY}{GRADE}{000}`; **মেসেজ পাবেন:** অভিভাবক

### কোচিং সেন্টার (Coaching centre, `coaching`)

- **শব্দ:** offering → কোর্স (Course), cohort → ব্যাচ (Batch), client_number → শিক্ষার্থী নম্বর (Student no.)
- **স্টেজ:** নতুন → কল করা হয়েছে → ডেমো ক্লাস → ভর্তি হয়েছে → হারানো
- **কাগজপত্র:** পাসপোর্ট সাইজের ছবি
- **ফি:** প্যাকেজ ফি (প্যাকেজ), মাসিক ফি (মাসিক); কিস্তি: হ্যাঁ; ছাড়/ওয়েভার: না
- **রোল টেমপ্লেট:** কোচিং সেট (মালিক, ম্যানেজার, কলার)
- **কাস্টম ফিল্ড:** বর্তমান ক্লাস / চাকরি, পছন্দের সময়
- **মডিউল চালু:** সেকশন ও সিট
- **নম্বরের প্যাটার্ন:** `{CODE}-{000}`; **মেসেজ পাবেন:** লিড / শিক্ষার্থী

### ট্রেনিং ইনস্টিটিউট (Training institute, `training`)

- **শব্দ:** client → প্রশিক্ষণার্থী (Trainee), offering → কোর্স (Course), cohort → ব্যাচ (Batch)
- **স্টেজ:** নতুন → কল করা হয়েছে → কাউন্সেলিং হয়েছে → ভর্তি হয়েছে → হারানো
- **কাগজপত্র:** পাসপোর্ট সাইজের ছবি, এনআইডির কপি (ঐচ্ছিক)
- **ফি:** কোর্স ফি (প্যাকেজ); কিস্তি: হ্যাঁ; ছাড়/ওয়েভার: না
- **রোল টেমপ্লেট:** কোচিং সেট (মালিক, ম্যানেজার, কলার)
- **কাস্টম ফিল্ড:** বর্তমান ক্লাস / চাকরি, পছন্দের সময়, জন্মতারিখ
- **মডিউল চালু:** সেকশন ও সিট, অ্যালামনাই
- **নম্বরের প্যাটার্ন:** `{CODE}-{YY}-{000}`; **মেসেজ পাবেন:** লিড / শিক্ষার্থী

### নার্সিং / মেডিকেল / স্বাস্থ্য (Nursing / medical / health, `health`)

- **শব্দ:** offering → কোর্স (Course), cohort → সেশন (Session), client_number → রোল (Roll)
- **স্টেজ:** নতুন → যোগাযোগ হয়েছে → ভিজিট → আবেদন করেছে → মেধাতালিকায় → কাগজপত্র যাচাই হয়েছে → ভর্তি হয়েছে → হারানো
- **কাগজপত্র:** এসএসসি নম্বরপত্র, এইচএসসি নম্বরপত্র, এসএসসি প্রশংসাপত্র, এইচএসসি প্রশংসাপত্র, পাসপোর্ট সাইজের ছবি, জন্ম নিবন্ধন সনদ, মেডিকেল ফিটনেস সনদ, অভিভাবকের এনআইডির কপি
- **ফি:** ভর্তি ফি (একবার), বার্ষিক ফি (বার্ষিক), হোস্টেল ফি (মাসিক); কিস্তি: হ্যাঁ; ছাড়/ওয়েভার: না
- **রোল টেমপ্লেট:** কলেজ সেট (অধ্যক্ষ = Super Admin, উপাধ্যক্ষ, Admin, শাখা ম্যানেজার, বিভাগীয় প্রধান, টিম লিড, কলার, ভর্তি কর্মকর্তা, হিসাবরক্ষক, দর্শক, গভর্নিং বডি)
- **কাস্টম ফিল্ড:** এসএসসি জিপিএ, এইচএসসি জিপিএ, বিভাগ, বোর্ড, পাসের বছর, জন্মতারিখ, আগের প্রতিষ্ঠান
- **মডিউল চালু:** সেকশন ও সিট, অভিভাবক, ভর্তি পরীক্ষা, মেধাতালিকা, বোর্ড ফ্লো, অ্যালামনাই, হোস্টেল ও পরিবহন
- **নম্বরের প্যাটার্ন:** `{YY}{CODE}{000}`; **মেসেজ পাবেন:** দুজনই

