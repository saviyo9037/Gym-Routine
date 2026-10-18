# RUN2_CLOUD - cloud, subscription, admin and security hardening (fork 3)

Scope: STEP 5 (cloud / subscription / admin completeness) and the server, admin and auth parts of STEP 6.
Everything below was run locally. Nothing was committed, pushed, deployed or uploaded. No keys or URLs were invented.
Tests that use a fake cloud, fake store or mocked Supabase client are labelled `MOCK-ONLY`.

## 1. Sync engine (`lib/services/sync_engine.dart`, `sync_service.dart`, `sync_tables.dart`)
| Gap found | Fix | Test (all MOCK-ONLY: FakeSyncRemote) |
|---|---|---|
| Wrong phone clock could win last-write-wins forever | **Clock rule:** at each run the engine asks the server for its time (`server_time()` RPC), measures the phone offset (ignored under 2 s), shifts local edit times into server time (never past server "now") before comparing / writing `client_updated_at`. The DB also clamps any client timestamp to now()+5 min (migration 0007). | `sync_hardening_test` "clock skew" (3 h behind wins correctly, 5 days ahead cannot overwrite, 30 days ahead is clamped, old backend without `server_time` falls back) |
| Equal timestamps were non-deterministic (both devices thought they won) | Equal -> the cloud copy wins on every device; for delete vs edit at the same instant the delete wins on both sides | tie tests |
| One failing table aborted the whole run | Per-table isolation; children of a failed parent are skipped; run ends with `SyncPartialFailure`, `last_synced_at` is NOT advanced; next run completes | partial-failure + "connection lost mid push" + "killed after upload before markClean" (idempotent) |
| Two devices could leave two plans active | After pull exactly one active plan is kept (newest, tie -> highest sync id), the losers are deactivated and pushed | one-active-plan tests |
| Custom exercise ids differ per device, plans pointed at the wrong exercise | Rows referencing a custom exercise carry `exercise_sync_id`; catalogue ids still travel as integers | custom exercise reference tests (different local ids) |
| Another account's data could be pushed silently into a new account | First sync binds the device to the user id; a different user -> `SyncAccountMismatch` / state `needsAccountLink`, nothing is sent until the user confirms (`linkAccount`) | account tests, `sync_service_states_test` |
| After account deletion the device believed it was still in sync | `forgetAccount()` marks everything dirty again and drops tombstones/cursors | deletion test |
| Catalogue favourites not synced | `favourite_sync` table + trigger (applied on open, see below), per-item LWW merge via `merge_favourites()`; soft-fails on an old backend | favourites tests |
| 1250 catalogue rows in ONE version lost rows after 500 (page by version only) | Keyset paging on (version, id) until a short page; nothing applied until all pages arrived | catalogue_sync_test (1250 rows, failure on page 2) |
`SyncState` gained `partial` and `needsAccountLink` (account screen handles both). New helpers for diagnostics:
`SyncService.pendingChanges()`, `SyncEngine.pendingChanges(db)`, `sync_meta` keys `clock_skew_ms`, `account_user_id`, `last_synced_at`.

## 2. Entitlements (`lib/services/premium_service.dart`)
`deriveEntitlement()` is the ONE pure rule: states `unknown, free, active, cancelledActive, gracePeriod, expired, staleOffline`.
Rules: cached premium trusted 14 days after the last successful check (not longer, and not if the phone clock was moved back);
cancelled stays premium until `expiresAt`; billing issue -> grace period (bounded to 16 days after expiry); refund/revocation
arrives as inactive -> not premium. `PremiumSnapshot` now stores `billingIssue`. `PremiumService.isPremium` uses the function.
Tests: `entitlement_state_test.dart` (19 tests, pure, not mock-based). The webhook (`_shared/entitlement.ts`) now revokes at once on
a refund cancellation (`cancel_reason = CUSTOMER_SUPPORT`) and handles `SUBSCRIPTION_PAUSED/EXTENDED`; out-of-order / duplicate
events were already handled in SQL (`apply_revenuecat_event`, tested). 17 node tests.

## 3. Account deletion (`account_screen.dart`, `auth_service.dart`)
Confirm dialog now needs the word DELETE typed (own StatefulWidget, controller disposed correctly), optional local wipe, text says the
Play subscription must be cancelled separately. After the server call: `forgetAccount()`, optional `clearAllData()`, sign out.
Server errors are mapped to a retry-safe message (the Edge Function is idempotent: data deletion can be repeated until the auth user is
gone). MOCK-ONLY widget test covers typed confirmation, cancel, deletion, local data kept by default.

## 4. Admin (`admin/`)
CSRF origin check in `runMutation`, login and logout; login throttle (5/email, 20/IP per 15 min, best effort, in-memory);
CSP + HSTS + Permissions-Policy + COOP headers; exact-match e-mail in `addAdmin` (was `ilike`); `auth.login` audit; guard re-audit
(every action already routes through `runMutation` -> `requireAdmin`, validated by the existing per-role matrix); no raw HTML test.
Results: `tsc` clean, `eslint` clean, `vitest` 137 passed (was 120), `next build` OK (19 routes), canary service-role value 0 hits in the bundle.

## 5. RLS / backend (`backend/`)
Migration **0007_hardening.sql** (see backend/README.md): `server_time()`, clamp triggers, `enforce_same_owner` triggers (cross-owner
parent links were possible), `exercise_sync_id` columns, `merge_favourites()`. New tests `hardening.test.sql` (29 assertions);
harness total 92 assertions, 0 failures (was 63). Failing-then-passing shown for the cross-owner and clamp checks.

## 6. Security (my area)
* Supabase session + PKCE verifier now live in the Android Keystore (`flutter_secure_storage`, `secure_auth_storage.dart`), not in
  SharedPreferences. No production build with plain-text sessions ever shipped, so no migration is needed.
* No tokens/e-mails in logs: remaining `debugPrint`s in my files log only exception types.
* Hardcoded-secret scan over lib/, admin/src, backend/, android/app/src: nothing found. `.env.example` documents all four
  `--dart-define`s (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `REVENUECAT_ANDROID_API_KEY`, `GOOGLE_WEB_CLIENT_ID`).
* CSV export neutralises spreadsheet formulas (`=`, `+`, `-`, `@`, tab, CR at the start of user text); catalogue media is only
  fetched over https and written under a numeric folder.

## Files changed / created
lib: `services/{sync_engine,sync_service,sync_remote,supabase_sync_remote,sync_tables,catalogue_sync_service,premium_service,auth_service,cloud_services,export_service}.dart`,
new `services/secure_auth_storage.dart`, `data/sync_schema.dart`, `screens/account_screen.dart`, `pubspec.yaml` (+`flutter_secure_storage ^11.2.0`).
`lib/data/db_helper.dart`: only `onOpen: SyncSchema.ensureCurrent` added to both `openDatabase` calls (no schema version bump: the
favourite tracking is an idempotent "extras revision" in `sync_meta`).
backend: `migrations/0007_hardening.sql`, `tests/hardening.test.sql`, `functions/_shared/entitlement.ts(+test)`, `functions/revenuecat-webhook/index.ts`, README.
admin: `src/lib/{csrf,rate-limit}.ts`, `action.ts`, `actions/{auth,admins}.ts`, `next.config.ts`, `tests/{security.test.ts,setup-mocks.ts,helpers/mock.ts}`, README.
tests: `sync_hardening_test`, `sync_service_states_test`, `entitlement_state_test`, `secure_auth_storage_test`, `export_service_hardening_test`
(+ updated `sync_engine_test`, `catalogue_sync_test`, `cloud_screens_test`, helpers `fake_sync_remote`, `cloud_fakes`).

## Notes for the other forks / the parent
* Hide archived catalogue exercises in new choices with `CatalogueSyncService.visibleExercisesWhere` (`catalogue_archived = 0`); plans and
  history that already use them keep working. Fork 1 owns the lists.
* Diagnostics screen can read: `CloudServices.sync.state / pendingChanges() / lastReport`, `CloudServices.premium.decision`,
  `SyncEngine.getMeta(db, 'clock_skew_ms')`.
* `SupabaseSyncRemote` now sends `exercise_sync_id` and calls `server_time` / `merge_favourites`: the backend needs migrations 0001-0007.

## Results (real)
`flutter analyze`: no issue in my files (one info lint in `test/migration_history_test.dart`, fork 2). My test files: 107 + 1 added pass.
Full `flutter test` run at the end: 372 passed, 7 failed - all 7 in `test/top_level_layout_test.dart` (fork 1, in progress), none in cloud code.
Backend harness 92/92, node 17/17, vitest 137/137, tsc/eslint clean, next build OK.

## BLOCKED / UNVERIFIED
* No real Supabase / RevenueCat / Play / Google connection: PostgREST `or` cursor filter, Edge Functions (no Deno), RLS on the real
  stack (harness uses stubs; `storage.objects` RLS only simulated), purchases, restore, Google sign-in, Keystore behaviour on a device.
* Two-device behaviour only simulated with in-memory databases.
* Login throttle is per instance only; the real limit must be set in Supabase Auth rate limits.
* `TRANSFER` webhook events are recorded but do not move entitlements (affects admin revenue metrics only).
* CSP keeps `'unsafe-inline'` for scripts (Next bootstrap); nonce-based CSP not done.
* Known sync gaps left: media attachments are not synced; archived catalogue exercises are only flagged (lists must apply the helper).
