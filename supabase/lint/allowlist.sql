-- Schema lint exceptions. Every row needs a real reason; reviewers check this file in every PR that changes it.
insert into lint.allow (rule, object, reason) values
  -- Platform-level tables: not owned by one institution.
  ('platform_table', 'public.institutions', 'The tenant table itself; rows are institutions.'),
  ('platform_table', 'public.profiles', 'One profile per person across all their institutions (D25).'),
  ('platform_table', 'public.platform_members', 'Master Admin side roles, separate from institutions (Ch 11.15).'),
  ('platform_table', 'app.definer_registry', 'Developer registry of SECURITY DEFINER functions, not tenant data.'),
  -- Membership is looked up by user before any institution is active (access-token hook, switcher).
  ('index_leading_institution', 'institution_members_user_idx', 'Hook and switcher look up memberships by user_id first.');
insert into lint.allow (rule, object, reason) values
  ('platform_table', 'public.setting_definitions', 'Product-wide definitions of settings (keys, schemas, defaults).'),
  ('platform_table', 'public.product_settings', 'Product-level values such as min_app_version; not per institution.');
insert into lint.allow (rule, object, reason) values
  ('platform_table', 'public.event_definitions', 'Product-wide catalogue of event keys and payload schemas.'),
  ('platform_table', 'public.platform_audit_log', 'Audit of product-level actions (no institution).'),
  ('platform_table', 'public.extensions', 'Product-wide registry of available extensions.'),
  ('platform_table', 'public.event_listeners', 'Product-wide registry of event listener functions.');
insert into lint.allow (rule, object, reason) values
  ('platform_table', 'app.extension_migrations', 'Tracks applied extension migration files; product-wide, not tenant data.');
insert into lint.allow (rule, object, reason) values
  ('platform_table', 'public.label_keys', 'Product-wide registry of neutral label keys (Ch 8.4).'),
  ('platform_table', 'public.label_defaults', 'Product, pack and type-profile default labels; not per institution.');
insert into lint.allow (rule, object, reason) values
  ('platform_table', 'public.permissions', 'Product-wide permission registry loaded from module manifests (Ch 11.5).'),
  ('platform_table', 'public.field_registry', 'Product-wide registry of sensitive fields (Ch 11.11).'),
  ('platform_table', 'public.behaviour_flags', 'Product-wide list of role behaviour flags (Ch 11.9).'),
  ('platform_table', 'public.role_templates', 'Product-wide role templates per type profile (D26).');
insert into lint.allow (rule, object, reason) values
  ('platform_table', 'app.record_entities', 'Developer registry of record types the access explainer can look up (0A.18); not tenant data.');
insert into lint.allow (rule, object, reason) values
  ('platform_table', 'public.config_groups', 'Product-wide catalogue of per-institution configuration groups and their owning tables (0B.01).');
insert into lint.allow (rule, object, reason) values
  ('platform_table', 'public.platform_alerts', 'Alerts for platform users (Master Admin side), read only by the recipient (0B.02).'),
  ('platform_table', 'public.platform_invites', 'Pending platform-user invitations by email; platform side only (0B.02).'),
  ('platform_table', 'public.platform_login_devices', 'Devices of platform users for new-device alerts; platform side only (0B.02).'),
  ('platform_table', 'public.platform_role_permissions', 'Rights of each platform role (product-wide, 0B.02).'),
  ('index_leading_institution', 'platform_audit_log_pkey', 'Platform audit log: institution_id is optional (most platform actions have none); read only on the platform side.'),
  ('unique_includes_institution', 'platform_audit_log_pkey', 'Platform audit log: one id per row across the platform; institution_id is optional.'),
  ('write_needs_can', 'public.platform_session_start', 'Self-service at panel sign-in: needs aal2 and an active platform membership of the caller; writes only the caller''s own device, alerts and invite.');
insert into lint.allow (rule, object, reason) values
  ('platform_table', 'public.data_schemas', 'Product-wide JSON schemas for pack / profile data (0B.03).'),
  ('platform_table', 'public.industries', 'Product-wide industry list for the sign-up wizard (0B.03, Ch 6.3).'),
  ('platform_table', 'public.industry_packs', 'Product-wide versioned industry packs edited by the Master Admin (0B.03, Ch 49).'),
  ('platform_table', 'public.type_profiles', 'Product-wide versioned type profiles edited by the Master Admin (0B.03, Ch 7).');
insert into lint.allow (rule, object, reason) values
  ('platform_table', 'public.profile_areas', 'Product-wide registry of profile areas and where each is used (0B.04).');
insert into lint.allow (rule, object, reason) values
  ('platform_table', 'public.modules', 'Product-wide module list (0B.05, Ch 9.2).'),
  ('platform_table', 'public.limit_metrics', 'Product-wide catalog of limit metrics (0B.05, Ch 9.5).'),
  ('platform_table', 'public.plans', 'Product-wide versioned plans catalog edited by the Master Admin (0B.05, Ch 9.3).'),
  ('platform_table', 'public.addons', 'Product-wide add-on catalog (0B.05, Ch 9.4).');
insert into lint.allow (rule, object, reason) values
  ('platform_table', 'app.status_guard_exempt', 'Developer list of tables a read-only institution may still write, with reasons (0B.07).');
insert into lint.allow (rule, object, reason) values
  ('index_leading_institution', 'support_sessions_id_key', 'Token checks look a support session up by its id before any institution is known (0B.08).'),
  ('unique_includes_institution', 'support_sessions_id_key', 'A support session id is unique across the platform: the token carries only the id (0B.08).'),
  ('index_leading_institution', 'support_sessions_open_idx', 'The sign-in hook finds a platform user''s open session before any institution is known (0B.08).'),
  ('write_needs_can', 'public.support_session_end', 'Ends only the caller''s own support sessions (leaving is always allowed); audited on both sides.');
insert into lint.allow (rule, object, reason) values
  ('platform_table', 'public.institution_signups', 'Platform record of institution sign-ups for rate limits and review; written before the institution exists (0B.09).'),
  ('index_leading_institution', 'institution_invites_email_idx', 'A confirmed login finds its open Super Admin invitations by email before any institution is known (0B.09).');
insert into lint.allow (rule, object, reason) values
  ('platform_table', 'public.setup_checklist_items', 'Product-wide setup checklist items (Proposed list), not per institution (0B.10).'),
  ('platform_table', 'public.copy_areas', 'Developer registry of configuration areas that can be copied between institutions (0B.10).');
insert into lint.allow (rule, object, reason) values
  ('platform_table', 'public.integration_providers', 'Product-wide provider catalog (0B.11, Ch 42.2).'),
  ('platform_table', 'public.integration_error_kinds', 'Product-wide list of integration error codes and whose side each is on (0B.11, I10).'),
  ('platform_table', 'public.platform_connections', 'The platform''s own gateways (default SMS / mail), not owned by an institution (0B.11, D15).'),
  ('platform_table', 'public.platform_secrets', 'Vault references of the platform gateways'' keys; no institution (0B.11, D4).'),
  ('platform_table', 'public.integration_audit', 'Audit of connection and key changes for institutions and the platform; read only through panel RPCs (0B.11).');
insert into lint.allow (rule, object, reason) values
  ('index_leading_institution', 'integration_audit_pkey', 'Platform audit table with an optional institution; rows are found by id (0B.11).'),
  ('unique_includes_institution', 'integration_audit_pkey', 'Platform audit table: the id is unique across the platform (0B.11).');
insert into lint.allow (rule, object, reason) values
  ('definer_tenant_check', 'app.can_check', 'Applies the app.auth_institution_id() rule inline (token institution + active membership with the token''s access version, or an open support session): calling the SQL helper plans it on every call, 4x slower (benchmark gate, lesson 13).');
