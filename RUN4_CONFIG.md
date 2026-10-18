# RUN4_CONFIG - remote app config, announcements, comp access, admin pages (fork B)

Everything here was run locally. Nothing was committed, pushed, deployed or uploaded; no key, URL or credential was invented.
Tests that use a fake remote, fake store or mocked Supabase client are labelled `MOCK-ONLY`. Nothing ran against a real Supabase, RevenueCat or Play project.
(The parent asked for a CONFIG.md; it was not created here: this file holds the configuration documentation for the parent to merge.)

## What is configurable remotely (migration 0009, table `app_config`, ONE row id = 1)
| Field | Limit (enforced in DB, admin zod, and the Flutter parser) | App behaviour when unset/invalid |
|---|---|---|
| `paywall_title` | 1-80 chars, plain text | built-in "RepTrack needs a subscription" |
| `paywall_subtitle` | 1-200 | built-in wording (the trial sentence is always added from the store offer) |
| `paywall_benefits` | <= 8 lines x 120 | built-in feature list |
| `plan_badges` | keys `monthly`/`yearly`, 1-24 | no badge |
| `promo_text` | 1-200 | none |
| `maintenance_mode` + `maintenance_message` | literal `true`; message 1-300 | normal app; built-in message if empty |
| `min_app_version` | semver `x.y.z[+build]` | none |
| `access_model_override` | `subscription_required` / `freemium` / null | build's `ACCESS_MODEL`; unknown value => subscription required (fail closed) |
Announcements (`announcements` table): title 80, body 500, level info/warning, start/end window, active.
Prices and trial text are NEVER remote copy: they come only from the store offers (RevenueCat/Play).

## App side
- `lib/services/app_config_service.dart`: strict total parser (`AppConfig.parse`, `Announcement.parse`), 6 s timeout, last-good cache in `user_settings`, rate-limited refresh (10 min; joins an in-flight fetch), defaults when offline/unconfigured/invalid. A payload over 20 KB is ignored as a whole. `AppConfigService.configureForApp()` is the one call to put in `main()` (not done here: main.dart belongs to another fork).
- `lib/widgets/app_config_gate.dart`: `AppConfigGate({required child})` shows a calm maintenance screen (message + Retry) or "Update required" (market://details?id=com.reptrack.app.reptrack, explained if it cannot open); refreshes on resume. **Parent to do:** wrap the app (`AppConfigGate(child: AccessRoot...)`) and call `AppConfigService.configureForApp()` before `runApp`.
- `lib/screens/announcement_banner.dart`: `AnnouncementBanner()` (dismissible, per-id dismissal persisted, max 3). **Parent to place** it (e.g. top of Home).
- `lib/core/access_config.dart`: remote layer between the build define and the test override; a remote value can never open a release build without a RevenueCat key; `AccessConfig.revision` makes PremiumService/listeners re-evaluate.
- `lib/services/premium_service.dart`: merges the signed-in user's `premium_comp` entitlement (new `EntitlementState.comp`, `hasCompAccess`); same pure rule as subscriptions (expiry, revoked, 14-day offline window, clock-moved-back); cache bound to ONE account, cleared on sign-out/switch; no paywall flash while a first comp answer is pending. New file `lib/services/comp_grant_source.dart` (Supabase reader, own row only via RLS).
- `lib/screens/paywall_screen.dart`: remote title/subtitle/benefits/badges/promo with the built-in copy as fallback; store prices/trial untouched.

## Admin side (see admin/README.md)
Pages `/paywall` (owner), `/app-config` (owner+support; access model owner-only), `/premium` (owner+support), `/announcements` (owner+support), user detail extended with comp state/grants. Env (server only): `REVENUECAT_API_KEY`, `REVENUECAT_PROJECT_ID` (optional; documented in `admin/.env.example`). The RevenueCat v2 call is UNVERIFIED.

## Tests run (this machine)
| Check | Result |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test` (whole suite, incl. other forks' work at that moment) | **583 passed, 0 failed** |
| new Flutter tests | `app_config_test` (37: parser, fuzz of 400 hostile structures, service, gate, banner, AccessConfig, applicationId), `comp_access_test` (18, MOCK-ONLY), `paywall_config_test` (9, MOCK-ONLY) |
| Backend SQL harness (PGlite) | 175 assertions, 0 failures (56 new in `app_config.test.sql`) |
| Admin `tsc` / `eslint` | clean |
| Admin `vitest` | 240 passed (93 new: role matrix per action x owner/support/content/no-MFA/no-session/CSRF, validation, RevenueCat adapter MOCK-ONLY, leak test extended) |
| `next build` (dummy env on the command line only) | OK, 23 routes (4 new) |
| Secret/canary grep of `.next/static` and `.next/server` (canary service-role + RevenueCat values) | 0 hits; env var names not present in the client bundle |

## UNVERIFIED / BLOCKED
- Everything against real Supabase (RLS, triggers, REST reads), RevenueCat (the v2 offerings call and its response shape) and Play.
- Apply migration 0009 (`supabase db push`) before using the pages; until then the app uses defaults and the admin pages show an error box.
- Comp access reaches the app only when it is signed in, online at least once, and Supabase is configured; offline it follows the 14-day rule.
- Admin dates are entered in UTC. Support grants max 90 days; owner max 10 years or no expiry (admin-enforced, not DB-enforced).
- Not wired (other fork owns the files): `AppConfigService.configureForApp()` in `main()`, `AppConfigGate` around the app, `AnnouncementBanner` placement.
