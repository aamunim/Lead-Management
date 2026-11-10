-- Removes the example extension completely. The core keeps working (tested in supabase/tests/0A09_events_test.sql).
-- Emitted events stay in the log as history; their definition is only marked deprecated.
drop schema ext_example cascade;                 -- tables, functions, triggers and the public RPCs that use them
delete from public.extensions where key = 'example';   -- cascades: institution_extensions, event_listeners
update public.event_definitions set deprecated_at = now() where extension_key = 'example' and deprecated_at is null;
delete from app.extension_migrations where extension_key = 'example';
