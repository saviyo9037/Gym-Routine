# RUN4_AUTH - user accounts in the Flutter app (fork A)

Scope: PART A of the brief. All of it ran locally; nothing against a real Supabase project, Google or RevenueCat. Tests that use a fake auth service are labelled `MOCK-ONLY`. Nothing committed/pushed; no keys or URLs invented.

## Flow (lib/screens/access_root.dart, lib/main.dart)
`onboarding -> sign in / register -> account checks -> paywall (LockedScreen) -> app`
- With cloud accounts configured (Supabase keys present) the user cannot reach the paywall without being signed in: the subscription belongs to the account (`Purchases.logIn(<supabase id>)` happens right after sign-in).
- Account checks, in order: signed out -> `AuthFlowScreen`; recovery link opened -> `ResetPasswordScreen`; signed in with an unconfirmed e-mail -> `VerifyEmailScreen`; a different account than the phone's data belongs to -> `AccountSwitchScreen`; store customer not yet linked to this account -> loader (never shows the previous account's entitlement).
- Not configured (no Supabase keys): no sign-in screens. A locked state shows `NotConfiguredScreen` (explains the build has no account service; export, manage subscription, restore and legal links stay). Debug builds without keys stay open for development; release builds without keys stay locked (unchanged rule from before).
- Locked users keep: Restore purchases, Manage subscription, privacy/terms links (hidden when the URL is not set), Export my data (also on the sign-in/register screens via `LockedOptions`), account deletion and sign out (paywall -> Account), all offline-safe. Nothing is deleted or changed.
- Integration spot for Part B: `AppHost.build` in `lib/main.dart` has a marked comment where the parent wraps `AccessRoot` in `AppConfigGate`.

## Screens (new)
`login_screen`, `register_screen`, `forgot_password_screen`, `verify_email_screen`, `reset_password_screen`, `account_switch_screen`, `not_configured_screen`, `auth_flow_screen` (login/register/forgot/verify state + back-button handling), shared `widgets/auth_widgets.dart` (scaffold, e-mail/password fields with show-hide toggle and autofill hints, live `PasswordRulesView` with strength meter, `AuthBanner` live-region errors, `LegalLinks`, `LockedOptions`).
- Register: e-mail, password with live rules, confirm password, required terms checkbox (links from `TERMS_URL`/`PRIVACY_POLICY_URL`, hidden if unset).
- Login: e-mail/password, Google button only when `GOOGLE_WEB_CLIENT_ID` is configured, forgot password, create account.
- Verify: resend with a 60 s cooldown (restarts after a rate-limit error), "I've confirmed it" (signed out -> back to sign-in with the e-mail kept; signed in -> refresh and check).
- Settings > Account: signed-out state now opens the same auth flow (route, closes itself after sign-in); signed-in state, sync status, sign out, typed-DELETE account deletion (existing dialog) unchanged except texts that said the account was optional.

## Services
- `auth_service.dart`: `AuthFailureKind` + pure `mapAuthError` (wrong password, e-mail taken, invalid e-mail, weak password, network, rate-limited incl. `over_email_send_rate_limit`, e-mail not confirmed, cancelled, not configured, server, unknown); messages never contain the e-mail, password or tokens. New: `resendConfirmation`, `refreshUser`, `updatePassword`, `recoveryPending`, `CloudUser.emailVerified`; sign-up detects the "already registered" fake user (empty identities).
- `password_rules.dart`: >=10 chars, lower, upper, digit (symbol/length only raise the strength meter), common-password and e-mail-name rejection, 0..4 strength.
- `account_switch.dart`: remembers which account the phone belongs to (sync binding, else `auth_last_user_id` in settings) and decides when to ask.
- `cloud_services.dart`: `attachAuth()` wiring (also used by tests): on identity change the store customer is re-linked (`premium.bindUser`), and when an account LEAVES (sign-out or switch) the protected video cache and the cached entitlement are cleared. User workout data is never touched. `AccountBinding` tells the root gate when the entitlement belongs to the current user.
- Session: persisted in the Android Keystore through the existing secure storage; restored and refreshed by the Supabase SDK at start (`CloudServices.initialize` awaits it before `runApp`).

## Account switching
Sign-in on a phone whose data belongs to another account shows `AccountSwitchScreen`: "Keep this phone's data and link it to this account" (explicit `SyncService.linkLocalDataToCurrentAccount`, nothing deleted or merged silently) or "Cancel and sign out". The existing `SyncAccountMismatch` guard still protects the sync engine.

## Password recovery
The reset e-mail link opens the Supabase-hosted reset page unless the app handles a recovery deep link. This build declares NO deep-link intent filter (no URL scheme was invented), so the practical path is: request link -> choose the new password on the hosted page -> return and sign in (the forgot screen says so). If the SDK emits `passwordRecovery` (a deep link configured later) the app shows `ResetPasswordScreen` automatically.

## Tests (all pass; MOCK-ONLY where a fake auth service is used)
- `auth_errors_and_rules_test` (17): every error kind with real `AuthApiException` types, no leaking of secrets, password rules/strength, `NoCloudAuthService` fails softly.
- `auth_screens_test` (41): register rules/strength/mismatch/terms/existing e-mail/network/rate-limit/double-submit/autofill, login errors + success + unverified + Google visibility + cancelled Google + locked options, forgot password, verify (cooldown, resend, rate limit, confirm paths), reset password, flow navigation, account-switch screen, not-configured on every auth screen, layout at 360x640 for text 1.0x and 2.0x on every auth screen.
- `auth_flow_gate_test` (18): onboarding -> auth, sign in -> paywall / app, restored session, unverified e-mail, recovery link, freemium, not configured + locked/valid, locked options, logout clears video + entitlement caches and keeps every workout table row, account switch (cancel / link / same account / first sign-in), A -> B never shows A's entitlement, RevenueCat customer linked and logged out.
- Updated truthfully: `access_gate_test` (a verified signed-in user is now part of the setup because the paywall needs an account), `cloud_screens_test` (account screen opens the auth flow), `test/helpers/cloud_fakes.dart` (three new abstract methods).
- `dart format .` clean, `flutter analyze` No issues, full `flutter test`: 583 passed, 0 failed (last run).

## UNVERIFIED / not done
- No real Supabase: sign-up, resend, refresh, recovery event, the "empty identities" detection of an existing address, rate-limit codes, Google idToken sign-in and secure-storage session restore are only exercised through fakes and the pure error mapper.
- Reset-password by deep link is not configured (see above).
- Nothing was run on a device; keyboard/autofill behaviour with a real password manager is untested.
- A subscriber who is already entitled but whose session expired offline is shown the sign-in screen once the SDK reports no user; the valid-cache offline window applies only while a session exists.
- The paywall screen was not modified (Part B owns it): it assumes a signed-in user and was not changed to hide purchase when signed out; the root gate guarantees that instead.
