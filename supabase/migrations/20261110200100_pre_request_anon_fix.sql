-- Fix (found in 0A.11): app.pre_request() ran as the caller and read product_settings / institution_settings_state,
-- which anonymous callers cannot read, so EVERY anonymous API call failed with 401 "permission denied".
-- It now runs as DEFINER: it reads only min_app_version and the caller's own active institution's settings version.
alter function app.pre_request() security definer;
insert into app.definer_registry (function_name, reason, added_in, reviewer, tenant_check) values
  ('app.pre_request', 'PostgREST pre-request hook for every role incl. anon: reads min_app_version and the settings '
   || 'version of app.auth_institution_id() only; returns nothing but a response header.', '0A.11',
   'architecture review 0A.11', 'filters_active_institution');
