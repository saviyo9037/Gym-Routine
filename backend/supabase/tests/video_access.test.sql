-- Tests for 0008 (protected videos): private bucket, no client access to it, and the server-side
-- access decision public.video_access() that the `video-url` Edge Function relies on.
begin;
select plan(34);

insert into auth.users (id, email) values
  ('a1000000-0000-0000-0000-0000000000a1', 'paidmonthly@example.test'), -- paid, renewing (was a trial before 0010)
  ('a2000000-0000-0000-0000-0000000000a2', 'free@example.test'),       -- no entitlement row
  ('a3000000-0000-0000-0000-0000000000a3', 'expired@example.test'),    -- is_active but past expiry (missed webhook)
  ('a4000000-0000-0000-0000-0000000000a4', 'grace@example.test'),      -- billing issue, 3 days past expiry
  ('a5000000-0000-0000-0000-0000000000a5', 'oldgrace@example.test'),   -- billing issue, 20 days past expiry
  ('a6000000-0000-0000-0000-0000000000a6', 'refund@example.test'),     -- refunded: is_active=false, future expiry
  ('a7000000-0000-0000-0000-0000000000a7', 'paid@example.test'),       -- normal paid, no expiry (lifetime)
  ('a8000000-0000-0000-0000-0000000000a8', 'other@example.test'),      -- another entitlement id only
  ('b1000000-0000-0000-0000-0000000000b1', 'trial@example.test'),      -- active store trial
  ('b3000000-0000-0000-0000-0000000000b3', 'both@example.test');       -- trial premium row AND a live comp grant

insert into public.entitlements (user_id, entitlement_id, is_active, period_type, expires_at, billing_issue_detected_at) values
  ('a1000000-0000-0000-0000-0000000000a1', 'premium', true,  'NORMAL', now() + interval '20 days', null),
  ('b1000000-0000-0000-0000-0000000000b1', 'premium', true,  'TRIAL',  now() + interval '1 day', null),
  ('b3000000-0000-0000-0000-0000000000b3', 'premium', true,  'TRIAL',  now() + interval '1 day', null),
  ('a3000000-0000-0000-0000-0000000000a3', 'premium', true,  'NORMAL', now() - interval '2 days', null),
  ('a4000000-0000-0000-0000-0000000000a4', 'premium', true,  'NORMAL', now() - interval '3 days', now() - interval '3 days'),
  ('a5000000-0000-0000-0000-0000000000a5', 'premium', true,  'NORMAL', now() - interval '20 days', now() - interval '20 days'),
  ('a6000000-0000-0000-0000-0000000000a6', 'premium', false, 'NORMAL', now() + interval '20 days', null),
  ('a7000000-0000-0000-0000-0000000000a7', 'premium', true,  'NORMAL', null, null),
  ('a8000000-0000-0000-0000-0000000000a8', 'other',   true,  'NORMAL', now() + interval '20 days', null),
  ('b3000000-0000-0000-0000-0000000000b3', 'premium_comp', true, 'COMP', null, null);

insert into public.exercises_catalog (id, name, primary_muscle_group, status) values
  (9101, 'Video ok', 'Chest', 'published'),
  (9102, 'No video at all', 'Chest', 'published'),
  (9103, 'Licence not verified', 'Chest', 'published'),
  (9104, 'Exercise still draft', 'Chest', 'draft'),
  (9105, 'Media still draft', 'Chest', 'published'),
  (9106, 'Image only', 'Chest', 'published');

insert into public.exercise_media (exercise_id, media_type, mime_type, storage_path, size_bytes, license, attribution, license_verified, status) values
  (9101, 'video', 'video/mp4', 'videos/9101.mp4', 1000, 'Own footage', 'Owner', true,  'published'),
  (9103, 'video', 'video/mp4', 'videos/9103.mp4', 1000, 'UNVERIFIED',  'Owner', false, 'published'),
  (9104, 'video', 'video/mp4', 'videos/9104.mp4', 1000, 'Own footage', 'Owner', true,  'published'),
  (9105, 'video', 'video/mp4', 'videos/9105.mp4', 1000, 'Own footage', 'Owner', true,  'draft'),
  (9106, 'image', 'image/jpeg', 'img/9106.jpg',   1000, 'Own photo',   'Owner', true,  'published');

-- ===== bucket =====
select is((select public from storage.buckets where id = 'exercise-videos'), false, 'exercise-videos is private');
select is((select allowed_mime_types from storage.buckets where id = 'exercise-videos'), array['video/mp4'], 'exercise-videos accepts mp4 only');
select ok((select not ('video/mp4' = any (allowed_mime_types)) from storage.buckets where id = 'exercise-media'),
  'the public exercise-media bucket no longer accepts videos');

-- ===== access decision (service role only) =====
select is((select public.video_access('a1000000-0000-0000-0000-0000000000a1', 9101)),
  jsonb_build_object('allowed', true, 'storage_path', 'videos/9101.mp4', 'mime_type', 'video/mp4'),
  'paid entitlement gets the path');
select is((select public.video_access('a7000000-0000-0000-0000-0000000000a7', 9101) ->> 'allowed'), 'true', 'paid entitlement without expiry is allowed');
select is((select public.video_access('a4000000-0000-0000-0000-0000000000a4', 9101) ->> 'allowed'), 'true', 'billing-issue grace (3 days past expiry) is allowed');
select is((select public.video_access('a2000000-0000-0000-0000-0000000000a2', 9101) ->> 'reason'), 'not_entitled', 'user with no entitlement is denied');
select is((select public.video_access('a3000000-0000-0000-0000-0000000000a3', 9101) ->> 'reason'), 'not_entitled', 'is_active but past expiry is denied (missed expiration webhook)');
select is((select public.video_access('a5000000-0000-0000-0000-0000000000a5', 9101) ->> 'reason'), 'not_entitled', 'grace older than 16 days is denied');
select is((select public.video_access('a6000000-0000-0000-0000-0000000000a6', 9101) ->> 'reason'), 'not_entitled', 'refunded (is_active=false) is denied even with a future expiry');
select is((select public.video_access('a8000000-0000-0000-0000-0000000000a8', 9101) ->> 'reason'), 'not_entitled', 'a different entitlement id does not count');
select is((select public.video_access('00000000-0000-0000-0000-00000000dead', 9101) ->> 'reason'), 'not_entitled', 'unknown user is denied');
select is((select public.video_access(null, 9101) ->> 'reason'), 'bad_request', 'null user is rejected');
select is((select public.video_access('a1000000-0000-0000-0000-0000000000a1', -5) ->> 'reason'), 'bad_request', 'invalid exercise id is rejected');

select is((select public.video_access('a1000000-0000-0000-0000-0000000000a1', 9102) ->> 'reason'), 'no_video', 'exercise without a video (NO_VIDEO) is rejected');
select is((select public.video_access('a1000000-0000-0000-0000-0000000000a1', 987654) ->> 'reason'), 'no_video', 'unknown exercise is rejected');
select is((select public.video_access('a1000000-0000-0000-0000-0000000000a1', 9103) ->> 'reason'), 'no_video', 'unverified licence is not served by default');
select is((select public.video_access('a1000000-0000-0000-0000-0000000000a1', 9103, false) ->> 'allowed'), 'true', 'unverified licence is served only when explicitly allowed (dev switch)');
select is((select public.video_access('a1000000-0000-0000-0000-0000000000a1', 9104) ->> 'reason'), 'no_video', 'draft exercise is not served');
select is((select public.video_access('a1000000-0000-0000-0000-0000000000a1', 9105) ->> 'reason'), 'no_video', 'draft media is not served');
select is((select public.video_access('a1000000-0000-0000-0000-0000000000a1', 9106) ->> 'reason'), 'no_video', 'an image row is not a video');

-- ===== trial tier (0010): trials are entitled but get NO signed path =====
select is((select public.entitlement_tier('b1000000-0000-0000-0000-0000000000b1')), 'trial', 'active store trial is tier trial');
select is((select public.entitlement_tier('a1000000-0000-0000-0000-0000000000a1')), 'full', 'paid renewing is tier full');
select is((select public.entitlement_tier('a4000000-0000-0000-0000-0000000000a4')), 'full', 'billing-issue grace on a paid row is tier full');
select is((select public.entitlement_tier('b3000000-0000-0000-0000-0000000000b3')), 'full', 'a live comp grant is full even next to a trial row');
select is((select public.entitlement_tier('a2000000-0000-0000-0000-0000000000a2')), 'none', 'no entitlement is tier none');
select is((select public.video_access('b1000000-0000-0000-0000-0000000000b1', 9101) ->> 'reason'), 'trial_locked', 'a trial user gets NO signed path (default)');
select is((select public.video_access('b1000000-0000-0000-0000-0000000000b1', 9101, true, true) ->> 'allowed'), 'true', 'a trial user is served only when p_allow_trial is set (TRIAL_VIDEOS_LOCKED=false)');

-- ===== storage: no client access to the private bucket =====
insert into storage.objects (bucket_id, name) values ('exercise-videos', 'videos/9101.mp4'), ('exercise-media', 'img/9106.jpg');
grant select, insert, update, delete on storage.objects to anon, authenticated, service_role;
-- Simulate a future mistake: an over-broad permissive policy. The restrictive policy must still win.
create policy tmp_open_read on storage.objects for select to anon, authenticated using (true);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a1000000-0000-0000-0000-0000000000a1', true);
select is((select count(*)::int from storage.objects where bucket_id = 'exercise-videos'), 0,
  'a signed-in (even entitled) client cannot read objects of the private bucket directly');
select is((select count(*)::int from storage.objects where bucket_id = 'exercise-media'), 1,
  'other buckets are unaffected by the restrictive policy');
select throws_ok($$insert into storage.objects (bucket_id, name) values ('exercise-videos', 'videos/evil.mp4')$$, '42501',
  'clients cannot upload to the private bucket');
reset role;
set local role anon;
select is((select count(*)::int from storage.objects where bucket_id = 'exercise-videos'), 0, 'anon cannot read the private bucket');
reset role;
set local role service_role;
select is((select count(*)::int from storage.objects where bucket_id = 'exercise-videos'), 1, 'the service role (signing/uploads) can see it');
reset role;

-- ===== privileges =====
set local role authenticated;
select throws_ok($$select public.video_access('a1000000-0000-0000-0000-0000000000a1', 9101)$$, '42501',
  'signed-in users cannot call video_access directly');
reset role;

select * from finish();
rollback;
