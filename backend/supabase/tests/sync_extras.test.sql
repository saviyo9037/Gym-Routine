-- Tests for 0006: training-plan sync tables, cardio columns, delete RPC coverage.
begin;
select plan(9);

create function pg_temp.affected(q text) returns int language plpgsql as $f$
declare n int;
begin execute q; get diagnostics n = row_count; return n; end $f$;

insert into auth.users (id, email) values
  ('a0000000-0000-0000-0000-0000000000a1', 'sa@example.test'),
  ('b0000000-0000-0000-0000-0000000000b2', 'sb@example.test');

insert into public.training_plans (id, user_id, name) values
  ('a5000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-0000000000a1', 'A plan'),
  ('b5000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-0000000000b2', 'B plan');
insert into public.training_plan_days (id, user_id, plan_id, weekday) values
  ('a6000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-0000000000a1', 'a5000000-0000-0000-0000-000000000001', 1);
insert into public.training_plan_day_exercises (id, user_id, day_id, exercise_name, target_duration_seconds, target_distance_km) values
  ('a7000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-0000000000a1', 'a6000000-0000-0000-0000-000000000001', 'Run', 1200, 3.5);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-0000000000a1', true);

select is((select count(*)::int from public.training_plans), 1, 'A sees only own training plans');
select is((select count(*)::int from public.training_plan_day_exercises), 1, 'A sees own plan exercises');
select is(pg_temp.affected($$update public.training_plans set name = 'hax' where id = 'b5000000-0000-0000-0000-000000000001'$$),
  0, 'A cannot update B training plan');
select lives_ok($$update public.training_plans set deleted_at = now() where id = 'a5000000-0000-0000-0000-000000000001'$$,
  'A can soft-delete own training plan');
select throws_ok($$delete from public.training_plans where id = 'a5000000-0000-0000-0000-000000000001'$$,
  '42501', 'no hard delete on training plans');
select throws_ok($$insert into public.training_plans (id, user_id, name) values ('b5000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-0000000000b2', 'x')$$,
  '42501', 'A cannot insert a training plan for B');
select lives_ok($$update public.workout_sessions set start_hhmm = '07:30' where false$$, 'start_hhmm column exists');

select lives_ok($$select public.delete_my_account_data()$$, 'delete RPC runs with new tables');
reset role;
select is((select count(*)::int from public.training_plans where user_id = 'a0000000-0000-0000-0000-0000000000a1'), 0,
  'delete RPC removed training plans');

select * from finish();
rollback;
