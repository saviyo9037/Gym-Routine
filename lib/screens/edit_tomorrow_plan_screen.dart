import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../models/muscle_group.dart';
import '../models/exercise.dart';
import '../models/workout_plan.dart';
import '../services/database_service.dart';
import '../widgets/voice_recorder_dialog.dart';
import '../widgets/exercise_image_widget.dart';

class EditTomorrowPlanScreen extends StatefulWidget {
  final WorkoutPlan? existingPlan;

  const EditTomorrowPlanScreen({super.key, this.existingPlan});

  @override
  State<EditTomorrowPlanScreen> createState() => _EditTomorrowPlanScreenState();
}

class _EditTomorrowPlanScreenState extends State<EditTomorrowPlanScreen> {
  final DatabaseService _dbService = DatabaseService();

  late String _dateStr;
  List<MuscleGroup> _allMuscleGroups = [];
  List<Exercise> _allExercises = [];
  bool _isLoading = true;

  MuscleGroup? _primaryMuscle;
  MuscleGroup? _secondaryMuscle;
  bool _isRestDay = false;

  final List<PlannedExercise> _plannedExercises = [];
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _trainerInstructionsController =
      TextEditingController();
  final TextEditingController _changeReasonController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _dateStr =
        widget.existingPlan?.date ??
        DateFormat('yyyy-MM-dd')
            .format(DateTime.now().add(const Duration(days: 1)));
    _changeReasonController.text = 'Trainer modification';
    _loadData();
  }

  Future<void> _loadData() async {
    final mgs = await _dbService.getAllMuscleGroups();
    final exs = await _dbService.getAllExercises();

    WorkoutPlan? currentPlan = widget.existingPlan;
    currentPlan ??= await _dbService.getPlanForDate(_dateStr);

    if (mounted) {
      setState(() {
        _allMuscleGroups = mgs;
        _allExercises = exs;

        if (currentPlan != null) {
          _isRestDay = currentPlan.isRestDay;
          _notesController.text = currentPlan.notes ?? '';
          _trainerInstructionsController.text =
              currentPlan.trainerInstructions ?? '';
          _plannedExercises.addAll(currentPlan.exercises);

          if (currentPlan.primaryMuscleId != null) {
            _primaryMuscle = mgs
                .where((m) => m.id == currentPlan!.primaryMuscleId)
                .firstOrNull;
          }
          if (currentPlan.secondaryMuscleId != null) {
            _secondaryMuscle = mgs
                .where((m) => m.id == currentPlan!.secondaryMuscleId)
                .firstOrNull;
          }
        } else {
          // Defaults
          if (mgs.length >= 2) {
            _primaryMuscle = mgs[1]; // Back
            _secondaryMuscle = mgs[3]; // Triceps
          }
        }
        _isLoading = false;
      });
    }
  }

  void _recordVoiceNote() {
    VoiceRecorderDialog.show(
      context,
      title: 'Trainer Voice Instructions',
      onSaved: (path, duration) {
        setState(() {
          final note = 'Voice Note recorded (${duration}s)';
          if (_trainerInstructionsController.text.isNotEmpty) {
            _trainerInstructionsController.text += '\n$note';
          } else {
            _trainerInstructionsController.text = note;
          }
        });
      },
    );
  }

  void _showAddExercisePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.9,
          builder: (_, controller) {
            return Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'CHOOSE EXERCISE TO ADD',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    controller: controller,
                    itemCount: _allExercises.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: AppColors.border, height: 1),
                    itemBuilder: (context, index) {
                      final ex = _allExercises[index];
                      return ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: ExerciseImageWidget(
                              imagePath: ex.imagePath,
                              personalPhotoPath: ex.personalPhotoPath,
                              exerciseName: ex.name,
                            ),
                          ),
                        ),
                        title: Text(
                          ex.name,
                          style: const TextStyle(
                            color: AppColors.textMain,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          '${ex.muscleGroupName} • ${ex.equipment}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          setState(() {
                            _plannedExercises.add(
                              PlannedExercise(
                                planId: widget.existingPlan?.id ?? 0,
                                exerciseId: ex.id ?? 0,
                                exerciseName: ex.name,
                                muscleGroupName: ex.muscleGroupName,
                                exerciseOrder: _plannedExercises.length,
                                targetSets: ex.defaultSets,
                                targetReps: ex.defaultReps,
                                targetWeightKg: ex.defaultWeightKg,
                                restSeconds: ex.restSeconds,
                                imagePath: ex.imagePath,
                                exercise: ex,
                              ),
                            );
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _saveRevisedPlan() async {
    final revised = WorkoutPlan(
      id: widget.existingPlan?.id,
      date: _dateStr,
      primaryMuscleId: _isRestDay ? null : _primaryMuscle?.id,
      primaryMuscleName: _isRestDay ? null : _primaryMuscle?.name,
      secondaryMuscleId: _isRestDay ? null : _secondaryMuscle?.id,
      secondaryMuscleName: _isRestDay ? null : _secondaryMuscle?.name,
      notes: _notesController.text.trim(),
      trainerInstructions: _trainerInstructionsController.text.trim(),
      isRestDay: _isRestDay,
      exercises: _plannedExercises,
    );

    final reason = _changeReasonController.text.trim().isNotEmpty
        ? _changeReasonController.text.trim()
        : 'Trainer revision';

    final muscleSummary = _isRestDay
        ? 'Rest Day'
        : '${_primaryMuscle?.name ?? "General"} & ${_secondaryMuscle?.name ?? "None"}';

    final changeDesc =
        'Updated plan to: $muscleSummary with ${_plannedExercises.length} exercises.';

    await _dbService.updateTomorrowPlanWithLog(
      revised,
      changeDescription: changeDesc,
      reason: reason,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tomorrow\'s plan updated & change logged!'),
          backgroundColor: AppColors.successDark,
        ),
      );
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Tomorrow')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    DateTime? parsedDate;
    try {
      parsedDate = DateTime.parse(_dateStr);
    } catch (_) {}
    final formattedDate = parsedDate != null
        ? DateFormat('EEEE, MMM d').format(parsedDate)
        : _dateStr;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TRAINER PLAN EDITOR',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
            Text(
              formattedDate,
              style: const TextStyle(color: AppColors.textMain, fontSize: 15),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton(
              onPressed: _saveRevisedPlan,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black,
              ),
              child: const Text(
                'Save Plan',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Rest Day toggle card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.cardSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Scheduled Rest Day',
                  style: TextStyle(
                    color: AppColors.textMain,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: const Text(
                  'Allow muscle recovery without target exercises',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                value: _isRestDay,
                activeThumbColor: AppColors.primary,
                onChanged: (val) => setState(() => _isRestDay = val),
              ),
            ),
            const SizedBox(height: 18),

            if (!_isRestDay) ...[
              // Two Muscle Groups Selectors
              const Text(
                'TARGET MUSCLE GROUPS (SELECT TWO)',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  // Primary Muscle
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: AppColors.cardSurface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<MuscleGroup>(
                          value: _primaryMuscle,
                          hint: const Text(
                            'Muscle 1',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                          isExpanded: true,
                          dropdownColor: AppColors.surfaceElevated,
                          items: _allMuscleGroups.map((mg) {
                            return DropdownMenuItem<MuscleGroup>(
                              value: mg,
                              child: Text(
                                mg.name,
                                style: const TextStyle(
                                  color: AppColors.textMain,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) =>
                              setState(() => _primaryMuscle = val),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Secondary Muscle
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: AppColors.cardSurface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<MuscleGroup>(
                          value: _secondaryMuscle,
                          hint: const Text(
                            'Muscle 2 (Optional)',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                          isExpanded: true,
                          dropdownColor: AppColors.surfaceElevated,
                          items: _allMuscleGroups.map((mg) {
                            return DropdownMenuItem<MuscleGroup>(
                              value: mg,
                              child: Text(
                                mg.name,
                                style: const TextStyle(
                                  color: AppColors.textMain,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) =>
                              setState(() => _secondaryMuscle = val),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Planned Exercises list
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'PLANNED EXERCISES (${_plannedExercises.length})',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _showAddExercisePicker,
                    icon: const Icon(
                      Icons.add,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    label: const Text(
                      'Add Exercise',
                      style: TextStyle(color: AppColors.primary, fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              if (_plannedExercises.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Center(
                    child: Text(
                      'No exercises added yet. Tap "+ Add Exercise" to choose.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _plannedExercises.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, idx) {
                    final pe = _plannedExercises[idx];
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.cardSurface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.15,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '${idx + 1}',
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  pe.exerciseName,
                                  style: const TextStyle(
                                    color: AppColors.textMain,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: AppColors.error,
                                  size: 20,
                                ),
                                onPressed: () {
                                  setState(
                                    () => _plannedExercises.removeAt(idx),
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  initialValue: '${pe.targetSets}',
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Sets',
                                    suffixText: 'sets',
                                  ),
                                  onChanged: (val) {
                                    final s =
                                        int.tryParse(val) ?? pe.targetSets;
                                    _plannedExercises[idx] = pe.copyWith(
                                      targetSets: s,
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  initialValue: '${pe.targetReps}',
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Reps',
                                    suffixText: 'reps',
                                  ),
                                  onChanged: (val) {
                                    final r =
                                        int.tryParse(val) ?? pe.targetReps;
                                    _plannedExercises[idx] = pe.copyWith(
                                      targetReps: r,
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  initialValue: '${pe.targetWeightKg}',
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    labelText: 'Weight',
                                    suffixText: 'kg',
                                  ),
                                  onChanged: (val) {
                                    final w =
                                        double.tryParse(val) ??
                                        pe.targetWeightKg;
                                    _plannedExercises[idx] = pe.copyWith(
                                      targetWeightKg: w,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],

            const SizedBox(height: 24),
            // Trainer Instructions & Voice Note
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'TRAINER INSTRUCTIONS & VOICE MEMOS',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                TextButton.icon(
                  onPressed: _recordVoiceNote,
                  icon: const Icon(
                    Icons.mic,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  label: const Text(
                    'Record Voice',
                    style: TextStyle(color: AppColors.primary, fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _trainerInstructionsController,
              maxLines: 3,
              style: const TextStyle(color: AppColors.textMain, fontSize: 14),
              decoration: const InputDecoration(
                hintText:
                    'Record coach tips, cadence, technique adjustments...',
              ),
            ),

            const SizedBox(height: 20),
            // Reason for change (for audit log)
            const Text(
              'REASON FOR REVISION (STORED IN AUDIT LOG)',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _changeReasonController,
              style: const TextStyle(color: AppColors.textMain, fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'e.g. Trainer adjusted volume, focus on eccentric bicep tempo...',
              ),
            ),
            const SizedBox(height: 36),
          ],
        ),
      ),
    );
  }
}
