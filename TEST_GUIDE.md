# RepTrack - phone test guide

How to use: install the build you want to test (`/release_candidates/final/` has a debug APK and an arm64 release APK), go through the tables top to bottom, and write **PASS** or **FAIL** (plus a note) in the last column. Nothing here was run on a phone by the developer tooling; every row is yours to verify.

Test on: at least one Android 13+ phone, ideally two brands (Samsung/Xiaomi/OnePlus/Oppo/Vivo/Realme behave differently for background work), one small screen and one large/tablet if available.
Before each section that says **fresh install**: uninstall RepTrack first (`adb uninstall com.reptrack.app.reptrack`).
Useful commands: `adb shell am force-stop com.reptrack.app.reptrack` (kill the app), `adb logcat | findstr RepTrack` (logs), `adb install -r app.apk` (update in place).
In the debug build, Settings > Diagnostics shows versions, row counts, scheduled alarms, permissions, sync queue and entitlement, and can copy a bug report. Paste that report when you log a failure.

## 0. First run and basics
| # | Steps | Expected | Pass/Fail |
|---|---|---|---|
| 0.1 | Fresh install, open the app with Wi-Fi and mobile data OFF | App opens to Home without errors; no login asked | |
| 0.2 | Look at Home, Routine, Plan, Library, History, Settings tabs | Every tab opens; no red error screens; dark theme (black background, orange accent) | |
| 0.3 | Home on a fresh install | Starter plan/routines visible; no fake stats; "first-time" wording where there is no history | |
| 0.4 | Back button on each tab | Returns to Home first, then exits the app | |
| 0.5 | Rotate the phone on every tab | No crash, no lost input, layout fits | |
| 0.6 | System font size to the largest, then 360-wide small phone | No overflowing text or hidden buttons on any tab | |

## 1. Exercise library, detail, videos
| # | Steps | Expected | Pass/Fail |
|---|---|---|---|
| 1.1 | Library: scroll the whole list fast | Smooth, no jank or blank cards that never fill | |
| 1.2 | Pick each of the 15 categories | Counts match the exercises shown; only exercises whose **primary** muscle is that category | |
| 1.3 | Search "wings", "db press", "quads", a typo | Slang/alias results appear; no crash on empty result (friendly empty state) | |
| 1.4 | Open a detail screen for an exercise WITH video (e.g. Standing Dumbbell Curl) | Video plays, muted by default, controls work, loops/replay works | |
| 1.5 | Open one of the NO_VIDEO exercises (see `audit/needs_video.csv`, e.g. Barbell Bench Press) | Photo shown with "No demonstration video yet"; no error, no spinner stuck, no old video | |
| 1.6 | Switch quickly between several exercises in the active workout | Each shows its own video or photo; never the previous exercise's | |
| 1.7 | Mark favourite, add a note, reopen after killing the app | Favourite and note are still there | |
| 1.8 | Add a custom exercise, edit it, delete it (confirm dialog) | Appears in library under its category; delete asks first | |
| 1.9 | Airplane mode, open videos | Bundled videos still play | |

## 2. Plans (weekly)
| # | Steps | Expected | Pass/Fail |
|---|---|---|---|
| 2.1 | Plan tab > "My training plans" > New plan; name it; leave name empty and press SAVE | Name required message | |
| 2.2 | Pick Mon-Sat as training days, Sun rest | Day chips show counts / "Rest" | |
| 2.3 | Add 10+ exercises to Monday through the picker | No limit; each asks sets/reps/weight; decimals like 12.5 accepted | |
| 2.4 | Add the same exercise twice | Warning dialog "Already in this day" | |
| 2.5 | Drag to reorder; swipe or X to remove; use UNDO | Order and removal behave; undo restores | |
| 2.6 | Cardio exercise (Treadmill Running) | Asks minutes / distance, not reps/weight | |
| 2.7 | Save, duplicate, set active, delete (confirm) | "Copy of ..." created; only one active; delete asks first | |
| 2.8 | (Only in a build with `--dart-define=ACCESS_MODEL=freemium`) create a 3rd plan | Paywall appears; existing plans untouched | |
| 2.9 | Set a plan active; check Home/Plan tab for tomorrow | Day follows the plan's weekday; edits to a single day do not change the template | |
| 2.10 | Browse past dates in the Plan tab | Nothing is created for past dates | |

## 3. Active workout
| # | Steps | Expected | Pass/Fail |
|---|---|---|---|
| 3.1 | Home > START WORKOUT | Only that day's exercises; timer running | |
| 3.2 | Complete a set | Set marked; rest timer sheet opens (Skip/+30s/Pause work) | |
| 3.3 | Edit weight to 67.5 and reps, then Undo | Value reverts; undo is one step per field edit | |
| 3.4 | Add set / Remove set; next/previous exercise; tap an exercise pill | Works; last set cannot be removed | |
| 3.5 | Pause, wait 1 min, Resume | Elapsed time did not run while paused | |
| 3.6 | **Kill the app** (swipe from recents, and once `am force-stop`), reopen | Home shows RESUME WORKOUT; sets intact; timer paused | |
| 3.7 | Resume, Finish, check History | Exactly ONE session saved; double-tapping Finish does not duplicate | |
| 3.8 | Back button mid-workout | Asks Keep training / Save & leave / Discard | |
| 3.9 | Start a new workout while one is in progress | Asks Resume / Discard & start new | |
| 3.10 | Rest-day: Home on a rest day, open the workout | Rest-day screen with "Start an unplanned workout" | |
| 3.11 | Unplanned workout: add exercises live, finish | Saved as a session | |
| 3.12 | Menu > Keep screen on | Screen stays on during the workout; restored after leaving | |
| 3.13 | Start at 23:50, finish after 00:00 | Session dated on the start day | |
| 3.14 | Cardio exercise: enter minutes and km | Saved; not counted as strength volume | |
| 3.15 | Start the workout from a non-today plan date | Confirmation first; session dated the day it was performed | |

## 4. History and stats
| # | Steps | Expected | Pass/Fail |
|---|---|---|---|
| 4.1 | History tab with no workouts | Friendly first-time state, no fake numbers | |
| 4.2 | After 2-3 workouts | Weekly summary, sessions list, per-exercise progress show real values | |
| 4.3 | Settings > week starts on Monday/Sunday, switch | History week, Home week strip and boundaries change accordingly | |
| 4.4 | Week boundaries: log a workout Sunday 23:55 and Monday 00:05 (or change the date) | Each lands in the right week for both settings | |
| 4.5 | Month/year boundary (31 Dec -> 1 Jan, if you can set the date) | Weeks/months roll over correctly | |
| 4.6 | Delete a session (confirm) | Stats update | |

## 5. Routines and alarms (most important; use a real phone)
| # | Steps | Expected | Pass/Fail |
|---|---|---|---|
| 5.1 | Fresh install (Android 13+): create a routine with Audible alarm | Notification-permission prompt in context; on Android 14 also full-screen prompt | |
| 5.2 | Deny notifications twice | Settings page opens; later Reminder reliability shows it missing | |
| 5.3 | Reminder reliability > Test the alarm (10 s) and lock the phone at once | Screen wakes, alarm sound, vibration, Stop/Snooze work | |
| 5.4 | Routine 3 minutes ahead, phone locked | Rings on time | |
| 5.5 | **Chaining**: leave a daily alarm routine; after it rang, do NOT open the app; next day | Rings again; Reminder reliability next alarm = following day | |
| 5.6 | **Reboot** with an alarm 10 min ahead; do NOT open the app | Rings | |
| 5.7 | **App update**: `adb install -r` over the old build, do not open | Alarm still rings | |
| 5.8 | **Timezone change**: alarm 07:00, change timezone | Fires at 07:00 local in the new zone | |
| 5.9 | **Clock change** by hours | Next scheduled alarms list is recomputed | |
| 5.10 | **Battery saver ON**, then Doze (screen off 30+ min) | Record whether it rings; try Unrestricted battery setting afterwards | |
| 5.11 | Do Not Disturb ON | Record whether the alarm sounds | |
| 5.12 | Swipe the app away / force stop / OEM "clean" | Record result per brand; follow the OEM guidance and retest | |
| 5.13 | Snooze | Rings once more after the snooze; tomorrow's regular alarm still listed | |
| 5.14 | Reminder 10 min before | One quiet notification at start-10, no duplicates | |
| 5.15 | Quiet reminder routine (type notification) | Notification at the right time | |
| 5.16 | Delete/disable a routine | Its alarm no longer rings and disappears from Next scheduled alarms | |
| 5.17 | Overnight routine (sleep 22:30-07:15) at 02:00 | Shown as in progress | |
| 5.18 | Routine with no repeat day selected | Cannot save without a day | |
| 5.19 | Revoke exact-alarm / full-screen / notification permission one by one | Status screen shows each as missing with a working fix button | |

## 6. Backup, restore, export
| # | Steps | Expected | Pass/Fail |
|---|---|---|---|
| 6.1 | Settings > backup: export JSON | File created and shareable | |
| 6.2 | Change data, then restore the backup (replace) | Asks for confirmation; data returns to backup state; routines/plans included | |
| 6.3 | Import with merge (if offered) | Dry-run summary first; existing data not clobbered; importing twice adds nothing | |
| 6.4 | Corrupt/wrong file | Clear error, nothing lost | |
| 6.5 | Premium: CSV/JSON history export | Works when premium; paywall otherwise | |

## 7. Permission-denied and offline cases
| # | Steps | Expected | Pass/Fail |
|---|---|---|---|
| 7.1 | Deny microphone, try a voice note | Friendly message, no crash | |
| 7.2 | Attach a photo/video via picker and camera | Works without storage permissions | |
| 7.3 | Whole app in airplane mode | Core features all work; account/sync screens explain they need internet | |
| 7.4 | App with NO cloud keys (default build) | Account screen says cloud is not configured; no crashes; paywall not shown as purchasable | |

## 8. After accounts exist (needs your Supabase / RevenueCat / Play setup; build with `--dart-define-from-file=env.local.json`)
| # | Steps | Expected | Pass/Fail |
|---|---|---|---|
| 8.1 | Sign up by email, confirm, sign out, sign in | Works | |
| 8.2 | Google sign-in | Works (needs the OAuth client with your SHA-1) | |
| 8.3 | Paywall: monthly and yearly offers load with Play prices | Prices shown; loading/error states sane when offline | |
| 8.4 | Purchase with a license tester | Premium unlocks within seconds; sync, Progress charts, export, 3rd plan available | |
| 8.5 | Restore purchases on a second device / after reinstall | Premium returns | |
| 8.6 | Cancel in Play, wait for expiry (use test accelerated renewals) | Premium ends at expiry; local data kept; plans over the limit kept | |
| 8.7 | Billing problem / grace period (test card declined) | Behaves per the entitlement states in PROGRESS.md | |
| 8.8 | Sync: edit on phone A, wait, open phone B | Change appears; both keep their local data | |
| 8.9 | Sync with airplane mode: edit offline, reconnect | Queue uploads; no duplicates | |
| 8.10 | Edit same item on two devices offline, then sync | Newest edit wins; a conflict is recorded; nothing crashes | |
| 8.11 | Delete on A, edit on B | Deterministic result per the documented rule | |
| 8.12 | Wrong phone clock (set 2 h ahead) then sync | Cannot overwrite newer cloud data forever (skew rule) | |
| 8.13 | Account deletion (Settings > Account > Delete) | Cloud data and auth user removed; local data kept unless you tick wipe; Play subscription note shown | |
| 8.14 | Admin panel (after deployment): login, 2FA, each role | Role limits enforced; every change appears in the audit log | |

## 9. Videos (licence decision)
| # | Steps | Expected | Pass/Fail |
|---|---|---|---|
| 9.1 | Review `audit/frames/*.jpg` against exercise names | Note any video that shows the wrong movement | |
| 9.2 | Build a release with `--dart-define=BUNDLED_VIDEOS=false` | Every exercise shows its photo, no video anywhere | |
| 9.3 | Normal build | 123 exercises with video, 78 without | |

## 10. Subscription-required flow (needs Play license testers + RevenueCat; build with your keys)
| # | Steps | Expected | Pass/Fail |
|---|---|---|---|
| 10.1 | Fresh install, open the app | 3-page onboarding once (collects nothing), then the paywall | |
| 10.2 | Paywall without subscribing | Nothing else in the app is reachable; prices and trial text come from the Play offer; auto-renew + cancel text visible; no "free" wording except the Play-provided trial text | |
| 10.3 | Privacy and terms links on the paywall | Open your hosted pages (hidden if the URLs were not set at build time) | |
| 10.4 | Start the trial with a license tester | Full access immediately; no paywall flash on later launches | |
| 10.5 | Trial ends / subscription expires (test renewals are accelerated) | App locks; data untouched; Restore, Manage subscription, privacy, Export my data, Delete account still work | |
| 10.6 | While locked: an alarm due | It still rings; no workout shortcut on the ringing screen | |
| 10.7 | While locked: try to open Plans/Routines/Workouts | Not reachable | |
| 10.8 | Subscribe again | Everything back; no data lost | |
| 10.9 | Airplane mode with a valid subscription | Still full access for up to 14 days offline, then asks to reconnect | |
| 10.10 | RevenueCat/Play unreachable at launch | "Could not verify your subscription - retry"; retries; never a hard failure for a user inside the offline window | |
| 10.11 | Refund the purchase (Play console) | Access ends promptly after the next check | |
| 10.12 | Open a video exercise while signed in + subscribed | Downloads once with progress, then plays; works offline afterwards | |
| 10.13 | Same without an account / without subscription / offline before first download | Photo + short explanation, never an error or a stale video | |
| 10.14 | Subscription ends or sign out | Downloaded videos are removed from the phone | |
| 10.15 | Debug build: Settings > Developer > Diagnostics | Shows entitlement state, queue, alarms; copy bug report works | |

## 11. Accounts (needs your Supabase project; build with your keys)
| # | Steps | Expected | Pass/Fail |
|---|---|---|---|
| 11.1 | Fresh install | Onboarding, then Create account / Sign in. The paywall is NOT reachable before you are signed in | |
| 11.2 | Register: weak password, mismatched confirm, no terms tick | Live rules + strength meter; each problem blocks the button with a clear message | |
| 11.3 | Register with a valid e-mail | "Check your e-mail" screen; resend works with a 60 s cooldown; "I've confirmed it" continues after you click the mail link | |
| 11.4 | Register an e-mail that already exists | Plain message, no crash, no leak of other details | |
| 11.5 | Login with wrong password | "Wrong e-mail or password"; right password goes to the paywall (or the app if subscribed) | |
| 11.6 | Login with an unconfirmed e-mail | Verification screen, not an error dump | |
| 11.7 | Airplane mode: login / register | "No internet connection" message, can retry | |
| 11.8 | Many wrong attempts / many resends | Rate-limit message, not a crash | |
| 11.9 | Forgot password | "If an account exists we sent a link"; the reset happens on the Supabase page (no deep link in this build) | |
| 11.10 | Google sign-in (only with `GOOGLE_WEB_CLIENT_ID` and your SHA-1) | Works; button hidden when not configured | |
| 11.11 | Kill and reopen the app | Still signed in (secure storage), no re-login; token refresh is silent | |
| 11.12 | Sign out | Returns to sign-in; video cache and cached entitlement cleared; ALL workout data still on the phone (check History/Plans after signing back in) | |
| 11.13 | Sign in as a DIFFERENT account on a phone with data | Account-switch screen: "keep this phone's data and link it" or "cancel and sign out"; nothing merged or deleted silently | |
| 11.14 | After login the subscription is tied to your account | Purchase on phone A, sign in on phone B with the same account: Restore gives access | |
| 11.15 | Delete account (type DELETE) | Cloud data and login removed; local data kept unless you tick wipe; Play subscription must be cancelled separately (note shown) | |
| 11.16 | Locked + signed out or signed in | Restore, Manage subscription, privacy/terms, Export my data still reachable | |
| 11.17 | App with NO keys | "Not connected" screen, no crash | |
| 11.18 | Text size max, small phone | Login/register/forgot/verify screens fit, buttons reachable, password manager autofill works | |

## 12. Admin-managed config (needs migration 0009 and the admin panel)
| # | Steps | Expected | Pass/Fail |
|---|---|---|---|
| 12.1 | Admin > Plans & Paywall: change the title, benefits, a "Best value" badge | The app shows the new copy after a restart/resume (within ~10 min); prices and trial text still come from Play | |
| 12.2 | Phone offline | Last cached copy, or the built-in defaults on a fresh install; never an empty paywall | |
| 12.3 | Admin > App Config: maintenance ON with a message | App shows the maintenance screen with Retry; alarms still ring; OFF restores the app | |
| 12.4 | Set min app version above the installed one | "Update required" screen with a Play Store button | |
| 12.5 | Access model override (owner only) | Takes effect; a support user cannot change it; a keyless release build is never opened by it | |
| 12.6 | Announcements: create one with a time window | Banner on Home inside the window; dismissal remembered; disappears after the window | |
| 12.7 | Admin > Manual premium: grant comp access with reason + expiry to a test user | The user gets access (and videos) after the app next refreshes; revoke/expiry removes it; audit log shows both actions | |
| 12.8 | Roles: content role tries Plans & Paywall / Manual premium; support tries pricing copy / access model | Refused server-side; nothing changes | |
| 12.9 | Edit config with bad data via SQL (e.g. a 5 KB title) | Constraint refuses it; the app still shows defaults on bad cached data | |
| 12.10 | Admin > Plans & Paywall RevenueCat table (with your REVENUECAT_API_KEY) | Real monthly/yearly price and trial read-only, or a clear "not provided" note | |
