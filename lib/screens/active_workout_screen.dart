import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/theme.dart';
import '../models/exercise.dart';
import '../models/workout_plan.dart';
import '../services/active_workout_controller.dart';
import '../services/database_service.dart';
import '../services/exercise_terminology_service.dart';
import '../widgets/exercise_demonstration_player.dart';
import '../widgets/exercise_picker_sheet.dart';
import '../widgets/media_attachment_section.dart';
import '../widgets/rest_timer_sheet.dart';
import '../widgets/voice_recorder_dialog.dart';
import 'workout_plan_screen.dart';

/// Live workout. Shows only the exercises of the plan it was started from,
/// persists every change (recoverable after the app is killed) and saves the
/// session exactly once.
class ActiveWorkoutScreen extends StatefulWidget {
  /// Plan to run. When null (and no [singleExercise]) today's plan is used.
  final WorkoutPlan? plan;
  final Exercise? singleExercise;

  /// Restore the workout that was in progress when the app was closed.
  final bool resume;

  /// Start an empty workout the user fills in (e.g. on a rest day).
  final bool startUnplanned;

  const ActiveWorkoutScreen({
    super.key,
    this.plan,
    this.singleExercise,
    this.resume = false,
    this.startUnplanned = false,
  });

  @override
  State<ActiveWorkoutScreen> createState() => _ActiveWorkoutScreenState();
}

enum _Leave { keep, discard }

class _ActiveWorkoutScreenState extends State<ActiveWorkoutScreen>
    with WidgetsBindingObserver {
  final DatabaseService _db = DatabaseService();
  final SqliteActiveSessionStore _store = SqliteActiveSessionStore();
  final ScrollController _pills = ScrollController();

  ActiveWorkoutController? _c;
  WorkoutPlan? _plan;
  bool _loading = true;
  bool _isRestDay = false;
  bool _finishing = false;
  String? _error;
  bool _keepAwake = false;
  Timer? _tick;
  int _tickCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _c?.removeListener(_onChanged);
    _c?.heartbeat();
    _c?.dispose();
    _pills.dispose();
    _setWakelock(false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _c?.heartbeat();
    }
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _setWakelock(bool on) async {
    try {
      await WakelockPlus.toggle(enable: on);
    } catch (_) {
      // Not supported on this device/test host: ignore.
    }
  }

  Future<void> _init() async {
    try {
      final existing = await ActiveWorkoutController.recover(_store);

      if (widget.resume) {
        if (existing == null) {
          if (!mounted) return;
          setState(() {
            _loading = false;
            _error = 'No workout in progress.';
          });
          return;
        }
        await _attach(existing, fresh: false);
        return;
      }

      if (existing != null) {
        final choice = await _askAboutExisting(existing);
        if (!mounted) return;
        if (choice == null) {
          Navigator.pop(context, false);
          return;
        }
        if (choice == 'resume') {
          await _attach(existing, fresh: false);
          return;
        }
        await _store.clear(); // user chose to discard the old one
      }

      await _startNew();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not start the workout.';
      });
    }
  }

  Future<String?> _askAboutExisting(ActiveWorkoutController old) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Workout in progress'),
        content: Text(
          'You already have a workout in progress '
          '(${old.completedSets}/${old.totalSets} sets done). '
          'Resume it, or discard it and start a new one?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: const Text(
              'Discard & start new',
              style: TextStyle(color: AppColors.error),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 'resume'),
            child: const Text('Resume'),
          ),
        ],
      ),
    );
  }

  Future<void> _startNew() async {
    ActiveWorkoutController c;
    if (widget.singleExercise != null) {
      c = ActiveWorkoutController.single(widget.singleExercise!, _store);
    } else if (widget.startUnplanned) {
      c = ActiveWorkoutController.unplanned(_store);
    } else {
      _plan = widget.plan ?? await _db.getTodayPlan();
      if (!mounted) return;
      if (_plan?.isRestDay ?? false) {
        setState(() {
          _isRestDay = true;
          _loading = false;
        });
        return;
      }
      if (_plan == null || _plan!.exercises.isEmpty) {
        setState(() => _loading = false); // empty-plan state
        return;
      }
      c = ActiveWorkoutController.fromPlan(_plan!, _store);
    }
    await _attach(c, fresh: true);
  }

  Future<void> _attach(ActiveWorkoutController c, {required bool fresh}) async {
    if (fresh) await c.start();
    final setting = await _db.getSetting(
      'keep_screen_on',
      defaultValue: 'false',
    );
    _keepAwake = setting == 'true';
    if (_keepAwake) _setWakelock(true);
    c.addListener(_onChanged);
    _c = c;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _tickCount++;
      if (_tickCount % 15 == 0) _c?.heartbeat();
      if (!(c.isPaused)) setState(() {});
    });
    if (!mounted) return;
    setState(() => _loading = false);
    if (c.exercises.isEmpty && widget.startUnplanned) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _addExercise());
    }
  }

  // --------------------------------------------------------------- actions

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _toggleKeepAwake() async {
    final next = !_keepAwake;
    setState(() => _keepAwake = next);
    await _db.setSetting('keep_screen_on', next ? 'true' : 'false');
    await _setWakelock(next);
  }

  Future<void> _addExercise() async {
    final c = _c;
    if (c == null) return;
    final ex = await ExercisePickerSheet.show(
      context,
      title: 'Add to workout',
      alreadyAddedIds: {for (final e in c.exercises) e.exerciseId},
    );
    if (ex == null || !mounted) return;
    if (c.hasExercise(ex.id ?? -1)) {
      final again = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          title: const Text('Already in this workout'),
          content: Text('Add "${ex.name}" again?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add again'),
            ),
          ],
        ),
      );
      if (again != true) return;
    }
    c.addExercise(ActiveWorkoutController.specFromExercise(ex));
    _scrollPills(c.currentIndex);
  }

  void _scrollPills(int index) {
    if (!_pills.hasClients) return;
    final target = (index * 150.0) - 40;
    _pills.animateTo(
      target.clamp(0.0, _pills.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish() async {
    final c = _c;
    if (c == null || _finishing || c.isFinished) return;
    final noneDone = c.completedSets == 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Finish workout?'),
        content: Text(
          noneDone
              ? 'You have not completed any sets. Saving will record an '
                    'empty session.'
              : 'Completed ${c.completedSets} of ${c.totalSets} sets across '
                    '${c.exercises.length} exercises.\nSave to history?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep training'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save & finish'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _finishing = true);
    try {
      c.pause();
      await c.finish();
      if (!mounted) return;
      _toast('Workout saved to history');
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _finishing = false);
      _toast('Could not save the workout. Nothing was lost — try again.');
    }
  }

  Future<void> _discard() async {
    final c = _c;
    if (c == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Discard workout?'),
        content: const Text('Everything logged in this session will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Discard',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await c.cancel();
    if (!mounted) return;
    Navigator.pop(context, false);
  }

  Future<void> _onBack() async {
    final c = _c;
    final nav = Navigator.of(context);
    if (c == null || c.isFinished || c.isCancelled || c.exercises.isEmpty) {
      nav.pop(false);
      return;
    }
    final choice = await showDialog<_Leave>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Leave workout?'),
        content: const Text(
          'Your progress is saved. You can resume it from the Home screen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep training'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _Leave.discard),
            child: const Text(
              'Discard',
              style: TextStyle(color: AppColors.error),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, _Leave.keep),
            child: const Text('Save & leave'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == _Leave.discard) {
      await c.cancel();
    } else {
      c.pause();
      await c.flush();
    }
    if (mounted) nav.pop(false);
  }

  // ----------------------------------------------------------------- build

  String _clock(int secs) {
    final h = secs ~/ 3600;
    final m = ((secs % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (secs % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }
    if (_error != null) return _messageScaffold(Icons.error_outline, _error!);
    if (_isRestDay) return _restDayScaffold();
    final c = _c;
    if (c == null) return _emptyPlanScaffold();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: _workoutScaffold(c),
    );
  }

  Widget _messageScaffold(IconData icon, String text) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Active Workout')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppColors.textMuted, size: 48),
              const SizedBox(height: 12),
              Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMain),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _restDayScaffold() {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Active Workout')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.bedtime_rounded,
                  color: AppColors.primary,
                  size: 40,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Today is a rest day',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textMain,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Recovery is part of training. If you still want to move, you '
                'can start an unplanned workout and pick the exercises '
                'yourself.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const ActiveWorkoutScreen(startUnplanned: true),
                  ),
                ),
                icon: const Icon(Icons.play_arrow_rounded, color: Colors.black),
                label: const Text('Start an unplanned workout'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const WorkoutPlanScreen()),
                ),
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('View / edit my schedule'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyPlanScaffold() {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Active Workout')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.fitness_center_rounded,
                color: AppColors.textMuted,
                size: 48,
              ),
              const SizedBox(height: 16),
              const Text(
                'No exercises planned for this workout',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textMain,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Add exercises to today\'s plan, or start an unplanned workout.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const WorkoutPlanScreen()),
                ),
                icon: const Icon(Icons.add, color: Colors.black),
                label: const Text('Configure today\'s plan'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const ActiveWorkoutScreen(startUnplanned: true),
                  ),
                ),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Start an unplanned workout'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _workoutScaffold(ActiveWorkoutController c) {
    final cur = c.current;
    final term = ExerciseTerminologyService.instance;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: _onBack,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              c.isPaused ? 'PAUSED' : 'ACTIVE WORKOUT',
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
            Semantics(
              liveRegion: false,
              label: '${_clock(c.elapsedSeconds())} elapsed',
              child: Text(
                '${_clock(c.elapsedSeconds())} elapsed',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Undo last change',
            icon: const Icon(Icons.undo_rounded),
            color: AppColors.primary,
            disabledColor: AppColors.textMuted,
            onPressed: c.canUndo ? c.undo : null,
          ),
          IconButton(
            tooltip: c.isPaused ? 'Resume workout' : 'Pause workout',
            icon: Icon(
              c.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              color: AppColors.primary,
            ),
            onPressed: c.isPaused ? c.resume : c.pause,
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            color: AppColors.surfaceElevated,
            onSelected: (v) {
              switch (v) {
                case 'rest':
                  RestTimerSheet.show(context, seconds: cur?.restSeconds ?? 90);
                case 'add':
                  _addExercise();
                case 'awake':
                  _toggleKeepAwake();
                case 'discard':
                  _discard();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'rest', child: Text('Rest timer')),
              const PopupMenuItem(value: 'add', child: Text('Add exercise')),
              CheckedPopupMenuItem(
                value: 'awake',
                checked: _keepAwake,
                child: const Text('Keep screen on'),
              ),
              const PopupMenuItem(
                value: 'discard',
                child: Text('Discard workout'),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Tooltip(
              message: 'Finish workout',
              child: ElevatedButton(
                onPressed: _finishing ? null : _finish,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: MediaQuery.textScalerOf(context).scale(1) > 1.3
                    ? const Icon(Icons.check_rounded)
                    : const Text(
                        'Finish',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ),
        ],
      ),
      body: cur == null
          ? _emptyWorkoutBody()
          : Column(
              children: [
                LinearProgressIndicator(
                  value: c.progress,
                  backgroundColor: AppColors.surfaceElevated,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.primary,
                  ),
                  minHeight: 4,
                ),
                _counterRow(c),
                _pillsRow(c, term),
                Expanded(child: _exerciseBody(c, cur, term)),
              ],
            ),
    );
  }

  Widget _emptyWorkoutBody() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Your workout is empty',
              style: TextStyle(
                color: AppColors.textMain,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _addExercise,
              icon: const Icon(Icons.add, color: Colors.black),
              label: const Text('Add an exercise'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _counterRow(ActiveWorkoutController c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              'EXERCISE ${c.currentIndex + 1} OF ${c.exercises.length}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '${c.completedSets} / ${c.totalSets} sets done',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pillsRow(ActiveWorkoutController c, ExerciseTerminologyService term) {
    return Container(
      height: 48,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView.builder(
        controller: _pills,
        physics: const BouncingScrollPhysics(),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: c.exercises.length,
        itemBuilder: (context, i) {
          final e = c.exercises[i];
          final selected = i == c.currentIndex;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (e.isDone)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(
                        Icons.check,
                        size: 14,
                        color: AppColors.success,
                      ),
                    ),
                  Text(term.getDisplayName(e.name, id: e.exerciseId)),
                ],
              ),
              selected: selected,
              selectedColor: AppColors.primary,
              backgroundColor: AppColors.cardSurface,
              labelStyle: TextStyle(
                color: selected ? Colors.black : AppColors.textSecondary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
              side: BorderSide(
                color: selected ? AppColors.primary : AppColors.border,
              ),
              onSelected: (_) {
                c.goTo(i);
                _scrollPills(i);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _exerciseBody(
    ActiveWorkoutController c,
    ActiveExercise cur,
    ExerciseTerminologyService term,
  ) {
    final displayName = term.getDisplayName(cur.name, id: cur.exerciseId);
    final muscle = term.getFriendlyMuscleName(cur.muscleGroup);
    final target = cur.isCardio
        ? 'Target: ${cur.sets.length} ${cur.sets.length == 1 ? 'round' : 'rounds'}'
              '${cur.targetDurationSeconds != null ? ' × ${(cur.targetDurationSeconds! / 60).round()} min' : ''}'
              '${cur.targetDistanceKm != null ? ' • ${cur.targetDistanceKm} km' : ''} • $muscle'
        : 'Target: ${cur.sets.length} sets × ${cur.targetReps} reps • $muscle';
    final ei = c.currentIndex;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(15),
                  ),
                  child: ExerciseDemonstrationPlayer(
                    key: ValueKey('active_demo_${cur.exerciseId}_${cur.name}'),
                    exerciseId: cur.exerciseId,
                    exerciseName: cur.name,
                    fallbackImagePath: cur.imagePath,
                    height: 210,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(15),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style: const TextStyle(
                                color: AppColors.textMain,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              target,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                            if (cur.notes != null && cur.notes!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  cur.notes!,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Record a voice cue',
                        onPressed: () => VoiceRecorderDialog.show(
                          context,
                          title: 'Trainer Cue - $displayName',
                          onSaved: (_, __) => _toast('Trainer note logged'),
                        ),
                        icon: const Icon(
                          Icons.mic_rounded,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.surfaceElevated,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _setsHeader(cur.isCardio),
          for (var si = 0; si < cur.sets.length; si++) ...[
            _setRow(c, cur, ei, si),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => c.addSet(ei),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(cur.isCardio ? 'Add round' : 'Add set'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.border),
                    minimumSize: const Size.fromHeight(42),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: cur.sets.length > 1
                    ? () {
                        c.removeLastSet(ei);
                        _toast(
                          'Removed last ${cur.isCardio ? 'round' : 'set'}',
                        );
                      }
                    : null,
                icon: const Icon(Icons.remove_rounded, size: 18),
                label: const Text('Remove'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 42),
                  side: const BorderSide(color: AppColors.border),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          MediaAttachmentSection(
            key: ValueKey('active_ex_${cur.exerciseId}'),
            entityType: 'exercise',
            entityId: cur.exerciseId,
            entityTitle: '$displayName Live Cue',
            sectionTitle: 'FORM MEDIA & TRAINER CUES',
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              if (ei > 0)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      c.previous();
                      _scrollPills(c.currentIndex);
                    },
                    icon: const Icon(Icons.arrow_back_rounded, size: 16),
                    label: const Text('Previous'),
                  ),
                ),
              if (ei > 0 && ei < c.exercises.length - 1)
                const SizedBox(width: 12),
              if (ei < c.exercises.length - 1)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      c.next();
                      _scrollPills(c.currentIndex);
                    },
                    icon: const Icon(
                      Icons.arrow_forward_rounded,
                      size: 16,
                      color: Colors.black,
                    ),
                    label: const Text('Next exercise'),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 36),
        ],
      ),
    );
  }

  Widget _setsHeader(bool cardio) {
    Widget h(String t, {double? w}) => w != null
        ? SizedBox(
            width: w,
            child: Text(t, style: _headStyle),
          )
        : Expanded(child: Text(t, style: _headStyle));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          h(cardio ? 'ROUND' : 'SET', w: 44),
          h(cardio ? 'DISTANCE (KM)' : 'WEIGHT (KG)'),
          h(cardio ? 'TIME (MIN)' : 'REPS'),
          const SizedBox(
            width: 50,
            child: Text('DONE', textAlign: TextAlign.center, style: _headStyle),
          ),
        ],
      ),
    );
  }

  static const _headStyle = TextStyle(
    color: AppColors.textSecondary,
    fontSize: 11,
    fontWeight: FontWeight.w700,
  );

  Widget _setRow(
    ActiveWorkoutController c,
    ActiveExercise cur,
    int ei,
    int si,
  ) {
    final s = cur.sets[si];
    String fmt(double v) =>
        v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
    final firstInitial = cur.isCardio
        ? (s.distanceKm == null ? '' : fmt(s.distanceKm!))
        : fmt(s.weight);
    final secondInitial = cur.isCardio
        ? (s.durationSeconds == null ? '' : fmt(s.durationSeconds! / 60))
        : '${s.reps}';
    final base = 'ex${ei}_set${si}_rev${c.revision}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: s.isCompleted
            ? AppColors.primary.withValues(alpha: 0.1)
            : AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: s.isCompleted
              ? AppColors.primary.withValues(alpha: 0.4)
              : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              '${s.setNumber}',
              style: TextStyle(
                color: s.isCompleted ? AppColors.primary : AppColors.textMain,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: _numberField(
              key: ValueKey('${base}_a'),
              initial: firstInitial,
              suffix: cur.isCardio ? 'km' : 'kg',
              decimal: true,
              label: cur.isCardio
                  ? 'Distance in kilometres'
                  : 'Weight in kilograms',
              onValue: (v) => cur.isCardio
                  ? c.updateSet(ei, si, distanceKm: v)
                  : c.updateSet(ei, si, weight: v),
            ),
          ),
          Expanded(
            child: _numberField(
              key: ValueKey('${base}_b'),
              initial: secondInitial,
              suffix: cur.isCardio ? 'min' : 'reps',
              decimal: cur.isCardio,
              label: cur.isCardio ? 'Time in minutes' : 'Repetitions',
              onValue: (v) => cur.isCardio
                  ? c.updateSet(ei, si, durationSeconds: (v * 60).round())
                  : c.updateSet(ei, si, reps: v.round()),
            ),
          ),
          IconButton(
            tooltip: s.isCompleted
                ? 'Mark ${cur.isCardio ? 'round' : 'set'} ${s.setNumber} not done'
                : 'Mark ${cur.isCardio ? 'round' : 'set'} ${s.setNumber} done',
            icon: Icon(
              s.isCompleted
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: s.isCompleted ? AppColors.primary : AppColors.textMuted,
              size: 28,
            ),
            onPressed: () {
              FocusScope.of(context).unfocus();
              final done = c.toggleSet(ei, si);
              if (done && si < cur.sets.length - 1) {
                RestTimerSheet.show(context, seconds: cur.restSeconds);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _numberField({
    required Key key,
    required String initial,
    required String suffix,
    required bool decimal,
    required String label,
    required void Function(double) onValue,
  }) {
    return Container(
      height: 44,
      margin: const EdgeInsets.only(right: 12),
      child: TextFormField(
        key: key,
        initialValue: initial,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        style: const TextStyle(
          color: AppColors.textMain,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
        decoration: InputDecoration(
          semanticCounterText: label,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 4,
          ),
          fillColor: AppColors.surfaceElevated,
          suffixText: suffix,
          suffixStyle: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
          ),
        ),
        onChanged: (raw) {
          final v = double.tryParse(raw.trim().replaceAll(',', '.'));
          if (v != null && v >= 0 && v < 100000) onValue(v);
        },
      ),
    );
  }
}
