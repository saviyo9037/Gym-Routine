# RepTrack Admin (Next.js)

Web admin panel for the RepTrack Supabase backend (see `../backend`). Next.js App Router, TypeScript, Tailwind, `@supabase/supabase-js` + `@supabase/ssr`. No AI features.

## Security model
- Every page and server action calls **one** guard, `requireAdmin(allowedRoles)` (`src/lib/guard.ts`): valid session -> MFA assurance level `aal2` -> a row in `admins` with an allowed role. The service-role client is only created after those checks pass and is handed out through the returned context.
- The service-role key (`SUPABASE_SERVICE_ROLE_KEY`) is read only in `src/lib/env.ts`, used only by `src/lib/supabase/admin.ts` (`import "server-only"`). `src/tests/no-service-role-in-client.test.ts` fails if a `"use client"` module can transitively reach a server-only module, if the key name appears elsewhere, or if it is exposed via `NEXT_PUBLIC_*`.
- Roles: `owner` (everything), `support` (users, subscriptions, workout data view), `content` (catalogue, media, templates). Admin management and the audit log are owner-only.
- Every mutating action runs through `runMutation` (`src/lib/action.ts`), which requires the handler to return an audit entry and writes it to `audit_log`; if the audit write fails the action reports failure. Viewing a user's workout data is audited before the data is read.
- Media uploads: allowed types mp4/jpg/png/webp, size limits (video 50 MB, image 5 MB), magic-byte check, mandatory licence + attribution, stored as `draft` with `license_verified=false`; publishing requires a person to click "Mark licence verified". Nothing auto-claims a licence.
- `src/proxy.ts` only refreshes the session cookie and redirects anonymous visitors to `/login`; it is not an authorisation boundary.

## Setup
```
cp .env.example .env.local     # fill in your own values
npm install
npm run dev
```
**First admin:** after the migrations are applied and `.env.local` has your real values, run `node scripts/create-first-admin.mjs you@example.com` (prints a generated password once; or pass your own as a second argument, min 12 characters). It creates the Supabase user and makes it an owner; then sign in and enrol TOTP.

**Troubleshooting:** if every page shows "Admin panel is not configured" (or the older "Invalid supabaseUrl" error), `.env.local` still holds the placeholder text from `.env.example`. Replace all three values with your own (Supabase dashboard > Project Settings > API) and restart `npm run dev`; env files are only read at start-up.

Env vars (see `.env.example`): `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` (server only).

## Scripts
`npm run typecheck`, `npm run lint`, `npm test` (vitest, mocked Supabase), `npm run build`.

## Prerequisites in Supabase (manual)
1. Apply `../backend/supabase/migrations` and create the `exercise-media` bucket (migration 0005 does so).
2. Enable TOTP MFA in Auth settings.
3. Insert the first owner into `public.admins` using the SQL editor (see `../backend/README.md`).
4. For "DAU"/"last sync" to show data, the app must write `profiles.last_seen_at` / `last_sync_at` (allowed by RLS for the user's own row).

## Deployment
Any Node 20+ host that can run `next build && next start` (or a platform with Next.js support). Set the three env vars in the host's secret store (the service-role key as a server-side secret, never exposed to the browser). Put the panel behind HTTPS. Server-action uploads are limited by `experimental.serverActions.bodySizeLimit` (55 MB in `next.config.ts`); your host/proxy must allow request bodies at least that large. Hosting choice and URLs are yours to decide; none are configured here.

## Known limitations
- No generated DB types: Supabase responses are loosely typed.
- No end-to-end test against a real Supabase project or browser; MFA/login flows are UNVERIFIED against a live Auth server.
- Dashboard MRR is computed in SQL (`revenue_summary()`) from RevenueCat events as documented in the backend README; revenue is USD as reported by RevenueCat.
- Template plans/routines have a JSON payload editor only; the app-side schema for templates is not defined yet.
- No rate limiting or lockout beyond what Supabase Auth provides.


## Security hardening (second autonomous run)

* **CSRF:** every mutation goes through `runMutation`, which first checks the request origin (`lib/csrf.ts`): `Sec-Fetch-Site:
  cross-site/same-site`, a mismatching `Origin`, or `Origin: null` are refused with `forbidden` BEFORE the guard or any database
  access. This is on top of Next.js's own server-action origin check and the SameSite=Lax session cookies. Login and logout check it too.
* **Login throttle:** `lib/rate-limit.ts` allows 5 failed sign-ins per e-mail and 20 per IP in 15 minutes. It is in-memory and
  per server instance, so it is BEST EFFORT only. The authoritative limit is Supabase Auth's own rate limits (Dashboard > Auth >
  Rate limits: set them) plus your hosting/CDN. A valid password for a non-admin counts as a failed attempt. Successful admin
  sign-ins are written to `audit_log` (`auth.login`, best effort).
* **XSS / headers:** `next.config.ts` sends a Content-Security-Policy (default-src 'self'; connect/img/media allowed only to your
  Supabase origin from `NEXT_PUBLIC_SUPABASE_URL`; no framing; no objects), HSTS, nosniff, frame deny, a locked-down
  Permissions-Policy and COOP. `script-src` still contains `'unsafe-inline'` because Next injects inline bootstrap scripts; a
  per-request nonce would remove it (future hardening). A test fails if the source ever uses `dangerouslySetInnerHTML`,
  `innerHTML =`, `eval` or `new Function`.
* **Admin grant:** `addAdmin` matches the e-mail exactly (it used `ilike`, where `_`/`%` in an address are wildcards and could
  select a different user).
* **Service-role key:** re-verified with `next build`: a canary service-role value had 0 hits in `.next/static` and
  `.next/server`; the name `SERVICE_ROLE` has 0 hits in `.next/static`.
* **Pagination:** every list is range-limited (`PAGE_SIZE`) and the page number is clamped by `pageSchema`.
* Tests: `src/tests/security.test.ts` (origin matrix, CSRF on mutations and login, limiter, throttle, exact-match grant, headers,
  no raw HTML). Tests that use the in-memory Supabase mock say `MOCK-ONLY`.

## Plans & Paywall, App config, Manual premium, Announcements (migration 0009)
| Page | Roles | What it does |
|---|---|---|
| `/paywall` Plans & Paywall | owner | Edits the paywall copy (title, subtitle, <= 8 bullets, monthly/yearly badge, promo). Also shows the store plans READ-ONLY from RevenueCat when `REVENUECAT_API_KEY` + `REVENUECAT_PROJECT_ID` are set server-side (see `.env.example`); otherwise a "not configured" note. Prices and the trial are changed in Google Play Console only. |
| `/app-config` | owner + support (access model: owner only) | Maintenance mode + message, minimum app version, remote access-model override. |
| `/premium` Manual premium | owner + support | Grant/revoke comp access: reason required, expiry required (support max 90 days, owner max 10 years); "no expiry" is owner only. The user detail page also has the form and the grant list. |
| `/announcements` | owner + support | Create/edit/activate/delete announcements shown in the app. |
Every mutation goes through `runMutation` (CSRF origin check, `requireAdmin`, zod validation, audit_log). Text fields reject `<` and `>`; dates are entered in UTC.

**RevenueCat adapter:** `src/lib/revenuecat.ts` calls `GET https://api.revenuecat.com/v2/projects/{id}/offerings?expand=items.package.product` with a Bearer v2 secret key. This call and its response shape were NOT verified against a real project (no key here); the parser is defensive and shows "not provided by the API" for any missing field. Verify it once with your key before trusting the table.
