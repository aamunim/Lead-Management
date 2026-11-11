#!/usr/bin/env python3
"""Generates the 0B.01 settings catalog part of supabase/migrations/20261112090000_settings_catalog.sql.

Appendix A keys with neutral names (D42): campus_visit -> appointment, alumni -> network, students -> clients,
admission -> conversion. Version-1 schemas are deliberately small: the milestone that builds a feature extends its
key with a schema-version migration (setting_definitions.version + migrate_fn). Run:
    python3 scripts/settings/gen_catalog_0B01.py > /tmp/catalog.sql   (then paste into the migration section)
"""
import json

ENABLED = {"type": "object", "required": ["enabled"], "properties": {"enabled": {"type": "boolean"}},
           "additionalProperties": False}
WHO = {"type": "object", "required": ["mode"], "additionalProperties": False, "properties": {
    "mode": {"enum": ["all", "roles", "users"]},
    "roles": {"type": "array", "items": {"type": "string"}},
    "user_ids": {"type": "array", "items": {"type": "string"}}}}


def minutes(lo, hi):
    return {"type": "integer", "minimum": lo, "maximum": hi}


# key, area (permission), schema, default, owner module, owner milestone, description
KEYS = [
    # Team and reports
    ("activity", "settings.team", ENABLED, {"enabled": False}, "team", "phase 4", "Team activity tracking (Ch 38)."),
    ("reports", "settings.team", ENABLED, {"enabled": True}, "reports", "phase 4", "Report settings (Ch 38)."),
    ("scorecard", "settings.team", ENABLED, {"enabled": False}, "team", "phase 4", "Weekly scorecard (Ch 39)."),
    ("credits", "settings.team", ENABLED, {"enabled": False}, "team", "phase 4", "Credits and leaderboard (Ch 39)."),
    ("credit_extras", "settings.team", ENABLED, {"enabled": False}, "team", "phase 4", "Extra credits (Ch 39)."),
    ("notifications", "settings.team", ENABLED, {"enabled": True}, "notifications", "1.22",
     "Who receives which notification (\"who\" selector, Ch 25)."),
    ("web", "settings.team", WHO, {"mode": "roles", "roles": []}, "web", "1.35",
     "Who may use the website besides admins, who always can (Ch 45)."),
    # Conversion and clients (education: admission and students)
    ("conversion", "settings.conversion", ENABLED, {"enabled": False}, "conversion", "2.05", "Conversion flow (Ch 17, 36)."),
    ("conversion_approval", "settings.conversion", ENABLED, {"enabled": False}, "conversion", "2.05",
     "Approval during conversion (Ch 17, 34)."),
    ("clients", "settings.conversion", ENABLED, {"enabled": False}, "clients", "2.08", "Clients tab (Ch 36)."),
    ("files", "settings.conversion", ENABLED, {"enabled": False}, "files", "2.14",
     "Files on or off and who sees everyone's files (Ch 32)."),
    ("upload_rules", "settings.conversion", ENABLED, {"enabled": False}, "files", "2.13", "Upload rules, edited on the web (Ch 31)."),
    ("photo_presets", "settings.conversion", ENABLED, {"enabled": False}, "files", "2.15", "Photo studio presets (Ch 31)."),
    # Fees
    ("fees", "settings.fees", ENABLED, {"enabled": False}, "fees", "2.02",
     "Fees, payments, methods, receipt design, reminders (Ch 34, 35)."),
    ("receipt_prefix", "settings.fees", {"type": "string", "pattern": "^[A-Za-z0-9-]{0,12}$"}, "R-", "fees", "2.07",
     "Prefix of receipt numbers (Ch 35)."),
    # Leads
    ("assignment", "settings.leads", ENABLED, {"enabled": True}, "leads", "1.03", "Lead assignment, round robin (Ch 14)."),
    ("board", "settings.pipeline", ENABLED, {"enabled": True}, "leads", "1.12", "Pipeline board (Ch 15)."),
    ("lead_cards", "settings.leads", ENABLED, {"enabled": True}, "leads", "1.04", "What a lead card shows (Ch 15)."),
    ("lead_filters", "settings.leads", ENABLED, {"enabled": True}, "leads", "1.12", "Lead filters (Ch 15)."),
    ("lead_score", "settings.leads", ENABLED, {"enabled": False}, "leads", "1.13",
     "Lead score rules, referring to stage kinds or ids, never hard-coded stage keys (Ch 22)."),
    ("appointment", "settings.leads", ENABLED, {"enabled": False}, "leads", "1.13", "Appointments, e.g. campus visits (Ch 22)."),
    ("message_templates", "settings.leads", ENABLED, {"enabled": True}, "messaging", "1.20", "Message templates (Ch 24)."),
    ("speed_to_lead_minutes", "settings.leads", minutes(1, 1440), 5, "leads", "1.11",
     "A new lead not called within this many minutes is escalated to its owner (Ch 18). Default Proposed."),
    ("early_reminder_minutes", "settings.leads", minutes(0, 1440), 15, "leads", "1.11",
     "Early reminder before a follow-up (Ch 18). Default Proposed."),
    ("repeat_reminder_minutes", "settings.leads", minutes(5, 1440), 30, "leads", "1.11",
     "Repeat reminder interval (Ch 18). Default Proposed."),
    ("escalate_team_lead_hours", "settings.leads", minutes(1, 168), 2, "leads", "1.11",
     "Escalate to the team lead after this many hours (Ch 18). Default Proposed."),
    ("escalate_admin_hours", "settings.leads", minutes(1, 336), 24, "leads", "1.11",
     "Escalate to an admin after this many hours (Ch 18). Default Proposed."),
    # Calls and contacts
    ("call_sync", "settings.calls", ENABLED, {"enabled": False}, "calls", "phase 3", "Call-log sync (Ch 41)."),
    ("call_lock", "settings.calls", ENABLED, {"enabled": False}, "calls", "1.10", "Call lock (Ch 19)."),
    ("double_call", "settings.calls", ENABLED, {"enabled": True}, "calls", "1.10", "Double-call warning (Ch 19)."),
    ("contacts_import", "settings.calls", WHO, {"mode": "roles", "roles": []}, "calls", "1.14",
     "Who may use the phone's contacts (Ch 23)."),
    # AI
    ("ai_chance", "settings.ai", ENABLED, {"enabled": False}, "ai", "phase 4", "Chance of conversion (Ch 40)."),
    ("ai_credit", "settings.ai", ENABLED, {"enabled": False}, "ai", "phase 4", "AI conversion credit (Ch 40)."),
    ("ai_providers", "settings.ai",
     {"type": "object", "required": ["enabled", "monthly_budget"], "additionalProperties": False,
      "properties": {"enabled": {"type": "boolean"}, "monthly_budget": {"type": "number", "minimum": 0}}},
     {"enabled": False, "monthly_budget": 0}, "ai", "phase 4",
     "AI provider, model and budget; keys only in the Vault (Ch 40, 42)."),
    # Network and forms (education: alumni)
    ("network", "settings.forms", ENABLED, {"enabled": False}, "network", "phase 5", "Network (alumni) and referrals (Ch 37)."),
    ("public_forms", "settings.forms", ENABLED, {"enabled": False}, "forms", "1.29", "Public forms (Ch 27)."),
]

# Single values stored elsewhere (registered so the catalog is complete; setting_set refuses them).
STORED_ELSEWHERE = [
    ("institution_name", "settings.general", {"type": "string", "maxLength": 120}, "", "core", "0A.03",
     "Institution name (Ch 6); stored in institutions.name.", "institutions.name"),
]

# Product-level, not per institution (0B.01-T9; Master Admin side).
PRODUCT = [
    ("app_name", {"type": "string", "minLength": 1, "maxLength": 60}, "Leadora", "App name (D37)."),
    ("app_domain", {"type": "string", "maxLength": 253}, "", "Product domain."),
    ("privacy_contact_email", {"type": "string", "maxLength": 254}, "", "Contact on the privacy page (Ch 5)."),
    ("developer_email", {"type": "string", "maxLength": 254}, "", "Owner of the developer / feedback inbox (Ch 46)."),
]

# Other per-institution configuration (0B.01-T3): where it lives and which milestone owns it.
GROUPS = [
    ("branding", "institutions, branding settings", "0B.10", "Name, short name, logo, colour (Ch 6)."),
    ("external_board_flow", "external board flow settings", "2.16", "Steps, board id label, fee default, on/off (Ch 36)."),
    ("reset_password_format", "login settings", "0B.19", "Plain or short-name based reset passwords (Ch 10)."),
    ("locale", "app_settings (locale keys)", "0A.11", "Time zone, currency, phone rules, week, payment methods, language (Ch 13)."),
    ("lead_score_rules", "lead score rules", "1.13", "Rules refer to stage kinds or ids (Ch 22)."),
    ("counters", "counters", "0A.08", "Receipt, refund and client id counters (Ch 33, 35)."),
    ("external_accounts", "integration hub connections, Vault", "0B.11", "Drive, PDF / photo services, AI, SMS, email, payments (Ch 42)."),
    ("types_and_packs", "type profiles, packs, labels, modules", "0B.03", "Type profile / industry, labels, modules on or off (Ch 7, 8, 9)."),
    ("plan_and_billing", "plans, subscriptions", "0B.16", "Plan, period, limits, prices, who pays gateway / SMS charges (Ch 9, D15)."),
    ("login", "login settings", "0B.17", "Google mode, domain auto-approval and default role, OTP channel (Ch 10)."),
    ("roles_and_access", "roles, role_assignments, field rules", "0A.16", "Roles, templates, field masking, export limits, approval policies (Ch 11)."),
    ("branches", "org_units, branches", "0A.15", "Branch name, address, phone, head (Ch 12)."),
    ("notification_matrix", "notification matrix, templates, consent", "1.21", "Kind x recipient x channel, template texts, opt-out (Ch 24, 25)."),
    ("campaigns", "campaign settings", "1.27", "Daily limit, approval limit, send speed (Ch 26)."),
    ("public_pages", "public pages, custom domains", "1.29", "Slug, own domain, application form, deadlines (Ch 27)."),
    ("custom_parts", "custom fields, custom records, automations, webhooks, API keys", "0B.06", "Per-institution custom parts and limits (Ch 14, 43)."),
]


def lit(v):
    return "'" + json.dumps(v, ensure_ascii=False).replace("'", "''") + "'"


def q(s):
    return "'" + s.replace("'", "''") + "'"


rows = []
for key, area, schema, default, owner, milestone, desc in KEYS:
    rows.append(f"  ({q(key)}, 'institution', {lit(schema)}, {lit(default)}, {q(area)}, {q(desc)}, {q('settings:keys.' + key)}, {q(owner)}, {q(milestone)}, 'app_settings')")
for key, area, schema, default, owner, milestone, desc, stored in STORED_ELSEWHERE:
    rows.append(f"  ({q(key)}, 'institution', {lit(schema)}, {lit(default)}, {q(area)}, {q(desc)}, {q('settings:keys.' + key)}, {q(owner)}, {q(milestone)}, {q(stored)})")
for key, schema, default, desc in PRODUCT:
    rows.append(f"  ({q(key)}, 'product', {lit(schema)}, {lit(default)}, 'platform.product_settings', {q(desc)}, {q('settings:keys.' + key)}, 'platform', '0B.01', 'product_settings')")

print("insert into public.setting_definitions (key, scope, schema, default_value, area, description, label_key, owner_module, owner_milestone, stored_in)")
print("select key, scope, schema::jsonb, default_value::jsonb, area, description, label_key, owner_module, owner_milestone, stored_in from (values")
print(",\n".join(rows))
print(") as v (key, scope, schema, default_value, area, description, label_key, owner_module, owner_milestone, stored_in);")
print()
print("insert into public.config_groups (group_key, owner_tables, owner_milestone, description, label_key) values")
print(",\n".join(f"  ({q(g)}, {q(t)}, {q(m)}, {q(d)}, {q('settings:groups.' + g)})" for g, t, m, d in GROUPS) + ";")
