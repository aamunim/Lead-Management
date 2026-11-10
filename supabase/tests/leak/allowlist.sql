-- Intended cross-institution visibility. Only for a person who is a member of BOTH institutions (D25), and only
-- their own membership facts, which the institution switcher needs. No tenant data of A is allowed for anyone.
insert into leak.allow (rule, object, viewer, reason) values
  ('table_leak', 'public.institutions', 'member of A and B, B active',
   'D25 switcher: a person sees the names of the institutions they actively belong to.'),
  ('table_leak', 'public.institution_members', 'member of A and B, B active',
   'A person sees their own membership rows in every institution (needed by the hook and the switcher).'),
  ('rpc_leak', 'public.set_active_institution', 'member of A and B, B active',
   'A member of A may switch to A; the RPC returns the id they chose.');
