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
