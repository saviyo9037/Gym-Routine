import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../core/clock.dart';
import '../data/db_helper.dart';
import '../models/exercise.dart';
import '../models/training_plan.dart';
import '../models/workout_plan.dart';
import '../models/workout_session.dart';
import 'database_service.dart';
import 'access_guard.dart';

/// One set (strength) or round (cardio) of a workout in progress.
class ActiveSet {
  ActiveSet({
    required this.setNumber,
    this.weight = 0,
    this.reps = 0,
    this.durationSeconds,
    this.distanceKm,
    this.isCompleted = false,
    this.completedAt,
  });

  int setNumber;
  double weight;
  int reps;
  int? durationSeconds;
  double? distanceKm;
  bool isCompleted;
  String? completedAt;

  ActiveSet copy() => ActiveSet(
    setNumber: setNumber,
    weight: weight,
    reps: reps,
    durationSeconds: durationSeconds,
    distanceKm: distanceKm,
    isCompleted: isCompleted,
    completedAt: completedAt,
  );

  Map<String, dynamic> toJson() => {
    'n': setNumber,
    'w': weight,
    'r': reps,
    'd': durationSeconds,
    'k': distanceKm,
    'c': isCompleted,
    't': completedAt,
  };

  factory ActiveSet.fromJson(Map<String, dynamic> j) => ActiveSet(
    setNumber: j['n'] as int? ?? 1,
    weight: (j['w'] as num?)?.toDouble() ?? 0,
    reps: j['r'] as int? ?? 0,
    durationSeconds: j['d'] as int?,
    distanceKm: (j['k'] as num?)?.toDouble(),
    isCompleted: j['c'] as bool? ?? false,
    completedAt: j['t'] as String?,
  );
}

class ActiveExercise {
  ActiveExercise({
    required this.exerciseId,
    required this.name,
    this.muscleGroup = '',
    this.imagePath,
    this.restSeconds = 90,
    this.targetReps = 10,
    this.targetWeightKg = 0,
    this.targetDurationSeconds,
    this.targetDistanceKm,
    this.notes,
    required this.isCardio,
    required this.sets,
  });

  final int exerciseId;
  final String name;
  final String muscleGroup;
  final String? imagePath;
  final int restSeconds;
  final int targetReps;
  final double targetWeightKg;
  final int? targetDurationSeconds;
  final double? targetDistanceKm;
  final String? notes;
  final bool isCardio;
  final List<ActiveSet> sets;

  int get completedSets => sets.where((s) => s.isCompleted).length;
  bool get isDone => sets.isNotEmpty && completedSets == sets.length;

  ActiveSet newSetFromLast() {
    final last = sets.isNotEmpty ? sets.last : null;
    return ActiveSet(
      setNumber: sets.length + 1,
      weight: last?.weight ?? targetWeightKg,
      reps: last?.reps ?? targetReps,
      durationSeconds: last?.durationSeconds ?? targetDurationSeconds,
      distanceKm: last?.distanceKm ?? targetDistanceKm,
    );
  }

  ActiveExercise copy() => ActiveExercise(
    exerciseId: exerciseId,
    name: name,
    muscleGroup: muscleGroup,
    imagePath: imagePath,
    restSeconds: restSeconds,
    targetReps: targetReps,
    targetWeightKg: targetWeightKg,
    targetDurationSeconds: targetDurationSeconds,
    targetDistanceKm: targetDistanceKm,
    notes: notes,
    isCardio: isCardio,
    sets: sets.map((s) => s.copy()).toList(),
  );

  Map<String, dynamic> toJson() => {
    'id': exerciseId,
    'name': name,
    'mg': muscleGroup,
    'img': imagePath,
    'rest': restSeconds,
    'tr': targetReps,
    'tw': targetWeightKg,
    'td': targetDurationSeconds,
    'tk': targetDistanceKm,
    'notes': notes,
    'cardio': isCardio,
    'sets': sets.map((s) => s.toJson()).toList(),
  };

  factory ActiveExercise.fromJson(Map<String, dynamic> j) => ActiveExercise(
    exerciseId: j['id'] as int? ?? 0,
    name: j['name'] as String? ?? 'Exercise',
    muscleGroup: j['mg'] as String? ?? '',
    imagePath: j['img'] as String?,
    restSeconds: j['rest'] as int? ?? 90,
    targetReps: j['tr'] as int? ?? 10,
    targetWeightKg: (j['tw'] as num?)?.toDouble() ?? 0,
    targetDurationSeconds: j['td'] as int?,
    targetDistanceKm: (j['tk'] as num?)?.toDouble(),
    notes: j['notes'] as String?,
    isCardio: j['cardio'] as bool? ?? false,
    sets: ((j['sets'] as List?) ?? const [])
        .map((e) => ActiveSet.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );

  /// Builds a card for a planned/catalogue exercise.
  factory ActiveExercise.fromSpec({
    required int exerciseId,
    required String name,
    required String muscleGroup,
    String equipment = '',
    String? imagePath,
    required int sets,
    required int reps,
    required double weightKg,
    required int restSeconds,
    int? durationSeconds,
    double? distanceKm,
    String? notes,
  }) {
    final cardio = isCardioExercise(
      muscleGroup: muscleGroup,
      equipment: equipment,
      name: name,
    );
    final count = sets < 1 ? 1 : sets;
    return ActiveExercise(
      exerciseId: exerciseId,
      name: name,
      muscleGroup: muscleGroup,
      imagePath: imagePath,
      restSeconds: restSeconds,
      targetReps: reps,
      targetWeightKg: weightKg,
      targetDurationSeconds: durationSeconds,
      targetDistanceKm: distanceKm,
      notes: notes,
      isCardio: cardio,
      sets: [
        for (var i = 0; i < count; i++)
          ActiveSet(
            setNumber: i + 1,
            weight: weightKg,
            reps: reps,
            durationSeconds: cardio ? (durationSeconds ?? reps * 60) : null,
            distanceKm: cardio ? distanceKm : null,
          ),
      ],
    );
  }
}

/// Where the in-progress workout is persisted.
abstract class ActiveSessionStore {
  Future<void> save(String clientRef, String stateJson, String startedAt);
  Future<String?> load();
  Future<void> clear();
}

class SqliteActiveSessionStore implements ActiveSessionStore {
  SqliteActiveSessionStore({DatabaseHelper? helper})
    : _helper = helper ?? DatabaseHelper.instance;

  final DatabaseHelper _helper;

  @override
  Future<void> save(
    String clientRef,
    String stateJson,
    String startedAt,
  ) async {
    final db = await _helper.database;
    await db.insert('active_sessions', {
      'id': 1,
      'client_ref': clientRef,
      'state_json': stateJson,
      'started_at': startedAt,
      'updated_at': AppClock.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<String?> load() async {
    final db = await _helper.database;
    final rows = await db.query('active_sessions', where: 'id = 1', limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['state_json'] as String?;
  }

  @override
  Future<void> clear() async {
    final db = await _helper.database;
    await db.delete('active_sessions');
  }
}

/// Small summary used by the "Resume workout" banner.
class ActiveWorkoutSummary {
  const ActiveWorkoutSummary({
    required this.title,
    required this.completedSets,
    required this.totalSets,
    required this.startedAt,
  });
  final String title;
  final int completedSets;
  final int totalSets;
  final DateTime startedAt;
}

typedef SessionSaver = Future<int> Function(WorkoutSession session);

/// State machine for a workout in progress. Every mutation is persisted so the
/// workout survives the app being killed; [finish] saves exactly once.
class ActiveWorkoutController extends ChangeNotifier {
  ActiveWorkoutController({
    required this.exercises,
    required this.store,
    this.planId,
    this.planDate,
    this.primaryMuscle = 'General',
    this.secondaryMuscle,
    this.isUnplanned = false,
    String? clientRef,
    DateTime? startedAt,
    int accumulatedSeconds = 0,
    DateTime? runningSince,
    this._currentIndex = 0,
    DateTime? lastActiveAt,
  }) : clientRef = clientRef ?? _newRef(),
       startedAt = startedAt ?? AppClock.now(),
       _accumulated = accumulatedSeconds,
       _runningSince =
           runningSince ?? (startedAt == null ? AppClock.now() : null),
       _lastActiveAt = lastActiveAt ?? AppClock.now();

  static String _newRef() =>
      '${AppClock.now().microsecondsSinceEpoch.toRadixString(36)}-'
      '${Random().nextInt(1 << 32).toRadixString(36)}';

  final List<ActiveExercise> exercises;
  final ActiveSessionStore store;
  final String clientRef;
  final int? planId;
  final String? planDate;
  final String primaryMuscle;
  final String? secondaryMuscle;
  final bool isUnplanned;
  final DateTime startedAt;

  int _accumulated;
  DateTime? _runningSince;
  int _currentIndex;
  DateTime _lastActiveAt;
  bool _finished = false;
  bool _finishing = false;
  bool _cancelled = false;
  Object? lastPersistError;

  /// Bumped on undo so the UI can rebuild text fields from the model.
  int revision = 0;
  String? _editKey;
  DateTime? _editAt;

  final List<List<ActiveExercise>> _undo = [];
  static const _maxUndo = 50;
  Future<void> _persistQueue = Future.value();

  // ---------------------------------------------------------------- build

  factory ActiveWorkoutController.fromPlan(
    WorkoutPlan plan,
    ActiveSessionStore store,
  ) {
    return ActiveWorkoutController(
      store: store,
      planId: plan.id,
      planDate: plan.date,
      primaryMuscle: plan.primaryMuscleName ?? 'General',
      secondaryMuscle: plan.secondaryMuscleName,
      exercises: [
        for (final pe in plan.exercises)
          ActiveExercise.fromSpec(
            exerciseId: pe.exerciseId,
            name: pe.exerciseName,
            muscleGroup: pe.muscleGroupName,
            equipment: pe.exercise?.equipment ?? '',
            imagePath: pe.imagePath,
            sets: pe.targetSets,
            reps: pe.targetReps,
            weightKg: pe.targetWeightKg,
            restSeconds: pe.restSeconds,
            durationSeconds: pe.targetDurationSeconds,
            distanceKm: pe.targetDistanceKm,
            notes: pe.notes,
          ),
      ],
    );
  }

  factory ActiveWorkoutController.single(
    Exercise ex,
    ActiveSessionStore store,
  ) {
    return ActiveWorkoutController(
      store: store,
      primaryMuscle: ex.muscleGroupName,
      isUnplanned: true,
      exercises: [specFromExercise(ex)],
    );
  }

  factory ActiveWorkoutController.unplanned(ActiveSessionStore store) =>
      ActiveWorkoutController(store: store, isUnplanned: true, exercises: []);

  static ActiveExercise specFromExercise(Exercise ex) =>
      ActiveExercise.fromSpec(
        exerciseId: ex.id ?? 0,
        name: ex.name,
        muscleGroup: ex.muscleGroupName,
        equipment: ex.equipment,
        imagePath: ex.imagePath,
        sets: ex.defaultSets,
        reps: ex.defaultReps,
        weightKg: ex.defaultWeightKg,
        restSeconds: ex.restSeconds,
      );

  // ---------------------------------------------------------------- state

  int get currentIndex => _currentIndex;
  ActiveExercise? get current =>
      exercises.isEmpty ? null : exercises[_currentIndex];
  bool get isPaused => _runningSince == null;
  bool get isFinished => _finished;
  bool get isCancelled => _cancelled;
  bool get canUndo => _undo.isNotEmpty;
  int get totalSets => exercises.fold(0, (n, e) => n + e.sets.length);
  int get completedSets => exercises.fold(0, (n, e) => n + e.completedSets);
  double get progress => totalSets == 0 ? 0 : completedSets / totalSets;

  int elapsedSeconds([DateTime? now]) {
    final n = now ?? AppClock.now();
    final extra = _runningSince == null
        ? 0
        : n.difference(_runningSince!).inSeconds.clamp(0, 1 << 30);
    return _accumulated + extra;
  }

  /// Local calendar date the session belongs to: the day it was started, so a
  /// workout that crosses midnight is still logged on the start day.
  String get sessionDate => AppClock.dateKey(startedAt);

  // ----------------------------------------------------------- navigation

  void goTo(int index) {
    if (exercises.isEmpty) return;
    final i = index.clamp(0, exercises.length - 1);
    if (i == _currentIndex) return;
    _currentIndex = i;
    _changed(trackUndo: false);
  }

  void next() => goTo(_currentIndex + 1);
  void previous() => goTo(_currentIndex - 1);

  // ---------------------------------------------------------------- timer

  void pause() {
    if (_runningSince == null || _finished) return;
    _accumulated = elapsedSeconds();
    _runningSince = null;
    _changed(trackUndo: false);
  }

  void resume() {
    if (_runningSince != null || _finished) return;
    _runningSince = AppClock.now();
    _changed(trackUndo: false);
  }

  /// Persist a heartbeat so a killed app can restore an accurate elapsed time.
  void heartbeat() {
    if (_finished || _cancelled) return;
    _changed(trackUndo: false, notify: false);
  }

  // ----------------------------------------------------------------- sets

  /// Returns true when the set became completed (caller may start rest timer).
  bool toggleSet(int exerciseIndex, int setIndex) {
    final s = exercises[exerciseIndex].sets[setIndex];
    _pushUndo();
    s.isCompleted = !s.isCompleted;
    s.completedAt = s.isCompleted ? AppClock.now().toIso8601String() : null;
    _changed(trackUndo: false);
    return s.isCompleted;
  }

  void updateSet(
    int exerciseIndex,
    int setIndex, {
    double? weight,
    int? reps,
    int? durationSeconds,
    double? distanceKm,
  }) {
    final s = exercises[exerciseIndex].sets[setIndex];
    // Typing in one field is one undo step, not one per keystroke.
    final key = '$exerciseIndex:$setIndex';
    final now = AppClock.now();
    final coalesce =
        _editKey == key &&
        _editAt != null &&
        now.difference(_editAt!).inSeconds < 3;
    if (!coalesce) _pushUndo();
    _editKey = key;
    _editAt = now;
    if (weight != null) s.weight = weight < 0 ? 0 : weight;
    if (reps != null) s.reps = reps < 0 ? 0 : reps;
    if (durationSeconds != null) s.durationSeconds = durationSeconds;
    if (distanceKm != null) s.distanceKm = distanceKm;
    _changed(trackUndo: false);
  }

  void addSet(int exerciseIndex) {
    final e = exercises[exerciseIndex];
    _pushUndo();
    e.sets.add(e.newSetFromLast());
    _changed(trackUndo: false);
  }

  /// Removes the last set of the exercise (never the only one).
  bool removeLastSet(int exerciseIndex) {
    final e = exercises[exerciseIndex];
    if (e.sets.length <= 1) return false;
    _pushUndo();
    e.sets.removeLast();
    _changed(trackUndo: false);
    return true;
  }

  /// Adds an exercise to the live workout (unplanned work / rest-day workout).
  int addExercise(ActiveExercise ex) {
    _pushUndo();
    exercises.add(ex);
    _currentIndex = exercises.length - 1;
    _changed(trackUndo: false);
    return _currentIndex;
  }

  bool hasExercise(int exerciseId) =>
      exercises.any((e) => e.exerciseId == exerciseId);

  void undo() {
    if (_undo.isEmpty) return;
    final snapshot = _undo.removeLast();
    revision++;
    _editKey = null;
    exercises
      ..clear()
      ..addAll(snapshot);
    if (_currentIndex >= exercises.length) {
      _currentIndex = exercises.isEmpty ? 0 : exercises.length - 1;
    }
    _changed(trackUndo: false);
  }

  void _pushUndo() {
    _editKey = null;
    _undo.add([for (final e in exercises) e.copy()]);
    if (_undo.length > _maxUndo) _undo.removeAt(0);
  }

  // ---------------------------------------------------------- persistence

  Map<String, dynamic> toJson() => {
    'v': 1,
    'ref': clientRef,
    'planId': planId,
    'planDate': planDate,
    'primary': primaryMuscle,
    'secondary': secondaryMuscle,
    'unplanned': isUnplanned,
    'startedAt': startedAt.toIso8601String(),
    'acc': _accumulated,
    'since': _runningSince?.toIso8601String(),
    'last': _lastActiveAt.toIso8601String(),
    'index': _currentIndex,
    'exercises': exercises.map((e) => e.toJson()).toList(),
  };

  void _changed({required bool trackUndo, bool notify = true}) {
    _lastActiveAt = AppClock.now();
    _persist();
    if (notify) notifyListeners();
  }

  /// Serialised so concurrent mutations cannot write out of order.
  void _persist() {
    if (_finished || _cancelled) return;
    final json = jsonEncode(toJson());
    _persistQueue = _persistQueue.then((_) async {
      if (_finished || _cancelled) return;
      try {
        await store.save(clientRef, json, startedAt.toIso8601String());
        lastPersistError = null;
      } catch (e) {
        lastPersistError = e;
      }
    });
  }

  /// Completes when all queued writes are done (used by tests and finish).
  Future<void> flush() => _persistQueue;

  /// Persist the very first snapshot so a freshly started workout is
  /// recoverable even before the first tap.
  Future<void> start() async {
    AccessGuard.ensureWritable();
    _persist();
    await flush();
  }

  /// Restores a persisted workout. It always comes back **paused** at the last
  /// moment the app was known to be active, so time spent while the app was
  /// dead is never counted as training time.
  static Future<ActiveWorkoutController?> recover(
    ActiveSessionStore store,
  ) async {
    final raw = await store.load();
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final since = j['since'] == null
          ? null
          : DateTime.parse(j['since'] as String);
      final last = DateTime.parse(j['last'] as String);
      var acc = j['acc'] as int? ?? 0;
      if (since != null && last.isAfter(since)) {
        acc += last.difference(since).inSeconds;
      }
      final list = ((j['exercises'] as List?) ?? const [])
          .map(
            (e) => ActiveExercise.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
      final idx = (j['index'] as int? ?? 0).clamp(
        0,
        list.isEmpty ? 0 : list.length - 1,
      );
      return ActiveWorkoutController(
        store: store,
        exercises: list,
        planId: j['planId'] as int?,
        planDate: j['planDate'] as String?,
        primaryMuscle: j['primary'] as String? ?? 'General',
        secondaryMuscle: j['secondary'] as String?,
        isUnplanned: j['unplanned'] as bool? ?? false,
        clientRef: j['ref'] as String?,
        startedAt: DateTime.parse(j['startedAt'] as String),
        accumulatedSeconds: acc,
        runningSince: null,
        currentIndex: idx,
        lastActiveAt: last,
      );
    } catch (_) {
      // Corrupt snapshot: never crash the app, drop it.
      await store.clear();
      return null;
    }
  }

  static Future<ActiveWorkoutSummary?> peekSummary(
    ActiveSessionStore store,
  ) async {
    final c = await recover(store);
    if (c == null) return null;
    final parts = <String>[
      if (c.primaryMuscle != 'General') c.primaryMuscle,
      if (c.secondaryMuscle != null) c.secondaryMuscle!,
    ];
    return ActiveWorkoutSummary(
      title: parts.isEmpty
          ? (c.exercises.isNotEmpty ? c.exercises.first.name : 'Workout')
          : parts.join(' & '),
      completedSets: c.completedSets,
      totalSets: c.totalSets,
      startedAt: c.startedAt,
    );
  }

  // ------------------------------------------------------------- complete

  WorkoutSession buildSession() {
    final ended = AppClock.now();
    return WorkoutSession(
      clientRef: clientRef,
      planId: planId,
      date: sessionDate,
      startTime: _hhmm(startedAt),
      endTime: _hhmm(ended),
      durationSeconds: elapsedSeconds(ended),
      primaryMuscle: primaryMuscle,
      secondaryMuscle: secondaryMuscle,
      notes: 'Completed $completedSets of $totalSets sets.',
      sets: [
        for (final e in exercises)
          for (final s in e.sets)
            WorkoutSetRecord(
              sessionId: 0,
              exerciseId: e.exerciseId,
              exerciseName: e.name,
              setNumber: s.setNumber,
              // Cardio keeps minutes in `reps`; real time/distance are stored
              // in their own columns so stats never multiply km by minutes.
              reps: e.isCardio
                  ? ((s.durationSeconds ?? s.reps * 60) / 60).round()
                  : s.reps,
              weightKg: e.isCardio ? 0 : s.weight,
              isCompleted: s.isCompleted,
              completedAt: s.completedAt,
              durationSeconds: e.isCardio ? s.durationSeconds : null,
              distanceKm: e.isCardio ? s.distanceKm : null,
            ),
      ],
    );
  }

  static String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// Saves the workout once. A second call (double tap, retry after a crash)
  /// returns the same session id without writing again.
  Future<int?> finish({SessionSaver? saver}) async {
    if (_finished || _finishing) return _savedId;
    _finishing = true;
    try {
      await flush();
      final id = await (saver ?? DatabaseService().createWorkoutSession)(
        buildSession(),
      );
      _savedId = id;
      _finished = true;
      await store.clear();
      notifyListeners();
      return id;
    } catch (e) {
      _finishing = false;
      rethrow;
    }
  }

  int? _savedId;

  Future<void> cancel() async {
    if (_finished) return;
    _cancelled = true;
    await flush();
    await store.clear();
    notifyListeners();
  }
}
