# RepTrack 🏋️‍♂️⏱️

> **The Ultimate Dark-Themed Android Gym Tracker, Workout Planner, Private Media Vault & Daily Routine Discipline Companion.**

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Platform](https://img.shields.io/badge/Platform-Android%20(API%2026%2B)-3DDC84?logo=android&logoColor=white)](https://developer.android.com)
[![Database](https://img.shields.io/badge/SQLite-Sqflite%20v5-003B57?logo=sqlite&logoColor=white)](https://pub.dev/packages/sqflite)
[![Tests](https://img.shields.io/badge/Tests-35%20Passing-brightgreen?logo=checkmarx&logoColor=white)]()
[![License](https://img.shields.io/badge/License-MIT-orange.svg)]()

---

## 📸 Overview

**RepTrack** is an offline-first, performance-obsessed personal fitness and discipline tracking application engineered with Flutter and native Android (Kotlin). Designed with a striking, high-contrast **black-and-orange portfolio theme** (`#0A0A0A`, `#141414`, `#FF8A00`), RepTrack bridges the gap between intense gym workouts, dietary nutrition, and structured daily habits through a unified, reliable ecosystem.

RepTrack features an extensive **190+ exercise library**, interactive **workout tracking with rest timers and volume analytics**, private **multimedia proof capture (photos, videos, audio memos)**, an **idempotent daily routine scheduler**, and a **hardware-level Android alarm system** using `AlarmManager.setAlarmClock` and `AudioAttributes.USAGE_ALARM` that rings through Doze and Silent modes.

---

## 🌟 Key Features

### 1. 📅 Daily Workout Planner & Tomorrow's Preview
- **Dual Muscle Group Focus**: Configure daily workout sessions with primary and secondary target muscle groups (e.g., *Chest + Triceps*, *Back + Biceps*, *Legs + Core*).
- **Tomorrow's Workout Preview**: Proactively inspect, customize, or re-order tomorrow’s exercises, target sets, and repetition counts ahead of time.
- **Trainer Voice & Text Memos**: Record voice instructions from your coach or dictate personalized cues saved directly alongside your workout plans.
- **Active Workout Execution Engine**:
  - Live session stopwatch and rest timer between sets.
  - Set-by-set weight (kg/lbs) and repetition logging.
  - Interactive checkboxes with real-time total volume calculation (`reps × weight`).
  - Add notes and attach visual proof (photos/videos) for each exercise or set.

---

### 2. 📚 190+ Comprehensive Exercise Library
- **14 Target Muscle Groups**: Chest, Back, Biceps, Triceps, Shoulders, Quads, Hamstrings, Glutes, Calves, Abs/Core, Forearms, Traps, Full Body, and Cardio.
- **6 Movement Modalities**: Barbell, Dumbbell, Cable, Machine, Bodyweight, and Kettlebell.
- **Rich Anatomical & Execution Data**:
  - Primary and secondary muscles targeted.
  - Mechanics classification (Compound vs. Isolation) and difficulty levels.
  - Step-by-step execution guides and anatomical cues.
  - Breathing recommendations, common mistakes, and trainer pro-tips.
- **Local Asset Architecture**: Bundles offline-ready exercise images without relying on external CDNs or network connections.
- **Custom Exercise Creator**: Add your own custom movements with photos captured from the camera or imported from the gallery.

---

### 3. 📊 Workout History & Weekly Discipline Analytics
- **Reverse Chronological Logs**: Browse all completed workout sessions with date, duration, muscle groups, total volume, and exercises completed.
- **This Week Summary**:
  - Calendar overview bounding Monday through Sunday.
  - Completion counters and visual day badges (Completed, Missed, Rest Day).
- **Muscle Group Frequency Heatmap**: Monitor muscle group stimulation over time to prevent overtraining or muscular imbalances.
- **Deep Session Inspector**: Tap any historical session to view every set performed, actual weights lifted, trainer instructions, and attached media.

---

### 4. 🔒 App-Private Media Vault (Photos, Videos & Audio)
- **Zero Media Loss Guarantee**: Photos and videos captured via camera or picked from the gallery are instantly cloned into app-private sandboxed storage (`getApplicationDocumentsDirectory()`), preventing missing thumbnails when system temp caches clear.
- **Built-in Video Player**: Watch recorded form-check videos directly inside the app with play, pause, replay, and seek controls.
- **High-Resolution Photo Viewer**: Full-screen photo preview with pinch-to-zoom, replace, and delete actions.
- **Voice Memo Player**: Review audio instructions and form notes recorded during training.
- **Decoupled SQLite Media Table**: Polymorphic linking to exercises, workout plans, active sessions, sets, and daily routines.

---

### 5. ⏰ Personalized Routine Dashboard & Food Reminders
- **Synchronized Bottom Navigation**: Dedicated **Routine** tab in the main navigation shell alongside Home, Plan, Library, History, and Settings.
- **Home Screen "My Routine" Widget**: Prominently highlights the next upcoming routine, scheduled time, and daily completion counter (`X/Y Done`).
- **9 Default Editable Daily Routines**:
  - 🌅 **7:15 AM** — Wake up & Morning Preparation (`alarm`, audible)
  - 🍳 **7:30 AM** — Breakfast (`notification`, oats, eggs, banana, peanut butter)
  - 💼 **9:00 AM** — Office / Work Start (`notification`)
  - 🍵 **10:30 AM** — Tea & Morning Snack (`notification`, green tea, chana, almonds)
  - 🥗 **1:30 PM** — Lunch (`notification`, rice/roti, lentils, chicken/paneer, salad)
  - 🍎 **4:30 PM** — Evening Snack (`notification`, banana, boiled eggs, sprouts)
  - 🏋️‍♂️ **7:00 PM** — Gym / Workout (`alarm`, connects directly to workout plan)
  - 🍗 **8:45 PM** — Dinner (Post-Gym Recovery) (`notification`, auto-calculated)
  - 🌙 **10:30 PM** — Sleep Preparation & Wind Down (`alarm`, overnight 22:30–07:15)
- **Next Meal Banner**: Displays current and upcoming meal reminders with editable dietary notes and affordable food alternatives.
- **Dynamic Post-Gym Dinner Calculation**: Automatically recalculates recovery dinner time based on configured gym end time (`endTime + 15m`).
- **Schedule Overlap Engine**: Real-time detection (`overlapsWith()`) alerting you to conflicting routines across weekdays and overnight shifts.
- **Decoupled History**: Editing a recurring routine schedule never alters past completion records.

---

### 6. 🔔 Reliable Hardware Android Alarm System
- **`AlarmManager.setAlarmClock()`**: Uses Android's highest-priority alarm API with `AlarmClockInfo`. Causes the native system alarm icon to appear in the status bar and guarantees CPU wakeup from deep Doze mode.
- **Audio Routing on `USAGE_ALARM`**: Native Kotlin foreground service (`AlarmAudioService`) outputs audio on `AudioManager.STREAM_ALARM`. Rings audibly even when the device ringtone or media volume is in **Silent** or **Vibrate** mode.
- **WakeLock & Full-Screen Lockscreen UI**: Holds a 45-second `PowerManager.WakeLock` and triggers `USE_FULL_SCREEN_INTENT` with `setShowWhenLocked(true)` and `setTurnScreenOn(true)` to display the ringing screen directly over the Android lockscreen.
- **Full-Screen Ringing Screen (`AlarmRingingScreen`)**: Features radar pulse animations, activity title, category, scheduled time, Stop, Snooze (5–30m), and a direct shortcut to open the Gym workout.
- **Alarm Settings & Android Health Checklist**:
  - Master alarm toggle & per-routine alarm enable/disable.
  - Sound selector (Digital Beep, Sunrise Bell, Gym Siren, Energetic Pulse, Gentle Chime).
  - Vibration toggle and configurable snooze durations.
  - Live **Test Alarm** button (fires a real test alarm in 2 seconds).
  - Built-in status checklist verifying **Exact Alarm**, **Notifications**, **Battery Optimization**, and **Do Not Disturb (DND)** permissions.
- **Reboot & Timezone Rescheduling**: Registered `BootReceiver` for `ACTION_BOOT_COMPLETED`, `ACTION_TIME_CHANGED`, `ACTION_TIMEZONE_CHANGED`, and `ACTION_MY_PACKAGE_REPLACED`.

---

## 🏛️ Architecture & Project Structure

```
gyn/
├── android/                         # Native Android layer
│   └── app/src/main/
│       ├── AndroidManifest.xml      # Exact alarms, boot, wakelock & full-screen permissions
│       └── kotlin/.../reptrack/
│           ├── MainActivity.kt      # MethodChannel ('com.reptrack.app/alarm'), lockscreen flags
│           ├── AlarmReceiver.kt     # BroadcastReceiver, WakeLock, Heads-up notification
│           ├── AlarmAudioService.kt # Foreground service playing USAGE_ALARM stream audio
│           └── BootReceiver.kt      # Listens for reboot & timezone events
├── assets/
│   ├── icons/                       # App branding and icon assets
│   └── images/exercises/            # 190+ bundled local exercise visual assets
├── lib/
│   ├── core/                        # Global design tokens and theme
│   │   └── theme.dart               # #0A0A0A dark mode, #FF8A00 primary accent
│   ├── data/
│   │   └── db_helper.dart           # SQLite schema v5, safe migrations, idempotent seeding
│   ├── models/
│   │   ├── exercise.dart            # Exercise catalogue model
│   │   ├── workout_plan.dart        # Daily workout plan model
│   │   ├── workout_session.dart     # Completed session & set logs
│   │   ├── media_attachment.dart    # Photo, video, audio attachment model
│   │   ├── routine.dart             # Routine schedule & alarm settings model
│   │   ├── routine_completion.dart  # Historical completion log model
│   │   └── routine_today_item.dart  # Chronological timeline item model
│   ├── services/
│   │   ├── database_service.dart    # Workout and exercise CRUD operations
│   │   ├── routine_service.dart     # Routine CRUD, meal tracking & dinner calculation
│   │   ├── alarm_service.dart       # Dart bridge to native Android AlarmManager
│   │   └── routine_notification_service.dart # Standard local notification fallback
│   ├── screens/
│   │   ├── home_screen.dart         # Dashboard, routine widget, tomorrow preview
│   │   ├── workout_plan_screen.dart # Weekly workout split manager
│   │   ├── active_workout_screen.dart # Real-time workout execution & logging
│   │   ├── exercise_library_screen.dart # 190+ exercise browser with filters
│   │   ├── exercise_detail_screen.dart  # Full instructions, mistakes & media
│   │   ├── history_screen.dart      # Session logs, weekly summary, volume stats
│   │   ├── routine_management_screen.dart # Today, Weekly & All Routines tabs
│   │   ├── alarm_settings_screen.dart # Alarm preferences & permission inspector
│   │   ├── alarm_ringing_screen.dart  # Lockscreen ringing UI with stop/snooze
│   │   └── settings_screen.dart     # Data backup, reset, and app info
│   └── main.dart                    # Bottom navigation shell, PopScope, alarm listener
└── test/                            # 35 automated unit & widget tests
    ├── exercise_library_test.dart   # 190 exercises, modalities & asset integrity
    ├── media_workflow_test.dart     # Photo/video/audio serialization & isolation
    ├── routine_workflow_test.dart   # Overlaps, overnight hours, alarms, dinner math
    ├── workout_history_test.dart    # Calendar bounds, volume math, decoupled history
    └── widget_test.dart             # Smoke test
```

---

## 🗄️ Database Architecture (SQLite Schema v5)

RepTrack utilizes a resilient SQLite schema managed through incremental, safe `onUpgrade` migrations:

| Table | Description |
|---|---|
| `exercises` | Master library of 190+ catalogue movements and user-created custom exercises |
| `workout_plans` | Daily planned splits (date, muscle groups, trainer notes, rest day flag) |
| `planned_exercises` | Planned sets, target reps, and exercise IDs assigned to a plan |
| `workout_sessions` | Completed workout history (start/end timestamp, total volume, notes) |
| `workout_sets` | Actual recorded sets (weight, reps, completed status, RPE) |
| `media_attachments` | App-private file paths for photos, videos, and trainer voice memos |
| `routines` | Daily routine definitions, repeat days, `alarm_type`, sound, vibration, snooze, and food details |
| `routine_completions` | Permanent historical completion logs (`completed` / `skipped`) decoupled from routine edits |

---

## 🚀 Getting Started

### Prerequisites
- **Flutter SDK**: `^3.19.0` or later
- **Dart SDK**: `^3.3.0` or later
- **Android SDK**: API 26 (Android 8.0 Oreo) or later (Target SDK 34)
- **Java / JDK**: OpenJDK 17

### Installation & Run

1. **Clone the repository**:
   ```bash
   git clone https://github.com/your-username/reptrack.git
   cd reptrack
   ```

2. **Install Flutter dependencies**:
   ```bash
   flutter pub get
   ```

3. **Verify static analysis**:
   ```bash
   flutter analyze
   ```

4. **Run the automated test suite**:
   ```bash
   flutter test
   ```

5. **Run on an Android device or emulator**:
   ```bash
   flutter run
   ```

---

## 📦 Building the Android APK

To generate a standalone Android debug APK:

```bash
flutter build apk --debug
```

The compiled APK will be located at:
```
build/app/outputs/flutter-apk/app-debug.apk
```

### Install directly to a connected device via ADB:
```bash
adb install -r "build/app/outputs/flutter-apk/app-debug.apk"
```

---

## 🛡️ Android Permissions Explained

RepTrack only requests permissions necessary for critical alarm delivery and private media management:

```xml
<!-- Hardware Alarms & Exact Timing -->
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
<uses-permission android:name="android.permission.USE_EXACT_ALARM" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.VIBRATE" />
<uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT" />

<!-- Background Services & Boot Recovery -->
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />

<!-- Media & Notifications -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
```

---

## 🧪 Testing Matrix

| Test Suite | Tests Passed | Coverage Highlights |
|---|:---:|---|
| `routine_workflow_test.dart` | **16 / 16** | Overlap detection, overnight duration (8h across midnight), repeat-day intersection, alarm attributes serialization, dynamic 15m post-gym dinner calculation |
| `workout_history_test.dart` | **6 / 6** | Monday–Sunday weekly bounds, volume aggregation (`reps × weight`), rest day exclusion, plan vs. history decoupling |
| `media_workflow_test.dart` | **7 / 7** | Photo, video & audio serialization, entity isolation, safe replacement copy |
| `exercise_library_test.dart` | **5 / 5** | 14 muscle groups, 6 modalities, 190 catalogue entries, asset manifest integrity |
| `widget_test.dart` | **1 / 1** | Dark theme rendering & widget smoke test |
| **Total** | **35 / 35** | **100% Passing** |

---

## 💡 Manufacturer-Specific Battery Tips

For guaranteed audible alarm playback when the device has been idle for several hours on aggressive Android skins (MIUI, OneUI, EMUI, ColorOS):

1. **Allow Autostart / Background Launch**: Enable RepTrack in your device's "Autostart" or "App Launch" settings.
2. **Ignore Battery Optimization**: Tap **Fix Battery Optimization** inside the in-app **Alarm Settings** screen to whitelist RepTrack.
3. **Do Not Disturb (DND) Exceptions**: By default, Android routes RepTrack alarms through `STREAM_ALARM`. If your system DND configuration silences all alarms, tap **Open DND Settings** inside Alarm Settings to allow alarm interruptions.

---

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
