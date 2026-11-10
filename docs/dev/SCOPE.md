# Scope boundary of the first release (Ch 2.6)

| Item | Status | Plan |
|---|---|---|
| All education institution types (D8) | **In**, through type profiles; blocks not built yet stay switched off by module | Ch 7 |
| Branches / campuses (D9) | **In**, from Phase 0 | Ch 12 |
| Bangla + English UI (D13) | **In** | Ch 13 |
| Android app + website (one codebase) | **In** | Ch 45 |
| One login across several institutions, institution groups (D25) | **In** (data model Phase 0, switcher and groups Phase 1) | Ch 10 |
| Android native call-log / WhatsApp sync | **Later** (Phase 3), after the Google Play policy is confirmed | Ch 41 |
| iOS | **Out** | — |
| Guardian / student portal (D10) | **Out for now** | Ch 53 |
| Industries outside education (D20) | **Out for now** — but neutral keys and packs-as-data are built in Phase 0 | Ch 8, 49 |
| Separate branded app per institution (D12) | **Later** (Phase 5), paid | Ch 5, 48 |
| Official WhatsApp Business API | **Later** | Ch 42 |
| Moving data from the old app | **Out** — the new app starts from zero | — |

## Legacy items that must never come back

The earlier single-college app had these; the new app must not recreate them:

- lists: `call_results`, `document_types` (duplicate of papers)
- table: `feature_flags` (replaced by per-institution modules and flags)
- settings keys: `max_call_attempts`, `call_log_lock_hours`, `activity_retention_days`
- any hard-coded college name, locale, stage key or rule (see `ARCHITECTURE_RULES.md` section 2)
