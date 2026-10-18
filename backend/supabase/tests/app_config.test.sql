-- Tests for 0009: app_config, announcements, manual (comp) premium grants, DB audit trail.
begin;
select plan(56);

create function pg_temp.affected(q text) returns int language plpgsql as $f$
declare n int;
begin execute q; get diagnostics n = row_count; return n; end $f$;

insert into auth.users (id, email) values
  ('c1000000-0000-0000-0000-0000000000c1', 'comp@example.test'),
  ('c2000000-0000-0000-0000-0000000000c2', 'other@example.test'),
  ('c3000000-0000-0000-0000-0000000000c3', 'owner@example.test');

insert into public.exercises_catalog (id, name, primary_muscle_group, status) values (9301, 'Comp video', 'Chest', 'published');
insert into public.exercise_media (exercise_id, media_type, mime_type, storage_path, size_bytes, license, attribution, license_verified, status)
  values (9301, 'video', 'video/mp4', 'videos/9301.mp4', 1000, 'Own footage', 'Owner', true, 'published');

-- ===== app_config: shape =====
select is((select count(*)::int from public.app_config), 1, 'exactly one config row exists after migration');
select is((select maintenance_mode from public.app_config), false, 'maintenance is off by default');
select throws_ok($$insert into public.app_config (id) values (2)$$, '23514', 'a second config row is impossible (id = 1 check)');
select throws_ok($$update public.app_config set min_app_version = '1.2'$$, '23514', 'min_app_version must be semver (x.y.z)');
select throws_ok($$update public.app_config set min_app_version = 'latest'$$, '23514', 'min_app_version rejects text');
select lives_ok($$update public.app_config set min_app_version = '1.2.3+4'$$, 'semver with build number is accepted');
select throws_ok($$update public.app_config set paywall_title = repeat('x', 81)$$, '23514', 'paywall title longer than 80 chars is rejected');
select throws_ok($$update public.app_config set paywall_title = ''$$, '23514', 'empty paywall title is rejected (use NULL for default)');
select throws_ok($$update public.app_config set paywall_benefits = '"not a list"'::jsonb$$, '23514', 'benefits must be an array');
select throws_ok($$update public.app_config set paywall_benefits = '[1,2]'::jsonb$$, '23514', 'benefits must be strings');
select throws_ok($$update public.app_config set paywall_benefits = '["a","b","c","d","e","f","g","h","i"]'::jsonb$$, '23514', 'more than 8 benefits is rejected');
select throws_ok($$update public.app_config set paywall_benefits = jsonb_build_array(repeat('x', 121))$$, '23514', 'a benefit longer than 120 chars is rejected');
select lives_ok($$update public.app_config set paywall_benefits = '["Track every set","Offline first"]'::jsonb$$, 'valid benefits are accepted');
select throws_ok($$update public.app_config set plan_badges = '{"weekly":"Hot"}'::jsonb$$, '23514', 'unknown plan key in badges is rejected');
select throws_ok($$update public.app_config set plan_badges = jsonb_build_object('yearly', repeat('x', 25))$$, '23514', 'badge text longer than 24 chars is rejected');
select lives_ok($$update public.app_config set plan_badges = '{"yearly":"Best value"}'::jsonb$$, 'valid badge is accepted');
select throws_ok($$update public.app_config set access_model_override = 'free'$$, '23514', 'unknown access model is rejected');
select lives_ok($$update public.app_config set access_model_override = 'freemium'$$, 'known access model is accepted');
select throws_ok($$update public.app_config set maintenance_message = repeat('x', 301)$$, '23514', 'maintenance message longer than 300 chars is rejected');

-- ===== app_config: who may read / write =====
set local role anon;
select is((select count(*)::int from public.app_config), 1, 'anon can read the config');
select throws_ok($$update public.app_config set maintenance_mode = true$$, '42501', 'anon cannot write the config');
select throws_ok($$delete from public.app_config$$, '42501', 'anon cannot delete the config');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'c2000000-0000-0000-0000-0000000000c2', true);
select is((select count(*)::int from public.app_config), 1, 'a signed-in user can read the config');
select throws_ok($$update public.app_config set maintenance_mode = true$$, '42501', 'a signed-in user cannot write the config');
select throws_ok($$insert into public.announcements (title, body) values ('x', 'y')$$, '42501', 'a signed-in user cannot create announcements');
reset role;
set local role service_role;
select lives_ok($$update public.app_config set maintenance_mode = true, maintenance_message = 'Back soon'$$, 'the service role can write the config');
reset role;
update public.app_config set maintenance_mode = false;

-- ===== announcements: visibility window =====
insert into public.announcements (id, title, body, level, starts_at, ends_at, active) values
  ('a0000000-0000-0000-0000-000000000001', 'Live', 'in window', 'info', now() - interval '1 day', now() + interval '1 day', true),
  ('a0000000-0000-0000-0000-000000000002', 'Open ended', 'no end', 'warning', now() - interval '1 day', null, true),
  ('a0000000-0000-0000-0000-000000000003', 'Switched off', 'inactive', 'info', now() - interval '1 day', null, false),
  ('a0000000-0000-0000-0000-000000000004', 'Future', 'not yet', 'info', now() + interval '1 day', null, true),
  ('a0000000-0000-0000-0000-000000000005', 'Expired', 'too late', 'info', now() - interval '3 days', now() - interval '1 day', true);
select throws_ok($$insert into public.announcements (title, body, level) values ('x', 'y', 'critical')$$, '23514', 'level must be info or warning');
select throws_ok($$insert into public.announcements (title, body, starts_at, ends_at) values ('x', 'y', now(), now() - interval '1 hour')$$, '23514', 'ends_at must be after starts_at');
select throws_ok($$insert into public.announcements (title, body) values (repeat('t', 81), 'y')$$, '23514', 'announcement title longer than 80 is rejected');
select throws_ok($$insert into public.announcements (title, body) values ('t', repeat('b', 501))$$, '23514', 'announcement body longer than 500 is rejected');

set local role anon;
select is((select count(*)::int from public.announcements), 2, 'anon sees only active announcements inside their window');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'c2000000-0000-0000-0000-0000000000c2', true);
select is((select count(*)::int from public.announcements where title in ('Switched off', 'Future', 'Expired')), 0,
  'inactive, future and expired announcements are invisible to users');
select throws_ok($$update public.announcements set title = 'hax'$$, '42501', 'users cannot edit announcements');
reset role;

-- ===== manual premium grants =====
select throws_ok($$insert into public.manual_premium_grants (user_id, reason) values ('c1000000-0000-0000-0000-0000000000c1', 'x')$$, '23514', 'a grant needs a real reason (3+ chars)');
select throws_ok($$insert into public.manual_premium_grants (user_id, reason, granted_at, expires_at)
  values ('c1000000-0000-0000-0000-0000000000c1', 'bad dates', now(), now() - interval '1 day')$$, '23514', 'a grant cannot expire before it starts');

insert into public.manual_premium_grants (id, user_id, reason, granted_by, expires_at)
  values ('b0000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-0000000000c1', 'Support goodwill', 'c3000000-0000-0000-0000-0000000000c3', now() + interval '7 days');
select is((select is_active from public.entitlements where user_id = 'c1000000-0000-0000-0000-0000000000c1' and entitlement_id = 'premium_comp'), true,
  'a live grant creates an active premium_comp entitlement');
select is((select store from public.entitlements where user_id = 'c1000000-0000-0000-0000-0000000000c1' and entitlement_id = 'premium_comp'), 'comp',
  'the comp row is marked as store = comp');
select is((select public.video_access('c1000000-0000-0000-0000-0000000000c1', 9301) ->> 'allowed'), 'true', 'comp access works for videos (video-url decision)');
select is((select public.is_entitled('c2000000-0000-0000-0000-0000000000c2')), false, 'a user without any grant is not entitled');

-- revoke
update public.manual_premium_grants set revoked_at = now(), revoked_by = 'c3000000-0000-0000-0000-0000000000c3'
 where id = 'b0000000-0000-0000-0000-000000000001';
select is((select is_active from public.entitlements where user_id = 'c1000000-0000-0000-0000-0000000000c1' and entitlement_id = 'premium_comp'), false, 'revoking the grant deactivates the entitlement');
select is((select public.video_access('c1000000-0000-0000-0000-0000000000c1', 9301) ->> 'reason'), 'not_entitled', 'a revoked grant no longer unlocks videos');

-- expired (is_active stays true in the row until a re-sync, but the expiry check must still deny)
insert into public.manual_premium_grants (id, user_id, reason, granted_at, expires_at)
  values ('b0000000-0000-0000-0000-000000000002', 'c2000000-0000-0000-0000-0000000000c2', 'Short comp', now() - interval '10 days', now() - interval '1 day');
select is((select public.is_entitled('c2000000-0000-0000-0000-0000000000c2')), false, 'an expired grant does not entitle');
select is((select is_active from public.entitlements where user_id = 'c2000000-0000-0000-0000-0000000000c2' and entitlement_id = 'premium_comp'), false,
  'an already-expired grant is stored inactive');

-- stale row: simulate a live grant whose expiry has since passed without a re-sync
update public.entitlements set is_active = true, expires_at = now() - interval '1 hour'
 where user_id = 'c2000000-0000-0000-0000-0000000000c2' and entitlement_id = 'premium_comp';
select is((select public.is_entitled('c2000000-0000-0000-0000-0000000000c2')), false, 'is_active but past expiry is denied (no clock sync needed)');

-- open-ended grant (the admin app allows it for owners only)
insert into public.manual_premium_grants (id, user_id, reason) values ('b0000000-0000-0000-0000-000000000003', 'c2000000-0000-0000-0000-0000000000c2', 'Founder access');
select is((select expires_at is null and is_active from public.entitlements where user_id = 'c2000000-0000-0000-0000-0000000000c2' and entitlement_id = 'premium_comp'), true,
  'an open-ended grant gives an active comp row without expiry');
select is((select public.is_entitled('c2000000-0000-0000-0000-0000000000c2')), true, 'open-ended comp entitles');

-- comp never counts as revenue
select is((select active_subscribers from public.revenue_summary()), 0::bigint, 'comp grants are not counted as paying subscribers');

-- ===== grants are private + the sync helper is not callable =====
set local role authenticated;
select set_config('request.jwt.claim.sub', 'c2000000-0000-0000-0000-0000000000c2', true);
select throws_ok($$select * from public.manual_premium_grants$$, '42501', 'users cannot read grants');
select throws_ok($$insert into public.manual_premium_grants (user_id, reason) values ('c2000000-0000-0000-0000-0000000000c2', 'self grant')$$, '42501', 'users cannot grant themselves access');
select throws_ok($$select public.sync_comp_entitlement('c2000000-0000-0000-0000-0000000000c2')$$, '42501', 'users cannot call the sync helper');
select throws_ok($$update public.entitlements set is_active = true where entitlement_id = 'premium_comp'$$, '42501', 'users cannot write entitlements');
select is((select count(*)::int from public.entitlements where entitlement_id = 'premium_comp'), 1, 'a user sees only their own comp entitlement row');
reset role;
set local role anon;
select throws_ok($$select * from public.manual_premium_grants$$, '42501', 'anon cannot read grants');
reset role;

-- ===== DB-level audit trail (names only, never values) =====
update public.app_config set maintenance_message = 'Secret planned work', maintenance_mode = true;
select is((select metadata -> 'columns' from public.audit_log where action = 'db.app_config.update' order by id desc limit 1),
  '["maintenance_message","maintenance_mode"]'::jsonb,
  'the latest config change is audited with exactly the changed column names');
select is((select count(*)::int from public.audit_log where metadata::text like '%Secret planned work%' or metadata::text like '%Support goodwill%'), 0,
  'the audit trail never stores values (copy / grant reasons)');
select ok((select count(*) from public.audit_log where action = 'db.manual_premium_grants.insert') >= 3, 'grant creation is audited at the DB level');

select * from finish();
rollback;
