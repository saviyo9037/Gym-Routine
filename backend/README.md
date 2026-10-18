# RepTrack backend (Supabase)

Schema, RLS, and Edge Functions for the RepTrack cloud sync / admin. Nothing here has been deployed or connected to any Supabase or RevenueCat account.

## Layout
- `supabase/migrations/0001..0009_*.sql` - ordered migrations (helpers, tables, functions/triggers, RLS + grants, storage bucket, 0006 = training-plan sync tables + cardio/HH:mm columns used by the Flutter client).
- `supabase/functions/revenuecat-webhook` - RevenueCat webhook (Deno). Pure logic in `functions/_shared/entitlement.ts` (+ tests).
- `supabase/functions/video-url` - signed URLs for protected videos (pure logic in `functions/_shared/video_url.ts` + tests).
- `supabase/functions/delete-account` - deletes caller's data (RPC) then the auth user (service role).
- `supabase/tests/*.test.sql` - pgTAP-style tests (RLS, grants, constraints, RPCs, reports).
- `harness/` - local test runner: PGlite (real Postgres compiled to WASM) + test-only Supabase stubs + a minimal pgTAP subset.

## Protected videos (migration 0008 + `video-url` function)
Videos are NOT in the app. They live in the **private** bucket `exercise-videos` (not public, mp4 only, 20 MB, no client policies:
a restrictive policy denies `anon`/`authenticated` direct access whatever other policies exist). The app calls the Edge Function
`video-url` with `{ "exercise_id": n }` and its user JWT; the function (1) validates the JWT, (2) calls `public.video_access()`
with the service role - entitlement `premium` active and not past expiry (a TRIAL is an active entitlement; billing-issue grace
bounded to 16 days; refunds/expiry arrive as `is_active=false`) AND a published exercise_media row of type `video` with
`license_verified = true` for a published catalogue exercise, (3) returns a **300 s signed URL**. Non-entitled -> 403, unknown /
NO_VIDEO / unlicensed -> 404, bad input -> 400, bad token -> 401, too many requests (60/min/user, per instance) -> 429. Tokens are
never logged or echoed. Deploy: `supabase functions deploy video-url` (JWT verification stays on). Upload files with
`node scripts/upload_videos.mjs` (see MEDIA_GUIDE.md); publish rows in the admin panel after verifying each licence.
Limits: entitlement is read from `public.entitlements`, which the RevenueCat webhook fills, so a purchase can take a few seconds
to become visible (the app simply retries); the in-memory rate limiter is per function instance.

## Mapping to local SQLite
Local ids are autoincrement integers; cloud user rows use client-generated uuid `id`, with the SQLite id kept in `local_id`.
`exercises` -> `exercises_catalog` (stable integer id, admin-managed) and `user_exercises` (custom); `workout_plans`/`planned_exercises` -> `workout_plans`/`workout_plan_exercises`; `workout_sessions`/`workout_sets` -> `workout_sessions`/`session_sets`; `routines`, `routine_completions` 1:1. `user_settings` -> `profiles.settings` (jsonb). `muscle_groups` is represented by the 15-category `primary_muscle_group` check. `media_attachments` and `plan_change_logs` are NOT synced (not in the requested scope).
Sync model: last-write-wins on `updated_at` (server-authoritative via trigger; the client's own timestamp goes in `client_updated_at`); deletes are soft (`deleted_at`). Users have no DELETE grant.
Catalogue sync: clients pull `exercises_catalog` rows with `catalogue_version > localVersion` (archived rows included so removals propagate). Rows become visible to clients only after `publish_catalogue()` stamps them.

## Apply
```
supabase link --project-ref <your-ref>     # human step
supabase db push                            # applies migrations in order
supabase functions deploy revenuecat-webhook --no-verify-jwt
supabase functions deploy delete-account
supabase functions deploy video-url
supabase secrets set REVENUECAT_WEBHOOK_AUTH="Bearer <long-random>"
```
`--no-verify-jwt` is required for the webhook because RevenueCat does not send a Supabase JWT; it is authenticated by the `Authorization` secret instead.

## Env vars
See `.env.example`. `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` are injected into hosted Edge Functions.

## Tests
```
cd harness && npm install
npm test          # SQL tests in PGlite + node:test for the webhook logic
```
With the Supabase CLI and Docker, `supabase test db` runs the same `.test.sql` files against real pgTAP (UNVERIFIED: not run here).
The `harness/sql/00_supabase_stubs.sql` file imitates `auth.users`, `auth.uid()`, the `anon/authenticated/service_role` roles, and `storage.*`. Real Supabase behaviour (e.g. `auth.uid()` reading `request.jwt.claims`, default grants) can differ; re-run on a real project/local stack before trusting it.

## Manual steps (human)
1. Create the Supabase project; apply migrations; enable email auth and (for the admin panel) MFA/TOTP in Auth settings.
2. Create the first admin: sign up a user, then with the SQL editor (service role) `insert into public.admins(user_id, role) values ('<uuid>', 'owner');`.
3. Seed `exercises_catalog` from the app's 201-exercise catalogue (not done here), then call `select public.publish_catalogue(null, 'initial')` as service role.
4. In RevenueCat: set the webhook URL to `<project-url>/functions/v1/revenuecat-webhook` and Authorization header to the same value as `REVENUECAT_WEBHOOK_AUTH`; create entitlement id `premium`; in the app call `Purchases.logIn(<supabase user id>)` so `app_user_id` is the auth uuid.
5. Wire the app's account-deletion button to POST `/functions/v1/delete-account` with the user's bearer token (required for store policy).
6. Review MRR definition (see `revenue_summary()`): derived from the latest PRODUCTION paid event per active auto-renewing subscriber, USD as reported by RevenueCat; trials/sandbox excluded.

## Known gaps
- Edge Functions were not executed (no Deno / no Supabase stack available); only the pure module is tested (Node).
- `TRANSFER` and other RevenueCat event types are recorded but do not change entitlements.
- No rate limiting on the webhook beyond the shared-secret check.


## Migration 0007 - hardening (added in the second autonomous run)

Applied after 0006. What it does and why:

| Change | Why |
|---|---|
| `server_time()` (authenticated only) | The app measures its clock skew against it and sends timestamps normalised to server time. |
| `clamp_client_updated_at` triggers on all 10 user tables | A client can never stamp a row more than 5 minutes in the future, so a phone with a wrong clock cannot win last-write-wins forever. |
| `enforce_same_owner` triggers on the 6 child tables | RLS only checked a child row's own `user_id`; a user could link a row to ANOTHER user's parent (plan, session, routine...). Now rejected with 42501. |
| `exercise_sync_id uuid` on `workout_plan_exercises`, `training_plan_day_exercises`, `session_sets` | Stable cross-device reference to a CUSTOM exercise (local integer ids differ per device). |
| `merge_favourites(jsonb)` (authenticated, SECURITY INVOKER) | Per-exercise last-write-wins merge of catalogue favourites in `profiles.settings->'favourites'`; validates keys/types, clamps timestamps, bounded to 2000 items. |

Tests: `supabase/tests/hardening.test.sql` (29 assertions). The cross-owner and clamp checks were run against a copy of the
migration WITHOUT those triggers first and failed (7 assertions), then passed with them (failing-then-passing).

### RLS review result (every policy re-read)
Checked and covered by tests: insert/update with another user's `user_id`; changing `user_id` on update; linking to another user's
parent row (fixed in 0007); anon writes to the catalogue; users calling `publish_catalogue`, `revenue_summary`, `apply_revenuecat_event`;
users writing/reading `entitlements` (read own only) and `audit_log` (no access; append-only trigger); editing privileged `profiles`
columns (`disabled`, `deleted_at`, `email`); storage uploads to `exercise-media` (no write policy; test enables RLS on the stub
`storage.objects` because the harness stub has it off - UNVERIFIED against real Supabase Storage).

New functions created after 0004 do NOT inherit the "revoke all" from 0004: every new function in 0007 has an explicit
`revoke ... from public, anon` and grants only what it needs. Keep doing that for future migrations.

### Webhook (revenuecat-webhook) changes
* Refund / support cancellation (`CANCELLATION` with `cancel_reason = CUSTOMER_SUPPORT`) revokes access immediately.
* `SUBSCRIPTION_PAUSED` and `SUBSCRIPTION_EXTENDED` are handled. Request bodies over 256 KB are refused (413).
* Still NOT handled: `TRANSFER` (entitlement moved between app user ids) is recorded but does not change `entitlements`. The app
  reads entitlements from the RevenueCat SDK, so this only affects admin revenue metrics.

## Migration 0009 - remote app config, announcements, comp (manual premium) access
- `app_config`: ONE row (`id = 1`, CHECK-enforced) with typed, constrained columns: paywall title/subtitle (80/200), benefit bullets (<= 8 x 120), plan badges (`monthly`/`yearly`, <= 24), promo (200), `maintenance_mode` + message (300), `min_app_version` (semver `x.y.z[+build]`), `access_model_override` (`subscription_required` | `freemium` | null). Chosen over key/value rows so the database validates every value, one UPDATE is atomic, and the app has a fixed schema to validate against.
- `announcements`: title (80), body (500), level `info|warning`, `starts_at`/`ends_at`, `active`; anon/authenticated can read ONLY active rows inside their window.
- RLS: `app_config` is read-only for `anon`/`authenticated` (non-sensitive by construction); no client write grants on any of the three tables; writes go through the admin panel (service role). Owner-only rules (pricing copy, access model) are enforced by the admin server actions.
- `manual_premium_grants` (reason 3-300 chars, expiry, granted_by, revoked): service role only. A trigger derives ONE entitlement row (`entitlement_id = 'premium_comp'`, `store = 'comp'`) from the live grants, which the signed-in user can read through the existing owner-select policy and which `is_entitled()` / `video_access()` honour (the `video-url` function therefore serves comp users; refunds/revocations/expiry stop it). `revenue_summary()` only counts `'premium'`, so comp is never counted as revenue.
- `audit_config_change()` trigger: DB-level audit rows (table, operation, changed column NAMES only, never values) for config, announcements and grants, in addition to the admin app's own `audit_log` entries.
- Tests: `supabase/tests/app_config.test.sql` (56 assertions; constraints, RLS for anon/authenticated/service role, announcement window, grant lifecycle, comp vs revenue, audit trail). Harness total after 0009: 175 assertions, 0 failures (PGlite only; not real pgTAP).

## Migration 0010 - trial tier for protected videos
- `entitlement_tier(user)` returns `'full'` (paid `premium` row, live `premium_comp` grant, or paid row in the <= 16-day billing grace), `'trial'` (live `premium` row with `period_type = 'TRIAL'`) or `'none'`. `is_entitled()` is unchanged: trial users stay entitled for everything except videos.
- `video_access(user, exercise, require_verified, allow_trial default false)` replaces the 3-argument function (dropped, so named-argument calls stay unambiguous). A trial user gets `{allowed:false, reason:'trial_locked'}` and no storage path; the `video-url` function answers `403 {"error":"trial_locked"}` and never signs a URL.
- To open videos during trials without code changes: `supabase secrets set TRIAL_VIDEOS_LOCKED=false` (the function then passes `p_allow_trial = true`; only the exact string `false` does that). The app has the matching build define `TRIAL_VIDEOS_LOCKED=false`. Redeploy `video-url` after changing the secret if your runtime caches env.
- Tests: `video_access.test.sql` now has 34 assertions (the old "active TRIAL gets the path" case was changed on purpose: the paid user a1 keeps the path, a new trial user is refused, and `p_allow_trial = true` opens it); harness total 182 assertions. Logic tests in `video_url.test.ts` cover trial refusal, full still served, the switch, and that it never opens videos to non-entitled users.
