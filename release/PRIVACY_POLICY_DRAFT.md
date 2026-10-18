# RepTrack - Privacy Policy (DRAFT - needs your review, and legal review before publishing)

> DRAFT. Not legal advice. Replace every [PLACEHOLDER]. Do not publish until the data
> practices below match the build you ship. No policy URL has been created: you must
> host this text yourself and enter that URL in Play Console.

**Last updated:** [DATE]
**Developer / controller:** [DEVELOPER OR COMPANY NAME], [POSTAL ADDRESS]
**Contact:** [PRIVACY CONTACT EMAIL]

## 1. Summary
RepTrack is a workout tracker that requires a paid subscription. Your workout data is stored on your device and the app works offline once installed. A RepTrack account is optional for the core app; it is needed only for cloud backup/sync and to download demonstration videos.

**Subscription:** RepTrack requires a paid subscription (after any trial offered by Google Play). The subscription is processed by Google Play and RevenueCat; see section 4.

**Demonstration videos:** videos are not inside the app. When you open an exercise video, the app asks our server for a short-lived link; this request carries your account ID and the exercise ID, and the server checks your subscription. The video is then saved in the app's private storage and deleted when your subscription ends or you sign out. [VERIFY against the shipped build]

## 2. Data that stays on your device (no account)
- Workout plans, workouts and sets you log, custom exercises, notes
- Routines, reminders and alarm settings
- Photos, videos and voice notes you attach (stored in the app's private storage)
- App settings (for example week start day)

We do not receive this data unless you turn on cloud sync (section 3).

## 3. Data processed if you create an account / use Premium
| Data | Purpose | When |
|---|---|---|
| Email address, account ID, sign-in method (email or Google) | Create and secure your account | When you sign up/sign in |
| Workout plans, workouts, sets, routines, custom exercises, timestamps | Cloud backup and sync between your devices | Only with Premium and while signed in |
| Subscription status (product, period, expiry, store transaction ids) | Unlock Premium, handle renewals, refunds and support | When you subscribe or restore |
| Technical data (last sync time, app version) | Operate and debug sync | While signed in |

Your favourite catalogue exercises are also synced. Photos, videos and voice notes are **not** uploaded by sync in this version. [VERIFY against the shipped build]

Your sign-in session is stored on the device in the Android Keystore (encrypted secure storage). RepTrack contains no analytics, advertising or crash-reporting service.

## 4. Service providers
We use these processors to run the service. [CONFIRM each and add their privacy links]
- Supabase (database, authentication, storage) - hosting region: [REGION]
- Google (Google sign-in, if you choose it; Google Play Billing for payments)
- RevenueCat (subscription management); it receives a purchase identifier and your account ID

We do not sell your personal data. We show no advertising and use no advertising SDKs. RepTrack uses no AI features.

## 5. Permissions the app requests, and why
- Notifications, exact/alarm scheduling, full-screen alerts: show routine reminders and ringing alarms
- Microphone: only when you record a voice note
- Camera/photos: only through the system camera or picker when you attach media (the app does not request broad storage access)

## 6. Retention and deletion
- **On device:** until you delete the data or uninstall the app.
- **Account deletion:** in the app go to Settings > Account > Delete account. This deletes your cloud data and your authentication user. Your local data stays on your device unless you choose to wipe it in the same screen.
- You can also request deletion by emailing [PRIVACY CONTACT EMAIL]. [STATE RESPONSE TIME]
- Subscription and tax records may be retained as required by law [CONFIRM RETENTION PERIOD].

## 7. Security
Data in transit is encrypted (HTTPS). Cloud data is protected by per-user access rules so each user can read only their own rows. No system is perfectly secure.

## 8. Children
RepTrack is not directed to children under [13/16 - CONFIRM]. We do not knowingly collect their data.

## 9. Your rights
Depending on where you live (for example GDPR in the EU/UK, CCPA/CPRA in California) you may have the right to access, correct, export, delete or restrict your data, and to complain to a regulator. Contact [PRIVACY CONTACT EMAIL].

## 10. International transfers
Cloud data may be processed outside your country by the providers above. [DESCRIBE SAFEGUARDS]

## 11. Changes
We will post changes here and update the date above.
