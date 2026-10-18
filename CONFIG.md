# RepTrack - configuration reference

Nothing secret is stored in the repo. Every real value goes in a gitignored file or in your host's secret store. If something is missing the app/admin stays in a safe "not configured" state; it never invents values.

## 1. Flutter app - build-time values (`--dart-define`)
Put them in `env.local.json` (gitignored; template in `.env.example`) and build with `--dart-define-from-file=env.local.json` (`scripts/build_release.ps1` does this).

| Name | Required for | Notes |
|---|---|---|
| `SUPABASE_URL` | accounts, sync, videos, remote config | `https://<project-ref>.supabase.co` |
| `SUPABASE_ANON_KEY` | same | anon / publishable key (public by design, still keep it out of the repo) |
| `REVENUECAT_ANDROID_API_KEY` | purchases | public Android SDK key. A **release build without it is locked for everyone** (debug builds stay open for development) |
| `GOOGLE_WEB_CLIENT_ID` | Google sign-in | web OAuth client id; the button is hidden when unset |
| `PRIVACY_POLICY_URL`, `TERMS_URL` | paywall/register links | https only; links are hidden when unset but Play requires both |
| `ACCESS_MODEL` | monetisation | `subscription_required` (default) or `freemium`; unknown values fail closed. The remote `access_model_override` can change it at runtime but can never open a release build that has no RevenueCat key |
| `TRIAL_VIDEOS_LOCKED` | videos in a trial | `true` (default) / `false`. Tiers: **locked** (no entitlement), **trial** (store free trial), **full** (paid, comp grant, billing grace). While `true`, a trial user gets everything except exercise videos (blurred photo + "Videos unlock with a full subscription" + Subscribe; no player, no signed-URL request). Set `false` to open videos during the trial. The server has its own matching switch: `supabase secrets set TRIAL_VIDEOS_LOCKED=false` (needs migration 0010); unset or anything else keeps trials locked, so the lock cannot be bypassed from the app |
| `BUNDLED_VIDEOS` | videos | `true` (default) / `false`. `false` = no demonstration video is requested at all. Keep `false` for a public release until every video licence is confirmed |

**Debug-only `MOCK_BILLING=true`** (never in `env.local.json`, `build_release.ps1` refuses it): `flutter run --dart-define=MOCK_BILLING=true` replaces RevenueCat with fake monthly/yearly offers ($4.99 / $29.99, 1-day trial text), a "TEST MODE, no real payment" purchase sheet (Success / Cancel / Failed / Pending) and Diagnostics buttons (No access, Trial, Premium, Expired, Grace period, Refunded). It is `kDebugMode && define`, so it is off in profile/release builds, and `MockEntitlementSource` throws outside debug mode. The state is kept across restarts. Videos' locked UI follows it, but the server-side `video-url` check still needs a real entitlement, so real video downloads are not unlocked by it.

Release build (obfuscated): `powershell -ExecutionPolicy Bypass -File scripts\build_release.ps1`. Archive `symbols\<version>`.

## 2. Remote app config (Supabase `app_config`, managed in the admin panel)
One row, validated by the DB, the admin forms and the app parser (bad data = defaults, never a crash; payload > 20 KB ignored; cached last-good copy; refresh at most every 10 min).

| Field | Limit | Who can change (admin) | App behaviour when unset/invalid |
|---|---|---|---|
| `paywall_title` | 1-80 | owner | built-in text |
| `paywall_subtitle` | 1-200 | owner | built-in text (trial sentence always comes from the store offer) |
| `paywall_benefits` | <= 8 lines x 120 | owner | built-in list |
| `plan_badges` (`monthly`, `yearly`) | 1-24 | owner | no badge |
| `promo_text` | 1-200 | owner | none |
| `maintenance_mode` / `maintenance_message` | message 1-300 | owner, support | normal app |
| `min_app_version` | semver | owner, support | none |
| `access_model_override` | `subscription_required` / `freemium` / null | **owner only** | build value |
| Announcements | title 80, body 500, info/warning, window | owner, support | none |
Prices and trial length are **never** remote copy: they come only from the Play/RevenueCat offers and are changed in Play Console. Apply migration `0009_app_config.sql` first.

## 3. Admin panel (`admin/.env.local`, server-only except the two NEXT_PUBLIC values)
`NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` (server only, never `NEXT_PUBLIC_`), optional `REVENUECAT_API_KEY` and `REVENUECAT_PROJECT_ID` (read-only price/trial display; verify the REST call with your key). First owner: `node scripts/create-first-admin.mjs <email>`. Details: `admin/README.md`.

## 4. Backend (Supabase)
Migrations `backend/supabase/migrations/0001` ... `0010` (0010 = trial video tier; apply it before deploying the updated `video-url`). Edge Functions: `revenuecat-webhook` (`--no-verify-jwt`, secret `REVENUECAT_WEBHOOK_AUTH`), `delete-account`, `video-url` (private bucket `exercise-videos`, entitlement checked server-side; trials and comp grants count). Upload videos with `scripts/upload_videos.mjs` (service-role key from your environment). Details: `backend/README.md`.

## 5. Android signing
`android/key.properties` (gitignored; template `android/key.properties.example`). Without it Gradle signs release builds with the DEBUG key (not uploadable). Application id stays `com.reptrack.app.reptrack`.

## 6. Order of precedence for the access model
test override > remote `access_model_override` (only if valid, and never loosening a keyless release build) > build `ACCESS_MODEL` > default `subscription_required`.
