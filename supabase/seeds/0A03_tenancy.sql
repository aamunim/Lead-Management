-- 0A.03-T9 Development / CI seed (local only — never run against staging or production).
-- Two institutions A and B; one user in each; one user in both (D25); one deactivated member; one platform member.
-- Password for every seeded user: password123 (local test data only, not a secret).

insert into public.institutions (id, slug, name, short_name, status) values
  ('a0000000-0000-4000-8000-00000000000a', 'test-college-a', 'Test College A', 'TCA', 'active'),
  ('b0000000-0000-4000-8000-00000000000b', 'test-school-b',  'Test School B',  'TSB', 'active');

with seed(id, email) as (
  values
    ('11111111-1111-4111-8111-111111111111'::uuid, 'a.member@example.test'),
    ('22222222-2222-4222-8222-222222222222'::uuid, 'b.member@example.test'),
    ('33333333-3333-4333-8333-333333333333'::uuid, 'both.member@example.test'),
    ('44444444-4444-4444-8444-444444444444'::uuid, 'gone.member@example.test'),
    ('55555555-5555-4555-8555-555555555555'::uuid, 'platform.admin@example.test')
)
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                        confirmation_token, recovery_token, email_change_token_new, email_change)
select '00000000-0000-0000-0000-000000000000', id, 'authenticated', 'authenticated', email,
       extensions.crypt('password123', extensions.gen_salt('bf')), now(),
       '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''
from seed;

insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
select gen_random_uuid(), u.id, u.id::text,
       jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
       'email', now(), now(), now()
from auth.users u
where u.email like '%@example.test';

update public.profiles set display_name = split_part(email, '@', 1) where email like '%@example.test';

insert into public.institution_members (institution_id, user_id, status) values
  ('a0000000-0000-4000-8000-00000000000a', '11111111-1111-4111-8111-111111111111', 'active'),
  ('b0000000-0000-4000-8000-00000000000b', '22222222-2222-4222-8222-222222222222', 'active'),
  ('a0000000-0000-4000-8000-00000000000a', '33333333-3333-4333-8333-333333333333', 'active'),
  ('b0000000-0000-4000-8000-00000000000b', '33333333-3333-4333-8333-333333333333', 'active'),
  ('a0000000-0000-4000-8000-00000000000a', '44444444-4444-4444-8444-444444444444', 'active');

-- Deactivate one member after joining (exercises the access_version bump).
update public.institution_members set status = 'deactivated'
 where institution_id = 'a0000000-0000-4000-8000-00000000000a' and user_id = '44444444-4444-4444-8444-444444444444';

insert into public.platform_members (user_id, platform_role) values
  ('55555555-5555-4555-8555-555555555555', 'master_admin');
