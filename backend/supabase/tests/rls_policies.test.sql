-- pgTAP-style tests for RLS, grants, triggers and RPCs. Run with `supabase test db`
-- (real pgTAP) or backend/harness/run-sql-tests.mjs (PGlite + minimal pgTAP subset).
begin;
select plan(47);

create function pg_temp.affected(q text) returns int language plpgsql as $f$
declare n int;
begin execute q; get diagnostics n = row_count; return n; end $f$;

-- fixtures (as superuser) ------------------------------------------------------
insert into auth.users (id, email) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'a@example.test'),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'b@example.test'),
  ('cccccccc-0000-0000-0000-000000000003', 'owner@example.test'),
  ('dddddddd-0000-0000-0000-000000000004', 'support@example.test');
insert into public.admins (user_id, role) values
  ('cccccccc-0000-0000-0000-000000000003', 'owner'),
  ('dddddddd-0000-0000-0000-000000000004', 'support');

insert into public.workout_plans (id, user_id, plan_date) values
  ('a1000000-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', '2026-01-01'),
  ('b1000000-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000002', '2026-01-01');
insert into public.workout_sessions (id, user_id, session_date, start_time, primary_muscle) values
  ('a2000000-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', '2026-01-01', now(), 'Chest'),
  ('b2000000-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000002', '2026-01-01', now(), 'Back');
insert into public.session_sets (id, user_id, session_id, exercise_id, exercise_name, set_number, reps, weight_kg, completed_at) values
  ('a3000000-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000001', 1, 'Bench', 1, 10, 50, now()),
  ('b3000000-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000002', 'b2000000-0000-0000-0000-000000000001', 2, 'Row', 1, 10, 40, now());
insert into public.entitlements (user_id, is_active) values
  ('aaaaaaaa-0000-0000-0000-000000000001', true),
  ('bbbbbbbb-0000-0000-0000-000000000002', true);
insert into public.exercises_catalog (id, name, primary_muscle_group, status) values
  (1, 'Bench Press', 'Chest', 'published'),
  (2, 'Secret Draft', 'Back', 'draft');
insert into public.catalogue_versions (version, notes) values (1, 'seed');
update public.exercises_catalog set catalogue_version = 1, needs_publish = false where id = 1;
insert into public.exercise_media (exercise_id, media_type, mime_type, storage_path, size_bytes, license, attribution, status)
  values (1, 'video', 'video/mp4', 'x/1.mp4', 1000, 'own-work', 'Me', 'published'),
         (1, 'image', 'image/png', 'x/2.png', 1000, 'own-work', 'Me', 'draft');

-- structure -----------------------------------------------------------------------
select is((select count(*)::int from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind = 'r'
             and not c.relrowsecurity), 0, 'RLS is enabled on every public table');

-- user A -------------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claim.sub', 'aaaaaaaa-0000-0000-0000-000000000001', true);

select is((select count(*)::int from public.workout_plans), 1, 'A sees only own plans');
select is((select count(*)::int from public.session_sets), 1, 'A sees only own sets');
select is((select count(*)::int from public.workout_sessions where user_id = 'bbbbbbbb-0000-0000-0000-000000000002'), 0, 'A cannot read B sessions');
select is((select count(*)::int from public.profiles), 1, 'A sees only own profile');
select is((select count(*)::int from public.entitlements), 1, 'A sees only own entitlement');
select lives_ok($$insert into public.routines (id, user_id, title, category, start_time, end_time, repeat_days)
  values ('a4000000-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'Run', 'Fitness', '06:00', '07:00', '1,3,5')$$,
  'A can insert own routine');
select throws_ok($$insert into public.routines (id, user_id, title, category, start_time, end_time, repeat_days)
  values ('a4000000-0000-0000-0000-000000000002', 'bbbbbbbb-0000-0000-0000-000000000002', 'Evil', 'x', '1', '2', '1')$$,
  '42501', 'A cannot insert a routine for B');
select is(pg_temp.affected($$update public.workout_plans set notes = 'hax' where id = 'b1000000-0000-0000-0000-000000000001'$$),
  0, 'A cannot update B plan (0 rows)');
select is(pg_temp.affected($$update public.workout_plans set notes = 'mine' where id = 'a1000000-0000-0000-0000-000000000001'$$),
  1, 'A can update own plan');
select throws_ok($$update public.workout_plans set user_id = 'bbbbbbbb-0000-0000-0000-000000000002' where id = 'a1000000-0000-0000-0000-000000000001'$$,
  '42501', 'A cannot hand own row to B (WITH CHECK)');
select lives_ok($$update public.workout_plans set deleted_at = now() where id = 'a1000000-0000-0000-0000-000000000001'$$,
  'A can soft-delete own plan');
select throws_ok($$delete from public.workout_plans where id = 'a1000000-0000-0000-0000-000000000001'$$,
  '42501', 'hard DELETE is not granted to users');
select lives_ok($$update public.profiles set display_name = 'Alice' where id = 'aaaaaaaa-0000-0000-0000-000000000001'$$,
  'A can edit own display_name');
select throws_ok($$update public.profiles set disabled = false where id = 'aaaaaaaa-0000-0000-0000-000000000001'$$,
  '42501', 'A cannot change the disabled flag');
select throws_ok($$insert into public.entitlements (user_id, is_active) values ('aaaaaaaa-0000-0000-0000-000000000001', true)$$,
  '42501', 'user cannot write entitlements');
select throws_ok($$select * from public.revenuecat_events$$, '42501', 'user cannot read revenuecat_events');
select throws_ok($$select * from public.audit_log$$, '42501', 'user cannot read audit_log');
select throws_ok($$insert into public.admins (user_id, role) values ('aaaaaaaa-0000-0000-0000-000000000001', 'owner')$$,
  '42501', 'user cannot make themselves admin');
select is((select count(*)::int from public.admins), 0, 'non-admin sees no admin rows');
select is(public.is_admin(), false, 'is_admin() false for normal user');
-- catalogue read-only
select is((select count(*)::int from public.exercises_catalog), 1, 'users see published catalogue rows only');
select is((select count(*)::int from public.exercise_media), 1, 'users see published media only');
select throws_ok($$insert into public.exercises_catalog (id, name, primary_muscle_group) values (99, 'x', 'Chest')$$,
  '42501', 'user cannot insert into catalogue');
select throws_ok($$update public.exercises_catalog set name = 'x' where id = 1$$, '42501', 'user cannot update catalogue');
select throws_ok($$select public.publish_catalogue()$$, '42501', 'user cannot call publish_catalogue');

-- anon ---------------------------------------------------------------------------
reset role;
set local role anon;
select throws_ok($$select * from public.workout_plans$$, '42501', 'anon cannot read user data');
select is((select count(*)::int from public.exercises_catalog), 1, 'anon can read published catalogue');

-- disabled user ----------------------------------------------------------------------
reset role;
update public.profiles set disabled = true where id = 'bbbbbbbb-0000-0000-0000-000000000002';
set local role authenticated;
select set_config('request.jwt.claim.sub', 'bbbbbbbb-0000-0000-0000-000000000002', true);
select throws_ok($$insert into public.routines (id, user_id, title, category, start_time, end_time, repeat_days)
  values ('b4000000-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000002', 'R', 'x', '1', '2', '1')$$,
  '42501', 'disabled user cannot write');

-- admin helpers -------------------------------------------------------------------------
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'cccccccc-0000-0000-0000-000000000003', true);
select is(public.is_admin('owner'), true, 'owner is_admin(owner)');
select is(public.is_admin('support'), false, 'owner is not support');
select is(public.current_admin_role(), 'owner', 'current_admin_role = owner');
select throws_ok($$delete from public.admins$$, '42501', 'admin users still cannot write admins through the API');

-- delete account RPC (as A) -------------------------------------------------------------
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'aaaaaaaa-0000-0000-0000-000000000001', true);
select lives_ok($$select public.delete_my_account_data()$$, 'A can call delete_my_account_data');
reset role;
select is((select count(*)::int from public.session_sets where user_id = 'aaaaaaaa-0000-0000-0000-000000000001'), 0, 'A data removed');
select is((select count(*)::int from public.session_sets where user_id = 'bbbbbbbb-0000-0000-0000-000000000002'), 1, 'B data untouched');

-- service role: constraints, publish, revenuecat, audit ------------------------------------
set local role service_role;
select throws_ok($$insert into public.exercises_catalog (id, name, primary_muscle_group) values (50, '  ', 'Chest')$$,
  '23514', 'empty exercise name rejected');
select throws_ok($$insert into public.exercises_catalog (id, name, primary_muscle_group) values (51, 'X', 'Neck')$$,
  '23514', 'invalid muscle group rejected');
select throws_ok($$insert into public.exercise_media (exercise_id, media_type, mime_type, storage_path, size_bytes, license, attribution)
  values (1, 'image', 'image/png', 'p', 5, '', 'a')$$, '23514', 'media without licence rejected');
select is(public.publish_catalogue(null, 't'), 2, 'publish bumps catalogue version to 2');
select is((select catalogue_version from public.exercises_catalog where id = 2), 2, 'pending rows stamped with new version');
select throws_ok($$select public.publish_catalogue()$$, 'P0001', 'publishing with nothing pending is refused');
select is(public.apply_revenuecat_event('{"id":"e1","type":"INITIAL_PURCHASE","event_timestamp_ms":100,"app_user_id":"x"}'::jsonb,
  '{"user_id":"bbbbbbbb-0000-0000-0000-000000000002","is_active":true,"will_renew":true}'::jsonb), 'applied', 'event applied');
select is(public.apply_revenuecat_event('{"id":"e1","type":"INITIAL_PURCHASE","event_timestamp_ms":100,"app_user_id":"x"}'::jsonb,
  '{"user_id":"bbbbbbbb-0000-0000-0000-000000000002","is_active":true,"will_renew":true}'::jsonb), 'duplicate', 'duplicate event id is idempotent');
select is(public.apply_revenuecat_event('{"id":"e0","type":"EXPIRATION","event_timestamp_ms":50,"app_user_id":"x"}'::jsonb,
  '{"user_id":"bbbbbbbb-0000-0000-0000-000000000002","is_active":false,"will_renew":false}'::jsonb), 'stale', 'older event ignored');
select is((select is_active from public.entitlements where user_id = 'bbbbbbbb-0000-0000-0000-000000000002'), true, 'stale event did not change entitlement');
insert into public.audit_log (actor_id, action) values (null, 'test');
select throws_ok($$update public.audit_log set action = 'x'$$, 'P0001', 'audit_log is append-only');

select * from finish();
rollback;
