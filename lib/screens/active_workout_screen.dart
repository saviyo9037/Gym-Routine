import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../models/exercise.dart';
import '../models/workout_plan.dart';
import '../models/workout_session.dart';
import '../services/database_service.dart';
import '../services/exercise_terminology_service.dart';
import '../widgets/exercise_demonstration_player.dart';
import '../widgets/rest_timer_sheet.dart';
import '../widgets/voice_recorder_dialog.dart';
import '../widgets/media_attachment_section.dart';
import 'workout_plan_screen.dart';

class ActiveWorkoutScreen extends StatefulWidget {
  final WorkoutPlan? plan;
  final Exercise? singleExercise;

  const ActiveWorkoutScreen({super.key, this.plan, this.singleExercise});

  @override
  State<ActiveWorkoutScreen> createState() => _ActiveWorkoutScreenState();
}

class _ActiveWorkoutExerciseItem {
  final int exerciseId;
  final String exerciseName;
  final String muscleGroup;
  final String? imagePath;
  final int targetSets;
  final int targetReps;
  final double targetWeightKg;
  final int restSeconds;
  final List<_ActiveSetData> sets;
  final bool isCardio;

  _ActiveWorkoutExerciseItem({
    required this.exerciseId,
    required this.exerciseName,
    required this.muscleGroup,
    this.imagePath,
    required this.targetSets,
    required this.targetReps,
    required this.targetWeightKg,
    required this.restSeconds,
    required this.sets,
    this.isCardio = false,
  });
}

class _ActiveSetData {
  final int setNumber;
  double weight;
  int reps;
  bool isCompleted;

  _ActiveSetData({
    required this.setNumber,
    required this.weight,
    required this.reps,
  }) : isCompleted = false;
}

class _ActiveWorkoutScreenState extends State<ActiveWorkoutScreen> {
  final DatabaseService _dbService = DatabaseService();
  final ScrollController _horizontalScrollController = ScrollController();

  final List<_ActiveWorkoutExerciseItem> _items = [];
  int _currentExerciseIndex = 0;
  WorkoutPlan? _loadedPlan;
  bool _isLoadingPlan = true;
  bool _isRestDay = false;

  // Workout timer
  int _workoutDurationSeconds = 0;
  Timer? _workoutTimer;
  late DateTime _startDateTime;

  @override
  void initState() {
    super.initState();
    _startDateTime = DateTime.now();
    _initWorkoutData();
    _workoutTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _workoutDurationSeconds++);
    });
  }

  Future<void> _initWorkoutData() async {
    _loadedPlan = widget.plan;
    if (_loadedPlan == null && widget.singleExercise == null) {
      final today = await _dbService.getTodayPlan();
      if (!mounted) return;
      _loadedPlan = today;
    }

    _isRestDay = _loadedPlan?.isRestDay ?? false;
    _items.clear();

    final plan = _loadedPlan;
    if (plan != null && !_isRestDay && plan.exercises.isNotEmpty) {
      for (final pe in plan.exercises) {
        final isCardio = _checkIfCardio(
          pe.muscleGroupName,
          pe.exercise?.equipment ?? '',
          pe.exerciseName,
        );
        final sets = List.generate(
          pe.targetSets,
          (i) => _ActiveSetData(
            setNumber: i + 1,
            weight: pe.targetWeightKg,
            reps: pe.targetReps,
          ),
        );
        _items.add(
          _ActiveWorkoutExerciseItem(
            exerciseId: pe.exerciseId,
            exerciseName: pe.exerciseName,
            muscleGroup: pe.muscleGroupName,
            imagePath: pe.imagePath,
            targetSets: pe.targetSets,
            targetReps: pe.targetReps,
            targetWeightKg: pe.targetWeightKg,
            restSeconds: pe.restSeconds,
            sets: sets,
            isCardio: isCardio,
          ),
        );
      }
    } else if (widget.singleExercise != null) {
      final ex = widget.singleExercise!;
      final isCardio = _checkIfCardio(
        ex.muscleGroupName,
        ex.equipment,
        ex.name,
      );
      final sets = List.generate(
        ex.defaultSets,
        (i) => _ActiveSetData(
          setNumber: i + 1,
          weight: ex.defaultWeightKg,
          reps: ex.defaultReps,
        ),
      );
      _items.add(
        _ActiveWorkoutExerciseItem(
          exerciseId: ex.id ?? 1,
          exerciseName: ex.name,
          muscleGroup: ex.muscleGroupName,
          imagePath: ex.imagePath,
          targetSets: ex.defaultSets,
          targetReps: ex.defaultReps,
          targetWeightKg: ex.defaultWeightKg,
          restSeconds: ex.restSeconds,
          sets: sets,
          isCardio: isCardio,
        ),
      );
    }

    if (mounted) {
      setState(() {
        _isLoadingPlan = false;
      });
    }
  }

  bool _checkIfCardio(String muscle, String equip, String name) {
    final m = muscle.toLowerCase();
    final e = equip.toLowerCase();
    final n = name.toLowerCase();
    return m.contains('cardio') ||
        e.contains('treadmill') ||
        e.contains('bike') ||
        e.contains('elliptical') ||
        e.contains('rowing') ||
        e.contains('stair') ||
        e.contains('jump rope') ||
        n.contains('treadmill') ||
        n.contains('cycling') ||
        n.contains('elliptical') ||
        n.contains('rowing machine') ||
        n.contains('stair climber') ||
        n.contains('jump rope') ||
        n.contains('jumping jacks') ||
        n.contains('high knees') ||
        n.contains('outdoor run') ||
        n.contains('outdoor walk');
  }

  void _scrollToCurrentExercise(int index) {
    if (!_horizontalScrollController.hasClients) return;
    const itemApproxWidth = 150.0;
    final targetOffset = (index * itemApproxWidth) - 40;
    _horizontalScrollController.animateTo(
      targetOffset.clamp(
        0.0,
        _horizontalScrollController.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _selectExercise(int index) {
    if (index >= 0 && index < _items.length) {
      setState(() => _currentExerciseIndex = index);
      _scrollToCurrentExercise(index);
    }
  }

  @override
  void dispose() {
    _workoutTimer?.cancel();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  void _onSetToggled(int setIdx) {
    if (_items.isEmpty) return;
    final currentEx = _items[_currentExerciseIndex];
    final targetSet = currentEx.sets[setIdx];

    setState(() {
      targetSet.isCompleted = !targetSet.isCompleted;
    });

    if (targetSet.isCompleted) {
      RestTimerSheet.show(context, seconds: currentEx.restSeconds);
    }
  }

  void _addSetToCurrentExercise() {
    if (_items.isEmpty) return;
    final currentEx = _items[_currentExerciseIndex];
    setState(() {
      final lastSet = currentEx.sets.isNotEmpty ? currentEx.sets.last : null;
      final newSetNumber = currentEx.sets.length + 1;
      currentEx.sets.add(
        _ActiveSetData(
          setNumber: newSetNumber,
          weight: lastSet?.weight ?? currentEx.targetWeightKg,
          reps: lastSet?.reps ?? currentEx.targetReps,
        ),
      );
    });
  }

  int get _totalSetsCount =>
      _items.fold(0, (sum, item) => sum + item.sets.length);
  int get _completedSetsCount => _items.fold(
    0,
    (sum, item) => sum + item.sets.where((s) => s.isCompleted).length,
  );

  Future<void> _finishWorkout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Complete Workout?',
          style: TextStyle(
            color: AppColors.textMain,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Completed $_completedSetsCount of $_totalSetsCount sets across ${_items.length} exercises.\nSave to history?',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Keep Training',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text(
              'Save & Finish',
              style: TextStyle(color: Colors.black),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final dateStr = DateFormat('yyyy-MM-dd').format(_startDateTime);
      final startTimeStr = DateFormat('HH:mm').format(_startDateTime);
      final endTimeStr = DateFormat('HH:mm').format(DateTime.now());

      final primaryMuscle =
          _loadedPlan?.primaryMuscleName ??
          (widget.singleExercise?.muscleGroupName ?? 'General');
      final secondaryMuscle = _loadedPlan?.secondaryMuscleName;

      final session = WorkoutSession(
        planId: _loadedPlan?.id,
        date: dateStr,
        startTime: startTimeStr,
        endTime: endTimeStr,
        durationSeconds: _workoutDurationSeconds,
        primaryMuscle: primaryMuscle,
        secondaryMuscle: secondaryMuscle,
        notes:
            'Session recorded in RepTrack. Completed $_completedSetsCount sets.',
        sets: [
          for (final item in _items)
            for (final s in item.sets)
              WorkoutSetRecord(
                sessionId: 0,
                exerciseId: item.exerciseId,
                exerciseName: item.exerciseName,
                setNumber: s.setNumber,
                reps: s.reps,
                weightKg: s.weight,
                isCompleted: s.isCompleted,
              ),
        ],
      );

      await _dbService.createWorkoutSession(session);

      if (_loadedPlan != null) {
        await _dbService.saveOrUpdatePlan(
          _loadedPlan!.copyWith(isCompleted: true),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Workout completed and saved to history!'),
            backgroundColor: AppColors.successDark,
          ),
        );
        Navigator.pop(context, true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingPlan) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    if (_isRestDay) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Active Workout')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
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
                  'Scheduled Rest & Recovery Day',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textMain,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Today is dedicated to muscle repair, hydration, and central nervous system recovery. Take a relaxing walk or focus on gentle stretching.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const WorkoutPlanScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.tune_rounded, color: Colors.black),
                  label: const Text('View / Edit Weekly Split'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_items.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Active Workout')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.fitness_center_rounded,
                  color: AppColors.textMuted,
                  size: 48,
                ),
                const SizedBox(height: 16),
                const Text(
                  'No exercises loaded for this session.',
                  style: TextStyle(
                    color: AppColors.textMain,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Customize today\'s workout plan to add exercises.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const WorkoutPlanScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.add, color: Colors.black),
                  label: const Text('Configure Today\'s Plan'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final currentEx = _items[_currentExerciseIndex];
    final durationMins = (_workoutDurationSeconds ~/ 60).toString().padLeft(
      2,
      '0',
    );
    final durationSecs = (_workoutDurationSeconds % 60).toString().padLeft(
      2,
      '0',
    );
    final progress = _totalSetsCount > 0
        ? _completedSetsCount / _totalSetsCount
        : 0.0;

    final displayName = ExerciseTerminologyService.instance.getDisplayName(
      currentEx.exerciseName,
      id: currentEx.exerciseId,
    );
    final friendlyMuscle = ExerciseTerminologyService.instance
        .getFriendlyMuscleName(currentEx.muscleGroup);

    final isCardio = currentEx.isCardio;
    final targetSubtitle = isCardio
        ? 'Target: ${currentEx.targetSets} ${currentEx.targetSets == 1 ? "round" : "rounds"} × ${currentEx.targetReps} mins • $friendlyMuscle'
        : 'Target: ${currentEx.targetSets} sets × ${currentEx.targetReps} reps • $friendlyMuscle';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ACTIVE WORKOUT',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
            Text(
              '$durationMins:$durationSecs elapsed',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.timer_outlined, color: AppColors.primary),
            tooltip: 'Open Rest Timer',
            onPressed: () =>
                RestTimerSheet.show(context, seconds: currentEx.restSeconds),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton(
              onPressed: _finishWorkout,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
              ),
              child: const Text(
                'Finish',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Workout overall progress bar
          LinearProgressIndicator(
            value: progress,
            backgroundColor: AppColors.surfaceElevated,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
            minHeight: 4,
          ),

          // Exercise Navigation Pills Header with Counter
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'EXERCISE ${_currentExerciseIndex + 1} OF ${_items.length}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
                Text(
                  '$_completedSetsCount / $_totalSetsCount sets done',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          // Horizontal Exercise Pills Selector (Smooth scrollable, reaches all exercises)
          Container(
            height: 48,
            margin: const EdgeInsets.only(bottom: 8),
            child: ListView.builder(
              controller: _horizontalScrollController,
              physics: const BouncingScrollPhysics(),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _items.length,
              itemBuilder: (context, i) {
                final isSelected = i == _currentExerciseIndex;
                final allDone = _items[i].sets.every((s) => s.isCompleted);
                final itemDisplayName = ExerciseTerminologyService.instance
                    .getDisplayName(
                      _items[i].exerciseName,
                      id: _items[i].exerciseId,
                    );

                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (allDone)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(
                              Icons.check,
                              size: 14,
                              color: AppColors.success,
                            ),
                          ),
                        Text(itemDisplayName),
                      ],
                    ),
                    selected: isSelected,
                    selectedColor: AppColors.primary,
                    backgroundColor: AppColors.cardSurface,
                    labelStyle: TextStyle(
                      color: isSelected
                          ? Colors.black
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                    side: BorderSide(
                      color: isSelected ? AppColors.primary : AppColors.border,
                    ),
                    onSelected: (val) {
                      if (val) _selectExercise(i);
                    },
                  ),
                );
              },
            ),
          ),

          // Exercise Highlight Card with Video Player
          Expanded(
            child: SingleChildScrollView(
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
                        // Exercise Demonstration Video Player (Replaces static image)
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(15),
                          ),
                          child: ExerciseDemonstrationPlayer(
                            key: ValueKey(
                              'active_demo_${currentEx.exerciseId}_${currentEx.exerciseName}',
                            ),
                            exerciseId: currentEx.exerciseId,
                            exerciseName: currentEx.exerciseName,
                            fallbackImagePath: currentEx.imagePath,
                            height: 210,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(15),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                      targetSubtitle,
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton.filledTonal(
                                onPressed: () {
                                  VoiceRecorderDialog.show(
                                    context,
                                    title: 'Trainer Cue - $displayName',
                                    onSaved: (_, __) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('Trainer note logged'),
                                        ),
                                      );
                                    },
                                  );
                                },
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

                  // Sets Table Header (Dynamically adapted for Cardio vs Strength)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 44,
                          child: Text(
                            isCardio ? 'ROUND' : 'SET',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            isCardio ? 'DIST / SPEED' : 'WEIGHT (KG)',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            isCardio ? 'TIME (MINS)' : 'REPS',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(
                          width: 50,
                          child: Text(
                            'DONE',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Sets / Rounds List
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: currentEx.sets.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, setIdx) {
                      final setData = currentEx.sets[setIdx];
                      final weightSuffix = isCardio ? 'km' : 'kg';
                      final repsSuffix = isCardio ? 'min' : 'reps';

                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: setData.isCompleted
                              ? AppColors.primary.withValues(alpha: 0.1)
                              : AppColors.cardSurface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: setData.isCompleted
                                ? AppColors.primary.withValues(alpha: 0.4)
                                : AppColors.border,
                          ),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 40,
                              child: Text(
                                '${setData.setNumber}',
                                style: TextStyle(
                                  color: setData.isCompleted
                                      ? AppColors.primary
                                      : AppColors.textMain,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            // Weight / Distance Input
                            Expanded(
                              child: Container(
                                height: 40,
                                margin: const EdgeInsets.only(right: 12),
                                child: TextFormField(
                                  key: ValueKey(
                                    'ex_${currentEx.exerciseId}_set_${setData.setNumber}_w',
                                  ),
                                  initialValue: setData.weight.toString(),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  style: const TextStyle(
                                    color: AppColors.textMain,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  decoration: InputDecoration(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    fillColor: AppColors.surfaceElevated,
                                    suffixText: weightSuffix,
                                    suffixStyle: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 11,
                                    ),
                                  ),
                                  onChanged: (val) {
                                    setData.weight =
                                        double.tryParse(val) ?? setData.weight;
                                  },
                                ),
                              ),
                            ),
                            // Reps / Duration Input
                            Expanded(
                              child: Container(
                                height: 40,
                                margin: const EdgeInsets.only(right: 12),
                                child: TextFormField(
                                  key: ValueKey(
                                    'ex_${currentEx.exerciseId}_set_${setData.setNumber}_r',
                                  ),
                                  initialValue: setData.reps.toString(),
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(
                                    color: AppColors.textMain,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  decoration: InputDecoration(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    fillColor: AppColors.surfaceElevated,
                                    suffixText: repsSuffix,
                                    suffixStyle: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 11,
                                    ),
                                  ),
                                  onChanged: (val) {
                                    setData.reps =
                                        int.tryParse(val) ?? setData.reps;
                                  },
                                ),
                              ),
                            ),
                            // Done Checkbox button
                            IconButton(
                              icon: Icon(
                                setData.isCompleted
                                    ? Icons.check_circle_rounded
                                    : Icons.radio_button_unchecked_rounded,
                                color: setData.isCompleted
                                    ? AppColors.primary
                                    : AppColors.textMuted,
                                size: 28,
                              ),
                              onPressed: () => _onSetToggled(setIdx),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),

                  // Add Set Button
                  OutlinedButton.icon(
                    onPressed: _addSetToCurrentExercise,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(isCardio ? '+ Add Round' : '+ Add Set'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.border),
                      minimumSize: const Size.fromHeight(42),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Form Media & Trainer Cues for this exercise
                  MediaAttachmentSection(
                    key: ValueKey('active_ex_${currentEx.exerciseId}'),
                    entityType: 'exercise',
                    entityId: currentEx.exerciseId,
                    entityTitle: '$displayName Live Cue',
                    sectionTitle: 'FORM MEDIA & TRAINER CUES',
                  ),

                  const SizedBox(height: 24),
                  // Bottom Previous / Next Exercise navigation
                  Row(
                    children: [
                      if (_currentExerciseIndex > 0)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                _selectExercise(_currentExerciseIndex - 1),
                            icon: const Icon(
                              Icons.arrow_back_rounded,
                              size: 16,
                            ),
                            label: const Text('Previous'),
                          ),
                        ),
                      if (_currentExerciseIndex > 0 &&
                          _currentExerciseIndex < _items.length - 1)
                        const SizedBox(width: 12),
                      if (_currentExerciseIndex < _items.length - 1)
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () =>
                                _selectExercise(_currentExerciseIndex + 1),
                            icon: const Icon(
                              Icons.arrow_forward_rounded,
                              size: 16,
                              color: Colors.black,
                            ),
                            label: const Text('Next Exercise'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 36),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
