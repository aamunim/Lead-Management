-- Demo preparation (0A.20-T9), local or staging with the test seed: branches on for Test College A with two branches.
-- Turning branches on is a platform setting (plans in 0B), so it is done here. Safe to run twice.
insert into public.app_settings (institution_id, key, value) values ('a0000000-0000-4000-8000-00000000000a', 'branches_enabled', 'true')
  on conflict (institution_id, key) do update set value = 'true';
insert into public.org_units (institution_id, id, kind, name) values
  ('a0000000-0000-4000-8000-00000000000a', 'd0000000-0000-4000-8000-0000000000d1', 'branch', 'Dhanmondi campus'),
  ('a0000000-0000-4000-8000-00000000000a', 'd0000000-0000-4000-8000-0000000000d2', 'branch', 'Mirpur campus')
  on conflict do nothing;
insert into public.branches (institution_id, org_unit_id, address, phone) values
  ('a0000000-0000-4000-8000-00000000000a', 'd0000000-0000-4000-8000-0000000000d1', 'Road 27, Dhanmondi, Dhaka', '01711000101'),
  ('a0000000-0000-4000-8000-00000000000a', 'd0000000-0000-4000-8000-0000000000d2', 'Section 10, Mirpur, Dhaka', '01711000102')
  on conflict do nothing;
select app.bump_settings_version('a0000000-0000-4000-8000-00000000000a');
