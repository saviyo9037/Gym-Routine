# Workout plans & active workout audit (Phase 1)

Audited before changing anything (code read, not device-tested).

## Findings in the original code

| # | Finding | Severity | Resolution |
|---|---------|----------|------------|
| 1 | Plans were **only dated rows** (`workout_plans.date`). There were no named plans, no duplicate/delete, no user-chosen training/rest days. The weekly view used hard-coded default muscles per weekday. | Feature gap | New `training_plans` / `training_plan_days` / `training_plan_day_exercises` tables (schema v6), `TrainingPlanService`, plans list + editor screens. The active plan fills dated plans lazily for today/future only. |
| 2 | **"3 exercise" limit**: no real restriction exists in the planner. The only caps found are display-only: `history_screen.dart` shows the first 4 exercise chips on a card, `exercise_library_screen.dart` shows 8 secondary-muscle filter chips, `muscle_detail_screen.dart` shows 10. The "slot" logic in `addExerciseToDatePlan` limits **muscle focus labels** (primary + secondary) to two, not exercises. | None blocking | Nothing to remove. New plan editor has no cap (tested with 60 exercises/day). Home already listed all planned exercises. |
| 3 | `WorkoutPlanScreen._loadData` **wrote a fake plan** (`primaryMuscleName: 'Biceps'`) into the DB for any date the user merely browsed, including past dates. | Bug (data pollution) | Past dates are never written; new empty plans have no fake muscle; label shows "No focus set". |
| 4 | Active workout was **in-memory only**: killing the app lost the session; no pause; no undo; the timer kept counting in the background; "Finish" could be double-tapped. | Bug | `ActiveWorkoutController` persists every change to SQLite (`active_sessions`), recovers paused, undo stack, pause/resume, idempotent finish via `workout_sessions.client_ref` unique index. |
| 5 | Cardio rows stored distance in `weight_kg` and minutes in `reps`, so volume = km x minutes was added to strength volume. | Bug (wrong stats) | New `distance_km` / `duration_seconds` columns; cardio saves `weight_kg = 0`. Existing rows are untouched. |
| 6 | Starter seed used `primary_muscle_id: 3` for "Biceps" (id 3 is Lats; Biceps is 6). | Bug (fresh installs only) | Fixed to 6. Existing installs are not rewritten. |
| 7 | `RestTimerSheet` overflowed vertically on short screens (600 px tall test viewport). | Bug | Scrollable, safe-area aware, haptic on completion. |
| 8 | Horizontal overflows at 2x text scale: media section header, demo player badge, active-workout counter row and app bar. | Bug | Flexible/ellipsis; app bar moves Rest timer into the overflow menu; compact Finish at large text. |
| 9 | `exportBackupJson` omits `routines`, `routine_completions` and (new) training plans; restore wipes existing tables first. | Risk | Open: handled in Phase 3 (backup/export). |
| 10 | Hard-coded exercise ids in `sixDaySplitConfig` were verified against the catalogue (all 7 days resolve to the intended exercises). | OK | None. |
| 11 | FK enforcement is off (`PRAGMA foreign_keys` not enabled), so deleting a catalogue exercise leaves planned rows. Plans store a name snapshot, so they still load and run. | Accepted | Covered by a test; PRAGMA deliberately not enabled to avoid cascading deletes of user data. |

## Behaviour decisions

- Dated plan wins: a saved plan for a date is never overwritten by the template.
- Past dates never get a plan created from the template.
- A workout belongs to the date it **started** (a session crossing midnight stays on the start day).
- A recovered workout always comes back **paused** at the last known-active moment, so the time the app was dead is not counted.
- Plan delete is a soft delete (`deleted_at`) with confirmation; dated plans and history made from it are untouched.

## Not verified on a device

All of the above is covered by unit/widget tests on the host (in-memory SQLite). Real-device behaviour (rotation with video, screen-awake, process death on a phone) is UNVERIFIED; see the Manual device tests list in PROGRESS.md.
