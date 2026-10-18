# Google Play "Data safety" checklist (DRAFT - you must verify every line in Play Console)

Prepared from the code in this repository. Fill the form yourself; Google holds you responsible for accuracy.
Re-check after any later change to cloud, analytics or permissions.

## Data collection overview
- Does the app collect or share required user data types? **Yes, only when the user signs in / subscribes.** Without an account nothing leaves the device.
- Is all collected data encrypted in transit? **Yes (HTTPS)** [verify Supabase/RevenueCat endpoints are HTTPS only].
- Can users request deletion? **Yes**: in-app account deletion + email request. You must also give a **web link** for deletion requests in Play Console [NO URL CREATED - you must provide one].

## Data types (collected only when the user opts into an account / Premium)
| Play category | Data type | Collected | Shared | Purpose | Optional? |
|---|---|---|---|---|---|
| Personal info | Email address | Yes | No (processor: Supabase) | Account management | Yes (account is optional) |
| Personal info | User IDs (account id) | Yes | No | Account management, sync | Yes |
| Health and fitness | Fitness info (workouts, sets, plans) | Yes | No | App functionality (backup/sync) | Yes (Premium sync only) |
| Financial info | Purchase history (subscription status) | Yes | Processor: RevenueCat | App functionality, subscription | Yes |
| App activity | Other user-generated content (notes, custom exercises, routines, catalogue favourites) | Yes | No | Backup/sync | Yes |
| App info and performance | Diagnostics | None currently (no crash reporting SDK) | - | - | - |
| Photos/videos/audio | Not collected (stay on device in this version) [verify] | No | No | - | - |
| Location, contacts, calendar, web history, messages | Not collected | No | No | - | - |

Notes for the form:
- "Shared" in Play's definition excludes service providers acting on your behalf; declare Google/RevenueCat/Supabase as processors where applicable and double-check Play's guidance.
- Advertising ID: **not used**. No ads. No third-party analytics SDK is present [verify with `flutter pub deps` before release].
- Security practices: data encrypted in transit; users can request deletion.

## Facts about the final code (verify against the build you upload)
- Sign-in session tokens are kept in the Android Keystore via secure storage, not in plain preferences.
- The in-app **Diagnostics** screen exists only in debug builds (compiled out of release); logs are debug-only and carry no user data.
- Export/backup is a local JSON file the user shares themselves; nothing is uploaded by the backup feature.
- Bundled demonstration videos: build with `--dart-define=BUNDLED_VIDEOS=false` for a public release until every video licence is confirmed (RELEASE_CHECKLIST.md); this does not change data collection.
- No crash-reporting, analytics or advertising SDK is included; dependency list: supabase_flutter, google_sign_in, purchases_flutter (RevenueCat), flutter_secure_storage, plus local-only packages (sqflite, video_player, audioplayers, record, image_picker, file_picker, share_plus, wakelock_plus, url_launcher, crypto, path_provider, intl).

## Subscription model and video delivery (added for the subscription-required model)
- The app is paid: describe it as a subscription app everywhere. Declare In-app purchases / subscriptions.
- Opening a protected video sends the **account ID and exercise ID** to the `video-url` function (collected: User IDs, purpose App functionality). Videos need an account because the entitlement is checked server-side against your account; a subscriber who is not signed in gets photos only [VERIFY in the shipped build].
- Downloaded videos are cached in app-private storage and deleted when the subscription ends or the user signs out.
- Release builds must be created with obfuscation (`scripts/build_release.ps1`) and, until every video licence is confirmed, with `--dart-define=BUNDLED_VIDEOS=false` (no video is then requested at all).

## Permissions to declare / justify (Play Console > App content)
- `SCHEDULE_EXACT_ALARM` / alarm scheduling, `USE_FULL_SCREEN_INTENT`, `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`, `WAKE_LOCK`, `VIBRATE`, `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_MEDIA_PLAYBACK` (alarm ringing service), `RECORD_AUDIO` (voice notes).
- **Full-screen intent** and **foreground-service type declaration** need a justification in Play Console (core feature: routine alarms that ring). Prepare a short demo video if Play asks.
- Removed on purpose: `USE_EXACT_ALARM`, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, `CAMERA`, `READ_MEDIA_*`, external storage permissions.
