import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../models/exercise.dart';
import '../models/workout_plan.dart';
import '../models/workout_session.dart';
import '../services/database_service.dart';
import '../widgets/exercise_image_widget.dart';
import '../widgets/rest_timer_sheet.dart';
import '../widgets/voice_recorder_dialog.dart';
import '../widgets/media_attachment_section.dart';

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

  final List<_ActiveWorkoutExerciseItem> _items = [];
  int _currentExerciseIndex = 0;

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

  void _initWorkoutData() {
    if (widget.plan != null && widget.plan!.exercises.isNotEmpty) {
      for (final pe in widget.plan!.exercises) {
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
          ),
        );
      }
    } else if (widget.singleExercise != null) {
      final ex = widget.singleExercise!;
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
        ),
      );
    }
  }

  @override
  void dispose() {
    _workoutTimer?.cancel();
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
      // Prompt rest timer
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
          widget.plan?.primaryMuscleName ??
          (widget.singleExercise?.muscleGroupName ?? 'Biceps');
      final secondaryMuscle = widget.plan?.secondaryMuscleName;

      final session = WorkoutSession(
        planId: widget.plan?.id,
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
    if (_items.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Active Workout')),
        body: const Center(
          child: Text('No exercises loaded for this session.'),
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
          // Progress bar
          LinearProgressIndicator(
            value: progress,
            backgroundColor: AppColors.surfaceElevated,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
            minHeight: 4,
          ),

          // Exercise Navigation Pills
          Container(
            height: 48,
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _items.length,
              itemBuilder: (context, i) {
                final isSelected = i == _currentExerciseIndex;
                final allDone = _items[i].sets.every((s) => s.isCompleted);
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
                        Text(_items[i].exerciseName),
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
                      if (val) setState(() => _currentExerciseIndex = i);
                    },
                  ),
                );
              },
            ),
          ),

          // Exercise Highlight Card
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
                        // Exercise Hero Image
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(15),
                          ),
                          child: ExerciseImageWidget(
                            imagePath: currentEx.imagePath,
                            exerciseName: currentEx.exerciseName,
                            height: 160,
                            width: double.infinity,
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
                                      currentEx.exerciseName,
                                      style: const TextStyle(
                                        color: AppColors.textMain,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Target: ${currentEx.targetSets} sets × ${currentEx.targetReps} reps • ${currentEx.muscleGroup}',
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
                                    title:
                                        'Trainer Cue - ${currentEx.exerciseName}',
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

                  // Sets Table Header
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 44,
                          child: Text(
                            'SET',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'WEIGHT (KG)',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'REPS',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        SizedBox(
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

                  // Sets List
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: currentEx.sets.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, setIdx) {
                      final setData = currentEx.sets[setIdx];
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
                            // Weight Input
                            Expanded(
                              child: Container(
                                height: 40,
                                margin: const EdgeInsets.only(right: 12),
                                child: TextFormField(
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
                                    suffixText: 'kg',
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
                            // Reps Input
                            Expanded(
                              child: Container(
                                height: 40,
                                margin: const EdgeInsets.only(right: 12),
                                child: TextFormField(
                                  initialValue: setData.reps.toString(),
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(
                                    color: AppColors.textMain,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  decoration: const InputDecoration(
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    fillColor: AppColors.surfaceElevated,
                                    suffixText: 'reps',
                                    suffixStyle: TextStyle(
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
                    label: const Text('+ Add Set'),
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
                    entityTitle: '${currentEx.exerciseName} Live Cue',
                    sectionTitle: 'FORM MEDIA & TRAINER CUES',
                  ),

                  const SizedBox(height: 24),
                  // Bottom Next Exercise navigation
                  Row(
                    children: [
                      if (_currentExerciseIndex > 0)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                setState(() => _currentExerciseIndex--),
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
                                setState(() => _currentExerciseIndex++),
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
