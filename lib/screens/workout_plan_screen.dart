import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../models/workout_plan.dart';
import '../models/muscle_group.dart';
import '../models/exercise.dart';
import '../models/plan_change_log.dart';
import '../services/database_service.dart';
import '../services/exercise_terminology_service.dart';
import '../widgets/change_log_dialog.dart';
import '../widgets/exercise_image_widget.dart';
import '../widgets/media_attachment_section.dart';
import 'active_workout_screen.dart';

class WorkoutPlanScreen extends StatefulWidget {
  const WorkoutPlanScreen({super.key});

  @override
  State<WorkoutPlanScreen> createState() => _WorkoutPlanScreenState();
}

class _WorkoutPlanScreenState extends State<WorkoutPlanScreen> {
  final DatabaseService _dbService = DatabaseService();

  late DateTime _selectedDate;
  List<WorkoutPlan> _weeklyPlans = [];
  WorkoutPlan? _currentPlan;
  List<MuscleGroup> _allMuscleGroups = [];
  List<Exercise> _allExercises = [];
  List<PlanChangeLog> _changeLogs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _loadData();
  }

  Future<void> _loadData() async {
    final mgs = await _dbService.getAllMuscleGroups();
    final exs = await _dbService.getAllExercises();
    final week = await _dbService.getWeeklyPlans(_selectedDate);
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    var plan = await _dbService.getPlanForDate(dateStr);
    if (plan == null) {
      await _dbService.saveOrUpdatePlan(
        WorkoutPlan(
          date: dateStr,
          isRestDay: (_selectedDate.weekday == DateTime.sunday),
          primaryMuscleName: 'Biceps',
        ),
      );
      plan = await _dbService.getPlanForDate(dateStr);
    }

    List<PlanChangeLog> logs = [];
    if (plan?.id != null) {
      logs = await _dbService.getLogsForPlan(plan!.id!);
    }

    if (mounted) {
      setState(() {
        _allMuscleGroups = mgs;
        _allExercises = exs;
        _weeklyPlans = week;
        _currentPlan = plan;
        _changeLogs = logs;
        _isLoading = false;
      });
    }
  }

  void _selectDate(DateTime dt) {
    setState(() {
      _selectedDate = dt;
      _isLoading = true;
    });
    _loadData();
  }

  Future<void> _addExerciseToPlan() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        String filterQuery = '';
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final filtered = filterQuery.isEmpty
                ? _allExercises
                : _allExercises.where((e) {
                    return ExerciseTerminologyService.instance.matchesSearch(
                      e,
                      filterQuery,
                    );
                  }).toList();

            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.75,
              maxChildSize: 0.95,
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
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: Text(
                        'SELECT EXERCISE FOR THIS PLAN',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: TextField(
                        style: const TextStyle(
                          color: AppColors.textMain,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText:
                              'Search by gym name, slang, RDL, butterfly...',
                          prefixIcon: const Icon(
                            Icons.search,
                            color: AppColors.primary,
                            size: 20,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: AppColors.border,
                            ),
                          ),
                        ),
                        onChanged: (val) {
                          setSheetState(() {
                            filterQuery = val;
                          });
                        },
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        controller: controller,
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            const Divider(color: AppColors.border, height: 1),
                        itemBuilder: (context, index) {
                          final ex = filtered[index];
                          final term = ExerciseTerminologyService.instance
                              .getTerminology(id: ex.id, name: ex.name);
                          final displayName =
                              term?.recommendedDisplayName.isNotEmpty == true
                              ? term!.recommendedDisplayName
                              : ex.name;
                          final primaryAlias =
                              term != null && term.aliases.isNotEmpty
                              ? term.aliases.firstWhere(
                                  (a) =>
                                      a.toLowerCase() !=
                                          displayName.toLowerCase() &&
                                      a.toLowerCase() != ex.name.toLowerCase(),
                                  orElse: () => term.aliases.first,
                                )
                              : '';
                          final friendlyMuscle = ExerciseTerminologyService
                              .instance
                              .getFriendlyMuscleName(ex.muscleGroupName);

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
                              displayName,
                              style: const TextStyle(
                                color: AppColors.textMain,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              primaryAlias.isNotEmpty &&
                                      primaryAlias.toLowerCase() !=
                                          displayName.toLowerCase()
                                  ? '$friendlyMuscle • ${ex.equipment} (Also: $primaryAlias)'
                                  : '$friendlyMuscle • ${ex.equipment} • ${ex.difficulty}',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11.5,
                              ),
                            ),
                            trailing: const Icon(
                              Icons.add_circle_outline,
                              color: AppColors.primary,
                              size: 20,
                            ),
                            onTap: () async {
                              Navigator.pop(ctx);
                              final dateStr = DateFormat('yyyy-MM-dd')
                                  .format(_selectedDate);
                              await _dbService.addExerciseToDatePlan(
                                dateStr,
                                ex,
                              );
                              _loadData();
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
      },
    );
  }

  Future<void> _savePlanChanges(WorkoutPlan updatedPlan) async {
    await _dbService.saveOrUpdatePlan(updatedPlan);
    _loadData();
  }

  void _showChangeMuscleGroupsDialog() {
    MuscleGroup? primary = _currentPlan?.primaryMuscleId != null
        ? _allMuscleGroups
              .where((m) => m.id == _currentPlan!.primaryMuscleId)
              .firstOrNull
        : (_allMuscleGroups.isNotEmpty ? _allMuscleGroups[0] : null);
    MuscleGroup? secondary = _currentPlan?.secondaryMuscleId != null
        ? _allMuscleGroups
              .where((m) => m.id == _currentPlan!.secondaryMuscleId)
              .firstOrNull
        : (_allMuscleGroups.length > 1 ? _allMuscleGroups[1] : null);
    bool isRest = _currentPlan?.isRestDay ?? false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.surfaceElevated,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                'Target Muscle Groups',
                style: TextStyle(
                  color: AppColors.textMain,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: const Text(
                      'Rest Day',
                      style: TextStyle(color: AppColors.textMain),
                    ),
                    value: isRest,
                    activeThumbColor: AppColors.primary,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) => setDialogState(() => isRest = val),
                  ),
                  if (!isRest) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<MuscleGroup>(
                      initialValue: primary,
                      decoration: const InputDecoration(
                        labelText: 'Primary Muscle',
                      ),
                      dropdownColor: AppColors.cardSurface,
                      items: _allMuscleGroups.map((mg) {
                        return DropdownMenuItem(
                          value: mg,
                          child: Text(mg.name),
                        );
                      }).toList(),
                      onChanged: (val) => setDialogState(() => primary = val),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<MuscleGroup>(
                      initialValue: secondary,
                      decoration: const InputDecoration(
                        labelText: 'Secondary Muscle (Optional)',
                      ),
                      dropdownColor: AppColors.cardSurface,
                      items: _allMuscleGroups.map((mg) {
                        return DropdownMenuItem(
                          value: mg,
                          child: Text(mg.name),
                        );
                      }).toList(),
                      onChanged: (val) => setDialogState(() => secondary = val),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final dateStr = DateFormat('yyyy-MM-dd')
                        .format(_selectedDate);
                    final newPlan = (_currentPlan ?? WorkoutPlan(date: dateStr))
                        .copyWith(
                          isRestDay: isRest,
                          primaryMuscleId: isRest ? null : primary?.id,
                          primaryMuscleName: isRest ? null : primary?.name,
                          secondaryMuscleId: isRest ? null : secondary?.id,
                          secondaryMuscleName: isRest ? null : secondary?.name,
                        );
                    await _savePlanChanges(newPlan);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                  child: const Text(
                    'Save',
                    style: TextStyle(color: Colors.black),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showSixDaySplitDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.calendar_view_week_rounded, color: AppColors.primary),
              SizedBox(width: 8),
              Text(
                '6-Day Training Split',
                style: TextStyle(
                  color: AppColors.textMain,
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Configurable 6-day training schedule + 1 rest day for hypertrophy and cardiovascular conditioning:',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 14),
                _buildSplitRow(
                  'Day 1 (Mon)',
                  'Chest + Triceps',
                  'Bench press, incline press & cable pushdowns',
                ),
                _buildSplitRow(
                  'Day 2 (Tue)',
                  'Back + Biceps',
                  'Lat pulldowns, rows & curls',
                ),
                _buildSplitRow(
                  'Day 3 (Wed)',
                  'Shoulders + Abs',
                  'Overhead presses, lateral raises & core circuits',
                ),
                _buildSplitRow(
                  'Day 4 (Thu)',
                  'Legs',
                  'Squats, RDLs, lunges & calf raises',
                ),
                _buildSplitRow(
                  'Day 5 (Fri)',
                  'Chest + Back',
                  'Upper body antagonist volume supersets',
                ),
                _buildSplitRow(
                  'Day 6 (Sat)',
                  'Arms + Cardio',
                  'Arm pump paired with running / skipping conditioning',
                ),
                _buildSplitRow(
                  'Day 7 (Sun)',
                  'Rest & Recovery',
                  'Complete muscular recovery & mobility',
                ),
                const SizedBox(height: 10),
                const Text(
                  '* Preserves your existing custom plans. You can freely customize exercises, sets/reps, and rest days for any date.',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11.5,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Close',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                setState(() => _isLoading = true);
                await _dbService.applySixDaySplitPreset(
                  _selectedDate,
                  overwriteExisting: false,
                );
                _loadData();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        '6-Day Split applied! Any previously customized days were preserved.',
                      ),
                      backgroundColor: AppColors.successDark,
                    ),
                  );
                }
              },
              icon: const Icon(
                Icons.check_rounded,
                color: Colors.black,
                size: 18,
              ),
              label: const Text(
                'Apply Split to Week',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSplitRow(String day, String muscles, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: Text(
              day,
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  muscles,
                  style: const TextStyle(
                    color: AppColors.textMain,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                Text(
                  desc,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    final headerDateStr = DateFormat('EEEE, MMMM d').format(_selectedDate);
    final isRest = _currentPlan?.isRestDay ?? false;
    final exercises = _currentPlan?.exercises ?? [];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('WORKOUT PLANNER'),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.calendar_view_week_rounded,
              color: AppColors.primary,
            ),
            tooltip: '6-Day Split Preset',
            onPressed: _showSixDaySplitDialog,
          ),
          if (_changeLogs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.history_rounded, color: AppColors.primary),
              tooltip: 'Trainer Revision History',
              onPressed: () => ChangeLogDialog.show(context, _changeLogs),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 7-Day Weekly Bar Header with 6-Day split action
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '7-DAY SCHEDULE (6-DAY SPLIT)',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                TextButton.icon(
                  onPressed: _showSixDaySplitDialog,
                  icon: const Icon(
                    Icons.auto_awesome_rounded,
                    size: 14,
                    color: AppColors.primary,
                  ),
                  label: const Text(
                    'Preset Split',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // 7-Day Weekly Bar
            _buildWeeklyBar(),
            const SizedBox(height: 20),

            // Date Header & Target Muscles Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.cardSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        headerDateStr.toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.tune_rounded,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        tooltip: 'Configure Muscle Groups',
                        onPressed: _showChangeMuscleGroupsDialog,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (isRest) ...[
                    const Row(
                      children: [
                        Icon(
                          Icons.bedtime_rounded,
                          color: AppColors.primary,
                          size: 24,
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Scheduled Rest & Recovery Day',
                          style: TextStyle(
                            color: AppColors.textMain,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    Row(
                      children: [
                        _buildMuscleTag(
                          _currentPlan?.primaryMuscleName ?? 'Biceps',
                        ),
                        if (_currentPlan?.secondaryMuscleName != null &&
                            _currentPlan!.secondaryMuscleName!.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          const Text(
                            '&',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildMuscleTag(_currentPlan!.secondaryMuscleName!),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 22),

            // Planned Exercises list
            if (!isRest) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'SCHEDULED EXERCISES (${exercises.length})',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _addExerciseToPlan,
                    icon: const Icon(
                      Icons.add_rounded,
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

              if (exercises.isEmpty)
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        const Icon(
                          Icons.fitness_center_rounded,
                          color: AppColors.textMuted,
                          size: 36,
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'No exercises added for this day.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 14),
                        ElevatedButton.icon(
                          onPressed: _addExerciseToPlan,
                          icon: const Icon(Icons.add, color: Colors.black),
                          label: const Text('Add Exercise'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: exercises.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final pe = exercises[index];
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.cardSurface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  pe.exerciseName,
                                  style: const TextStyle(
                                    color: AppColors.textMain,
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${pe.targetSets} sets × ${pe.targetReps} reps • ${pe.targetWeightKg} kg • Rest ${pe.restSeconds}s',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              color: AppColors.error,
                              size: 20,
                            ),
                            onPressed: () async {
                              final updatedList = List<PlannedExercise>.from(
                                exercises,
                              )..removeAt(index);
                              final updatedPlan = _currentPlan!.copyWith(
                                exercises: updatedList,
                              );
                              await _savePlanChanges(updatedPlan);
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),

              if (_currentPlan != null && _currentPlan!.id != null) ...[
                const SizedBox(height: 24),
                MediaAttachmentSection(
                  entityType: 'plan',
                  entityId: _currentPlan!.id!,
                  entityTitle: 'Plan: $headerDateStr',
                  sectionTitle: 'PLANNED WORKOUT MEDIA & NOTES',
                ),
              ],

              const SizedBox(height: 24),
              // Prominent Start Workout button
              if (exercises.isNotEmpty)
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final res = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ActiveWorkoutScreen(plan: _currentPlan),
                        ),
                      );
                      if (res == true) _loadData();
                    },
                    icon: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.black,
                    ),
                    label: const Text(
                      'Start This Workout',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                    ),
                  ),
                ),
            ],

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklyBar() {
    return SizedBox(
      height: 74,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _weeklyPlans.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final p = _weeklyPlans[i];
          DateTime? pDate;
          try {
            pDate = DateTime.parse(p.date);
          } catch (_) {}
          final dayName = pDate != null
              ? DateFormat('E').format(pDate).toUpperCase()
              : '';
          final dayNum = pDate != null ? '${pDate.day}' : '';
          final isSelected =
              pDate != null &&
              pDate.year == _selectedDate.year &&
              pDate.month == _selectedDate.month &&
              pDate.day == _selectedDate.day;

          return InkWell(
            onTap: () {
              if (pDate != null) _selectDate(pDate);
            },
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 58,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : AppColors.cardSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.border,
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    dayName,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.black
                          : AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    dayNum,
                    style: TextStyle(
                      color: isSelected ? Colors.black : AppColors.textMain,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMuscleTag(String name) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
      ),
      child: Text(
        name.toUpperCase(),
        style: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w800,
          fontSize: 13,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
