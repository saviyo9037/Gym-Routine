# Run 2, fork 2 report: video switch, data safety, services fixes

Scope: STEP 2 (video licence safety), STEP 4 (data safety/migrations), services side of STEP 3.
All results below were produced by commands run on this machine. Nothing committed/pushed.

## STEP 2 - video licence safety
- `lib/core/media_config.dart`: `kBundledVideosEnabled` (default `true` = unchanged behaviour), overridable at build time:
  `flutter build appbundle --release --dart-define=BUNDLED_VIDEOS=false`.
- `ExerciseMediaService`: when off, every exercise is NO_VIDEO (photo fallback, no controller, no remote stream, downloads refused, inventory report shows 0 videos / 201 photo-only). `getDemonstration*` returns a `withoutVideo()` copy so screens that read `demo.hasVideo` also show the no-video state. No file is deleted. Test hook: `ExerciseMediaService.instance.videosEnabledForTesting`.
- `test/media_flag_test.dart` (6 tests, both values, files still on disk).
- `scripts/validate_media.py` (file existence, orphans, manifest completeness for all 201 ids, demonstrations JSON agreement, NO_VIDEO maps no video, sha256/size, duplicate content, H.264 / no audio / <=10 s / <=960x540, VERIFIED needs real source + licence + evidence + reviewed_by). Real run on the repo: `201 exercises, 123 files, VERIFIED 0, unverified 123, NO_VIDEO 78 -> 0 error(s), 1 warning(s)` (the warning says to keep BUNDLED_VIDEOS=false for a public release).
- `scripts/test_validate_media.py`: 10 negative/positive tests with generated fixture videos, all pass.
- `MEDIA_GUIDE.md`: how to add a verified video for one exercise id.
- Nothing was marked VERIFIED. PARENT: `PROGRESS.md` / release checklist must say the flag must be `false` for a public release unless licences are confirmed (add `--dart-define=BUNDLED_VIDEOS=false` to the release build command).

## STEP 4 - data safety and migrations
### Migration tests (`test/migration_history_test.dart`, 7 tests)
Repository history contains ONLY schema v5 (all three commits). v1-v4 are RECONSTRUCTED from the `onUpgrade` branches (labelled so in the test); v6 is the current schema with every v7 artefact stripped. Each upgrades through the production `onUpgrade` + `syncCatalogue` with realistic data (favourites, notes, custom exercises, plans, sessions+sets, routines+completions, media, settings) and asserts: every user row unchanged, no duplicates (201 catalogue + 2 custom), favourites/notes kept, seeding twice and upgrading twice change nothing, existing history is queued for first sync, routine seeding behaviour (9 starters only for installs that had no routine tables).

### REAL BUG FOUND AND FIXED (data loss)
`syncCatalogue` matched catalogue exercises by `id = ? OR name = ?`. A custom exercise created while the catalogue was smaller can sit on an id the catalogue now uses (the catalogue grew 190 -> 201), so on upgrade the custom row was overwritten with catalogue data and the real catalogue exercise was never inserted. Fix in `lib/data/db_helper.dart`: (1) `_relocateCustomExerciseIds` moves clashing custom exercises to ids >= 100001 and repoints `planned_exercises`, `workout_sets`, `training_plan_day_exercises` (only rows whose stored exercise name matches) and exercise `media_attachments`; (2) catalogue matching is restricted to `is_custom = 0`, so a custom exercise named like a catalogue exercise is left alone. Regression tests: `test/custom_exercise_collision_test.dart` (2). The migration tests above failed before the fix.

### Backup / import (`lib/services/backup_service.dart`)
- Export format 3: `format`, `format_version`, `schema_version`, `app_version` (`lib/core/app_info.dart`, test keeps it equal to pubspec), `exported_at`, per-table `counts`, SHA-256 `checksum` of the data, `tables`. Legacy flat files (v1/v2) still import.
- Validation (`parse`, throws `BackupException` with a stable code): `not_json`, `not_a_backup`, `unsupported_format`, `schema_too_new`, `missing_table`, `bad_rows`, `checksum_mismatch`.
- API for the UI (PARENT wires it into Settings; nothing was added to `settings_screen.dart`):
  ```dart
  final svc = BackupService();
  final text = await svc.exportJson();                   // share/save
  final file = svc.parse(pickedFileText);                // may throw BackupException
  final plan = await svc.planMerge(file);                // dry run: plan.tables[t].added/updated/skipped, plan.warnings
  final r = await svc.applyMerge(file, confirmed: true); // keep-newer merge, never deletes
  final r = await svc.applyReplace(file, confirmed: true); // destructive, atomic
  ```
  Both apply methods refuse unless `confirmed: true` (show the plan/warning first).
- Merge rules: ids are remapped via natural keys (plans by date, sessions by `client_ref` or date+start+created, routines by title+start, training plans by name, custom exercises by name, completions by routine+date); local rows are overwritten only when the backup copy is strictly newer (`updated_at` / `completed_at`); history is never changed; a finished day is never un-finished; favourites are unioned; imported training plans arrive inactive; deleted plans are not resurrected; existing settings win, internal flags are never imported; catalogue and muscle groups are not merged; all-or-nothing transaction. Importing the same file twice is a no-op (found and fixed a media-duplication bug through this test).
- Replace keeps `sync_id`/`sync_updated_at`, and drops tombstones of rows that came back, so a restore never queues the restored data as cloud deletions.
- `DatabaseService.exportBackupJson/restoreBackupJson` now delegate to this service (same signatures). `test/backup_restore_test.dart` was updated to the new file shape (old flat shape rebuilt as the legacy case); no assertion was weakened.
- Tests: `test/backup_service_test.dart` (17): envelope, round trip, corrupt/edited/wrong-version/foreign files, legacy, confirmation required, atomic rollback for replace AND merge, dry run writes nothing, remapped ids with a second "device", idempotent merge, conflicts keep-newer both directions, favourites union, deleted plans.

## STEP 3 - services side
- `getWeeklyPlans` no longer invents muscle groups or a Sunday rest day for unplanned days: it returns empty unsaved plans (`id == null`, no names, `isRestDay == false`). UI contract for fork 1/parent: render those as "not planned".
- A workout started from another date's plan is logged on the day it was performed (it already was) and `createWorkoutSession` now marks a plan completed ONLY when `plan.date == session.date` (previously the other day's plan was marked done). Tests in `test/services_open_items_test.dart` (6).
- `lib/core/safe_cast.dart` + models (`workout_plan`, `workout_session`, `routine`, `exercise`, `routine_completion`, `media_attachment`, `muscle_group`, `plan_change_log`, `training_plan`) read database values tolerantly (closes AUDIT_UI #14): a number where text is expected, or the reverse, no longer throws. `test/safe_cast_test.dart` (2).
- `lib/core/dev_log.dart`: `alarm_service.dart` logs through `devLog` (debug builds only), closing AUDIT_UI #11 for that file. Other `debugPrint` calls live in screens/cloud files owned by other forks (screens: fork 1; sync/premium: fork 3).
- Dead settings (`theme_mode`, `weight_unit`, `reminders_enabled`) are no longer seeded; nothing read them (closes the weight-unit leftover; AUDIT_UI #13 is closed once `settings_screen` has no kg/lbs control, which fork B removed).

## Results
- `flutter analyze` on my files: clean. (Whole-repo analyze was briefly red from other forks' in-progress `export_service.dart` / sync test helpers when I ran it.)
- New/changed tests all pass: media_flag 6, backup_service 17, backup_restore 5, migration_history 7, custom_exercise_collision 2, safe_cast 2, services_open_items 6; python validator tests 10.
- Full `flutter test` at the time of my last run: 345 passed, 18 failed. All 18 failures are in `test/top_level_layout_test.dart` (fork 1's new layout test reporting real overflows on home/plan/history/routines/settings) and one `cloud_screens_test.dart` load error (fork 3, in progress). None is in files I own. Re-run after those forks finish.

## BLOCKED / open
- v1-v4 database layouts are reconstructed, not extracted from a shipped build (no such revision exists in git); marked as such in the test.
- Merge-import UI is not wired (documented above; parent to add a Settings entry with plan preview + confirm).
- Media attachment records import but their files are device-local (a warning is returned in `ImportPlan.warnings`).
- No device run of anything.
