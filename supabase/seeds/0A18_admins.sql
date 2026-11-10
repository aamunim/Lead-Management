-- 0A.18 test admins (local / CI only; password: password123, test data). Institution A gets the college role
-- template with owner.admin as its Super Admin and one pending join request; the weird-labels institution C gets the
-- same so its screens can be checked with long labels. Permissions are rolled out to these system roles by the
-- registry sync that runs after the seed (npm run db:permissions).
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                        confirmation_token, recovery_token, email_change_token_new, email_change)
select '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.email,
       extensions.crypt('password123', extensions.gen_salt('bf')), now(),
       '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''
  from (values ('77777777-7777-4777-8777-777777777777'::uuid, 'owner.admin@example.test'),
               ('88888888-8888-4888-8888-888888888888'::uuid, 'pending.member@example.test')) u (id, email);
insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
select gen_random_uuid(), u.id, u.id::text, jsonb_build_object('sub', u.id, 'email', u.email, 'email_verified', true), 'email', now(), now(), now()
  from (values ('77777777-7777-4777-8777-777777777777'::uuid, 'owner.admin@example.test'),
               ('88888888-8888-4888-8888-888888888888'::uuid, 'pending.member@example.test')) u (id, email);
update public.profiles set display_name = 'owner.admin' where user_id = '77777777-7777-4777-8777-777777777777';
update public.profiles set display_name = 'pending.member', phone = '01711000088' where user_id = '88888888-8888-4888-8888-888888888888';
insert into public.institution_members (institution_id, user_id, status) values
  ('a0000000-0000-4000-8000-00000000000a', '77777777-7777-4777-8777-777777777777', 'active'),
  ('a0000000-0000-4000-8000-00000000000a', '88888888-8888-4888-8888-888888888888', 'pending');

select app.apply_role_template('a0000000-0000-4000-8000-00000000000a', 'college');
select app.apply_role_template('c0000000-0000-4000-8000-00000000000c', 'college');
insert into public.role_assignments (institution_id, user_id, role_id)
select r.institution_id, u.user_id, r.id
  from public.roles r
  join (values ('a0000000-0000-4000-8000-00000000000a'::uuid, '77777777-7777-4777-8777-777777777777'::uuid),
               ('c0000000-0000-4000-8000-00000000000c'::uuid, '66666666-6666-4666-8666-666666666666'::uuid)) u (inst, user_id)
    on u.inst = r.institution_id
 where r.is_super_admin;
select app.flush_access_queue();
