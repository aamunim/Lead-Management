-- 0A.04-T11 guard trigger: protected columns change only inside the owning RPC (session flag set).
\set ON_ERROR_STOP on
begin;
create function pg_temp.check(cond boolean, what text) returns void language plpgsql as $$
begin
  if cond is distinct from true then raise exception 'FAILED: %', what; end if;
  raise notice 'ok - %', what;
end $$;
create function pg_temp.error_of(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return ''; exception when others then return sqlerrm; end $$;

create temp table guarded (id int primary key, stage text, note text);
insert into guarded values (1, 'new', 'x');
create trigger guarded_guard before update on guarded for each row
  execute function app.guard_columns('app.pipeline_action', 'stage');

select pg_temp.check(pg_temp.error_of('update guarded set stage = ''won'' where id = 1') = 'protected_column',
                     'guard: direct edit of a protected column is blocked');
update guarded set note = 'free' where id = 1;
select pg_temp.check((select note from guarded) = 'free', 'guard: other columns stay editable');

-- What the owning RPC does: set the flag for this transaction only, then update.
select set_config('app.pipeline_action', 'on', true);
update guarded set stage = 'won' where id = 1;
select pg_temp.check((select stage from guarded) = 'won', 'guard: allowed inside the owning RPC (flag on)');
select set_config('app.pipeline_action', '', true);
select pg_temp.check(pg_temp.error_of('update guarded set stage = ''lost'' where id = 1') = 'protected_column',
                     'guard: blocked again once the flag is off');
rollback;
