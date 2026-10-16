import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../models/routine.dart';
import '../models/routine_completion.dart';
import '../models/routine_today_item.dart';
import '../services/routine_service.dart';
import '../services/alarm_service.dart';
import '../services/database_service.dart';
import '../widgets/routine_detail_sheet.dart';
import 'add_edit_routine_screen.dart';
import 'alarm_settings_screen.dart';
import 'alarm_ringing_screen.dart';
import 'active_workout_screen.dart';
import 'workout_plan_screen.dart';

class RoutineManagementScreen extends StatefulWidget {
  final int initialTabIndex;
  final VoidCallback? onBackToHome;

  const RoutineManagementScreen({
    super.key,
    this.initialTabIndex = 0,
    this.onBackToHome,
  });

  @override
  State<RoutineManagementScreen> createState() =>
      _RoutineManagementScreenState();
}

class _RoutineManagementScreenState extends State<RoutineManagementScreen>
    with SingleTickerProviderStateMixin {
  final RoutineService _routineService = RoutineService();

  late TabController _tabController;

  bool _isLoading = true;
  List<RoutineTodayItem> _todayItems = [];
  List<Routine> _allRoutines = [];
  RoutineWeeklyStats? _weeklyStats;
  RoutineTodayItem? _nextMealItem;
  String? _suggestedDinnerTime;
  List<String> _overlapWarnings = [];

  // Weekly tab selected day (default today)
  late DateTime _selectedWeeklyDate;

  // Selected day items for Weekly tab
  List<RoutineTodayItem> _weeklyDayItems = [];
  bool _isLoadingWeeklyDay = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });

    _selectedWeeklyDate = DateTime.now();
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);

    final today = await _routineService.getTodayRoutineItems();
    final all = await _routineService.getAllRoutines();
    final stats = await _routineService.getWeeklyRoutineStats(DateTime.now());
    final weeklyDay = await _routineService.getRoutineItemsForDate(
      _selectedWeeklyDate,
    );
    final nextMeal = await _routineService.getNextUpcomingMeal();
    final dinnerTime = await _routineService.getSuggestedDinnerTime();

    // Check for routine overlaps across today's enabled routines
    final warnings = <String>[];
    final activeToday = today
        .where((i) => i.routine.isEnabled)
        .map((i) => i.routine)
        .toList();
    for (int i = 0; i < activeToday.length; i++) {
      for (int j = i + 1; j < activeToday.length; j++) {
        if (activeToday[i].overlapsWith(activeToday[j])) {
          warnings.add(
            '${activeToday[i].title} (${activeToday[i].formattedTimeRange}) overlaps with ${activeToday[j].title} (${activeToday[j].formattedTimeRange})',
          );
        }
      }
    }

    if (mounted) {
      setState(() {
        _todayItems = today;
        _allRoutines = all;
        _weeklyStats = stats;
        _weeklyDayItems = weeklyDay;
        _nextMealItem = nextMeal;
        _suggestedDinnerTime = dinnerTime;
        _overlapWarnings = warnings;
        _isLoading = false;
      });
    }
  }

  Future<void> _openGymWorkout() async {
    final todayPlan = await DatabaseService().getTodayPlan();
    if (!mounted) return;
    if (todayPlan != null &&
        !todayPlan.isRestDay &&
        todayPlan.exercises.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ActiveWorkoutScreen(plan: todayPlan)),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const WorkoutPlanScreen()),
      );
    }
  }

  Future<void> _triggerQuickTestAlarm([Routine? routine]) async {
    final title = routine?.title ?? 'RepTrack Test Alarm';
    final category = routine?.category ?? 'Gym';
    final isAudible = routine != null
        ? (routine.alarmType == 'alarm' || routine.isAlarmEnabled)
        : true;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Triggering real test alarm for "$title" in 2 seconds...',
        ),
        backgroundColor: AppColors.primary,
        duration: const Duration(seconds: 2),
      ),
    );

    await AlarmService().testAlarm(
      title: title,
      category: category,
      delaySeconds: 2,
      isAudible: isAudible,
    );

    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AlarmRingingScreen(
            routineId: routine?.id ?? 99999,
            title: title,
            category: category,
            scheduledTime: routine?.startTime ?? 'Now',
            snoozeMinutes: routine?.snoozeMinutes ?? 10,
          ),
        ),
      );
    }
  }

  Future<void> _loadWeeklyDayData(DateTime day) async {
    setState(() {
      _selectedWeeklyDate = day;
      _isLoadingWeeklyDay = true;
    });

    final items = await _routineService.getRoutineItemsForDate(day);
    if (mounted) {
      setState(() {
        _weeklyDayItems = items;
        _isLoadingWeeklyDay = false;
      });
    }
  }

  Future<void> _navigateToAddRoutine() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddEditRoutineScreen()),
    );
    if (result == true) {
      await _loadAllData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('New routine added successfully'),
            backgroundColor: AppColors.cardSurface,
          ),
        );
      }
    }
  }

  Future<void> _navigateToEditRoutine(Routine routine) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AddEditRoutineScreen(routine: routine)),
    );
    if (result == true) {
      await _loadAllData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Routine updated successfully'),
            backgroundColor: AppColors.cardSurface,
          ),
        );
      }
    }
  }

  Future<void> _toggleCompletion(
    int routineId,
    DateTime date,
    String status,
  ) async {
    // Find if already completed/skipped
    final existingItem = _todayItems.firstWhere(
      (item) => item.routine.id == routineId,
      orElse: () => RoutineTodayItem(
        routine: _allRoutines.firstWhere((r) => r.id == routineId),
        date: date,
      ),
    );

    if (existingItem.completion?.status.toLowerCase() == status.toLowerCase()) {
      await _routineService.removeRoutineCompletion(
        routineId: routineId,
        date: date,
      );
    } else {
      await _routineService.setRoutineCompletion(
        routineId: routineId,
        date: date,
        status: status,
      );
    }

    await _loadAllData();
  }

  Future<void> _toggleWeeklyCompletion(int routineId, String status) async {
    final date = _selectedWeeklyDate;
    final existingItem = _weeklyDayItems.firstWhere(
      (item) => item.routine.id == routineId,
      orElse: () => RoutineTodayItem(
        routine: _allRoutines.firstWhere((r) => r.id == routineId),
        date: date,
      ),
    );

    if (existingItem.completion?.status.toLowerCase() == status.toLowerCase()) {
      await _routineService.removeRoutineCompletion(
        routineId: routineId,
        date: date,
      );
    } else {
      await _routineService.setRoutineCompletion(
        routineId: routineId,
        date: date,
        status: status,
      );
    }

    await _loadAllData();
  }

  Future<void> _toggleRoutineEnabled(Routine routine) async {
    if (routine.id == null) return;
    await _routineService.toggleRoutineEnabled(routine.id!, !routine.isEnabled);
    await _loadAllData();
  }

  Future<void> _changeTimeDialog(Routine routine) async {
    final startParts = routine.startTime.split(':');
    final endParts = routine.endTime.split(':');

    TimeOfDay start = TimeOfDay(
      hour: int.tryParse(startParts[0]) ?? 8,
      minute: int.tryParse(startParts.length > 1 ? startParts[1] : '0') ?? 0,
    );
    TimeOfDay end = TimeOfDay(
      hour: int.tryParse(endParts[0]) ?? 9,
      minute: int.tryParse(endParts.length > 1 ? endParts[1] : '0') ?? 0,
    );

    final pickedStart = await showTimePicker(
      context: context,
      initialTime: start,
      helpText: 'Select Start Time',
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primary,
            onPrimary: Colors.black,
            surface: AppColors.cardSurface,
            onSurface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );

    if (pickedStart == null || !mounted) return;

    final pickedEnd = await showTimePicker(
      context: context,
      initialTime: end,
      helpText: 'Select End Time',
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primary,
            onPrimary: Colors.black,
            surface: AppColors.cardSurface,
            onSurface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );

    if (pickedEnd == null || !mounted || routine.id == null) return;

    final newStart =
        '${pickedStart.hour.toString().padLeft(2, '0')}:${pickedStart.minute.toString().padLeft(2, '0')}';
    final newEnd =
        '${pickedEnd.hour.toString().padLeft(2, '0')}:${pickedEnd.minute.toString().padLeft(2, '0')}';

    await _routineService.updateRoutineTime(routine.id!, newStart, newEnd);
    await _loadAllData();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Time updated for "${routine.title}" ($newStart – $newEnd)',
          ),
          backgroundColor: AppColors.cardSurface,
        ),
      );
    }
  }

  Future<void> _changeRepeatDaysDialog(Routine routine) async {
    List<int> selectedDays = List<int>.from(routine.repeatDays);

    final result = await showDialog<List<int>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            const daysMap = {
              1: 'Mon',
              2: 'Tue',
              3: 'Wed',
              4: 'Thu',
              5: 'Fri',
              6: 'Sat',
              7: 'Sun',
            };

            return AlertDialog(
              backgroundColor: AppColors.surfaceElevated,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppColors.border),
              ),
              title: const Text(
                'Change Repeat Days',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: daysMap.entries.map((entry) {
                        final isSelected = selectedDays.contains(entry.key);
                        return FilterChip(
                          label: Text(entry.value),
                          selected: isSelected,
                          selectedColor: AppColors.primary,
                          checkmarkColor: Colors.black,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.black : Colors.white,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                          backgroundColor: AppColors.cardSurface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.border,
                            ),
                          ),
                          onSelected: (selected) {
                            setDialogState(() {
                              if (selected) {
                                selectedDays.add(entry.key);
                                selectedDays.sort();
                              } else {
                                if (selectedDays.length > 1) {
                                  selectedDays.remove(entry.key);
                                }
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
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
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () => Navigator.pop(ctx, selectedDays),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null && routine.id != null && mounted) {
      await _routineService.updateRoutineRepeatDays(routine.id!, result);
      await _loadAllData();
    }
  }

  Future<void> _confirmDelete(Routine routine) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Text(
          'Delete Routine?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to permanently delete "${routine.title}"? This will also remove its logged completions.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && routine.id != null) {
      await _routineService.deleteRoutine(routine.id!);
      await _loadAllData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Routine "${routine.title}" deleted'),
            backgroundColor: AppColors.cardSurface,
          ),
        );
      }
    }
  }

  void _openDetails(Routine routine, [RoutineTodayItem? item]) {
    RoutineDetailSheet.show(
      context,
      routine: routine,
      todayItem: item,
      onDataChanged: _loadAllData,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                onPressed: () => Navigator.pop(context),
              )
            : (widget.onBackToHome != null
                  ? IconButton(
                      icon: const Icon(
                        Icons.home_rounded,
                        color: AppColors.primary,
                        size: 22,
                      ),
                      tooltip: 'Back to Home',
                      onPressed: widget.onBackToHome,
                    )
                  : null),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Routine Management',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Daily Schedule & Discipline Tracker',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.alarm_on_rounded,
              color: AppColors.primary,
              size: 22,
            ),
            tooltip: 'Alarm Settings',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AlarmSettingsScreen()),
              );
              _loadAllData();
            },
          ),
          IconButton(
            icon: const Icon(
              Icons.notifications_active_rounded,
              color: AppColors.primary,
              size: 22,
            ),
            tooltip: 'Test Alarm Now',
            onPressed: () => _triggerQuickTestAlarm(),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text(
                'Add',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              onPressed: _navigateToAddRoutine,
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: Colors.black,
              unselectedLabelColor: AppColors.textSecondary,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
              tabs: const [
                Tab(text: "Today's Schedule"),
                Tab(text: "Weekly Schedule"),
                Tab(text: "All Routines"),
              ],
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _buildTodayTab(),
                _buildWeeklyTab(),
                _buildAllRoutinesTab(),
              ],
            ),
    );
  }

  // ==========================================
  // TAB 1: TODAY'S SCHEDULE
  // ==========================================
  Widget _buildTodayTab() {
    final now = DateTime.now();
    final formattedToday = DateFormat('EEEE, MMMM d').format(now);

    final completedCount = _todayItems.where((i) => i.isCompleted).length;
    final totalCount = _todayItems.length;
    final progress = totalCount > 0 ? (completedCount / totalCount) : 0.0;

    // Identify next upcoming routine
    int? nextUpcomingIndex;
    for (int i = 0; i < _todayItems.length; i++) {
      if (_todayItems[i].isUpcoming) {
        nextUpcomingIndex = i;
        break;
      }
    }

    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.surfaceElevated,
      onRefresh: _loadAllData,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          // Today's Header Banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.cardSurface, AppColors.surfaceElevated],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TODAY',
                          style: TextStyle(
                            color: AppColors.primary.withValues(alpha: 0.9),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formattedToday,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        '$completedCount / $totalCount Done',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: Colors.white10,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_overlapWarnings.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF331500),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.primary, width: 1.2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'SCHEDULE OVERLAP DETECTED',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._overlapWarnings.map(
                    (w) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '• ',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              w,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (_nextMealItem != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.cardSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFF00B894).withValues(alpha: 0.5),
                  width: 1.2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.restaurant_rounded,
                            color: Color(0xFF00B894),
                            size: 18,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'NEXT MEAL REMINDER',
                            style: TextStyle(
                              color: Color(0xFF00B894),
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00B894)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _nextMealItem!.routine.startTime,
                          style: const TextStyle(
                            color: Color(0xFF00B894),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _nextMealItem!.routine.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (_nextMealItem!.routine.foodDetails != null &&
                      _nextMealItem!.routine.foodDetails!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '🥗 Meal Notes: ${_nextMealItem!.routine.foodDetails!}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (_suggestedDinnerTime != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.bolt_rounded,
                            color: AppColors.primary,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Suggested dinner at $_suggestedDinnerTime (calculated 15m after gym workout)',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Section Title
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "CHRONOLOGICAL TIMELINE",
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              Text(
                '${_todayItems.length} activities',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          if (_todayItems.isEmpty)
            _buildEmptyState(
              icon: Icons.calendar_today_rounded,
              title: 'No routines scheduled for today',
              subtitle: 'Add a new routine or check your repeat days setting.',
              buttonLabel: '+ Add Routine',
              onButtonPressed: _navigateToAddRoutine,
            )
          else
            ...List.generate(_todayItems.length, (index) {
              final item = _todayItems[index];
              final isCurrent = item.isInProgress;
              final isNextUpcoming = !isCurrent && index == nextUpcomingIndex;
              return _buildTodayRoutineCard(
                item: item,
                isCurrent: isCurrent,
                isNextUpcoming: isNextUpcoming,
              );
            }),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildTodayRoutineCard({
    required RoutineTodayItem item,
    required bool isCurrent,
    required bool isNextUpcoming,
  }) {
    final routine = item.routine;
    final catColor = routine.color;
    final status = item.status;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrent
              ? AppColors.primary
              : isNextUpcoming
              ? AppColors.primary.withValues(alpha: 0.4)
              : AppColors.border,
          width: isCurrent ? 1.8 : 1.0,
        ),
        boxShadow: isCurrent
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openDetails(routine, item),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: highlight badge / category & status badge & overflow
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        if (isCurrent) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.play_arrow_rounded,
                                  size: 12,
                                  color: Colors.black,
                                ),
                                SizedBox(width: 3),
                                Text(
                                  'NOW ACTIVE',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                        ] else if (isNextUpcoming) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'NEXT UP',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: catColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            routine.category.toUpperCase(),
                            style: TextStyle(
                              color: catColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (routine.alarmType == 'alarm' ||
                            routine.isAlarmEnabled)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppColors.primary.withValues(alpha: 0.5),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.alarm_on_rounded,
                                  size: 11,
                                  color: AppColors.primary,
                                ),
                                SizedBox(width: 3),
                                Text(
                                  'ALARM',
                                  style: TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else if (routine.alarmType == 'notification')
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blueAccent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.notifications_none_rounded,
                                  size: 11,
                                  color: Colors.blueAccent,
                                ),
                                SizedBox(width: 3),
                                Text(
                                  'NOTIF',
                                  style: TextStyle(
                                    color: Colors.blueAccent,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    Row(
                      children: [
                        _buildStatusChip(status),
                        _buildRoutinePopupMenu(routine, item: item),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Routine title & category icon
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: catColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: catColor.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Icon(routine.icon, color: catColor, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            routine.title,
                            style: TextStyle(
                              color: item.isCompleted
                                  ? AppColors.textSecondary
                                  : Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              decoration: item.isCompleted
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              const Icon(
                                Icons.access_time_rounded,
                                size: 13,
                                color: AppColors.textSecondary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                routine.formattedTimeRange,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
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
                                  routine.formattedDuration,
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (routine.isOvernight) ...[
                                const SizedBox(width: 6),
                                const Text(
                                  '🌙',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                if (routine.notes != null && routine.notes!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 44),
                    child: Text(
                      routine.notes!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],

                if (routine.foodDetails != null &&
                    routine.foodDetails!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    margin: const EdgeInsets.only(left: 44),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.restaurant_menu_rounded,
                          size: 14,
                          color: Color(0xFF00B894),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Food: ${routine.foodDetails!}',
                            style: const TextStyle(
                              color: AppColors.textMain,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                if (routine.isGymCategory) ...[
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.only(left: 44),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(
                            color: AppColors.primary,
                            width: 1.2,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: const Icon(
                          Icons.fitness_center_rounded,
                          size: 16,
                        ),
                        label: const Text(
                          'Start / View Today\'s Workout Plan',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: _openGymWorkout,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 12),
                const Divider(color: AppColors.border, height: 1),
                const SizedBox(height: 8),

                // Bottom row: Quick action buttons (Mark Done / Mark Skip)
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: item.isSkipped
                            ? Colors.white
                            : Colors.amberAccent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                      ),
                      icon: Icon(
                        item.isSkipped
                            ? Icons.undo_rounded
                            : Icons.fast_forward_rounded,
                        size: 16,
                      ),
                      label: Text(
                        item.isSkipped ? 'Unskip' : 'Skip',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: () {
                        if (routine.id != null) {
                          _toggleCompletion(routine.id!, item.date, 'skipped');
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: item.isCompleted
                            ? Colors.grey.shade800
                            : const Color(0xFF00B894),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: Icon(
                        item.isCompleted
                            ? Icons.undo_rounded
                            : Icons.check_circle_rounded,
                        size: 16,
                      ),
                      label: Text(
                        item.isCompleted ? 'Done' : 'Mark Done',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: () {
                        if (routine.id != null) {
                          _toggleCompletion(
                            routine.id!,
                            item.date,
                            'completed',
                          );
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // TAB 2: WEEKLY SCHEDULE
  // ==========================================
  Widget _buildWeeklyTab() {
    final now = DateTime.now();
    // Compute current week's Monday
    final monday = now.subtract(Duration(days: now.weekday - 1));

    final weekDays = List.generate(7, (i) => monday.add(Duration(days: i)));

    final completedCount = _weeklyDayItems.where((i) => i.isCompleted).length;
    final totalCount = _weeklyDayItems.length;

    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.surfaceElevated,
      onRefresh: _loadAllData,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          // Weekly Completion Overview Card
          if (_weeklyStats != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.cardSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '${(_weeklyStats!.completionRate * 100).toInt()}%',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'THIS WEEK SUMMARY',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_weeklyStats!.completedCount} of ${_weeklyStats!.totalScheduled} routines completed',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (_weeklyStats!.skippedCount > 0)
                          Text(
                            '${_weeklyStats!.skippedCount} routines skipped',
                            style: const TextStyle(
                              color: Colors.amberAccent,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 18),

          // Monday - Sunday Horizontal Day Selector
          const Text(
            'SELECT DAY (MON – SUN)',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),

          Row(
            children: weekDays.map((day) {
              final isSelected =
                  day.year == _selectedWeeklyDate.year &&
                  day.month == _selectedWeeklyDate.month &&
                  day.day == _selectedWeeklyDate.day;
              final isToday =
                  day.year == now.year &&
                  day.month == now.month &&
                  day.day == now.day;

              const dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
              final dayLetter = dayLetters[day.weekday - 1];

              return Expanded(
                child: GestureDetector(
                  onTap: () => _loadWeeklyDayData(day),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary
                          : isToday
                          ? AppColors.surfaceElevated
                          : AppColors.cardSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : isToday
                            ? AppColors.primary.withValues(alpha: 0.5)
                            : AppColors.border,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          dayLetter,
                          style: TextStyle(
                            color: isSelected
                                ? Colors.black
                                : AppColors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${day.day}',
                          style: TextStyle(
                            color: isSelected ? Colors.black : Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected
                                ? Colors.black
                                : isToday
                                ? AppColors.primary
                                : Colors.transparent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 20),

          // Day summary header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                DateFormat('EEEE, MMM d')
                    .format(_selectedWeeklyDate)
                    .toUpperCase(),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              Text(
                '$completedCount / $totalCount Done',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          if (_isLoadingWeeklyDay)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (_weeklyDayItems.isEmpty)
            _buildEmptyState(
              icon: Icons.event_busy_rounded,
              title: 'No routines for this day',
              subtitle: 'Enjoy your rest or configure routines to repeat on this weekday.',
              buttonLabel: '+ Add Routine',
              onButtonPressed: _navigateToAddRoutine,
            )
          else
            ..._weeklyDayItems.map((item) {
              final routine = item.routine;
              final catColor = routine.color;

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: AppColors.cardSurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: ListTile(
                  onTap: () => _openDetails(routine, item),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: catColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(routine.icon, color: catColor, size: 20),
                  ),
                  title: Text(
                    routine.title,
                    style: TextStyle(
                      color: item.isCompleted
                          ? AppColors.textSecondary
                          : Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      decoration: item.isCompleted
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  subtitle: Text(
                    '${routine.formattedTimeRange} (${routine.formattedDuration})',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildStatusChip(item.status),
                      IconButton(
                        icon: Icon(
                          item.isCompleted
                              ? Icons.check_circle_rounded
                              : Icons.check_circle_outline_rounded,
                          color: item.isCompleted
                              ? const Color(0xFF00B894)
                              : AppColors.textSecondary,
                          size: 20,
                        ),
                        onPressed: () {
                          if (routine.id != null) {
                            _toggleWeeklyCompletion(routine.id!, 'completed');
                          }
                        },
                      ),
                    ],
                  ),
                ),
              );
            }),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 3: ALL ROUTINES
  // ==========================================
  Widget _buildAllRoutinesTab() {
    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.surfaceElevated,
      onRefresh: _loadAllData,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'ALL CONFIGURED ROUTINES',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              Text(
                '${_allRoutines.length} total',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_allRoutines.isEmpty)
            _buildEmptyState(
              icon: Icons.list_alt_rounded,
              title: 'No routines created yet',
              subtitle: 'Establish your daily structure by adding your first routine.',
              buttonLabel: '+ Add Routine',
              onButtonPressed: _navigateToAddRoutine,
            )
          else
            ..._allRoutines.map((routine) {
              final catColor = routine.color;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.cardSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: routine.isEnabled
                        ? AppColors.border
                        : Colors.grey.shade900,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _openDetails(routine),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: routine.isEnabled
                                  ? catColor.withValues(alpha: 0.15)
                                  : Colors.white10,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: routine.isEnabled
                                    ? catColor.withValues(alpha: 0.3)
                                    : Colors.transparent,
                              ),
                            ),
                            child: Icon(
                              routine.icon,
                              color: routine.isEnabled ? catColor : Colors.grey,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: catColor.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        routine.category.toUpperCase(),
                                        style: TextStyle(
                                          color: catColor,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    if (routine.alarmType == 'alarm' ||
                                        routine.isAlarmEnabled)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withValues(
                                            alpha: 0.2,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.alarm_on_rounded,
                                              size: 10,
                                              color: AppColors.primary,
                                            ),
                                            SizedBox(width: 2),
                                            Text(
                                              'ALARM',
                                              style: TextStyle(
                                                color: AppColors.primary,
                                                fontSize: 8.5,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    else if (routine.alarmType ==
                                        'notification')
                                      const Icon(
                                        Icons.notifications_active_rounded,
                                        size: 13,
                                        color: Colors.blueAccent,
                                      ),
                                    if (routine.isOvernight) ...[
                                      const SizedBox(width: 4),
                                      const Text(
                                        '🌙',
                                        style: TextStyle(fontSize: 10),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  routine.title,
                                  style: TextStyle(
                                    color: routine.isEnabled
                                        ? Colors.white
                                        : AppColors.textSecondary,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${routine.formattedTimeRange} • ${routine.formattedRepeatDays}',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 11,
                                  ),
                                ),
                                if (routine.foodDetails != null &&
                                    routine.foodDetails!.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    '🥗 ${routine.foodDetails!}',
                                    style: const TextStyle(
                                      color: Color(0xFF00B894),
                                      fontSize: 10.5,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Switch(
                            value: routine.isEnabled,
                            activeThumbColor: AppColors.primary,
                            onChanged: (val) => _toggleRoutineEnabled(routine),
                          ),
                          _buildRoutinePopupMenu(routine),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ==========================================
  // SHARED UI HELPERS
  // ==========================================

  Widget _buildStatusChip(RoutineCompletionStatus status) {
    Color bg;
    Color fg;
    String label;

    switch (status) {
      case RoutineCompletionStatus.completed:
        bg = const Color(0xFF00B894).withValues(alpha: 0.2);
        fg = const Color(0xFF00B894);
        label = 'Completed';
        break;
      case RoutineCompletionStatus.skipped:
        bg = Colors.amberAccent.withValues(alpha: 0.2);
        fg = Colors.amberAccent;
        label = 'Skipped';
        break;
      case RoutineCompletionStatus.inProgress:
        bg = AppColors.primary.withValues(alpha: 0.2);
        fg = AppColors.primary;
        label = 'In Progress';
        break;
      case RoutineCompletionStatus.upcoming:
        bg = Colors.grey.withValues(alpha: 0.15);
        fg = Colors.grey.shade400;
        label = 'Upcoming';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildRoutinePopupMenu(Routine routine, {RoutineTodayItem? item}) {
    return PopupMenuButton<String>(
      icon: const Icon(
        Icons.more_vert_rounded,
        color: AppColors.textSecondary,
        size: 20,
      ),
      color: AppColors.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      onSelected: (action) {
        switch (action) {
          case 'details':
            _openDetails(routine, item);
            break;
          case 'edit':
            _navigateToEditRoutine(routine);
            break;
          case 'time':
            _changeTimeDialog(routine);
            break;
          case 'days':
            _changeRepeatDaysDialog(routine);
            break;
          case 'test_alarm':
            _triggerQuickTestAlarm(routine);
            break;
          case 'alarm_settings':
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AlarmSettingsScreen()),
            ).then((_) => _loadAllData());
            break;
          case 'toggle_enabled':
            _toggleRoutineEnabled(routine);
            break;
          case 'complete':
            if (routine.id != null) {
              final d = item?.date ?? DateTime.now();
              _toggleCompletion(routine.id!, d, 'completed');
            }
            break;
          case 'skip':
            if (routine.id != null) {
              final d = item?.date ?? DateTime.now();
              _toggleCompletion(routine.id!, d, 'skipped');
            }
            break;
          case 'delete':
            _confirmDelete(routine);
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'details',
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: Colors.white),
              SizedBox(width: 10),
              Text(
                'View Details',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit_rounded, size: 18, color: AppColors.primary),
              SizedBox(width: 10),
              Text(
                'Edit Routine',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'time',
          child: Row(
            children: [
              Icon(Icons.schedule_rounded, size: 18, color: Colors.cyanAccent),
              SizedBox(width: 10),
              Text(
                'Change Time',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'days',
          child: Row(
            children: [
              Icon(
                Icons.calendar_month_rounded,
                size: 18,
                color: Colors.amberAccent,
              ),
              SizedBox(width: 10),
              Text(
                'Change Repeat Days',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'test_alarm',
          child: Row(
            children: [
              Icon(
                Icons.notifications_active_rounded,
                size: 18,
                color: AppColors.primary,
              ),
              SizedBox(width: 10),
              Text(
                'Test Alarm Now',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'alarm_settings',
          child: Row(
            children: [
              Icon(Icons.alarm_on_rounded, size: 18, color: AppColors.primary),
              SizedBox(width: 10),
              Text(
                'Alarm Settings',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'toggle_enabled',
          child: Row(
            children: [
              Icon(
                routine.isEnabled
                    ? Icons.pause_circle_outline_rounded
                    : Icons.play_circle_outline_rounded,
                size: 18,
                color: routine.isEnabled
                    ? Colors.orangeAccent
                    : const Color(0xFF00B894),
              ),
              const SizedBox(width: 10),
              Text(
                routine.isEnabled ? 'Disable' : 'Enable',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        const PopupMenuItem(
          value: 'complete',
          child: Row(
            children: [
              Icon(
                Icons.check_circle_rounded,
                size: 18,
                color: Color(0xFF00B894),
              ),
              SizedBox(width: 10),
              Text(
                'Mark Completed',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'skip',
          child: Row(
            children: [
              Icon(
                Icons.fast_forward_rounded,
                size: 18,
                color: Colors.amberAccent,
              ),
              SizedBox(width: 10),
              Text(
                'Mark Skipped',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: Colors.redAccent,
              ),
              SizedBox(width: 10),
              Text(
                'Delete Routine',
                style: TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    required String buttonLabel,
    required VoidCallback onButtonPressed,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(icon, size: 32, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(
              buttonLabel,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: onButtonPressed,
          ),
        ],
      ),
    );
  }
}
