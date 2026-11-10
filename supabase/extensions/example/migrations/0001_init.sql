-- Example extension (0A.09): proves the extension rules end to end. Not shown to users.
-- Own schema ext_example; never alters core tables; registers itself, one event and one listener. Its RPCs are
-- SQL-standard functions (BEGIN ATOMIC), so Postgres tracks what they use and `drop schema ext_example cascade`
-- removes them as well (see ../uninstall.sql). Rules: docs/dev/EXTENSIONS.md.

create schema ext_example;
grant usage on schema ext_example to authenticated, service_role;

-- Registration in the core registries (inserts only; the extension never alters core tables).
insert into public.extensions (key, schema_name, version, description)
values ('example', 'ext_example', '1.0.0', 'Example extension: short notes per institution and a count of setting changes.')
on conflict (key) do update set version = excluded.version, description = excluded.description, status = 'available';

insert into public.event_definitions (event_key, version, entity_type, payload_schema, description, extension_key)
values ('example.note_added', 1, 'note',
        '{"type":"object","required":["note_id"],"properties":{"note_id":{"type":"string"}},"additionalProperties":false}',
        'A note was added by the example extension.', 'example')
on conflict (event_key, version) do update set deprecated_at = null;

-- Is the extension on for the active institution?
create function ext_example.enabled() returns boolean
language sql stable set search_path = '' as $$ select app.extension_enabled('example') $$;
grant execute on function ext_example.enabled() to authenticated, service_role;

create function ext_example.assert_enabled() returns void
language plpgsql stable set search_path = '' as $$
begin
  perform app.require_active_session();
  if not app.extension_enabled('example') then
    raise exception 'extension_disabled' using errcode = 'P0403', detail = 'example';
  end if;
end $$;
grant execute on function ext_example.assert_enabled() to authenticated;

-- Tables: institution_id first, RLS on, visible only while the extension is enabled for the active institution.
create table ext_example.notes (
  institution_id  uuid not null references public.institutions (id) on delete cascade,
  id              uuid not null default gen_random_uuid(),
  body            text not null check (length(body) between 1 and 500),
  created_by      uuid default auth.uid(),
  created_at      timestamptz not null default now(),
  primary key (institution_id, id)
);
create index notes_time_idx on ext_example.notes (institution_id, created_at desc);
create trigger notes_set_institution before insert on ext_example.notes
  for each row execute function app.set_institution_id();
alter table ext_example.notes enable row level security;
grant select, insert on ext_example.notes to authenticated;
create policy notes_read on ext_example.notes for select to authenticated
  using (institution_id = (select app.auth_institution_id()) and (select ext_example.enabled()));
create policy notes_insert on ext_example.notes for insert to authenticated
  with check (institution_id = (select app.auth_institution_id()) and (select ext_example.enabled()));

-- Every new note is announced on the event log (other extensions / automation may listen).
create function ext_example.on_note_added() returns trigger
language plpgsql set search_path = '' as $$
begin
  perform app.emit_event(new.institution_id, 'example.note_added', 1, 'note', new.id::text,
                         jsonb_build_object('note_id', new.id));
  return null;
end $$;
create trigger notes_emit after insert on ext_example.notes
  for each row execute function ext_example.on_note_added();

create table ext_example.setting_change_counts (
  institution_id  uuid not null references public.institutions (id) on delete cascade,
  changes         integer not null default 0,
  last_key        text,
  updated_at      timestamptz not null default now(),
  primary key (institution_id)
);
alter table ext_example.setting_change_counts enable row level security;
grant select on ext_example.setting_change_counts to authenticated;
grant select, insert, update on ext_example.setting_change_counts to service_role;
create policy setting_change_counts_read on ext_example.setting_change_counts for select to authenticated
  using (institution_id = (select app.auth_institution_id()) and (select ext_example.enabled()));

-- Listener (run by app.dispatch_events only for institutions that have the extension on).
create function ext_example.on_setting_changed(p_event jsonb) returns void
language plpgsql set search_path = '' as $$
begin
  insert into ext_example.setting_change_counts (institution_id, changes, last_key, updated_at)
  values ((p_event ->> 'institution_id')::uuid, 1, p_event -> 'payload' ->> 'key', now())
  on conflict (institution_id) do update
    set changes = ext_example.setting_change_counts.changes + 1, last_key = excluded.last_key, updated_at = now();
end $$;
revoke all on function ext_example.on_setting_changed(jsonb) from public, anon, authenticated;
grant execute on function ext_example.on_setting_changed(jsonb) to service_role;

insert into public.event_listeners (listener_key, event_key, function_name, extension_key)
values ('example.count_setting_changes', 'setting.changed', 'ext_example.on_setting_changed', 'example')
on conflict (listener_key) do update set function_name = excluded.function_name, enabled = true;

-- RPCs for the app (public, so the API exposes them; prefixed with the extension key).
create function public.ext_example_note_add(p_body text) returns uuid
language sql volatile set search_path = ''
begin atomic
  select ext_example.assert_enabled();
  insert into ext_example.notes (body) values (p_body) returning id;
end;

create function public.ext_example_notes_list()
returns table (id uuid, body text, created_at timestamptz)
language sql stable set search_path = ''
begin atomic
  select n.id, n.body, n.created_at from ext_example.notes n order by n.created_at desc limit 200;
end;

revoke all on function public.ext_example_note_add(text), public.ext_example_notes_list() from public, anon;
grant execute on function public.ext_example_note_add(text), public.ext_example_notes_list() to authenticated;
