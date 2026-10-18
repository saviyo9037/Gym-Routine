import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../models/routine.dart';
import '../models/routine_completion.dart';
import '../models/routine_today_item.dart';
import '../screens/add_edit_routine_screen.dart';
import '../services/routine_service.dart';

class RoutineDetailSheet extends StatefulWidget {
  final Routine routine;
  final RoutineTodayItem? todayItem;
  final VoidCallback onDataChanged;

  const RoutineDetailSheet({
    super.key,
    required this.routine,
    this.todayItem,
    required this.onDataChanged,
  });

  static Future<void> show(
    BuildContext context, {
    required Routine routine,
    RoutineTodayItem? todayItem,
    required VoidCallback onDataChanged,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => RoutineDetailSheet(
        routine: routine,
        todayItem: todayItem,
        onDataChanged: onDataChanged,
      ),
    );
  }

  @override
  State<RoutineDetailSheet> createState() => _RoutineDetailSheetState();
}

class _RoutineDetailSheetState extends State<RoutineDetailSheet> {
  final RoutineService _routineService = RoutineService();
  late Routine _currentRoutine;
  List<RoutineCompletion> _history = [];
  bool _isLoadingHistory = true;

  @override
  void initState() {
    super.initState();
    _currentRoutine = widget.routine;
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    if (_currentRoutine.id == null) return;
    setState(() => _isLoadingHistory = true);
    final history = await _routineService.getRoutineCompletionHistory(
      _currentRoutine.id!,
    );
    if (mounted) {
      setState(() {
        _history = history;
        _isLoadingHistory = false;
      });
    }
  }

  Future<void> _toggleCompletion(String status) async {
    if (_currentRoutine.id == null) return;
    final now = DateTime.now();

    // If already in this status, unmark it
    if (widget.todayItem?.completion?.status.toLowerCase() ==
        status.toLowerCase()) {
      await _routineService.removeRoutineCompletion(
        routineId: _currentRoutine.id!,
        date: now,
      );
    } else {
      await _routineService.setRoutineCompletion(
        routineId: _currentRoutine.id!,
        date: now,
        status: status,
      );
    }

    widget.onDataChanged();
    await _loadHistory();
    if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _editRoutine() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddEditRoutineScreen(routine: _currentRoutine),
      ),
    );
    if (result == true) {
      widget.onDataChanged();
      if (_currentRoutine.id != null) {
        final updated = await _routineService.getRoutineById(
          _currentRoutine.id!,
        );
        if (updated != null && mounted) {
          setState(() => _currentRoutine = updated);
          await _loadHistory();
        }
      }
    }
  }

  Future<void> _changeTimeDialog() async {
    final startParts = _currentRoutine.startTime.split(':');
    final endParts = _currentRoutine.endTime.split(':');

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

    if (pickedEnd == null || !mounted || _currentRoutine.id == null) return;

    final newStart =
        '${pickedStart.hour.toString().padLeft(2, '0')}:${pickedStart.minute.toString().padLeft(2, '0')}';
    final newEnd =
        '${pickedEnd.hour.toString().padLeft(2, '0')}:${pickedEnd.minute.toString().padLeft(2, '0')}';

    await _routineService.updateRoutineTime(
      _currentRoutine.id!,
      newStart,
      newEnd,
    );
    final updated = await _routineService.getRoutineById(_currentRoutine.id!);
    if (updated != null && mounted) {
      setState(() => _currentRoutine = updated);
      widget.onDataChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Time updated to $newStart – $newEnd'),
          backgroundColor: AppColors.cardSurface,
        ),
      );
    }
  }

  Future<void> _changeRepeatDaysDialog() async {
    List<int> selectedDays = List<int>.from(_currentRoutine.repeatDays);

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

    if (result != null && _currentRoutine.id != null && mounted) {
      await _routineService.updateRoutineRepeatDays(
        _currentRoutine.id!,
        result,
      );
      final updated = await _routineService.getRoutineById(_currentRoutine.id!);
      if (updated != null && mounted) {
        setState(() => _currentRoutine = updated);
        widget.onDataChanged();
      }
    }
  }

  Future<void> _toggleEnabled() async {
    if (_currentRoutine.id == null) return;
    final newStatus = !_currentRoutine.isEnabled;
    await _routineService.toggleRoutineEnabled(_currentRoutine.id!, newStatus);
    final updated = await _routineService.getRoutineById(_currentRoutine.id!);
    if (updated != null && mounted) {
      setState(() => _currentRoutine = updated);
      widget.onDataChanged();
    }
  }

  Future<void> _deleteRoutine() async {
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
          'Are you sure you want to permanently delete "${_currentRoutine.title}"? This will also remove its logged completions.',
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

    if (confirmed == true && _currentRoutine.id != null && mounted) {
      await _routineService.deleteRoutine(_currentRoutine.id!);
      widget.onDataChanged();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Routine "${_currentRoutine.title}" deleted'),
            backgroundColor: AppColors.cardSurface,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoryColor = _currentRoutine.color;
    final todayStatus = widget.todayItem?.status;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: AppColors.border, width: 1.5)),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: categoryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: categoryColor.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Icon(
                    _currentRoutine.icon,
                    color: categoryColor,
                    size: 26,
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
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: categoryColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _currentRoutine.category.toUpperCase(),
                              style: TextStyle(
                                color: categoryColor,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (!_currentRoutine.isEnabled)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'DISABLED',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _currentRoutine.title,
                        style: const TextStyle(
                          color: AppColors.textMain,
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(
                    Icons.close_rounded,
                    color: AppColors.textSecondary,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const Divider(color: AppColors.border, height: 1),

          // Scrollable body
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Quick Action Bar for Today's Execution
                if (widget.todayItem != null) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "TODAY'S STATUS",
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0,
                              ),
                            ),
                            _buildStatusBadge(
                              todayStatus ?? RoutineCompletionStatus.upcoming,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      todayStatus ==
                                          RoutineCompletionStatus.completed
                                      ? Colors.grey.shade800
                                      : const Color(0xFF00B894),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                ),
                                icon: Icon(
                                  todayStatus ==
                                          RoutineCompletionStatus.completed
                                      ? Icons.undo_rounded
                                      : Icons.check_circle_rounded,
                                  size: 18,
                                ),
                                label: Text(
                                  todayStatus ==
                                          RoutineCompletionStatus.completed
                                      ? 'Unmark'
                                      : 'Mark Done',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                onPressed: () => _toggleCompletion('completed'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor:
                                      todayStatus ==
                                          RoutineCompletionStatus.skipped
                                      ? Colors.white
                                      : Colors.amberAccent,
                                  side: BorderSide(
                                    color:
                                        todayStatus ==
                                            RoutineCompletionStatus.skipped
                                        ? Colors.white38
                                        : Colors.amberAccent.withValues(
                                            alpha: 0.6,
                                          ),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                ),
                                icon: Icon(
                                  todayStatus == RoutineCompletionStatus.skipped
                                      ? Icons.undo_rounded
                                      : Icons.fast_forward_rounded,
                                  size: 18,
                                ),
                                label: Text(
                                  todayStatus == RoutineCompletionStatus.skipped
                                      ? 'Unskip'
                                      : 'Skip Today',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                onPressed: () => _toggleCompletion('skipped'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Schedule details grid
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      _buildDetailRow(
                        icon: Icons.access_time_rounded,
                        label: 'Time Range',
                        value: _currentRoutine.formattedTimeRange,
                        extraWidget: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _currentRoutine.formattedDuration,
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      if (_currentRoutine.isOvernight) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6C5CE7)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(0xFF6C5CE7)
                                  .withValues(alpha: 0.3),
                            ),
                          ),
                          child: const Row(
                            children: [
                              Text('🌙', style: TextStyle(fontSize: 13)),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Overnight schedule (crosses midnight into next morning)',
                                  style: TextStyle(
                                    color: Color(0xFFB388FF),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const Divider(color: AppColors.border, height: 20),
                      _buildDetailRow(
                        icon: Icons.repeat_rounded,
                        label: 'Repeat Schedule',
                        value: _currentRoutine.formattedRepeatDays,
                      ),
                      const Divider(color: AppColors.border, height: 20),
                      _buildDetailRow(
                        icon: Icons.notifications_active_rounded,
                        label: 'Reminders',
                        value: _currentRoutine.isReminderEnabled
                            ? '${_currentRoutine.reminderMinutesBefore} minutes before'
                            : 'Disabled',
                      ),
                      if (_currentRoutine.notes != null &&
                          _currentRoutine.notes!.isNotEmpty) ...[
                        const Divider(color: AppColors.border, height: 20),
                        _buildDetailRow(
                          icon: Icons.notes_rounded,
                          label: 'Notes',
                          value: _currentRoutine.notes!,
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Management Action Chips
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      avatar: const Icon(
                        Icons.edit_rounded,
                        size: 16,
                        color: AppColors.primary,
                      ),
                      label: const Text(
                        'Edit Routine',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      backgroundColor: AppColors.surfaceElevated,
                      side: const BorderSide(color: AppColors.border),
                      onPressed: _editRoutine,
                    ),
                    ActionChip(
                      avatar: const Icon(
                        Icons.schedule_rounded,
                        size: 16,
                        color: Colors.cyanAccent,
                      ),
                      label: const Text(
                        'Change Time',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      backgroundColor: AppColors.surfaceElevated,
                      side: const BorderSide(color: AppColors.border),
                      onPressed: _changeTimeDialog,
                    ),
                    ActionChip(
                      avatar: const Icon(
                        Icons.calendar_month_rounded,
                        size: 16,
                        color: Colors.amberAccent,
                      ),
                      label: const Text(
                        'Change Repeat Days',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      backgroundColor: AppColors.surfaceElevated,
                      side: const BorderSide(color: AppColors.border),
                      onPressed: _changeRepeatDaysDialog,
                    ),
                    ActionChip(
                      avatar: Icon(
                        _currentRoutine.isEnabled
                            ? Icons.pause_circle_outline_rounded
                            : Icons.play_circle_outline_rounded,
                        size: 16,
                        color: _currentRoutine.isEnabled
                            ? Colors.orangeAccent
                            : const Color(0xFF00B894),
                      ),
                      label: Text(
                        _currentRoutine.isEnabled
                            ? 'Disable Routine'
                            : 'Enable Routine',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                      backgroundColor: AppColors.surfaceElevated,
                      side: const BorderSide(color: AppColors.border),
                      onPressed: _toggleEnabled,
                    ),
                    ActionChip(
                      avatar: const Icon(
                        Icons.delete_outline_rounded,
                        size: 16,
                        color: Colors.redAccent,
                      ),
                      label: const Text(
                        'Delete Routine',
                        style: TextStyle(color: Colors.redAccent, fontSize: 12),
                      ),
                      backgroundColor: AppColors.surfaceElevated,
                      side: const BorderSide(color: Colors.redAccent),
                      onPressed: _deleteRoutine,
                    ),
                  ],
                ),

                const SizedBox(height: 22),

                // Completion History Section
                const Text(
                  'COMPLETION HISTORY',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 10),

                if (_isLoadingHistory)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                        strokeWidth: 2,
                      ),
                    ),
                  )
                else if (_history.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Center(
                      child: Text(
                        'No completion history recorded yet.\nMark this routine done as you complete it!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _history.length,
                      separatorBuilder: (_, __) =>
                          const Divider(color: AppColors.border, height: 1),
                      itemBuilder: (context, index) {
                        final comp = _history[index];
                        final isDone = comp.isCompleted;
                        DateTime? parsedDate;
                        try {
                          parsedDate = DateTime.parse(comp.date);
                        } catch (_) {}
                        final formattedDate = parsedDate != null
                            ? DateFormat('EEE, MMM d, yyyy').format(parsedDate)
                            : comp.date;

                        return ListTile(
                          dense: true,
                          leading: Icon(
                            isDone
                                ? Icons.check_circle_rounded
                                : Icons.fast_forward_rounded,
                            color: isDone
                                ? const Color(0xFF00B894)
                                : Colors.amberAccent,
                            size: 20,
                          ),
                          title: Text(
                            formattedDate,
                            style: const TextStyle(
                              color: AppColors.textMain,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  (isDone
                                          ? const Color(0xFF00B894)
                                          : Colors.amberAccent)
                                      .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isDone ? 'Completed' : 'Skipped',
                              style: TextStyle(
                                color: isDone
                                    ? const Color(0xFF00B894)
                                    : Colors.amberAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                const SizedBox(height: 30),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    Widget? extraWidget,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.textMain,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        ?extraWidget,
      ],
    );
  }

  Widget _buildStatusBadge(RoutineCompletionStatus status) {
    Color bg;
    Color fg;
    String text;

    switch (status) {
      case RoutineCompletionStatus.completed:
        bg = const Color(0xFF00B894).withValues(alpha: 0.2);
        fg = const Color(0xFF00B894);
        text = 'Completed';
        break;
      case RoutineCompletionStatus.skipped:
        bg = Colors.amberAccent.withValues(alpha: 0.2);
        fg = Colors.amberAccent;
        text = 'Skipped';
        break;
      case RoutineCompletionStatus.inProgress:
        bg = AppColors.primary.withValues(alpha: 0.2);
        fg = AppColors.primary;
        text = 'In Progress';
        break;
      case RoutineCompletionStatus.upcoming:
        bg = Colors.grey.withValues(alpha: 0.2);
        fg = Colors.grey.shade400;
        text = 'Upcoming';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: fg.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}
