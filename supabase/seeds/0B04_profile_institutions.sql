-- 0B.04 seed: one test institution per education type profile and one mixed (school + college), set up by the profile
-- applier (Ch 7.3, Ch 7.9 row 1). No members: CI and the screenshot / role checks read them as the platform.
insert into public.institutions (id, slug, name, short_name, status) values
  ('f0000000-0000-4000-8000-0000000000f1', 'profile-school', 'Profile School', 'PSC', 'active'),
  ('f0000000-0000-4000-8000-0000000000f2', 'profile-college', 'Profile College', 'PCO', 'active'),
  ('f0000000-0000-4000-8000-0000000000f3', 'profile-university', 'Profile University', 'PUN', 'active'),
  ('f0000000-0000-4000-8000-0000000000f4', 'profile-polytechnic', 'Profile Polytechnic', 'PPO', 'active'),
  ('f0000000-0000-4000-8000-0000000000f5', 'profile-madrasa', 'Profile Madrasa', 'PMA', 'active'),
  ('f0000000-0000-4000-8000-0000000000f6', 'profile-english-medium', 'Profile English Medium', 'PEM', 'active'),
  ('f0000000-0000-4000-8000-0000000000f7', 'profile-coaching', 'Profile Coaching', 'PCC', 'active'),
  ('f0000000-0000-4000-8000-0000000000f8', 'profile-training', 'Profile Training', 'PTR', 'active'),
  ('f0000000-0000-4000-8000-0000000000f9', 'profile-health', 'Profile Health', 'PHE', 'active'),
  ('f0000000-0000-4000-8000-0000000000fa', 'profile-mixed', 'Profile Mixed School and College', 'PMX', 'active')
on conflict (id) do nothing;

select app.apply_profiles(i.id, p.profiles, '{}', '{}', 'seed (0B.04)')
  from (values
    ('f0000000-0000-4000-8000-0000000000f1'::uuid, array['school']),
    ('f0000000-0000-4000-8000-0000000000f2', array['college']),
    ('f0000000-0000-4000-8000-0000000000f3', array['university']),
    ('f0000000-0000-4000-8000-0000000000f4', array['polytechnic']),
    ('f0000000-0000-4000-8000-0000000000f5', array['madrasa']),
    ('f0000000-0000-4000-8000-0000000000f6', array['english_medium']),
    ('f0000000-0000-4000-8000-0000000000f7', array['coaching']),
    ('f0000000-0000-4000-8000-0000000000f8', array['training']),
    ('f0000000-0000-4000-8000-0000000000f9', array['health']),
    ('f0000000-0000-4000-8000-0000000000fa', array['school', 'college'])
  ) as p (id, profiles)
  join public.institutions i on i.id = p.id;
