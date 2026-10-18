/// Version string written into backups and diagnostics. Must equal the
/// `version:` line of pubspec.yaml (a test enforces this).
const String kAppVersion = '1.0.0+1';

/// Android application id (Play Store package). Must equal `applicationId` in
/// android/app/build.gradle.kts (a test enforces it). Used to build the
/// market:// link of the "update required" screen.
const String kApplicationId = 'com.reptrack.app.reptrack';
