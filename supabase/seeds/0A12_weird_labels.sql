-- 0A.12-T10 "Weird labels" test institution (local / CI only): long, unusual words in both languages, so screenshot
-- tests catch layouts that break when an institution renames things (Ch 8.9 rule 4). Password: password123 (test data).
insert into public.institutions (id, slug, name, short_name, status) values
  ('c0000000-0000-4000-8000-00000000000c', 'test-weird-labels', 'Weird Labels Training Institute of Professional Studies', 'WLT', 'active');

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                        confirmation_token, recovery_token, email_change_token_new, email_change)
values ('00000000-0000-0000-0000-000000000000', '66666666-6666-4666-8666-666666666666', 'authenticated', 'authenticated',
        'weird.member@example.test', extensions.crypt('password123', extensions.gen_salt('bf')), now(),
        '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '');
insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
values (gen_random_uuid(), '66666666-6666-4666-8666-666666666666', '66666666-6666-4666-8666-666666666666',
        '{"sub":"66666666-6666-4666-8666-666666666666","email":"weird.member@example.test","email_verified":true}',
        'email', now(), now(), now());
update public.profiles set display_name = 'weird.member' where user_id = '66666666-6666-4666-8666-666666666666';
insert into public.institution_members (institution_id, user_id, status) values
  ('c0000000-0000-4000-8000-00000000000c', '66666666-6666-4666-8666-666666666666', 'active');

insert into public.institution_labels (institution_id, key, en_singular, en_plural, bn_forms)
select 'c0000000-0000-4000-8000-00000000000c', v.key, v.en_s, v.en_p, app.bn_forms(v.bn, k.animate)
from (values
  ('client', 'Professional Development Participant', 'Professional Development Participants', 'পেশাগত উন্নয়ন অংশগ্রহণকারী'),
  ('lead', 'Prospective Programme Applicant', 'Prospective Programme Applicants', 'সম্ভাব্য কর্মসূচি আবেদনকারী'),
  ('offering', 'Certification Pathway', 'Certification Pathways', 'সার্টিফিকেশন পাথওয়ে'),
  ('cohort', 'Quarterly Intake Window', 'Quarterly Intake Windows', 'ত্রৈমাসিক ভর্তির সময়সীমা'),
  ('conversion', 'Programme Registration', 'Programme Registrations', 'কর্মসূচিতে নিবন্ধন'),
  ('contact_person', 'Corporate Sponsor Contact', 'Corporate Sponsor Contacts', 'প্রাতিষ্ঠানিক স্পনসর প্রতিনিধি'),
  ('fee', 'Participation Contribution', 'Participation Contributions', 'অংশগ্রহণ অনুদান')
) as v (key, en_s, en_p, bn)
join public.label_keys k on k.key = v.key;
