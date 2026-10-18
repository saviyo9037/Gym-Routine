# RepTrack - Final report (2026-10-17, updated after run 2)

> **Run 3 (subscription-required + protected videos) supersedes the numbers below**: 443 Flutter tests pass; admin 147; backend 119 SQL assertions; release AAB 69.5 MiB (no videos inside), arm64 APK 35.7 MB, debug APK 184 MiB; obfuscated release builds. The app is now subscription-required (store-managed trial); videos come from a private bucket via an entitlement-checked function. See PROGRESS.md "RUN 3".
>
> **Run 2 numbers (older)**: 383 Flutter tests pass, admin 137, backend 92 assertions, debug APK 204.5 MB, release AAB 88.5 MB, arm64 APK 48.5 MB (debug-signed). See PROGRESS.md section "RUN 2" for what changed (lazy lists, video licence flag, migration tests and a data-loss fix, backup merge/replace import, sync/entitlement/admin/RLS hardening, secure token storage, Diagnostics, TEST_GUIDE.md, RELEASE_CHECKLIST.md). Still true: nothing has been run on a device or against real services; this is not production-ready.


Everything below was done locally. Nothing was committed, pushed or uploaded; no secrets, keys or URLs were invented.
**This is NOT production-ready.** Nothing has been run on a phone, against real Supabase, RevenueCat or Google Play.

## Verified results (commands actually run on this machine, at the end)
| Check | Result |
|---|---|
| `dart format .` | clean (101 files, 0 changed) |
| `flutter analyze` | No issues found |
| `flutter test` | **253 passed, 0 failed** |
| Kotlin JVM tests (`gradlew :app:testDebugUnitTest`) | 9 passed (NextOccurrence) |
| Backend SQL tests (PGlite, not real pgTAP/Supabase) | 63 assertions passed (as reported by the backend worker) |
| Webhook logic tests (node) | 12 passed |
| Admin: `tsc`, `eslint`, `vitest`, `next build` | all passed, 120 tests (as reported by the admin worker) |
| `flutter build apk --debug` (after `flutter clean`) | built, 204,012,070 bytes (194.6 MiB) |
| `flutter build appbundle --release` | built, 88,127,464 bytes (84.0 MiB), **debug-signed** (no key.properties exists) |
| `flutter build apk --split-per-abi` | armeabi-v7a 46,158,679 B (44.0 MiB), arm64-v8a 48,373,131 B (46.1 MiB), x86_64 49,922,439 B (47.6 MiB), debug-signed |

Release builds use R8 + resource shrinking; they compile, but the shrunk build was NEVER run (UNVERIFIED at runtime).

## Size breakdown (why the debug APK is ~195 MiB while videos are 11 MB)
Debug APK = 3 ABIs of native code (arm64 ~56 MB, x86_64 ~42 MB, armeabi-v7a ~35 MB incl. a 15 MB Vulkan validation layer) + the debug Dart kernel (~80 MB raw, ~26 MB zipped) + 12.4 MB images + 11.4 MB videos + 2 MB code. A release arm64 APK is 46 MiB: native libs 21 MB, images 12.4 MB, videos 11.4 MB, code 2 MB. Play delivers per-ABI splits from the AAB. The AAB (84 MiB) is far below the 200 MB limit, so **Play Asset Delivery was not configured and is not needed**. Images (243 JPG, 12.4 MB) could shrink ~30% as WebP but every reference is a `.jpg` path; left as is.

## Exercises: video vs no video
201 exercises: **123 have a bundled video, 78 are NO_VIDEO** (photo fallback, listed in `audit/needs_video.csv`). The 78 had videos that were byte-identical to other exercises and were removed rather than guessed. **None of the 123 is VERIFIED**: the source and licence of every video are unknown/unproven (the JSON's "MIT License" claim has no evidence) and nobody has reviewed their content (`audit/frames/`). Do not ship them publicly before sorting this out.

## Features implemented
- **Plans/active workout (Phase 1):** named weekly training plans (create/edit/duplicate/soft-delete with confirmation, choose training/rest days incl. six, unlimited exercises per day, picker with primary-muscle filter + alias search, duplicate warning, sets/reps/decimal weight/rest/notes, cardio time/distance, drag reorder); active workout with pause/resume, undo, add/remove sets, next/prev/jump, rest timer, unplanned workout on rest days, persisted in SQLite and recoverable after app kill ("Resume workout"), finish saves exactly once, optional keep-screen-on.
- **Routines/alarms/stats (Phase 2):** native alarm chaining + restore after boot/update/clock/timezone change, lead-time reminders, separate snooze, in-context permission prompts, Reminder reliability screen, seeded-once defaults, overnight routine handling; `StatsService` single source with Monday/Sunday week start, DST-safe dates, strength-only volume, per-exercise progress, streaks, empty states.
- **Polish (Phase 3):** retry/empty/error states, validation, confirmations, tooltips, overflow fixes at 360x640 / 2.0x text, disposed controllers, full backup/restore including routines and plans, honest manual-log form (removed hard-coded fake sets).
- **Backend (Phase 4):** Supabase migrations 0001-0006 with RLS on every table, versioned catalogue, entitlements, audit log, delete-account and RevenueCat webhook Edge Functions.
- **Client (Phases 4-5):** optional email/Google accounts, account deletion, premium-only sync (LWW, tombstones, resumable), catalogue delta sync (never touches user data), RevenueCat paywall (monthly/yearly, restore, manage link), single `PremiumService`; free users keep 2 plans (existing never removed); premium: sync, Progress charts, CSV/JSON export. Alarms, logging, library, basic history, routines, local backup are never gated (tested). Without any `--dart-define` the app runs local-only.
- **Admin panel (Phase 6):** Next.js/TS/Tailwind in `admin/` (roles enforced server-side on every action, TOTP, audit logging, dashboard, users, subscriptions, catalogue CRUD, media upload, templates, admins, audit viewer).
- **Release prep (Phase 7):** signing config reading gitignored `android/key.properties` (example provided, no key created), R8 + shrink, adaptive icon, removed Play-restricted/unneeded permissions (`USE_EXACT_ALARM`, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, `CAMERA`, `READ_MEDIA_*`, storage), drafts in `release/` (privacy policy, Data Safety checklist, store listing, content rating, subscription disclosure) - all DRAFT.

## Bugs fixed (highlights; full lists in AUDIT_WORKOUT.md, AUDIT_UI.md, PROGRESS.md)
Alarms were never re-armed after firing or reboot; reminder service was a stub; quiet reminders never scheduled; snooze overwrote the daily alarm; no runtime notification permission; fake "Biceps" plans written while browsing; workout lost on app kill; cardio polluted strength volume; seeded routines resurrected on every launch; DST-unsafe date math in several places; endless spinners; undisposed controllers; overflows; backup omitted routines; fake hard-coded manual log; non-functional settings (reminders switch, global alarm config, kg/lbs).

## Schema / migration changes
Local SQLite v5 -> v6 (training plans, active session, cardio columns, `client_ref`) -> v7 (sync_id/updated/dirty columns, tombstones, sync meta, conflict log). Additive only, idempotent, tested with existing data. Backend: migrations 0001-0006.

## Files
Created: see `git status` (new: `lib/core/*`, `lib/models/training_plan.dart`, services for plans/active workout/stats/auth/sync/premium/catalogue/export, screens for plans/editor/account/paywall/progress, widgets, Kotlin `AlarmStore/AlarmScheduler/NextOccurrence`, `backend/`, `admin/`, `release/`, `tool/`, `audit/`, `media_manifest.json`, tests, audit docs). Removed: `routine_notification_service.dart` (stub), 80 duplicate video files (originals kept in gitignored `media_src/`), the two unmapped videos. Backups of original alarm code: `backup_alarm/*.bak`.

## NOT done / UNVERIFIED
- No real-device test of anything (alarms, Doze, reboot, OEM kill, notifications, full-screen, recovery after kill, video/photo, rotation, wakelock). See "Manual device tests" in PROGRESS.md.
- No live Supabase/RevenueCat/Google/Play connection: RLS only tested in PGlite with stubs; Edge Functions never executed (no Deno); sync, purchases, restore and account deletion untested for real; admin panel never opened in a browser; admin tests use a mocked client.
- Release/R8 build never run; both bundles are debug-signed.
- Video licences/sources unproven; 78 exercises have no video; photos/UI strings not reviewed by a human.
- Library and muscle-detail lists still build ~200 cards eagerly; catalogue favourites and media attachments are not synced; deltas capped at 500 rows; two devices can both mark a plan active; custom-exercise ids may differ across devices.
- Privacy policy and store texts are drafts with placeholders; no policy URL exists.
- `applicationId` is `com.reptrack.app.reptrack` (unusual; cannot change after publishing; changing it now would make the current dev install a separate app). Your decision before the first upload.
- `anonKey` of supabase_flutter is deprecated in favour of a publishable key; not checked against your project.

## MANUAL STEPS (yours)
1. Supabase: create project(s); `supabase db push` migrations 0001-0006; enable email auth + TOTP MFA; deploy `revenuecat-webhook` (`--no-verify-jwt`) and `delete-account`; set `REVENUECAT_WEBHOOK_AUTH`; insert the first owner into `public.admins`; seed `exercises_catalog` from the app data and call `publish_catalogue()`; run the real pgTAP suite.
2. Google OAuth: create the OAuth client(s) (web client id for `GOOGLE_WEB_CLIENT_ID`, Android client with your signing SHA-1/SHA-256) and enable Google in Supabase Auth.
3. RevenueCat: create the project, entitlement `premium`, offerings with monthly + yearly packages, Play service credentials, webhook URL + Authorization header.
4. Play Console: create the app, the subscription products (monthly/yearly), license testers, upload the signed AAB, complete Data safety, content rating, full-screen-intent and foreground-service declarations, and an account-deletion web link.
5. Keystore: create it yourself, copy `android/key.properties.example` to `android/key.properties`, rebuild the release (then test the shrunk release build on a phone).
6. Build with your own keys: `flutter build appbundle --release --dart-define-from-file=env.local.json` (see `.env.example`).
7. Admin hosting: choose domain/host (HTTPS), set the env vars from `admin/.env.example` (service-role key server-side only), allow >= 55 MB request bodies for uploads.
8. Privacy policy: finish `release/PRIVACY_POLICY_DRAFT.md`, host it, put the URL in Play Console and the app; same for terms.
9. Videos: source or shoot correct footage with proper licences for the 78 NO_VIDEO exercises (`audit/needs_video.csv`) and prove/replace the licence of the 123 existing ones; review `audit/frames/`.
10. Decide the final `applicationId` before the first upload.
11. Run every item of "Manual device tests" in PROGRESS.md on real phones (several brands).
12. Play closed-testing requirement: new personal developer accounts must run a closed test with at least 12 testers for 14 continuous days before production access.
