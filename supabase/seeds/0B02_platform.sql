-- 0B.02 platform test users (local / CI only; password password123). Every platform user has a verified TOTP factor
-- with the PUBLIC TEST secret below, so tests can compute real codes (scripts/e2e/helpers.mjs totp()). Never on
-- staging or production: scripts/demo/load-staging.sh removes platform roles and factors of every @example.test user.
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                        confirmation_token, recovery_token, email_change_token_new, email_change)
select '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.email,
       extensions.crypt('password123', extensions.gen_salt('bf')), now(),
       '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''
  from (values ('e1000000-0000-4000-8000-0000000000e1'::uuid, 'platform.support@example.test'),
               ('e2000000-0000-4000-8000-0000000000e2'::uuid, 'platform.billing@example.test'),
               ('e3000000-0000-4000-8000-0000000000e3'::uuid, 'platform.developer@example.test')) u (id, email);
insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
select u.id, u.id, u.id::text, jsonb_build_object('sub', u.id, 'email', u.email, 'email_verified', true), 'email', now(), now(), now()
  from (values ('e1000000-0000-4000-8000-0000000000e1'::uuid, 'platform.support@example.test'),
               ('e2000000-0000-4000-8000-0000000000e2'::uuid, 'platform.billing@example.test'),
               ('e3000000-0000-4000-8000-0000000000e3'::uuid, 'platform.developer@example.test')) u (id, email);
insert into public.platform_members (user_id, platform_role) values
  ('e1000000-0000-4000-8000-0000000000e1', 'support'),
  ('e2000000-0000-4000-8000-0000000000e2', 'billing'),
  ('e3000000-0000-4000-8000-0000000000e3', 'developer');

-- Test TOTP factor (secret JBSWY3DPEHPK3PXP, public test value) for every platform test user.
insert into auth.mfa_factors (id, user_id, friendly_name, factor_type, status, created_at, updated_at, secret)
select gen_random_uuid(), u, 'Test authenticator', 'totp', 'verified', now(), now(), 'JBSWY3DPEHPK3PXP'
  from unnest(array['55555555-5555-4555-8555-555555555555', 'e1000000-0000-4000-8000-0000000000e1',
                    'e2000000-0000-4000-8000-0000000000e2', 'e3000000-0000-4000-8000-0000000000e3']::uuid[]) u;
