-- 0A.14 App shell: the institution setting for idle sign-out (Ch 47.10). Key name to confirm with the Appendix A
-- owner (0B); 0 = off. The app signs a person out after this many minutes without any touch or key press.
insert into public.setting_definitions (key, scope, schema, default_value, area, description) values
  ('idle_signout_minutes', 'institution', '{"type":"integer","minimum":0,"maximum":1440}', '0', 'settings.security',
   'Sign out automatically after this many idle minutes (0 = never). Protects data on shared or lost phones.');
