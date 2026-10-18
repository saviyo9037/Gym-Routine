# RepTrack - release checklist (manual steps, in order)

Everything in code is finished as far as it can be proven without devices and accounts. These are the steps only you can do. Do them in this order. Nothing here has been run for you; exact commands are given where they exist.

## A. Decisions you must make first
1. **Application ID** is `com.reptrack.app.reptrack` (kept as you asked). It can never change after the first Play upload.
2. **`kBundledVideosEnabled` / `--dart-define=BUNDLED_VIDEOS=false`**: the 123 bundled videos have NO proven source or licence (`media_manifest.json`, all UNVERIFIED). For a **public** release either (a) build with `BUNDLED_VIDEOS=false` (every exercise shows its photo), or (b) prove the licence of every video and mark them VERIFIED with evidence (see `MEDIA_GUIDE.md`). A closed test with only your testers carries the same legal risk, so decide before uploading anything.
3. Subscription prices and the trial length. The model is **subscription required** (`ACCESS_MODEL`, default `subscription_required`; `freemium` is only for experiments). The trial length is whatever the Play offer defines (you plan 1 day, if Play allows); the app never hard-codes it.

## B. Local verification before accounts
1. Run `TEST_GUIDE.md` sections 0-7 and 9 on real phones (2 brands). Fix or report every FAIL.
2. Review `audit/frames/` against exercise names.

## C. Keystore and signed builds
1. Create the upload keystore yourself (keep it safe and backed up; losing it blocks updates unless Play App Signing resets it):
   ```
   keytool -genkey -v -keystore %USERPROFILE%\reptrack-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. Copy `android/key.properties.example` to `android/key.properties` and fill in the four values (the file is gitignored; never commit it or the keystore).
3. Build with obfuscation: `powershell -ExecutionPolicy Bypass -File scriptsuild_release.ps1` (runs `flutter build appbundle --release --obfuscate --split-debug-info=symbols\<version>` plus the split APKs, reading your keys from `env.local.json`). Put `BUNDLED_VIDEOS`, `PRIVACY_POLICY_URL`, `TERMS_URL` and (optionally) `ACCESS_MODEL` in `env.local.json` too. **Archive `symbols\<version>` of every build you ship** (outside the repo): `flutter symbolize -i stack.txt -d symbols\<version>` turns an obfuscated crash trace back into readable names. The Gradle output must NOT print the "signed with the DEBUG key" warning.
4. Install the release APK from `flutter build apk --split-per-abi` on a phone and run the alarm and workout tests again: the shrunk (R8) release build has never been run.

## D. Supabase (backend/README.md has details)
1. Create the project (choose region; note it for the privacy policy).
2. Authentication: enable email, enable Google provider later (step F), enable **TOTP MFA**.
3. Apply migrations 0001...0006 (`supabase link`, `supabase db push`).
4. Deploy functions: `supabase functions deploy delete-account` and `supabase functions deploy revenuecat-webhook --no-verify-jwt`; set the secret `REVENUECAT_WEBHOOK_AUTH` (`supabase secrets set REVENUECAT_WEBHOOK_AUTH="Bearer <long random value>"`).
5. Insert the first owner row into `public.admins` (SQL in backend/README.md); seed `exercises_catalog` from the app data and call `publish_catalogue()` as the service role.
6. Run the real pgTAP suite on a local Supabase stack (`supabase test db`); the repo only ran it in PGlite.
7. Put the project URL and anon/publishable key into `env.local.json` (copy `.env.example`; gitignored).

## E. RevenueCat
1. Create the project and an Android app (package `com.reptrack.app.reptrack`), add Play service-account credentials.
2. Entitlement id exactly `premium`; offering with a monthly and a yearly package.
3. Webhook: URL = your deployed `revenuecat-webhook` function, Authorization header = the exact secret from step D4.
4. Put the Android public SDK key into `env.local.json` as `REVENUECAT_ANDROID_API_KEY`.

## F. Google OAuth
1. Google Cloud console: create an OAuth consent screen and clients: a **Web** client (its id = `GOOGLE_WEB_CLIENT_ID`; also enter id+secret in Supabase Google provider) and an **Android** client with package `com.reptrack.app.reptrack` and your upload/app-signing SHA-1.
2. Test sign-in on a signed build.

## G. Play Console
1. Create the developer account (personal accounts created after Nov 2023: **closed test with at least 12 testers opted in for 14 continuous days** before you can apply for production access).
2. Create the app; set up the store listing from `release/STORE_LISTING_DRAFT.md` (review it), graphics: 512x512 icon, 1024x500 feature graphic, screenshots.
3. App content: privacy policy URL (see H), Data safety (`release/DATA_SAFETY_CHECKLIST_DRAFT.md`), content rating (`release/CONTENT_RATING_NOTES_DRAFT.md`), ads declaration (none), account-deletion web link, target audience, **full-screen intent** and **foreground service (media playback)** declarations with the alarm justification, exact-alarm declaration if requested.
4. Monetisation: create subscription products (monthly, yearly) and base plans; add license testers; link RevenueCat.
5. Upload the signed AAB to **Internal testing** first, then a **Closed testing** track with 12+ testers for 14 days.
6. Run `TEST_GUIDE.md` section 8 with license testers.

## H. Legal text and web hosting
1. Finish and legally review `release/PRIVACY_POLICY_DRAFT.md` and the subscription disclosure; host them on a domain you control (any static host; the admin panel host works too). The resulting HTTPS URL goes into Play Console and the app (no URL was invented).
2. Terms of use if you want them.

## I. Admin panel hosting (Vercel or any Node host)
1. Domain/DNS and HTTPS; deploy `admin/` (see `admin/README.md`).
2. Env vars (server-side only): Supabase URL, anon key, **service-role key**, any others listed in `admin/.env.example`. The host must accept request bodies >= 55 MB (media upload).
3. Enrol TOTP for the first owner, test every role, check the audit log.

## J. Videos for the 78 exercises without one
Source or shoot footage you own or are licensed to use; follow `MEDIA_GUIDE.md` (encode, manifest evidence, `scripts/validate_media.py`), then re-run the tests.

## K. Final gate
1. `dart format .`, `flutter analyze`, `flutter test`, admin `npm test`, backend harness all green.
2. Final release build signed with your key, tested on devices.
3. Promote through Internal -> Closed (14 days) -> Production.

## L. Subscription-required model and protected videos (new)
1. The app is subscription-required: after a 3-page onboarding the user sees the paywall; nothing else is reachable until they subscribe (trial counts as access). A locked user can only restore purchases, manage the subscription, read the privacy/terms links, export their local data and delete their account. Nothing is ever deleted when locked; already scheduled alarms keep ringing.
2. **Play Console trial:** create the monthly and yearly base plans and add an **introductory offer / free trial** to the one you want (you plan 1 day; check that Play allows it). The app reads the trial length from RevenueCat/Play; never type it into code.
3. **Required build values** (`env.local.json`, gitignored): `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `REVENUECAT_ANDROID_API_KEY`, `GOOGLE_WEB_CLIENT_ID`, `PRIVACY_POLICY_URL`, `TERMS_URL`. A release build without the RevenueCat key is LOCKED for everyone (by design); only debug builds without keys stay open for development.
4. **Videos are no longer in the APK/AAB.** They live in the private Supabase bucket `exercise-videos` and are served as 5-minute signed links by the `video-url` Edge Function after a server-side entitlement check (an account is required, because the entitlement belongs to the Supabase user). Steps:
   - `supabase db push` (migration 0008) and `supabase functions deploy video-url`;
   - upload: `node scripts/upload_videos.mjs --dry-run`, then for real with `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` in your environment (it uploads only VERIFIED entries unless you pass `--include-unverified`; the originals stay in `media_src/encoded`, which is gitignored);
   - for each video you can prove the licence of, mark it VERIFIED with evidence in `media_manifest.json` (MEDIA_GUIDE.md), then publish it in the admin panel; the server serves nothing that is not verified and published;
   - decide `BUNDLED_VIDEOS`: `false` = no video is requested at all (photos only).
5. In RevenueCat call `Purchases.logIn(<supabase user id>)` is done by the app; make sure the webhook is configured so trials and renewals reach `public.entitlements` (trials count as active). After a purchase the videos appear a few seconds later, when the webhook has written the entitlement.
6. Test with a license tester: trial start, trial end, renewal, cancel, refund, billing failure (TEST_GUIDE.md section 10).

## M. Trial tier (videos locked during the store trial)
1. Apply migration `0010_trial_video_tier.sql` (SQL editor or `supabase db push`), then redeploy `video-url`: `supabase functions deploy video-url`. Apply 0010 BEFORE deploying, because the new function passes `p_allow_trial`.
2. Default is safe: trial users get no signed URL. To open videos during the trial later, set BOTH `supabase secrets set TRIAL_VIDEOS_LOCKED=false` and build with `TRIAL_VIDEOS_LOCKED=false` in `env.local.json`.
3. Test with a license tester: start the trial (videos show the blurred photo + Subscribe), let it convert (videos play), comp grant (videos play).
