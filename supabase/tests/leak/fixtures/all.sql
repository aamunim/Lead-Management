-- Table-specific leak fixtures (0A.05-T1). Add a function here when the generic insert cannot fill a table:
--   create function leak_fixtures.public__<table>(p_institution uuid) returns void language plpgsql as $$
--   begin insert into public.<table> (institution_id, ...) values (p_institution, ...); end $$;
-- The runner calls it once for institution A and once for B.
select 1;
