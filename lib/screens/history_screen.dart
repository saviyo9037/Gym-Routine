import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../widgets/exercise_picker_sheet.dart';
import '../widgets/load_error_view.dart';
import '../models/workout_session.dart';
import '../core/clock.dart';
import '../models/weekly_summary.dart';
import '../services/stats_service.dart';
import '../services/database_service.dart';
import '../widgets/media_attachment_section.dart';
import 'active_workout_screen.dart';
import '../core/dev_log.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final DatabaseService _dbService = DatabaseService();
  final StatsService _stats = StatsService();
  bool _sundayStart = false;

  // Segmented Navigation: 0 = This Week, 1 = All Sessions, 2 = Muscle History
  int _selectedSegment = 0;

  // Weekly Summary State
  DateTime _currentWeekAnchor = AppClock.now();
  WeeklySummary? _weeklySummary;

  // All Sessions State
  List<WorkoutSession> _allSessions = [];
  List<WorkoutSession> _filteredSessions = [];
  String _dateRangeFilter = 'All Time';
  DateTimeRange? _customRange;
  bool _isCalendarView = false;
  DateTime _calendarMonth = DateTime(
    AppClock.now().year,
    AppClock.now().month,
    1,
  );
  DateTime? _selectedCalendarDate;

  // Muscle History State
  String _muscleFilterPeriod = 'All Time';
  String _selectedMuscleCategory = 'All';
  Map<String, int> _muscleFrequencyStats = {};
  List<WorkoutSession> _muscleSessions = [];

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  bool _loadFailed = false;

  Future<void> _loadAllData() async {
    try {
      await _loadAllDataImpl();
      if (mounted && _loadFailed) setState(() => _loadFailed = false);
    } catch (e, st) {
      devLog('history_screen.dart: load failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loadFailed = true;
        _isLoading = false;
      });
    }
  }

  void _retryLoad() {
    setState(() {
      _loadFailed = false;
      _isLoading = true;
    });
    _loadAllData();
  }

  Future<void> _loadAllDataImpl() async {
    _sundayStart = await _stats.weekStartsOnSunday();
    final week = await _stats.weeklySummary(_currentWeekAnchor);
    final all = await _dbService.getAllSessions();

    if (mounted) {
      setState(() {
        _weeklySummary = week;
        _allSessions = all;
        _applyDateRangeFilter();
        _loadMuscleHistoryData();
        _isLoading = false;
      });
    }
  }

  // ------------------- DATE RANGE FILTERING -------------------
  void _applyDateRangeFilter() {
    List<WorkoutSession> result = List.from(_allSessions);

    final range = StatsService.rangeForFilter(
      _dateRangeFilter,
      AppClock.now(),
      sundayStart: _sundayStart,
    );
    if (range != null) {
      result = result
          .where(
            (s) =>
                s.date.compareTo(range.start) >= 0 &&
                s.date.compareTo(range.end) <= 0,
          )
          .toList();
    } else if (_dateRangeFilter == 'Custom' && _customRange != null) {
      final startStr = DateFormat('yyyy-MM-dd').format(_customRange!.start);
      final endStr = DateFormat('yyyy-MM-dd').format(_customRange!.end);
      result = result
          .where(
            (s) =>
                s.date.compareTo(startStr) >= 0 &&
                s.date.compareTo(endStr) <= 0,
          )
          .toList();
    }

    if (_selectedCalendarDate != null && _isCalendarView) {
      final calDateStr = DateFormat('yyyy-MM-dd')
          .format(_selectedCalendarDate!);
      result = result.where((s) => s.date == calDateStr).toList();
    }

    _filteredSessions = result;
  }

  // ------------------- MUSCLE HISTORY LOADING -------------------
  Future<void> _loadMuscleHistoryData() async {
    final range = StatsService.rangeForFilter(
      _muscleFilterPeriod,
      AppClock.now(),
      sundayStart: _sundayStart,
    );
    final stats = await _stats.muscleFrequency(range);
    final sessions = await _stats.sessionsForMuscle(
      _selectedMuscleCategory,
      range,
    );

    if (mounted) {
      setState(() {
        _muscleFrequencyStats = stats;
        _muscleSessions = sessions;
      });
    }
  }

  // ------------------- WEEK NAVIGATION -------------------
  void _navigateWeek(int dayOffset) async {
    final a = _currentWeekAnchor;
    final newAnchor = DateTime(a.year, a.month, a.day + dayOffset);
    final summary = await _stats.weeklySummary(newAnchor);
    if (mounted) {
      setState(() {
        _currentWeekAnchor = newAnchor;
        _weeklySummary = summary;
      });
    }
  }

  void _resetToCurrentWeek() async {
    final now = AppClock.now();
    final summary = await _stats.weeklySummary(now);
    if (mounted) {
      setState(() {
        _currentWeekAnchor = now;
        _weeklySummary = summary;
      });
    }
  }

  bool get _isCurrentWeek {
    final nowStart = StatsService.weekStart(
      AppClock.now(),
      sundayStart: _sundayStart,
    );
    final anchorStart = StatsService.weekStart(
      _currentWeekAnchor,
      sundayStart: _sundayStart,
    );
    return nowStart == anchorStart;
  }

  // ------------------- SESSION DETAILS BOTTOM SHEET -------------------
  void _showSessionDetails(WorkoutSession session) {
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final durationMins = session.durationSeconds ~/ 60;
        final durationSecs = session.durationSeconds % 60;
        final isPartial = session.completionStatus == 'Partially Completed';

        // Group sets by exercise
        final Map<String, List<WorkoutSetRecord>> exerciseSetsMap = {};
        for (final s in session.sets) {
          exerciseSetsMap.putIfAbsent(s.exerciseName, () => []).add(s);
        }

        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.82,
              maxChildSize: 0.96,
              builder: (_, controller) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: ListView(
                    controller: controller,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.border,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),

                      // Session Title & Status
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      session.date,
                                      style: const TextStyle(
                                        color: AppColors.primary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isPartial
                                            ? Colors.amber.withValues(
                                                alpha: 0.2,
                                              )
                                            : AppColors.successDark.withValues(
                                                alpha: 0.2,
                                              ),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: isPartial
                                              ? Colors.amber
                                              : AppColors.success,
                                          width: 1,
                                        ),
                                      ),
                                      child: Text(
                                        session.completionStatus,
                                        style: TextStyle(
                                          color: isPartial
                                              ? Colors.amber
                                              : AppColors.success,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${session.primaryMuscle}${session.secondaryMuscle != null ? " + ${session.secondaryMuscle}" : ""}',
                                  style: const TextStyle(
                                    color: AppColors.textMain,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.cardSurface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${durationMins}m ${durationSecs}s',
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  '${session.totalVolumeKg.toStringAsFixed(0)} kg vol',
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
                      const SizedBox(height: 14),

                      // Session Notes
                      if (session.notes != null &&
                          session.notes!.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.cardSurface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.notes_rounded,
                                color: AppColors.primary,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  session.notes!,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Completed Sets Grouped by Exercise
                      const Text(
                        'LOGGED EXERCISES & SETS',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 10),

                      if (exerciseSetsMap.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'No exercise sets recorded for this session.',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        )
                      else
                        ...exerciseSetsMap.entries.map((entry) {
                          final exName = entry.key;
                          final sets = entry.value;
                          final completedSets = sets
                              .where((s) => s.isCompleted)
                              .length;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.cardSurface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        exName,
                                        style: const TextStyle(
                                          color: AppColors.textMain,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14.5,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '$completedSets/${sets.length} sets completed',
                                      style: TextStyle(
                                        color: completedSets == sets.length
                                            ? AppColors.success
                                            : Colors.amber,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(
                                  color: AppColors.border,
                                  height: 16,
                                ),
                                ...sets.map((s) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 24,
                                          height: 24,
                                          decoration: BoxDecoration(
                                            color: s.isCompleted
                                                ? AppColors.primary.withValues(
                                                    alpha: 0.2,
                                                  )
                                                : Colors.grey.withValues(
                                                    alpha: 0.2,
                                                  ),
                                            shape: BoxShape.circle,
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            '${s.setNumber}',
                                            style: TextStyle(
                                              color: s.isCompleted
                                                  ? AppColors.primary
                                                  : AppColors.textSecondary,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          '${s.weightKg} kg',
                                          style: const TextStyle(
                                            color: AppColors.textMain,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const Text(
                                          '  ×  ',
                                          style: TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 12,
                                          ),
                                        ),
                                        Text(
                                          '${s.reps} reps',
                                          style: const TextStyle(
                                            color: AppColors.textMain,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const Spacer(),
                                        Icon(
                                          s.isCompleted
                                              ? Icons.check_circle_rounded
                                              : Icons
                                                    .remove_circle_outline_rounded,
                                          color: s.isCompleted
                                              ? AppColors.success
                                              : Colors.amber,
                                          size: 18,
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
                          );
                        }),

                      const SizedBox(height: 12),
                      MediaAttachmentSection(
                        entityType: 'session',
                        entityId: session.id ?? 0,
                        entityTitle:
                            'Session: ${session.date} (${session.primaryMuscle})',
                        sectionTitle: 'SESSION MEDIA ATTACHMENTS',
                        onChanged: () {
                          _loadAllData();
                        },
                      ),

                      const SizedBox(height: 24),

                      // Delete Session Button
                      OutlinedButton.icon(
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.redAccent,
                          size: 18,
                        ),
                        label: const Text(
                          'Delete Session',
                          style: TextStyle(color: Colors.redAccent),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: Colors.redAccent.withValues(alpha: 0.5),
                          ),
                          minimumSize: const Size.fromHeight(44),
                        ),
                        onPressed: () => _confirmDeleteSession(session),
                      ),

                      const SizedBox(height: 36),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _confirmDeleteSession(WorkoutSession session) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text(
          'Delete Session?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to remove this workout record from your history? This will also remove associated set logs.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            onPressed: () => Navigator.pop(ctx),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
            onPressed: () async {
              Navigator.pop(ctx); // Close dialog
              Navigator.pop(context); // Close bottom sheet
              if (session.id != null) {
                try {
                  await _dbService.deleteWorkoutSession(session.id!);
                  _loadAllData();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Workout session removed from history'),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  }
                } catch (_) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Could not delete the session. Nothing was changed.',
                        ),
                      ),
                    );
                  }
                }
              }
            },
          ),
        ],
      ),
    );
  }

  // ------------------- MANUAL WORKOUT LOGGING DIALOG -------------------
  void _openManualWorkoutDialog() {
    DateTime selectedDate = DateTime.now();
    String primaryMuscle = 'Chest';
    String secondaryMuscle = 'Triceps';
    int durationMinutes = 45;
    final notesController = TextEditingController();

    // Starts empty: a manual log only ever contains what the user adds.
    final List<Map<String, dynamic>> manualSets = [];
    String? formError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (modalContext, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: MediaQuery.of(modalContext).viewInsets.bottom + 20,
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'LOG WORKOUT SESSION',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Record a completed session to save into workout history.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),

                // Date Picker
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                      builder: (c, child) => Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: const ColorScheme.dark(
                            primary: AppColors.primary,
                            onPrimary: Colors.black,
                            surface: AppColors.surfaceElevated,
                            onSurface: Colors.white,
                          ),
                        ),
                        child: child!,
                      ),
                    );
                    if (picked != null) {
                      setModalState(() => selectedDate = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.cardSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Date: ${DateFormat('yyyy-MM-dd (EEEE)').format(selectedDate)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Icon(
                          Icons.calendar_today_rounded,
                          color: AppColors.primary,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Muscle Groups
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('primary_$primaryMuscle'),
                        isExpanded: true,
                        initialValue: primaryMuscle,
                        dropdownColor: AppColors.surfaceElevated,
                        decoration: const InputDecoration(
                          labelText: 'Primary Muscle',
                        ),
                        items:
                            const [
                                  'Chest',
                                  'Back',
                                  'Shoulders',
                                  'Biceps',
                                  'Triceps',
                                  'Quadriceps',
                                  'Hamstrings',
                                  'Glutes',
                                  'Abs and Core',
                                  'Full Body',
                                ]
                                .map(
                                  (m) => DropdownMenuItem(
                                    value: m,
                                    child: Text(m),
                                  ),
                                )
                                .toList(),
                        onChanged: (v) =>
                            setModalState(() => primaryMuscle = v ?? 'Chest'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: secondaryMuscle,
                        dropdownColor: AppColors.surfaceElevated,
                        decoration: const InputDecoration(
                          labelText: 'Secondary Muscle',
                        ),
                        items:
                            const [
                                  'Triceps',
                                  'Biceps',
                                  'Shoulders',
                                  'Upper Back and Traps',
                                  'Calves',
                                  'Forearms',
                                  'Abs and Core',
                                  'None',
                                ]
                                .map(
                                  (m) => DropdownMenuItem(
                                    value: m,
                                    child: Text(m),
                                  ),
                                )
                                .toList(),
                        onChanged: (v) =>
                            setModalState(() => secondaryMuscle = v ?? 'None'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Duration & Notes
                TextFormField(
                  initialValue: durationMinutes.toString(),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Duration (minutes)',
                    suffixText: 'mins',
                  ),
                  onChanged: (v) => durationMinutes = int.tryParse(v) ?? 45,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes / Personal Reflections',
                  ),
                ),
                const SizedBox(height: 16),

                // Exercises actually performed (required)
                const Text(
                  'EXERCISES',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                if (manualSets.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Add at least one exercise with its sets, reps and weight.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                for (int i = 0; i < manualSets.length; i++)
                  Container(
                    key: ValueKey('manual_ex_$i'),
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.cardSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                manualSets[i]['exercise'] as String,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Remove exercise',
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () =>
                                  setModalState(() => manualSets.removeAt(i)),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            for (final f in const [
                              ('sets', 'Sets'),
                              ('reps', 'Reps'),
                              ('weight', 'Kg'),
                            ])
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: TextFormField(
                                    key: ValueKey('manual_${i}_${f.$1}'),
                                    initialValue: () {
                                      final v = manualSets[i][f.$1] as num;
                                      return v == v.roundToDouble()
                                          ? v.toStringAsFixed(0)
                                          : v.toString();
                                    }(),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: InputDecoration(
                                      labelText: f.$2,
                                      isDense: true,
                                    ),
                                    onChanged: (v) {
                                      final n = double.tryParse(
                                        v.trim().replaceAll(',', '.'),
                                      );
                                      if (n == null || n < 0) return;
                                      manualSets[i][f.$1] = f.$1 == 'weight'
                                          ? n
                                          : n.round();
                                    },
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final ex = await ExercisePickerSheet.show(
                      context,
                      title: 'Add to this session',
                      alreadyAddedIds: {
                        for (final m in manualSets) m['id'] as int,
                      },
                    );
                    if (ex == null) return;
                    setModalState(() {
                      const primaries = [
                        'Chest',
                        'Back',
                        'Shoulders',
                        'Biceps',
                        'Triceps',
                        'Quadriceps',
                        'Hamstrings',
                        'Glutes',
                        'Abs and Core',
                        'Full Body',
                      ];
                      if (manualSets.isEmpty &&
                          primaries.contains(ex.muscleGroupName)) {
                        primaryMuscle = ex.muscleGroupName;
                      }
                      manualSets.add({
                        'id': ex.id ?? 0,
                        'exercise': ex.name,
                        'group': ex.muscleGroupName,
                        'sets': ex.defaultSets,
                        'reps': ex.defaultReps,
                        'weight': ex.defaultWeightKg,
                      });
                      formError = null;
                    });
                  },
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add exercise'),
                ),
                if (formError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      formError!,
                      style: const TextStyle(color: AppColors.error),
                    ),
                  ),
                const SizedBox(height: 16),

                // Save Button
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    if (manualSets.isEmpty) {
                      setModalState(
                        () => formError = 'Add at least one exercise first.',
                      );
                      return;
                    }
                    if (durationMinutes < 1 || durationMinutes > 600) {
                      setModalState(
                        () => formError = 'Duration must be 1-600 minutes.',
                      );
                      return;
                    }
                    for (final m in manualSets) {
                      if ((m['sets'] as int) < 1 ||
                          (m['reps'] as int) < 1 ||
                          (m['sets'] as int) > 50) {
                        setModalState(
                          () => formError =
                              'Check sets and reps for ${m['exercise']}.',
                        );
                        return;
                      }
                    }
                    final dateStr = DateFormat('yyyy-MM-dd')
                        .format(selectedDate);
                    final start = DateTime(
                      selectedDate.year,
                      selectedDate.month,
                      selectedDate.day,
                      10,
                    );
                    final end = start.add(Duration(minutes: durationMinutes));
                    String hhmm(DateTime d) =>
                        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
                    final session = WorkoutSession(
                      date: dateStr,
                      startTime: hhmm(start),
                      endTime: hhmm(end),
                      durationSeconds: durationMinutes * 60,
                      primaryMuscle: primaryMuscle,
                      secondaryMuscle: secondaryMuscle == 'None'
                          ? null
                          : secondaryMuscle,
                      notes: notesController.text.trim().isEmpty
                          ? 'Manually logged gym workout'
                          : notesController.text.trim(),
                      sets: [
                        for (int i = 0; i < manualSets.length; i++)
                          for (
                            int s = 1;
                            s <= (manualSets[i]['sets'] as int);
                            s++
                          )
                            WorkoutSetRecord(
                              sessionId: 0,
                              exerciseId: manualSets[i]['id'] as int,
                              exerciseName: manualSets[i]['exercise'] as String,
                              setNumber: s,
                              reps: manualSets[i]['reps'] as int,
                              weightKg: (manualSets[i]['weight'] as num)
                                  .toDouble(),
                              isCompleted: true,
                            ),
                      ],
                    );

                    try {
                      await _dbService.createWorkoutSession(session);
                    } catch (_) {
                      setModalState(
                        () => formError =
                            'Could not save the workout. Try again.',
                      );
                      return;
                    }
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                    }
                    if (mounted) {
                      _loadAllData();
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Workout successfully recorded in history!',
                          ),
                          backgroundColor: AppColors.successDark,
                        ),
                      );
                    }
                  },
                  child: const Text(
                    'SAVE TO WORKOUT HISTORY',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ------------------- BUILD UI -------------------
  @override
  Widget build(BuildContext context) {
    if (_loadFailed) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(),
        body: LoadErrorView(onRetry: _retryLoad),
      );
    }
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('WORKOUT HISTORY'),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.add_rounded,
              color: AppColors.primary,
              size: 26,
            ),
            tooltip: 'Log Workout Session',
            onPressed: _openManualWorkoutDialog,
          ),
          IconButton(
            icon: const Icon(
              Icons.refresh_rounded,
              color: AppColors.textSecondary,
            ),
            tooltip: 'Refresh',
            onPressed: _loadAllData,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top Navigation Segment Pills
            _buildSegmentedHeader(),

            // Active Tab Content
            Expanded(
              child: _selectedSegment == 0
                  ? _buildThisWeekView()
                  : (_selectedSegment == 1
                        ? _buildAllSessionsView()
                        : _buildMuscleHistoryView()),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------- SEGMENT HEADER -------------------
  Widget _buildSegmentedHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        children: [
          _buildSegmentPill(0, 'This Week'),
          const SizedBox(width: 8),
          _buildSegmentPill(1, 'All Sessions'),
          const SizedBox(width: 8),
          _buildSegmentPill(2, 'Muscle History'),
        ],
      ),
    );
  }

  Widget _buildSegmentPill(int index, String label) {
    final isSelected = _selectedSegment == index;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedSegment = index;
            if (index == 2) _loadMuscleHistoryData();
          });
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.border,
              width: 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.black : AppColors.textSecondary,
              fontWeight: FontWeight.bold,
              fontSize: 12.5,
            ),
          ),
        ),
      ),
    );
  }

  // ------------------- TAB 1: THIS WEEK SUMMARY -------------------
  Widget _buildThisWeekView() {
    if (_weeklySummary == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    final ws = _weeklySummary!;
    final weekStartStr = DateFormat('MMM d').format(ws.startOfWeek);
    final weekEndStr = DateFormat('MMM d, yyyy').format(ws.endOfWeek);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // Week Navigation Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.cardSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                tooltip: 'Back',
                icon: const Icon(
                  Icons.arrow_back_ios_rounded,
                  color: AppColors.primary,
                  size: 18,
                ),
                onPressed: () => _navigateWeek(-7),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      '$weekStartStr – $weekEndStr',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textMain,
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                      ),
                    ),
                    if (_isCurrentWeek)
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'CURRENT WEEK',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    else
                      InkWell(
                        onTap: _resetToCurrentWeek,
                        child: const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Text(
                            'Jump to This Week',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Forward',
                icon: const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: AppColors.primary,
                  size: 18,
                ),
                onPressed: () => _navigateWeek(7),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        if (!_allSessions.any((x) => x.isEffective)) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: const Text(
              'No workouts logged yet. Finish your first workout and your '
              'weekly totals, volume and progress will appear here.',
              style: TextStyle(color: AppColors.textSecondary, height: 1.4),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // 4 Summary Metrics Cards (2x2 Grid)
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                title: 'Workouts Completed',
                value: '${ws.workoutsCompleted}',
                icon: Icons.check_circle_rounded,
                accentColor: AppColors.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricTile(
                title: 'Exercises Done',
                value: '${ws.exercisesCompleted}',
                icon: Icons.fitness_center_rounded,
                accentColor: AppColors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                title: 'Planned Workouts',
                value: '${ws.plannedWorkouts}',
                icon: Icons.event_note_rounded,
                accentColor: Colors.blueAccent,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricTile(
                title: 'Rest Days',
                value: '${ws.restDays}',
                icon: Icons.nightlight_round,
                accentColor: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Timeline Header
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            const Text(
              '7-DAY WORKOUT SCHEDULE',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
            Text(
              '${(ws.totalDurationSeconds ~/ 60)}m • ${ws.totalVolumeKg.toStringAsFixed(0)} kg total',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // 7 Days List
        ...ws.days.map((day) => _buildDayTimelineCard(day)),
      ],
    );
  }

  Widget _buildMetricTile({
    required String title,
    required String value,
    required IconData icon,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: accentColor, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.textMain,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayTimelineCard(DayWorkoutSummary day) {
    Color statusColor;
    IconData statusIcon;

    switch (day.status) {
      case DayStatus.completed:
        statusColor = AppColors.success;
        statusIcon = Icons.check_circle_rounded;
        break;
      case DayStatus.partiallyCompleted:
        statusColor = Colors.amber;
        statusIcon = Icons.remove_circle_outline_rounded;
        break;
      case DayStatus.planned:
        statusColor = Colors.blueAccent;
        statusIcon = Icons.calendar_today_rounded;
        break;
      case DayStatus.missed:
        statusColor = Colors.redAccent;
        statusIcon = Icons.cancel_outlined;
        break;
      case DayStatus.restDay:
        statusColor = AppColors.textMuted;
        statusIcon = Icons.nightlight_round;
        break;
      case DayStatus.noPlan:
        statusColor = AppColors.textMuted;
        statusIcon = Icons.remove_rounded;
        break;
    }

    final hasSession = day.sessions.isNotEmpty;
    final primaryMuscle =
        day.primaryMuscle ??
        (day.status == DayStatus.restDay
            ? 'Rest Day'
            : (day.status == DayStatus.noPlan ? 'Not scheduled' : 'Workout'));
    final secondaryMuscle = day.secondaryMuscle;

    return InkWell(
      onTap: () {
        if (hasSession) {
          _showSessionDetails(day.sessions.first);
        } else if (day.status == DayStatus.planned) {
          _showPlannedDaySheet(day);
        } else if (day.status == DayStatus.missed) {
          _showMissedDaySheet(day);
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: day.isToday ? AppColors.primary : AppColors.border,
            width: day.isToday ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            // Left Day Column
            Container(
              width: 52,
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: day.isToday
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text(
                    day.dayName.toUpperCase(),
                    style: TextStyle(
                      color: day.isToday
                          ? AppColors.primary
                          : AppColors.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    DateFormat('d').format(day.date),
                    style: TextStyle(
                      color: day.isToday
                          ? AppColors.primary
                          : AppColors.textMain,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Middle Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '$primaryMuscle${secondaryMuscle != null ? " + $secondaryMuscle" : ""}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textMain,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (day.isToday) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'TODAY',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 8.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    day.completedExerciseCount > 0
                        ? '${day.completedExerciseCount} exercises completed • ${day.sessions.first.durationSeconds ~/ 60}m'
                        : (hasSession
                              ? 'Session saved with no completed sets'
                              : (day.status == DayStatus.restDay
                                    ? 'Scheduled rest and recovery'
                                    : (day.status == DayStatus.noPlan
                                          ? 'Nothing scheduled'
                                          : '${day.plannedExerciseCount} exercises planned'))),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),

            // Right Status Badge
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.4),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, color: statusColor, size: 12),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        day.statusLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
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
    );
  }

  void _showPlannedDaySheet(DayWorkoutSummary day) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Planned Workout for ${day.dayName}, ${day.dateStr}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${day.primaryMuscle}${day.secondaryMuscle != null ? " + ${day.secondaryMuscle}" : ""}',
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 14),
            if (day.plan?.exercises.isNotEmpty == true)
              ...day.plan!.exercises
                  .take(4)
                  .map(
                    (pe) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.arrow_right,
                            color: AppColors.primary,
                            size: 18,
                          ),
                          Text(
                            pe.exerciseName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${pe.targetSets} × ${pe.targetReps}',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
            else
              const Text(
                'No specific exercises configured.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow_rounded, color: Colors.black),
                label: const Text(
                  'START THIS WORKOUT',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  final res = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ActiveWorkoutScreen(plan: day.plan),
                    ),
                  );
                  if (res == true) _loadAllData();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMissedDaySheet(DayWorkoutSummary day) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Missed Workout: ${day.dateStr}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'This scheduled workout was not completed on the planned date. You can still log the session if you performed it without the app.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.edit_note_rounded, color: Colors.black),
                label: const Text(
                  'LOG COMPLETED SESSION FOR THIS DATE',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _openManualWorkoutDialog();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------- TAB 2: ALL SESSIONS (HISTORY & CALENDAR) -------------------
  Widget _buildAllSessionsView() {
    return Column(
      children: [
        // Filter & View Toggle Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: AppColors.background,
          child: Row(
            children: [
              // Filter Chips Dropdown
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children:
                        [
                          'All Time',
                          'This Week',
                          'Last 7 Days',
                          'This Month',
                          'Last 30 Days',
                          'Custom',
                        ].map((f) {
                          final isSelected = _dateRangeFilter == f;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(
                                f,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: isSelected
                                      ? Colors.black
                                      : AppColors.textSecondary,
                                ),
                              ),
                              selected: isSelected,
                              selectedColor: AppColors.primary,
                              backgroundColor: AppColors.surfaceElevated,
                              side: BorderSide(
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.border,
                              ),
                              onSelected: (val) async {
                                if (f == 'Custom') {
                                  final picked = await showDateRangePicker(
                                    context: context,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime.now(),
                                    builder: (c, child) => Theme(
                                      data: Theme.of(context).copyWith(
                                        colorScheme: const ColorScheme.dark(
                                          primary: AppColors.primary,
                                          onPrimary: Colors.black,
                                          surface: AppColors.surfaceElevated,
                                          onSurface: Colors.white,
                                        ),
                                      ),
                                      child: child!,
                                    ),
                                  );
                                  if (picked != null) {
                                    setState(() {
                                      _customRange = picked;
                                      _dateRangeFilter = 'Custom';
                                      _applyDateRangeFilter();
                                    });
                                  }
                                } else {
                                  setState(() {
                                    _dateRangeFilter = f;
                                    _applyDateRangeFilter();
                                  });
                                }
                              },
                            ),
                          );
                        }).toList(),
                  ),
                ),
              ),

              // Calendar Toggle Button
              IconButton(
                icon: Icon(
                  _isCalendarView
                      ? Icons.view_list_rounded
                      : Icons.calendar_month_rounded,
                  color: AppColors.primary,
                  size: 22,
                ),
                tooltip: _isCalendarView
                    ? 'Switch to List View'
                    : 'Switch to Calendar View',
                onPressed: () {
                  setState(() {
                    _isCalendarView = !_isCalendarView;
                    if (!_isCalendarView) _selectedCalendarDate = null;
                    _applyDateRangeFilter();
                  });
                },
              ),
            ],
          ),
        ),

        // Body: Calendar Grid or Sessions List
        Expanded(
          child: _isCalendarView
              ? _buildCalendarGridView()
              : _buildSessionsListView(),
        ),
      ],
    );
  }

  Widget _buildCalendarGridView() {
    final year = _calendarMonth.year;
    final month = _calendarMonth.month;
    final firstDayOfMonth = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final startWeekday = firstDayOfMonth.weekday; // 1 = Mon, 7 = Sun

    // Set of dates with sessions in this month
    final workoutDates = _allSessions.map((s) => s.date).toSet();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // Month Selector Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              tooltip: 'Previous',
              icon: const Icon(
                Icons.chevron_left_rounded,
                color: AppColors.primary,
              ),
              onPressed: () =>
                  setState(() => _calendarMonth = DateTime(year, month - 1, 1)),
            ),
            Text(
              DateFormat('MMMM yyyy').format(_calendarMonth),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            IconButton(
              tooltip: 'Next',
              icon: const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.primary,
              ),
              onPressed: () =>
                  setState(() => _calendarMonth = DateTime(year, month + 1, 1)),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Day of Week Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
              .map(
                (d) => Text(
                  d,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 8),

        // Grid of Month Days
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: (startWeekday - 1) + daysInMonth,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: 1.1,
          ),
          itemBuilder: (ctx, index) {
            if (index < startWeekday - 1) {
              return const SizedBox.shrink();
            }

            final dayNum = index - (startWeekday - 2);
            final dayDate = DateTime(year, month, dayNum);
            final dateStr = DateFormat('yyyy-MM-dd').format(dayDate);
            final hasWorkout = workoutDates.contains(dateStr);
            final isSelected =
                _selectedCalendarDate != null &&
                DateFormat('yyyy-MM-dd').format(_selectedCalendarDate!) ==
                    dateStr;

            return InkWell(
              onTap: () {
                setState(() {
                  if (isSelected) {
                    _selectedCalendarDate = null;
                  } else {
                    _selectedCalendarDate = dayDate;
                  }
                  _applyDateRangeFilter();
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary
                      : (hasWorkout
                            ? AppColors.surfaceElevated
                            : Colors.transparent),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primary
                        : (hasWorkout
                              ? AppColors.primary.withValues(alpha: 0.5)
                              : AppColors.border),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$dayNum',
                      style: TextStyle(
                        color: isSelected ? Colors.black : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    if (hasWorkout)
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.black : AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),

        // Sessions list for selected date or month
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _selectedCalendarDate != null
                  ? 'SESSIONS ON ${DateFormat('MMM d, yyyy').format(_selectedCalendarDate!)}'
                  : 'SESSIONS THIS MONTH (${_filteredSessions.length})',
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
            if (_selectedCalendarDate != null)
              TextButton(
                onPressed: () {
                  setState(() {
                    _selectedCalendarDate = null;
                    _applyDateRangeFilter();
                  });
                },
                child: const Text(
                  'Show All',
                  style: TextStyle(color: AppColors.primary, fontSize: 11),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),

        if (_filteredSessions.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: const Center(
              child: Text(
                'No workout sessions recorded for this date.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          )
        else
          ..._filteredSessions.map((s) => _buildSessionCard(s)),
      ],
    );
  }

  Widget _buildSessionsListView() {
    if (_filteredSessions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border),
                ),
                child: const Icon(
                  Icons.history_toggle_off_rounded,
                  color: AppColors.primary,
                  size: 44,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'No Workout History Found',
                style: TextStyle(
                  color: AppColors.textMain,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'No sessions recorded matching this filter. Start a workout today or log past sessions to see them here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: const Icon(Icons.add_rounded, color: Colors.black),
                label: const Text(
                  'Log Workout Session',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                onPressed: _openManualWorkoutDialog,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _filteredSessions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) => _buildSessionCard(_filteredSessions[i]),
    );
  }

  Widget _buildSessionCard(WorkoutSession s) {
    final durationMins = s.durationSeconds ~/ 60;
    final isPartial = s.completionStatus == 'Partially Completed';
    final completedSets = s.completedSetsCount;
    final totalSets = s.totalSetsCount;

    return InkWell(
      key: ValueKey('history_session_${s.id}'),
      onTap: () => _showSessionDetails(s),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Date & Status Badge & Duration
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  s.date,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: isPartial
                        ? Colors.amber.withValues(alpha: 0.15)
                        : AppColors.successDark.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    s.completionStatus,
                    style: TextStyle(
                      color: isPartial ? Colors.amber : AppColors.success,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${durationMins}m duration',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Muscles
            Text(
              '${s.primaryMuscle}${s.secondaryMuscle != null ? " + ${s.secondaryMuscle}" : ""}',
              style: const TextStyle(
                color: AppColors.textMain,
                fontSize: 16.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),

            // Sets & Volume Summary
            Row(
              children: [
                Icon(
                  isPartial
                      ? Icons.remove_circle_outline_rounded
                      : Icons.check_circle_rounded,
                  color: isPartial ? Colors.amber : AppColors.success,
                  size: 15,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$completedSets/$totalSets sets logged • ${s.totalVolumeKg.toStringAsFixed(0)} kg vol',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
                const Text(
                  'Details',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.primary,
                  size: 16,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ------------------- TAB 3: MUSCLE GROUP HISTORY -------------------
  Widget _buildMuscleHistoryView() {
    final totalTrainings = _muscleFrequencyStats.values.fold(
      0,
      (a, b) => a + b,
    );

    return CustomScrollView(
      key: const PageStorageKey<String>('history_muscle_scroll'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Time Period Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children:
                        [
                          'All Time',
                          'This Month',
                          'Last 30 Days',
                          'This Week',
                        ].map((period) {
                          final isSel = _muscleFilterPeriod == period;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(
                                period,
                                style: TextStyle(
                                  color: isSel
                                      ? Colors.black
                                      : AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                              selected: isSel,
                              selectedColor: AppColors.primary,
                              backgroundColor: AppColors.surfaceElevated,
                              side: BorderSide(
                                color: isSel
                                    ? AppColors.primary
                                    : AppColors.border,
                              ),
                              onSelected: (val) {
                                setState(() {
                                  _muscleFilterPeriod = period;
                                  _loadMuscleHistoryData();
                                });
                              },
                            ),
                          );
                        }).toList(),
                  ),
                ),
                const SizedBox(height: 16),

                // Frequency Breakdown Progress Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Flexible(
                            child: Text(
                              'MUSCLE TRAINING FREQUENCY',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.1,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '$totalTrainings total hits',
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      ..._muscleFrequencyStats.entries.map((entry) {
                        final muscle = entry.key;
                        final count = entry.value;
                        final fraction = totalTrainings > 0
                            ? count / totalTrainings
                            : 0.0;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Flexible(
                                    child: Text(
                                      muscle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      '$count sessions (${(fraction * 100).toStringAsFixed(0)}%)',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              LinearProgressIndicator(
                                value: fraction,
                                backgroundColor: AppColors.surfaceElevated,
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  AppColors.primary,
                                ),
                                minHeight: 6,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Filter sessions by specific muscle
                const Text(
                  'FILTER BY TARGET MUSCLE',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 8),

                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children:
                        [
                          'All',
                          'Chest',
                          'Back',
                          'Shoulders',
                          'Biceps',
                          'Triceps',
                          'Legs',
                          'Abs',
                          'Full Body',
                        ].map((m) {
                          final isSel = _selectedMuscleCategory == m;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: FilterChip(
                              label: Text(
                                m,
                                style: TextStyle(
                                  color: isSel ? Colors.black : Colors.white,
                                  fontSize: 11.5,
                                ),
                              ),
                              selected: isSel,
                              selectedColor: AppColors.primary,
                              backgroundColor: AppColors.surfaceElevated,
                              side: BorderSide(
                                color: isSel
                                    ? AppColors.primary
                                    : AppColors.border,
                              ),
                              onSelected: (val) {
                                setState(() {
                                  _selectedMuscleCategory = m;
                                  _loadMuscleHistoryData();
                                });
                              },
                            ),
                          );
                        }).toList(),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),

        // Filtered sessions: lazy sliver list (only visible cards are built).
        if (_muscleSessions.isEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            sliver: SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.cardSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Center(
                  child: Text(
                    'No workouts found targeting $_selectedMuscleCategory in this time period.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            sliver: SliverList.separated(
              itemCount: _muscleSessions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (ctx, i) => _buildSessionCard(_muscleSessions[i]),
            ),
          ),
      ],
    );
  }
}
