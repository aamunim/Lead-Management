-- 0B.05 seed: the test institutions above run on Standard (enough users for the test suites); one test institution
-- per plan for CI (Ch 9.9 row 1).
update public.institution_plan set plan_key = 'standard', plan_version = 1, expires_at = null
 where plan_key = 'trial' and institution_id in (select id from public.institutions where slug not like 'plan-%');

insert into public.institutions (id, slug, name, short_name, status) values
  ('d0000000-0000-4000-8000-0000000000d1', 'plan-trial', 'Plan Trial', 'PLT', 'trial'),
  ('d0000000-0000-4000-8000-0000000000d2', 'plan-starter', 'Plan Starter', 'PLS', 'active'),
  ('d0000000-0000-4000-8000-0000000000d3', 'plan-standard', 'Plan Standard', 'PLD', 'active'),
  ('d0000000-0000-4000-8000-0000000000d4', 'plan-pro', 'Plan Pro', 'PLP', 'active'),
  ('d0000000-0000-4000-8000-0000000000d5', 'plan-enterprise', 'Plan Enterprise', 'PLE', 'active')
on conflict (id) do nothing;
update public.institution_plan ip set plan_key = v.plan, plan_version = 1,
       expires_at = case when v.plan = 'trial' then now() + interval '14 days' end
  from (values ('d0000000-0000-4000-8000-0000000000d1'::uuid, 'trial'), ('d0000000-0000-4000-8000-0000000000d2', 'starter'),
               ('d0000000-0000-4000-8000-0000000000d3', 'standard'), ('d0000000-0000-4000-8000-0000000000d4', 'pro'),
               ('d0000000-0000-4000-8000-0000000000d5', 'enterprise')) as v (id, plan)
 where ip.institution_id = v.id;
select app.apply_profiles(id, array['school'], '{}', '{}', 'seed (0B.05)') from public.institutions where slug like 'plan-%';
