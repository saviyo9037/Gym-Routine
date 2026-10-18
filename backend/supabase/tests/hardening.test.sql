-- Tests for 0007 (hardening): cross-owner links, future timestamps, privileged functions,
-- catalogue/entitlement/audit tampering, storage write policies, favourites merge,
-- exercise_sync_id columns, server_time().
begin;
select plan(29);

create function pg_temp.affected(q text) returns int language plpgsql as $f$
declare n int;
begin execute q; get diagnostics n = row_count; return n; end $f$;

insert into auth.users (id, email) values
  ('a0000000-0000-0000-0000-0000000000a1', 'ha@example.test'),
  ('b0000000-0000-0000-0000-0000000000b2', 'hb@example.test');

insert into public.workout_plans (id, user_id, plan_date) values
  ('b1000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-0000000000b2', '2026-10-20'),
  ('a1000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-0000000000a1', '2026-10-21');
insert into public.workout_sessions (id, user_id, session_date, start_time, primary_muscle) values
  ('b2000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-0000000000b2', '2026-10-20', now(), 'Chest');
insert into public.routines (id, user_id, title, category, start_time, end_time, repeat_days) values
  ('b3000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-0000000000b2', 'B routine', 'Gym', '07:00', '08:00', '1');
insert into public.training_plans (id, user_id, name) values
  ('b4000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-0000000000b2', 'B plan');
insert into public.exercises_catalog (id, name, primary_muscle_group, status) values (9001, 'Hardening test', 'Chest', 'draft');

-- ===== anonymous caller =====
set local role anon;
select throws_ok($$insert into public.exercises_catalog (id, name, primary_muscle_group) values (9002, 'x', 'Chest')$$,
  '42501', 'anon cannot insert into the catalogue');
select throws_ok($$update public.exercises_catalog set name = 'hax' where id = 9001$$,
  '42501', 'anon cannot update the catalogue');
select throws_ok($$select public.server_time()$$, '42501', 'anon cannot call server_time()');
reset role;

-- ===== signed-in user A =====
set local role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-0000000000a1', true);

-- cross-owner parent links
select throws_ok($$insert into public.workout_plan_exercises (id, user_id, plan_id, exercise_name)
  values ('a2000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-0000000000a1', 'b1000000-0000-0000-0000-000000000001', 'Curl')$$,
  '42501', 'A cannot attach a plan exercise to B plan');
select throws_ok($$insert into public.session_sets (id, user_id, session_id, exercise_name, set_number, reps, weight_kg, completed_at)
  values ('a2000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-0000000000a1', 'b2000000-0000-0000-0000-000000000001', 'Curl', 1, 5, 10, now())$$,
  '42501', 'A cannot attach a set to B session');
select throws_ok($$insert into public.routine_completions (id, user_id, routine_id, completion_date, status, completed_at)
  values ('a2000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-0000000000a1', 'b3000000-0000-0000-0000-000000000001', '2026-10-20', 'completed', now())$$,
  '42501', 'A cannot complete B routine');
select throws_ok($$insert into public.training_plan_days (id, user_id, plan_id, weekday)
  values ('a2000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-0000000000a1', 'b4000000-0000-0000-0000-000000000001', 2)$$,
  '42501', 'A cannot add a day to B training plan');
select throws_ok($$insert into public.workout_sessions (id, user_id, session_date, start_time, primary_muscle, plan_id)
  values ('a2000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-0000000000a1', '2026-10-22', now(), 'Chest', 'b1000000-0000-0000-0000-000000000001')$$,
  '42501', 'A cannot link a session to B plan');
select lives_ok($$insert into public.workout_plan_exercises (id, user_id, plan_id, exercise_name)
  values ('a2000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-0000000000a1', 'a1000000-0000-0000-0000-000000000001', 'Own')$$,
  'A can attach a plan exercise to an own plan');

-- identity columns
select throws_ok($$update public.workout_plans set user_id = 'b0000000-0000-0000-0000-0000000000b2' where id = 'a1000000-0000-0000-0000-000000000001'$$,
  '42501', 'A cannot hand a row to B (update changing user_id)');

-- future client timestamps are clamped (clock-skew guard)
select lives_ok($$update public.workout_plans set client_updated_at = now() + interval '30 days' where id = 'a1000000-0000-0000-0000-000000000001'$$,
  'A can send a far-future client timestamp');
select ok((select client_updated_at <= now() + interval '6 minutes' from public.workout_plans where id = 'a1000000-0000-0000-0000-000000000001'),
  'the far-future client timestamp was clamped to now()+5min');
select lives_ok($$insert into public.routines (id, user_id, title, category, start_time, end_time, repeat_days, client_updated_at)
  values ('a2000000-0000-0000-0000-000000000007', 'a0000000-0000-0000-0000-0000000000a1', 'R', 'Gym', '07:00', '08:00', '1', now() + interval '10 years')$$,
  'insert with a far-future timestamp works');
select ok((select client_updated_at <= now() + interval '6 minutes' from public.routines where id = 'a2000000-0000-0000-0000-000000000007'),
  'insert timestamp clamped too');

-- privileged functions are service-role only
select throws_ok($$select public.publish_catalogue()$$, '42501', 'users cannot publish the catalogue');
select throws_ok($$select public.revenue_summary()$$, '42501', 'users cannot read revenue');
select throws_ok($$select public.apply_revenuecat_event('{"id":"x"}'::jsonb, '{}'::jsonb)$$, '42501', 'users cannot apply billing events');
select lives_ok($$select public.server_time()$$, 'signed-in users can read the server time');

-- entitlements / audit / catalogue tampering
select throws_ok($$insert into public.entitlements (user_id, entitlement_id, is_active) values ('a0000000-0000-0000-0000-0000000000a1', 'premium', true)$$,
  '42501', 'users cannot grant themselves premium');
select throws_ok($$update public.entitlements set is_active = true where user_id = 'a0000000-0000-0000-0000-0000000000a1'$$,
  '42501', 'users cannot edit their entitlement');
select throws_ok($$insert into public.audit_log (action) values ('forged')$$, '42501', 'users cannot write the audit log');
select throws_ok($$select count(*) from public.audit_log$$, '42501', 'users cannot read the audit log');
select throws_ok($$update public.profiles set deleted_at = null, disabled = false where id = 'a0000000-0000-0000-0000-0000000000a1'$$,
  '42501', 'users cannot edit privileged profile columns');

-- favourites merge
select is((select public.merge_favourites('{"12": {"f": true, "t": "2026-10-01T10:00:00Z"}, "bad key": {"f": true, "t": "2026-10-01T10:00:00Z"}}'::jsonb) -> '12' ->> 'f'), 'true',
  'favourites: valid item stored');
select is((select public.merge_favourites('{"12": {"f": false, "t": "2026-09-01T10:00:00Z"}}'::jsonb) -> '12' ->> 'f'), 'true',
  'favourites: an older change does not override a newer one');
select is((select public.merge_favourites('{"12": {"f": false, "t": "2026-11-01T10:00:00Z"}}'::jsonb) -> '12' ->> 'f'), 'false',
  'favourites: a newer change wins');
select ok(not ((select settings -> 'favourites' from public.profiles where id = 'a0000000-0000-0000-0000-0000000000a1') ? 'bad key'),
  'favourites: invalid keys are dropped');
reset role;

-- ===== user B cannot see A favourites; storage writes denied =====
set local role authenticated;
select set_config('request.jwt.claim.sub', 'b0000000-0000-0000-0000-0000000000b2', true);
select ok((select settings -> 'favourites' from public.profiles where id = 'b0000000-0000-0000-0000-0000000000b2') is null,
  'B has no favourites from A (isolation)');
reset role;

-- storage: real Supabase has RLS on storage.objects; the stub does not, so enable it here.
grant all on storage.objects to authenticated;
alter table storage.objects enable row level security;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-0000000000a1', true);
select throws_ok($$insert into storage.objects (bucket_id, name) values ('exercise-media', 'evil.mp4')$$,
  '42501', 'authenticated users cannot upload to the catalogue media bucket');
reset role;

select * from finish();
rollback;
