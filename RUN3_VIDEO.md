# RUN3_VIDEO - protected, on-demand exercise videos (fork B)

Scope: take videos out of the APK/AAB, serve them only to entitled users from a private Supabase bucket through
short-lived signed URLs, download on demand per exercise, cache privately, delete the cache when the entitlement ends.
Nothing was committed, pushed, deployed or uploaded. No keys or URLs were invented. All network behaviour is tested
with fakes (labelled MOCK-ONLY); nothing ran against a real Supabase project.

## What changed
**Assets / data**
* The 123 encoded files moved `assets/videos/exercises/` -> `media_src/encoded/` (gitignored; the originals stay in `media_src/`).
  `assets/videos/` no longer exists; `pubspec.yaml` assets list has no video path (photos stay bundled).
  One-off, idempotent tool: `tool/relocate_videos_to_storage.py`.
* `assets/exercise_demonstrations.json`: `local_bundled_path` and the third-party `video_url` are null for every exercise;
  every exercise with a video has `storage_path = videos/<exercise_id>.mp4`. The old text "MIT License / Free Exercise DB ..." that the
  UI showed as the video licence was an unverified claim: every entry now says `license: UNVERIFIED`,
  `attribution: Source and licence not yet verified`. Nothing was marked VERIFIED.
* `media_manifest.json`: `storage_path` + `encoded_path` per entry and a `delivery` note.
* `scripts/validate_media.py` (+ `scripts/test_validate_media.py`, 14 python tests) now validates `media_src/encoded`, checks
  `storage_path`, rejects any video under `assets/` or in `pubspec.yaml`, any `local_bundled_path` and any `video_url`;
  `tool/*.py` default paths updated; `MEDIA_GUIDE.md` rewritten for the new workflow.

**Backend** (`backend/`)
* `migrations/0008_protected_videos.sql`: PRIVATE bucket `exercise-videos` (not public, mp4, 20 MB); a RESTRICTIVE policy on
  `storage.objects` denies `anon`/`authenticated` any access to that bucket even if an over-broad permissive policy is added later
  (verified failing-then-passing in the harness); the public bucket `exercise-media` now accepts images only;
  `public.video_access(user, exercise, require_verified)` (service role only) = server-side decision: `premium` entitlement active and
  not past expiry (TRIAL counts; billing-issue grace <= 16 days; refunded/expired -> denied), published catalogue exercise, published
  `exercise_media` video row with `license_verified = true`.
* Edge Function `video-url` (`functions/video-url/index.ts`, pure logic in `functions/_shared/video_url.ts`): bearer JWT -> user,
  clamps `exercise_id`, per-user rate limit (60/min per instance), 300 s signed URL, 403 not entitled / 404 no video (unknown id, NO_VIDEO,
  unlicensed) / 401 / 400 / 405 / 429, generic 5xx, never logs or echoes tokens. NOT executed (no Deno).
* RevenueCat webhook module: trial handling confirmed and covered by 4 new tests (INITIAL_PURCHASE `period_type: TRIAL` is an ACTIVE
  entitlement until the trial ends; trial EXPIRATION removes access; conversion by RENEWAL is active; cancel during trial keeps access
  to the end, a CUSTOMER_SUPPORT refund revokes at once).
* Harness stubs: now grant `usage` on schema `storage`, so storage tests exercise RLS instead of passing on "permission denied for schema"
  (this also makes the older hardening storage test meaningful). `backend/README.md` documents the function; harness `test:logic` runs the new node tests.
* `scripts/upload_videos.mjs`: uploads `media_src/encoded` to the private bucket at `storage_path`; VERIFIED entries only unless
  `--include-unverified` (test uploads); skips same-size objects (`--force` replaces); `--rows` creates DRAFT, unverified rows (never
  publishes); `--dry-run` needs no network. Service-role key from env or `admin/.env.local` only.
* Admin panel: video uploads now go to the private bucket (`exercise-videos`), images stay in `exercise-media`; deleting a video removes it
  from the right bucket. Admin tests: 147 pass (3 new, MOCK-ONLY).

**Flutter**
* `lib/services/video_access_service.dart` (new): `VideoAccessService` with injectable `canAccessVideos` and `SignedUrlFetcher`, a
  downloader interface, a private-directory cache (`<app support>/video_cache`, JSON index, `.part` + atomic rename, size check on read,
  corrupt index ignored), one in-flight download per exercise, entitlement re-checked after the download, `clearCache()`,
  `onEntitlementChanged(entitled, {known})`, `purgeIfNotEntitled()`. Real wiring: `VideoAccessService.instance` uses
  `CloudServices.premium.isPremium` (read-only; adapt that single line if the access-gate API differs) and
  `Supabase.instance.client.functions.invoke('video-url')`; failures map to `notEntitled / noVideo / offline / unavailable / failed`.
* `ExerciseMediaService`: new source types `protectedDownload` (entitled, not cached yet: the player downloads now) and `lockedPhoto`
  (has a video but no active subscription: photo + short text, never the video). Cached + entitled -> `downloadedFile`. NO_VIDEO -> photo.
  `kBundledVideosEnabled=false` -> photo for everything with no access/network call. The third-party remote-stream branch was removed.
  Inventory report gained `protected_video_demonstrations_count`.
* `ExerciseDemonstrationPlayer`: states for downloading (progress), offline ("Connect once to download this video" + Retry), error (Retry),
  locked, NO_VIDEO; a download finishing after the user moved to another exercise is ignored (init token), so a stale video is never shown;
  overlays scroll instead of overflowing at 360x640 / text x2.0 (also fixed the old error overlay overflow).
* `ExerciseDemonstration` model: `storagePath`, `hasProtectedVideo`; default licence text is now `UNVERIFIED` instead of "MIT License".

## Wiring the parent / fork A must do (not done here, files not mine)
1. After `CloudServices.premium.initialize()` in `main.dart`: `VideoAccessService.instance.purgeIfNotEntitled()` (only when the entitlement
   state is known; use `onEntitlementChanged(entitled, known: false)` before that).
2. Whenever the access gate flips to "locked" / the subscription expires / the user signs out / the account is deleted:
   `VideoAccessService.instance.onEntitlementChanged(false)` (or `clearCache()`).
3. If the gate API exposes a different "trial or premium" check than `CloudServices.premium.isPremium`, change the one `canAccessVideos` line
   in `VideoAccessService.instance`.
4. Privacy/Data-safety drafts: opening an exercise video sends the account id and the exercise id to the `video-url` function; the signed URL
   points at Supabase Storage. Mention it. The release checklist must include: apply migration 0008, deploy `video-url`, run
   `scripts/upload_videos.mjs`, verify licences + publish rows in the admin panel (until then the app simply shows photos).

## Tests and real results (run in this session)
* `flutter analyze`: clean for my files at the time of the last run (another fork's `test/access_gate_test.dart` was still in progress).
* New/updated Flutter tests: `video_protection_test` (12, cache), `media_flag_test`, `media_integrity_test` (no video in assets/pubspec,
  `storage_path` consistency), `video_player_states_test` (10 widget tests incl. 360x640 at text 1.0x/2.0x), plus truthful updates to
  `exercise_demonstration_test`, `active_workout_and_split_test`, `catalogue_audit_comprehensive_test`, `category_filtering_test`.
* Backend harness: 119 SQL assertions (27 new in `video_access.test.sql`), 33 node tests (12 new for `video_url`, 4 new for trial), 0 failures.
* Admin: tsc + eslint clean, 147 vitest tests pass. Python: validator tests 14 pass; `validate_media.py` on the repo: 0 errors, 1 warning.

## UNVERIFIED / BLOCKED
* Nothing ran against a real Supabase project (no bucket, no Edge Function execution, no real signed URL), against Google Play or a device.
  The native video player is not available under `flutter test`, so playback from the cached file is untested; tests stop at the states before playback.
* The Edge Function was not executed (no Deno); only its pure module (node) and the SQL decision (PGlite) are tested.
* A purchase becomes visible to the function only after the RevenueCat webhook has written `entitlements` (seconds); until then the app shows the
  photo/locked state and retries on the next open.
* The 123 videos still have no proven source/licence: the server will not serve them until a human verifies and publishes each row.
