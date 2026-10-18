# RepTrack - PROGRESS (resume file)

Strictly local: nothing committed, pushed or uploaded. No secrets in repo.

## Checklist
- [x] Verification & size phase (media provenance, re-encode, NO_VIDEO decision)
- [x] Phase 1 - Workout plans & active workout (host-tested; device UNVERIFIED) - AUDIT_WORKOUT.md
- [x] Phase 2 - Routines, alarms, history, stats (host + JVM tested; ALL alarm behaviour UNVERIFIED on a device)
- [x] Phase 3 - UI polish, error handling, performance, asset breakdown - AUDIT_UI.md (library/muscle lists still build all cards at once)
- [x] Phase 4 - Backend (backend/, migrations 0001-0006, RLS tests in PGlite only) + Flutter client (auth, sync engine, catalogue sync) - tested against fakes only
- [x] Phase 5 - Subscriptions client (PremiumService, paywall, gating) + webhook function - no live RevenueCat/Play
- [x] Phase 6 - Admin panel (admin/): 120 tests, typecheck, lint, `next build`; never opened in a browser or run against real Supabase
- [x] Phase 7 - Release prep (signing config, R8, adaptive icon, store/policy drafts in release/, builds)
- [x] Final report (FINAL_REPORT.md)

## RUN 2 (autonomous completion run) - results
All run on this machine; nothing on a device, no real Supabase/RevenueCat/Play. Details per area: RUN2_DATA.md, RUN2_CLOUD.md, AUDIT_UI.md ("Run 2 additions").
- [x] STEP 1 Performance: library, muscle detail, history and routines lists are lazy (slivers/builders); `lazy_lists_test.dart`; `top_level_layout_test.dart` pumps every bottom-nav screen at 360x640 and 800x1280, text 1.0x/2.0x (24 cases) and found/fixed real overflows. Scroll smoothness on a device UNVERIFIED.
- [x] STEP 2 Video licence safety: `kBundledVideosEnabled` in `lib/core/media_config.dart` (default true; `--dart-define=BUNDLED_VIDEOS=false` turns every exercise into NO_VIDEO/photo without deleting files; tests cover both). **RELEASE GUARD: for a public release build with `--dart-define=BUNDLED_VIDEOS=false` unless every video licence is confirmed** (none of the 123 is VERIFIED). `scripts/validate_media.py` (exists, hash duplicates, codec/duration/size limits, manifest completeness): runs with 0 errors and 1 warning (123 unverified videos). `MEDIA_GUIDE.md` explains adding a verified video.
- [x] STEP 3 Open items: lazy lists, generic tooltips, archived catalogue exercises hidden from lists/pickers (still resolvable by id), plans started from a non-today date logged on the performed date, unplanned days no longer get invented muscles, `debugPrint` -> debug-only `devLog`, model reads tolerate wrong types, lbs control removed.
- [x] STEP 4 Data safety: migration tests from every schema version (git history only contains v5; v1-v4 reconstructed from the upgrade branches and labelled so; v6 = current schema minus v7); seeding/upgrade twice is a no-op; **fixed a data-loss bug** (a custom exercise on an id later claimed by the catalogue was overwritten; custom exercises now move to ids >= 100001 and references are repointed); versioned, checksummed backup (format 3) with merge (dry-run summary, keep-newest, ids remapped, idempotent) and replace (atomic); both need explicit confirmation: Settings > "Import Backup (merge or replace)" shows the dry run, Merge by default, Replace needs a second confirmation (`backup_import_dialog.dart`, tests).
- [x] STEP 5 Cloud/subscription/admin gaps fixed (see RUN2_CLOUD.md): clock-skew rule via `server_time()`, deterministic ties, per-table partial failure + resume, one active plan, custom-exercise refs by sync id, account-mismatch guard, favourites sync, catalogue keyset paging; one pure entitlement function (free/active/cancelledActive/gracePeriod/expired/staleOffline; 14-day offline cache; refund revokes at once); account deletion needs typed DELETE; admin CSRF origin check, login throttle, CSP/HSTS headers, exact-match admin grant, audit of sign-ins; migration 0007 (cross-owner links blocked, timestamp clamp). Fake-based tests are labelled MOCK-ONLY.
- [x] STEP 6 Security: Supabase session in Android Keystore (flutter_secure_storage), no tokens/emails in logs, all debug logging gated, no hard-coded secrets (scan clean), unused permissions/deps removed (cupertino_icons, camera, media, storage, exact-alarm-use, battery request), CSV formula-injection guard, Diagnostics only in debug. R8: the release builds print no missing-class warnings, so no extra keep rules were needed (the shrunk build has still NEVER been run on a device).
- [x] STEP 7 `TEST_GUIDE.md` (phone checklist with Pass/Fail column) and debug-only Diagnostics screen (Settings > Developer, `kDebugMode`; versions, DB version, row counts, scheduled alarms, permissions, sync queue, entitlement; copy bug report, no personal data; test included).
- [x] STEP 8 Release readiness: applicationId unchanged (`com.reptrack.app.reptrack`), app name RepTrack, adaptive icon, version 1.0.0+1 (`kAppVersion` test keeps pubspec in sync), minSdk 24 / targetSdk 36, release signing reads gitignored `android/key.properties` (no key created; builds warn and fall back to the debug key), R8 on. Drafts in `release/` refreshed (still DRAFT, no URLs). `RELEASE_CHECKLIST.md` lists every manual step in order.
- [x] STEP 9 Final verification (below). Debug APK and arm64 release APK copied to `release_candidates/final/` (gitignored).

### Final verification numbers (this run)
| Check | Result |
|---|---|
| `dart format .` | clean (124 files) |
| `flutter pub get` | OK |
| `flutter analyze` | No issues found |
| `flutter test` | **383 passed, 0 failed** |
| Admin `tsc`, `eslint`, `vitest` | clean, 137 tests passed |
| Backend harness (PGlite) | 92 assertions, 0 failures |
| Kotlin JVM tests | 9 passed (last run earlier in this session) |
| `flutter build apk --debug` (after clean) | 204,532,837 B (195 MiB) |
| `flutter build appbundle --release` | 88,491,503 B (84.4 MiB), debug-signed |
| `flutter build apk --split-per-abi` | arm64-v8a 48,537,399 B, armeabi-v7a 46,322,947 B, x86_64 50,152,243 B (debug-signed) |
| `scripts/validate_media.py` | 0 errors, 1 warning (123 unverified videos) |

### BLOCKED / needs you
Device testing (TEST_GUIDE.md), Supabase/RevenueCat/Google/Play accounts and keys, keystore, licences and footage for videos, privacy policy URL, the BUNDLED_VIDEOS decision, applicationId decision (kept as instructed). Nothing was marked VERIFIED that I could not prove.

## RUN 3 - subscription-required model + protected videos (results)
Details: RUN3_ACCESS.md, RUN3_VIDEO.md. All run locally; nothing on a device and nothing against real RevenueCat/Play/Supabase.
- **Access model:** `ACCESS_MODEL` (dart-define, default `subscription_required`, `freemium` kept; unknown value fails closed). `PremiumService.accessLevel` = the single gate (checking / full / locked); trial counts as full access (trial detected from the RevenueCat entitlement period type; length is read from the Play offer only, never hard-coded); expired or refunded locks; valid cached entitlement works offline up to 14 days; store/network failure shows a retry state and never hard-fails; no paywall flash while the state is being determined.
- **Flow:** 3-page onboarding (collects nothing, shown once) -> paywall (prices and trial text from the offerings, auto-renew/cancel text, Restore, Manage subscription, privacy/terms links from `PRIVACY_POLICY_URL`/`TERMS_URL`, hidden if unset). Locked users see only the locked screen (paywall, restore, manage, links, Export my data, account deletion). Nothing is deleted or changed when locked; scheduled alarms keep ringing; the ringing screen hides the workout shortcut when locked; write entry points refuse when locked. A release build with no RevenueCat key is locked; debug builds without keys stay open for development.
- **Videos no longer ship in the app:** the 123 encoded files moved to `media_src/encoded/` (gitignored); `pubspec.yaml` lists no video path (test enforces it; release APK breakdown shows no video entry). Private Supabase bucket `exercise-videos` (migration 0008), `video-url` Edge Function (entitlement checked server-side from `public.entitlements`, trial active, refund/expiry denied, unknown/no-video/unlicensed exercise rejected, 300 s signed URL), `scripts/upload_videos.mjs` (uploads VERIFIED only unless `--include-unverified`). Flutter: on-demand per-exercise download to private cache, offline playback from cache, cache deleted when entitlement ends or the user signs out (wired in `cloud_services.dart`), `BUNDLED_VIDEOS=false` = no video request at all; states: downloading/offline/error/locked/no-video. Videos need an account (entitlement belongs to the Supabase user); a subscriber who is not signed in sees photos. The server serves nothing until each video is marked VERIFIED with evidence and published (all 123 are UNVERIFIED today, so **no video will be served** until you verify licences).
- **Obfuscation:** release builds use `--obfuscate --split-debug-info`; `scripts/build_release.ps1` does it with the right flags, symbols go to `symbols/<version>` (gitignored; archive them yourself; decode with `flutter symbolize`). Builds print a Dart warning about DWARF info in the ELF (informational; the split symbols are written outside the app).
- **Docs:** `release/` drafts now say a subscription is required after the trial and never "free"; RELEASE_CHECKLIST.md section L; TEST_GUIDE.md section 10.
- **Fixed on the way:** `.env.example` had been filled with what looked like a real key; it is back to placeholders only (keep real values in the gitignored `env.local.json`).

### Verification numbers (RUN 3, this machine)
| Check | Result |
|---|---|
| `dart format .` / `flutter analyze` | clean / No issues found |
| `flutter test` | **443 passed, 0 failed** |
| Admin typecheck, lint, vitest | clean, 147 passed |
| Backend SQL harness (PGlite) | 119 assertions, 0 failures |
| Edge-function pure modules (node) | 33 passed |
| scripts unit tests (python) | 14 passed |
| `scripts/validate_media.py` | 0 errors, 1 warning (123 unverified) |
| `flutter build apk --debug` (after clean) | 193,110,381 B (184 MiB) |
| `flutter build appbundle --release --obfuscate` | 72,873,226 B (69.5 MiB), debug-signed |
| `flutter build apk --split-per-abi --obfuscate` | arm64 35,692,031 B, armeabi-v7a 33,117,131 B, x86_64 37,241,339 B (debug-signed) |
Debug APK and the obfuscated arm64 release APK are in `release_candidates/final/` (gitignored).

### Still UNVERIFIED / yours
Real Play trial detection, purchase/restore/refund flows, the `video-url` function on a real project (Deno never ran), native video playback from the cache, signed-URL downloads, Keystore, R8 + obfuscated build behaviour on a device, privacy/terms URLs, every video licence, the trial length in Play Console, and all of TEST_GUIDE.md.

## RUN 4 - user accounts + admin-managed config (results)
Details: RUN4_AUTH.md, RUN4_CONFIG.md, CONFIG.md (new reference of every config value). Local only; nothing against real Supabase/Google/RevenueCat/Play and nothing on a device.
**Part A (accounts):** flow onboarding -> register/login -> account checks -> paywall -> app (`AccessRoot`); the paywall is unreachable without an account when Supabase is configured. Screens: login, register (live password rules + strength, confirm, terms checkbox with TERMS/PRIVACY links), forgot password, verify e-mail (60 s resend cooldown), reset password, account switch, not-configured, Google button only when `GOOGLE_WEB_CLIENT_ID` is set. Error mapping (wrong password, existing e-mail, invalid e-mail, weak password, network down, rate-limited, unconfirmed), autofill, labels, 360x640 + 2.0x text. Session in secure storage with auto-restore/refresh; RevenueCat user linked to the Supabase user after login and logged out on logout; logout clears the video cache and the entitlement cache but never workout data (tested across all tables); account switching never mixes data (explicit link-or-cancel screen). Locked users still reach restore, manage subscription, privacy/terms, export, delete account, sign out. Password reset: no deep link in this build (no scheme invented); reset happens on the Supabase hosted page and the app says so.
**Part B (admin/config):** migration 0009 (`app_config` single row with DB constraints, `announcements`, `manual_premium_grants` -> `premium_comp` entitlement honoured by the app and the `video-url` function; read-only for the app, writes via service role). App: `AppConfigService` (strict parser, 20 KB cap, 6 s timeout, cached last-good, defaults offline/invalid), `AppConfigGate` (maintenance screen, update-required via market://details?id=com.reptrack.app.reptrack), `AnnouncementBanner` (on Home), remote `access_model_override` (never opens a keyless release build; unknown fails closed), paywall copy from config with built-in fallback, prices/trial only from the store. Admin pages: Plans & Paywall (owner; real prices read-only via RevenueCat REST adapter if configured), App Config (access model owner-only), Manual premium (reason + expiry; no-expiry owner-only; support max 90 days), Announcements, Users detail with comp state; all through the existing guard + CSRF + zod + audit log. Parent integration done this run: `AppConfigService.configureForApp()` in `main()`, `AppConfigGate` around `AccessRoot`, `AnnouncementBanner` on Home.

| Check (this run) | Result |
|---|---|
| `dart format .` / `flutter analyze` | clean / No issues found |
| `flutter test` | **583 passed, 0 failed** |
| Admin typecheck / eslint / vitest | clean / clean / **240 passed** |
| Backend SQL harness (PGlite) | **175 assertions, 0 failures** |
| Edge-function pure modules (node) | 33 passed |
| `next build` (dummy env on the command line) | OK, 23 routes (reported by the config fork) |
| `flutter build apk --debug` | 221,524,326 B (211 MiB); copy in `release_candidates/final/` |
Release AAB / obfuscated APKs were NOT rebuilt in this run (last release build is from RUN 3, before the auth/config work).
UNVERIFIED: real Supabase sign-up/recovery/rate-limit behaviour, Google sign-in, RevenueCat v2 offerings call, migration 0009 on a real project (apply it first), comp grants reaching a real device, maintenance/update screens on a phone, everything in TEST_GUIDE.md sections 11-12.

## Phase 1 results (workout plans & active workout)
Schema v6 (additive, backward compatible; migration test keeps v5 data and is idempotent):
`training_plans`, `training_plan_days`, `training_plan_day_exercises`, `active_sessions`; new nullable columns
`planned_exercises.target_duration_seconds/target_distance_km`, `workout_sets.duration_seconds/distance_km`,
`workout_sessions.client_ref` (+ partial unique index).
New: `lib/core/clock.dart`, `models/training_plan.dart`, `services/training_plan_service.dart`,
`services/active_workout_controller.dart`, `widgets/exercise_picker_sheet.dart`,
`screens/training_plans_screen.dart`, `screens/training_plan_editor_screen.dart`; rewritten `screens/active_workout_screen.dart`.
Plan tab got a "My training plans" button; Home got a Resume banner and an unplanned-workout option on rest days.
Added deps: `wakelock_plus` (keep screen on, opt-in), dev `sqflite_common_ffi` (DB tests).
Tests added: `training_plan_service_test`, `active_workout_controller_test`, `active_workout_screen_test`, `training_plan_screens_test`.

## Phase 2 results (routines, alarms, history, stats)
Backup of the original alarm/Kotlin files before editing: `backup_alarm/*.bak`.

Alarm findings (original code) and fixes:
1. **After an alarm fired, the next day's alarm was never scheduled**, and `BootReceiver` was empty, so alarms were lost after every reboot/update/clock or timezone change until the user happened to edit each routine. `rescheduleAllRoutines()` existed but was never called. -> New native `AlarmStore` (SharedPreferences) + `AlarmScheduler` + pure `NextOccurrence`; `AlarmReceiver` chains the next occurrence first thing; `BootReceiver` restores all alarms on BOOT_COMPLETED, MY_PACKAGE_REPLACED, TIMEZONE_CHANGED, TIME_SET; Flutter re-pushes the database to native at start and on resume and prunes stale native alarms.
2. `RoutineNotificationService` was a stub that logged and scheduled nothing; "remind me N minutes before" never worked. -> Removed; native silent heads-up notification at start - N min (replaces itself, no duplicates).
3. Quiet "notification" routines were never scheduled at all (`isAlarmEnabled` is false for them). -> Fixed through the reminder path.
4. Snooze reused the routine's request code, so snoozing overwrote the routine's regular alarm. -> Own request code + snooze flag.
5. Scheduling used `Duration(days: 1)` arithmetic and looped 8 days on empty repeat days (bogus date). -> Calendar arithmetic (Dart `NextOccurrence`, Kotlin `NextOccurrence.kt`), empty days schedule nothing.
6. Default routines were re-inserted on every launch if the user deleted/renamed one. -> Seeded once (`default_routines_seeded`); existing installs keep what they have.
7. Overnight routines (sleep 22:30-07:15) were not "in progress" after midnight; clock was `DateTime.now()`. -> AppClock + carry-over from yesterday.
8. Permissions: POST_NOTIFICATIONS was never requested at runtime (Android 13+ hides reminders); the "Allow" button did nothing; full-screen-intent permission (Android 14) not checked; battery exemption used a Play-restricted request. -> In-context prompt when saving a routine (`AlarmPermissionPrompt`), new Reminder reliability screen (status, fix buttons, next scheduled alarms from native, OEM guidance, 10 s test alarm, no delivery promise). Removed `USE_EXACT_ALARM` and `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` from the manifest (Play policy); `SCHEDULE_EXACT_ALARM` kept (alarms use `setAlarmClock`, which does not need it, but the status screen reports it).
9. Settings: "Workout Reminders" switch stored a value nothing read -> replaced by a link to Reminder reliability. The old "Global alarm configuration" (master switch, default sound/vibration/snooze) was local state only -> removed.

Stats (done by a parallel worker, reviewed by test results): `StatsService` is the single source for history/home/settings stats; week start Monday/Sunday setting; DST-safe date arithmetic; strength-only volume; first-time/empty states; see `test/stats_service_test.dart`.

Verification run for this phase: Kotlin `NextOccurrence` JVM unit tests (9) pass via `gradlew :app:testDebugUnitTest`; Dart tests (see totals at the end of the file); the debug APK compiles the new Kotlin.

## Manual device tests (you must run these; none were run by me)
Use a real phone, Android 13+ and, if you can, a second brand (Samsung/Xiaomi/OnePlus/Oppo/Vivo/Realme) because makers differ.
1. **Doze alarm**: Reminder reliability > "Test the alarm" (10 s), lock the phone at once. Expect: screen wakes, alarm sound on the alarm stream, vibration, Stop/Snooze work.
2. **Real routine alarm**: create a routine 3 minutes ahead, type Audible alarm, lock the phone, leave it. Expect the same as 1.
3. **Chaining**: leave that routine on every day. After it rang, WITHOUT opening RepTrack, check the status-bar "next alarm" or open Reminder reliability next morning: the next time must be tomorrow. Do this for 3 consecutive days.
4. **Reboot**: schedule an alarm 10 minutes ahead, reboot, do NOT open RepTrack. Expect it to ring.
5. **App update**: with an alarm scheduled, `adb install -r` a newer build over it (do not open the app). Expect it to ring.
6. **Timezone**: alarm at 07:00, change the phone timezone to another zone. Expect 07:00 in the new local time (check Reminder reliability).
7. **Clock change**: set the time forward/back by hours in system settings, then check Next scheduled alarms updated.
8. **DST** (if you can set the date): around a DST change the alarm must stay at the same wall-clock time.
9. **Snooze**: ring, snooze, expect exactly one more ring after the snooze minutes; tomorrow's regular alarm must still be listed.
10. **Heads-up reminder**: routine with reminder 10 min before: one quiet notification at start - 10 min, no duplicates, none at start for alarm type with lead > 0 besides the alarm itself.
11. **Permissions, fresh install on Android 13/14**: create an alarm routine. Expect the notification prompt, then (Android 14) the full-screen-alarm prompt with a button to settings. Deny notifications twice: the settings page must open. Revoke each permission afterwards: the status screen must show it as missing.
12. **OEM kill**: swipe RepTrack from recents, force-stop it, wait: record which phones still ring. Follow the OEM guidance on the screen and repeat.
13. **Do Not Disturb**: DND on, alarm due: record whether it rings.
14. **Workout recovery**: start a workout, log 2 sets, swipe the app from recents (and once `adb shell am force-stop com.reptrack.app.reptrack`), reopen: Home must show RESUME WORKOUT, sets intact, timer paused, Finish saves ONCE (check History shows one session).
15. **Rotation/video**: rotate during an active workout and on an exercise with a video; NO_VIDEO exercises must show the photo and the text "No demonstration video yet".
16. **Keep screen on**: Active workout menu > Keep screen on; the screen must not time out; leave the screen and it must switch back.
17. **Midnight**: start a workout at 23:50, finish at 00:10; History must show it on the start date; Home must switch day without duplicates.
18. **Accessibility**: system font size at maximum and a small phone: workout, plan editor, reliability screen must not overflow or hide buttons.
19. **Back button / confirmation**: back during a workout asks Keep/Save&leave/Discard; plan editor asks before discarding.

## Decisions
- SQLite stays the source of truth. Weekly plans are templates; a dated `workout_plans` row is created lazily for today/future only and never overwritten.
- Plan delete = soft delete with confirmation. Active workout recovers paused.
- Cardio stored as time/distance in dedicated columns; strength volume excludes cardio.

## Bugs found / fixed (details in AUDIT_WORKOUT.md)
Fake "Biceps" plan written on browsing; in-memory-only workout; cardio polluting volume; wrong starter muscle id;
rest-timer and large-text overflows. Open: backup omits routines (Phase 3).

## Manual steps / device tests (running list)
See the "Manual device tests" section, filled in during Phase 2.

---
# Earlier phases

All work was local only. Nothing was pushed or uploaded. Nothing was committed.
No PROGRESS.md existed before this phase, so this file starts here.

## Media provenance (media_manifest.json)
- 203 mp4 files, 201 mapped to exercises, 2 orphans (`bench_press.mp4`, `barbell_curl.mp4`, referenced only by tests).
- **How the videos were made: UNKNOWN.** The repo holds no script, README or commit note recording a source.
  `exercise_demonstrations.json` self-declares "MIT License", "Free Exercise DB 3D Biomechanics Demonstration" and an r2.dev URL. None of this is backed by evidence, so the licence is UNVERIFIED for all 203. The URL was not fetched.
- Status counts: 0 VERIFIED, 68 UNVERIFIED, 135 FLAGGED.
- **80 files are byte-identical copies in 35 groups** reused for different exercises (e.g. `dead_hang`=`pull_up`, `dumbbell_pullover`=`flat_dumbbell_press`, `high_knees`=`outdoor_running`=`outdoor_walking`). These videos cannot all show the right movement.
- 70 files have a near-identical first-second frame to another file (overlaps heavily with the duplicates; heuristic only).
- 9 catalogue entries carry `status: FAILED` in the JSON (Dumbbell Hip Thrust, Glute Bridge, Crunch, Reverse Crunch, Plank, Dead Bug, Russian Twist, Stability Ball Crunch, Hollow Body Hold).
- 4 originals are 480x480 (the rest 1920x1080); 1 original had an audio track (`bicycle_crunch`); none shorter than 3 s (min 3.93 s after trimming); none without a video stream.

## Visual review material
- `audit/frames/<category>.jpg`: 15 contact sheets, 3 frames (start/middle/end) per video, labelled with ID, name and filename.
- The sheets were generated from the re-encoded files. Nobody has judged the content; manual review is still needed.

## Size
Videos: 170.8 MB -> 19.9 MB (target 150 MB met, so Play Asset Delivery was NOT needed or configured).
Settings: H.264, <=960x540, no audio, CRF 28, +faststart, capped at 10 s. Shorter clips were not padded or looped. Originals are in `media_src/` (gitignored).

| Category | Files | Before | After |
|---|---|---|---|
| Abs and Core | 20 | 38.7 MB | 2.1 MB |
| Chest | 22 | 19.0 | 2.5 |
| Biceps | 22 | 14.8 | 1.9 |
| Triceps | 19 | 13.3 | 1.5 |
| Shoulders | 17 | 11.8 | 1.5 |
| Quadriceps | 16 | 11.6 | 1.8 |
| Cardio | 11 | 10.1 | 1.3 |
| Full Body | 9 | 9.0 | 1.5 |
| Hamstrings | 11 | 8.4 | 1.1 |
| Back | 10 | 6.7 | 0.9 |
| Glutes | 9 | 6.2 | 0.9 |
| Upper Back and Traps | 10 | 6.1 | 0.8 |
| Lats | 9 | 4.9 | 0.8 |
| Forearms | 9 | 5.1 | 0.6 |
| Calves | 7 | 4.4 | 0.5 |
| orphans | 2 | 0.7 | 0.2 |

Playback code was not changed. By reading the code (not run on a device): a missing or unplayable bundled file throws in `controller.initialize()`, is caught, and shows an error overlay with Retry over the photo fallback. **On-device playback in exercise-detail and active-workout is UNVERIFIED.**

## Builds (all run on this machine)
| Command | Result |
|---|---|
| dart format . | OK (only my new test reformatted) |
| flutter pub get | OK |
| flutter analyze | No issues |
| flutter test | 100 tests: 99 pass, **1 fails** (intended, see below) |
| flutter build apk --debug (clean build) | 197,610,356 bytes (188 MB). An incremental build before `flutter clean` showed 374 MB because of leftover dead space in the zip. |
| flutter build appbundle --release | 88,996,911 bytes (84.9 MB). **Debug-signed**: no release signing config exists. |
| flutter build apk --split-per-abi | armeabi-v7a 49.0 MB, arm64-v8a 51.2 MB, x86_64 52.7 MB (debug-signed) |

## Tests
- `catalogue_audit_comprehensive_test.dart`: checks 201 exercises, categories, ID uniqueness, leg/search isolation, the 15 per-category counts, and that each exercise has a demo entry with an existing file >10 KB and >=3 cues. It does not check video content or the entry `status`. No test claimed 201 per category.
- `category_filtering_test.dart`: checks category mapping, per-group counts, parent groups, and a spot check of 6 named video mappings plus image fallbacks. Test 9 claimed "mapping integrity" for the whole catalogue; renamed to say what it checks. Audit test 5 was renamed likewise.
- New `test/media_integrity_test.dart`: exact per-category counts, a manifest entry per exercise, file exists / is MP4 (`ftyp`) / matches manifest size, no duplicate video content, no VERIFIED claim without evidence.
- **The duplicate-content test fails** (35 groups). This is a real defect and was left failing on purpose.

## Duplicate-video decision (Option A) - applied
- All 35 duplicate groups (80 files) had filenames that matched their own exercise, so filename gave no way to tell which exercise a video really shows. I did not judge content, so **no video was kept for any member of a duplicate group**.
- 78 exercises are now `NO_VIDEO`: `has_video=false`, `media_type=image`, `video_url` and `local_bundled_path` cleared, `status=NO_VIDEO` in `exercise_demonstrations.json` and `media_manifest.json`. Their exercise rows and photos are untouched. List: `audit/needs_video.csv` (id, name, category).
- **123 exercises keep a bundled video.** These are unique files, but still **unreviewed and with unproven licence** (0 VERIFIED). 55 of the 123 are FLAGGED for other reasons (near-identical frame, square source, `FAILED` status in the old JSON, trimmed, had audio).
- The 80 files were deleted from `assets/videos/exercises/` (originals remain in `media_src/`). That includes the 2 unmapped files `bench_press.mp4` and `barbell_curl.mp4`; they were only referenced as alternatives in two tests, which now assert the photo fallback.
- Videos in assets: 11.4 MB (123 files).
- UI: `ExerciseDemonstrationPlayer` is used by both exercise-detail and active-workout. For NO_VIDEO exercises `resolveMediaSource` returns the photo fallback before any controller is created, so no player error or stale video can show. The overlay now says "No demonstration video yet / Showing the exercise photo". **Not run on a device (UNVERIFIED visually).**
- Tests updated honestly (not relaxed): tests that required video for all 201 now assert 123 with an existing file and 78 NO_VIDEO with no video path, and that NO_VIDEO exercises resolve to their photo. The duplicate-content test is unchanged and passes because the duplicates are gone. A new check fails if a video file on disk is missing from the manifest.
- Caveat: the JSON field `mapped_model_source` is unreliable metadata (several tests compare it, which cannot prove the videos differ).

### Results
- `dart format .`: OK. `flutter analyze`: no issues. `flutter test`: **101 passed, 0 failed.**
- `flutter build apk --debug` (after `flutter clean`): 189,174,575 bytes (180 MB).
- Contact sheets in `audit/frames/` were made before this step and still include the removed videos.

## Open issues (superseded items marked)
1. ~~35 duplicate groups~~ resolved by removal; 78 exercises need correct footage (`audit/needs_video.csv`).
2. Licence and source of every video unproven; resolve before any release.
3. Manual review of `audit/frames/` is required.
4. `duration_seconds` in `exercise_demonstrations.json` does not match the real clip lengths.
5. The JSON `video_url` r2.dev links are unchecked, and the app can stream them (not strictly offline).
6. Release signing is not configured.
7. ~~2 orphan videos~~ removed.
8. Pre-existing uncommitted source changes (muscle_detail_screen, database_service, exercise_terminology_service) were left untouched.

Tools: `tool/media_probe.py`, `tool/reencode_videos.py`, `tool/audit_frames.py`, `tool/build_manifest.py` (ffmpeg via the imageio-ffmpeg Python package; no system ffmpeg/ffprobe).

## TRIAL TIER (videos locked during the store trial)
- **Tiers** (`AccessTier`, ONE getter `PremiumService.tier`): `locked` (no entitlement / unknown / expired / refunded / stale offline), `trial` (store trial period), `full` (paid, cancelled-but-paid, billing grace, valid comp grant even next to a trial). `videosAllowed` / `videosLockedForTrial` derive from it; nothing else decides.
- Trial behaves exactly like full for plans, routines, alarms, history, stats, charts, sync and export; only exercise videos differ. `TRIAL_VIDEOS_LOCKED` (dart-define, default `true`, read only in `lib/core/access_config.dart`) opens videos for trials when `false`. Strings are in `lib/core/strings.dart`.
- Video area for a trial user (`DemonstrationSourceType.trialLockedPhoto`): blurred photo, lock icon, "Videos unlock with a full subscription", Subscribe -> paywall (which explains the lock). Decided in `ExerciseMediaService.resolveMediaSource` before any source: no `VideoPlayerController`, no signed-URL request, no download. Exercises without a video keep "No demonstration video yet" (no lock). The locked tier keeps its existing card. The video cache is cleared whenever videos stop being allowed (never user data).
- Server: migration `0010_trial_video_tier.sql` (`entitlement_tier`, `video_access(..., p_allow_trial default false)`), `video-url` answers `403 trial_locked` for trials; secret `TRIAL_VIDEOS_LOCKED=false` is the server-side switch.
- Mock billing: Trial -> trial tier (videos locked), Premium/Grace -> full; Diagnostics shows `access tier`, `trial videos locked`, `videos allowed` and the tier next to the mock buttons.
- Locked users keep (unchanged, covered by existing access tests plus a new paywall check): restore, manage subscription, privacy/terms, export of local data, account deletion; scheduled alarms keep ringing; nothing is deleted.
- Verified on this machine: `flutter analyze` clean; `flutter test` 649 passed (35 new in `test/trial_tier_test.dart`); backend PGlite harness 182 assertions, 0 failures; edge-function logic tests 37 passed. UNVERIFIED: the real `video-url` on Supabase (Deno never ran; migration 0010 not applied to your project yet), real Play trial detection (`period_type TRIAL` mapping), the blur on a device, release-build behaviour.
