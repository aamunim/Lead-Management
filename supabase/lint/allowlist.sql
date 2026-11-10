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
