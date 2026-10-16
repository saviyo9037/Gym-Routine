import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../models/workout_plan.dart';
import '../models/workout_session.dart';
import '../services/database_service.dart';
import '../widgets/voice_recorder_dialog.dart';
import 'active_workout_screen.dart';
import 'edit_tomorrow_plan_screen.dart';
import 'add_edit_exercise_screen.dart';
import 'routine_management_screen.dart';
import '../models/routine_today_item.dart';
import '../services/routine_service.dart';

class HomeScreen extends StatefulWidget {
  final Function(int tabIndex)? onNavigateToTab;

  const HomeScreen({super.key, this.onNavigateToTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DatabaseService _dbService = DatabaseService();
  final RoutineService _routineService = RoutineService();

  WorkoutPlan? _todayPlan;
  WorkoutPlan? _tomorrowPlan;
  List<WorkoutPlan> _weeklyPlans = [];
  List<WorkoutSession> _recentSessions = [];
  RoutineTodayItem? _nextRoutineItem;
  int _todayRoutinesCount = 0;
  int _todayCompletedRoutinesCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    final today = await _dbService.getTodayPlan();
    final tomorrow = await _dbService.getTomorrowPlan();
    final week = await _dbService.getWeeklyPlans(DateTime.now());
    final recent = await _dbService.getRecentSessions(5);
    final todayRoutineItems = await _routineService.getTodayRoutineItems();
    final nextRoutine = await _routineService.getNextUpcomingRoutine();
    final completedRoutines = todayRoutineItems
        .where((i) => i.isCompleted)
        .length;

    if (mounted) {
      setState(() {
        _todayPlan = today;
        _tomorrowPlan = tomorrow;
        _weeklyPlans = week;
        _recentSessions = recent;
        _nextRoutineItem = nextRoutine;
        _todayRoutinesCount = todayRoutineItems.length;
        _todayCompletedRoutinesCount = completedRoutines;
        _isLoading = false;
      });
    }
  }

  void _recordTrainerVoiceMemo() {
    VoiceRecorderDialog.show(
      context,
      title: 'Trainer Quick Note',
      onSaved: (path, duration) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Trainer voice memo recorded and saved privately'),
            backgroundColor: AppColors.successDark,
          ),
        );
      },
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

    final todayDate = DateTime.now();
    final formattedDate = DateFormat('EEEE, MMMM d').format(todayDate);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          backgroundColor: AppColors.surfaceElevated,
          onRefresh: _loadDashboardData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Header: Brand & Date
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'REPTRACK',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          formattedDate,
                          style: const TextStyle(
                            color: AppColors.textMain,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.calendar_month_rounded,
                            color: AppColors.primary,
                            size: 22,
                          ),
                          tooltip: 'My Routine',
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.surfaceElevated,
                            side: const BorderSide(
                              color: AppColors.primary,
                              width: 1.2,
                            ),
                          ),
                          onPressed: () {
                            if (widget.onNavigateToTab != null) {
                              widget.onNavigateToTab!(1);
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const RoutineManagementScreen(),
                                ),
                              ).then((_) => _loadDashboardData());
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(
                            Icons.mic_rounded,
                            color: AppColors.primary,
                            size: 22,
                          ),
                          tooltip: 'Record Trainer Note',
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.surfaceElevated,
                            side: const BorderSide(color: AppColors.border),
                          ),
                          onPressed: _recordTrainerVoiceMemo,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // PROMINENT ROUTINE MANAGEMENT BUTTON (Near top of Home screen)
                _buildRoutineHeaderButton(),
                const SizedBox(height: 18),

                // Weekly 7-Day Completion Tracker
                _buildWeeklyTracker(),
                const SizedBox(height: 22),

                // TODAY'S WORKOUT CARD
                _buildTodayWorkoutCard(),
                const SizedBox(height: 20),

                // TOMORROW'S WORKOUT PREVIEW (Critical Master Feature)
                _buildTomorrowPreviewCard(),
                const SizedBox(height: 24),

                // QUICK ACTIONS BAR
                _buildQuickActions(),
                const SizedBox(height: 24),

                // RECENTLY COMPLETED SESSIONS
                _buildRecentSessions(),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWeeklyTracker() {
    final now = DateTime.now();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
              const Text(
                'WEEKLY SCHEDULE',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
              Text(
                '${_weeklyPlans.where((p) => p.isCompleted).length}/7 Completed',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (i) {
              DateTime? planDate;
              if (i < _weeklyPlans.length) {
                try {
                  planDate = DateTime.parse(_weeklyPlans[i].date);
                } catch (_) {}
              }
              final dayName = planDate != null
                  ? DateFormat('E').format(planDate).substring(0, 1)
                  : '';
              final dayNum = planDate != null ? '${planDate.day}' : '';
              final isToday =
                  planDate != null &&
                  planDate.year == now.year &&
                  planDate.month == now.month &&
                  planDate.day == now.day;
              final isDone =
                  i < _weeklyPlans.length && _weeklyPlans[i].isCompleted;

              return Column(
                children: [
                  Text(
                    dayName,
                    style: TextStyle(
                      color: isToday ? AppColors.primary : AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isToday
                          ? AppColors.primary
                          : (isDone
                                ? AppColors.surfaceHighlight
                                : AppColors.surfaceElevated),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isToday ? AppColors.primary : AppColors.border,
                        width: isToday ? 2 : 1,
                      ),
                    ),
                    child: Center(
                      child: isDone
                          ? const Icon(
                              Icons.check,
                              size: 16,
                              color: AppColors.success,
                            )
                          : Text(
                              dayNum,
                              style: TextStyle(
                                color: isToday
                                    ? Colors.black
                                    : AppColors.textMain,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildTodayWorkoutCard() {
    final plan = _todayPlan;
    final hasPlan =
        plan != null && !plan.isRestDay && plan.exercises.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.6),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: const BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.flash_on_rounded,
                      color: AppColors.primary,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'TODAY\'S TRAINING',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: plan?.isCompleted == true
                        ? AppColors.success.withValues(alpha: 0.2)
                        : (plan?.isRestDay == true
                              ? AppColors.surfaceElevated
                              : AppColors.primary.withValues(alpha: 0.15)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    plan?.isCompleted == true
                        ? 'COMPLETED'
                        : (plan?.isRestDay == true
                              ? 'REST DAY'
                              : 'READY TO START'),
                    style: TextStyle(
                      color: plan?.isCompleted == true
                          ? AppColors.success
                          : (plan?.isRestDay == true
                                ? AppColors.textSecondary
                                : AppColors.primary),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(18),
            child: hasPlan
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Muscle Groups Pill
                      Row(
                        children: [
                          _buildMusclePill(plan.primaryMuscleName ?? 'Biceps'),
                          if (plan.secondaryMuscleName != null &&
                              plan.secondaryMuscleName!.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            const Text(
                              '+',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildMusclePill(plan.secondaryMuscleName!),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Exercise count & volume preview
                      Text(
                        '${plan.exercises.length} Exercises Planned',
                        style: const TextStyle(
                          color: AppColors.textMain,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      if (plan.notes != null && plan.notes!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          plan.notes!,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 14),

                      // Exercise list chips (Shows all planned exercises without 3-item cap)
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: plan.exercises.map((pe) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Text(
                              '${pe.exerciseName} (${pe.targetSets}×${pe.targetReps})',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),

                      // Big Prominent START WORKOUT Button
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final res = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ActiveWorkoutScreen(plan: plan),
                              ),
                            );
                            if (res == true) _loadDashboardData();
                          },
                          icon: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.black,
                            size: 24,
                          ),
                          label: const Text(
                            'START WORKOUT',
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              letterSpacing: 0.5,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : (plan != null && plan.isRestDay
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.15,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.bedtime_rounded,
                                    color: AppColors.primary,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  'Scheduled Rest & Recovery Day',
                                  style: TextStyle(
                                    color: AppColors.textMain,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Today is dedicated to recovery, muscle growth, and mobility. Hydrate, eat nutrient-dense meals, and recharge.',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed: () => widget.onNavigateToTab?.call(2),
                              icon: const Icon(
                                Icons.calendar_month_rounded,
                                size: 16,
                              ),
                              label: const Text('View 6-Day Weekly Schedule'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                side: const BorderSide(color: AppColors.border),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'No workout scheduled for today yet.',
                              style: TextStyle(
                                color: AppColors.textMain,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Select muscle groups and customize your exercise program.',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () => widget.onNavigateToTab?.call(2),
                              icon: const Icon(
                                Icons.add_rounded,
                                color: Colors.black,
                              ),
                              label: const Text('Create Today\'s Workout'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                              ),
                            ),
                          ],
                        )),
          ),
        ],
      ),
    );
  }

  Widget _buildTomorrowPreviewCard() {
    final tomorrow = _tomorrowPlan;
    final hasTomorrow =
        tomorrow != null &&
        !tomorrow.isRestDay &&
        tomorrow.exercises.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.upcoming_rounded,
                      color: AppColors.primary,
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'TOMORROW\'S PREVIEW',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () async {
                    final res = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            EditTomorrowPlanScreen(existingPlan: tomorrow),
                      ),
                    );
                    if (res == true) _loadDashboardData();
                  },
                  icon: const Icon(
                    Icons.edit_note_rounded,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  label: const Text(
                    'Edit Tomorrow',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            if (hasTomorrow) ...[
              Row(
                children: [
                  _buildMusclePill(tomorrow.primaryMuscleName ?? 'Back'),
                  if (tomorrow.secondaryMuscleName != null &&
                      tomorrow.secondaryMuscleName!.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    const Text(
                      '+',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildMusclePill(tomorrow.secondaryMuscleName!),
                  ],
                  const Spacer(),
                  Text(
                    '${tomorrow.exercises.length} Exercises',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Exercises list preview (Shows all exercises planned for tomorrow)
              Column(
                children: tomorrow.exercises.map((pe) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.arrow_right_rounded,
                          color: AppColors.primary,
                          size: 18,
                        ),
                        Expanded(
                          child: Text(
                            pe.exerciseName,
                            style: const TextStyle(
                              color: AppColors.textMain,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          '${pe.targetSets} sets × ${pe.targetReps} reps',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
              if (tomorrow.trainerInstructions != null &&
                  tomorrow.trainerInstructions!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.record_voice_over_rounded,
                        color: AppColors.primary,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tomorrow.trainerInstructions!,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ] else ...[
              Text(
                tomorrow?.isRestDay == true
                    ? 'Scheduled Rest & Recovery Day for tomorrow.'
                    : 'No workout scheduled for tomorrow yet. Tap "Edit Tomorrow" to configure.',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'QUICK ACTIONS',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildActionBtn(
                icon: Icons.schedule_rounded,
                label: 'My Routine',
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const RoutineManagementScreen(),
                    ),
                  );
                  _loadDashboardData();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildActionBtn(
                icon: Icons.add_rounded,
                label: 'Add Exercise',
                onTap: () async {
                  final res = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AddEditExerciseScreen(),
                    ),
                  );
                  if (res == true) _loadDashboardData();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildActionBtn(
                icon: Icons.edit_calendar_rounded,
                label: 'Weekly Plan',
                onTap: () => widget.onNavigateToTab?.call(
                  2,
                ), // Workout Plan tab (index 2)
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildActionBtn(
                icon: Icons.mic_none_rounded,
                label: 'Voice Note',
                onTap: _recordTrainerVoiceMemo,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textMain,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentSessions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'RECENT WORKOUTS',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
            if (_recentSessions.isNotEmpty)
              TextButton(
                onPressed: () =>
                    widget.onNavigateToTab?.call(4), // History tab (index 4)
                child: const Text(
                  'View All',
                  style: TextStyle(color: AppColors.primary, fontSize: 12),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_recentSessions.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: const Center(
              child: Text(
                'No completed workouts yet. Hit "START WORKOUT" above to log your first session!',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _recentSessions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final s = _recentSessions[index];
              final durationMins = (s.durationSeconds ~/ 60);

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
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.fitness_center_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${s.primaryMuscle}${s.secondaryMuscle != null ? " & ${s.secondaryMuscle}" : ""}',
                            style: const TextStyle(
                              color: AppColors.textMain,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${s.date} • ${s.sets.length} sets logged • ${durationMins}m duration',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.success,
                      size: 20,
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildMusclePill(String name) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
      ),
      child: Text(
        name.toUpperCase(),
        style: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w800,
          fontSize: 12,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  /// Prominent, responsive Routine button positioned near the top of the Home screen
  /// below the app header and above the workout dashboard.
  Widget _buildRoutineHeaderButton() {
    final nextItem = _nextRoutineItem;
    final hasRoutines = _todayRoutinesCount > 0;
    final allCompleted =
        hasRoutines && _todayCompletedRoutinesCount == _todayRoutinesCount;

    String headline;
    String subtitle;
    IconData iconData = Icons.schedule_rounded;
    Color accentColor = AppColors.primary;

    if (nextItem != null) {
      if (nextItem.isInProgress) {
        headline = 'Now: ${nextItem.routine.title}';
        subtitle = '${nextItem.routine.formattedTimeRange} • In Progress';
        iconData = Icons.play_circle_fill_rounded;
        accentColor = AppColors.primary;
      } else {
        headline = 'Next: ${nextItem.routine.title}';
        subtitle =
            'Starts at ${nextItem.routine.startTime} • ${nextItem.routine.formattedDuration}';
        iconData = Icons.alarm_on_rounded;
        accentColor = nextItem.routine.color;
      }
    } else if (allCompleted) {
      headline = 'All routines completed today!';
      subtitle =
          '$_todayCompletedRoutinesCount of $_todayRoutinesCount done • Great discipline';
      iconData = Icons.task_alt_rounded;
      accentColor = const Color(0xFF00B894);
    } else if (!hasRoutines) {
      headline = 'No routines scheduled today';
      subtitle = 'Tap to organize daily habits & activities';
      iconData = Icons.calendar_month_rounded;
      accentColor = AppColors.primary;
    } else {
      headline = 'My Daily Routine';
      subtitle =
          '$_todayCompletedRoutinesCount of $_todayRoutinesCount completed • Tap to view';
      iconData = Icons.schedule_rounded;
      accentColor = AppColors.primary;
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            if (widget.onNavigateToTab != null) {
              widget.onNavigateToTab!(1);
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const RoutineManagementScreen(),
                ),
              ).then((_) => _loadDashboardData());
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                // Icon block with electric tint
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Center(
                    child: Icon(iconData, color: accentColor, size: 24),
                  ),
                ),
                const SizedBox(width: 14),
                // Text details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: accentColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'MY ROUTINE',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                            ),
                          ),
                          if (hasRoutines) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceElevated,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '$_todayCompletedRoutinesCount/$_todayRoutinesCount Done',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        headline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textMain,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Forward navigation indicator
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: AppColors.primary,
                    size: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
