import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/routine.dart';
import '../services/routine_service.dart';

class AddEditRoutineScreen extends StatefulWidget {
  final Routine? routine;

  const AddEditRoutineScreen({super.key, this.routine});

  @override
  State<AddEditRoutineScreen> createState() => _AddEditRoutineScreenState();
}

class _AddEditRoutineScreenState extends State<AddEditRoutineScreen> {
  final _formKey = GlobalKey<FormState>();
  final RoutineService _routineService = RoutineService();

  late TextEditingController _titleController;
  late TextEditingController _notesController;
  late TextEditingController _foodDetailsController;

  late RoutineCategory _selectedCategory;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late List<int> _repeatDays;
  late bool _isReminderEnabled;
  late int _reminderMinutesBefore;
  late String _alarmType; // 'alarm' | 'notification' | 'none'
  late String _soundName;
  late bool _isVibrationEnabled;
  late int _snoozeMinutes;
  late bool _isEnabled;

  List<Routine> _existingRoutines = [];
  bool _isSaving = false;

  final List<String> _soundOptions = [
    'Digital Beep',
    'Sunrise Bell',
    'Gym Siren',
    'Energetic Pulse',
    'Gentle Chime',
  ];

  final List<String> _commonFoodSuggestions = [
    'Rice & Dal / Lentils',
    'Boiled Eggs & Banana',
    'Oats & Peanut Butter',
    'Chicken Breast / Paneer',
    'Sprouted Legumes & Nuts',
    'Chapati & Mixed Veggies',
  ];

  @override
  void initState() {
    super.initState();
    final r = widget.routine;

    _titleController = TextEditingController(text: r?.title ?? '');
    _notesController = TextEditingController(text: r?.notes ?? '');
    _foodDetailsController = TextEditingController(text: r?.foodDetails ?? '');

    _selectedCategory = r != null ? r.categoryEnum : RoutineCategory.gym;

    if (r != null) {
      final startParts = r.startTime.split(':');
      final endParts = r.endTime.split(':');
      _startTime = TimeOfDay(
        hour: int.tryParse(startParts[0]) ?? 7,
        minute: int.tryParse(startParts.length > 1 ? startParts[1] : '0') ?? 0,
      );
      _endTime = TimeOfDay(
        hour: int.tryParse(endParts[0]) ?? 8,
        minute: int.tryParse(endParts.length > 1 ? endParts[1] : '30') ?? 0,
      );
      _repeatDays = List<int>.from(r.repeatDays);
      _isReminderEnabled = r.isReminderEnabled;
      _reminderMinutesBefore = r.reminderMinutesBefore;
      _alarmType = r.alarmType;
      _soundName = r.soundName;
      _isVibrationEnabled = r.isVibrationEnabled;
      _snoozeMinutes = r.snoozeMinutes;
      _isEnabled = r.isEnabled;
    } else {
      _startTime = const TimeOfDay(hour: 7, minute: 15);
      _endTime = const TimeOfDay(hour: 8, minute: 30);
      _repeatDays = [1, 2, 3, 4, 5, 6, 7]; // Default every day
      _isReminderEnabled = true;
      _reminderMinutesBefore = 10;
      _alarmType = 'notification';
      _soundName = 'Digital Beep';
      _isVibrationEnabled = true;
      _snoozeMinutes = 10;
      _isEnabled = true;
    }

    _loadExistingRoutines();
  }

  Future<void> _loadExistingRoutines() async {
    final routines = await _routineService.getAllRoutines();
    if (mounted) {
      setState(() => _existingRoutines = routines);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _foodDetailsController.dispose();
    super.dispose();
  }

  String _formatTime(TimeOfDay t) {
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  int _timeToMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

  bool get _isOvernight {
    return _timeToMinutes(_endTime) <= _timeToMinutes(_startTime);
  }

  String get _durationLabel {
    final startM = _timeToMinutes(_startTime);
    final endM = _timeToMinutes(_endTime);
    int totalM;
    if (endM > startM) {
      totalM = endM - startM;
    } else {
      totalM = (24 * 60 - startM) + endM;
    }
    final hours = totalM ~/ 60;
    final mins = totalM % 60;
    if (hours > 0 && mins > 0) return '${hours}h ${mins}m';
    if (hours > 0) return '${hours}h';
    return '${mins}m';
  }

  Routine? get _overlappingRoutine {
    final candidate = Routine(
      id: widget.routine?.id,
      title: _titleController.text.trim(),
      category: _selectedCategory.label,
      startTime: _formatTime(_startTime),
      endTime: _formatTime(_endTime),
      repeatDays: _repeatDays,
    );

    for (final other in _existingRoutines) {
      if (candidate.overlapsWith(other)) {
        return other;
      }
    }
    return null;
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
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
    if (picked != null) {
      setState(() => _startTime = picked);
    }
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
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
    if (picked != null) {
      setState(() => _endTime = picked);
    }
  }

  void _applyPresetDays(List<int> days) {
    setState(() {
      _repeatDays = List<int>.from(days);
    });
  }

  Future<void> _saveRoutine() async {
    if (!_formKey.currentState!.validate()) return;

    if (_repeatDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one repeat day'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final routine = Routine(
        id: widget.routine?.id,
        title: _titleController.text.trim(),
        category: _selectedCategory.label,
        startTime: _formatTime(_startTime),
        endTime: _formatTime(_endTime),
        repeatDays: _repeatDays,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        foodDetails: _foodDetailsController.text.trim().isEmpty ? null : _foodDetailsController.text.trim(),
        isReminderEnabled: _isReminderEnabled,
        reminderMinutesBefore: _reminderMinutesBefore,
        alarmType: _alarmType,
        isAlarmEnabled: _alarmType == 'alarm',
        soundName: _soundName,
        isVibrationEnabled: _isVibrationEnabled,
        snoozeMinutes: _snoozeMinutes,
        isEnabled: _isEnabled,
        colorHex: '#${_selectedCategory.defaultColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
      );

      if (widget.routine == null) {
        await _routineService.insertRoutine(routine);
      } else {
        await _routineService.updateRoutine(routine);
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving routine: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.routine != null;
    const dayNames = {
      1: 'Mon',
      2: 'Tue',
      3: 'Wed',
      4: 'Thu',
      5: 'Fri',
      6: 'Sat',
      7: 'Sun',
    };

    final overlapping = _overlappingRoutine;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          isEditing ? 'Edit Routine' : 'Add Routine',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: _isSaving ? null : _saveRoutine,
              icon: _isSaving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Icon(Icons.check_rounded, size: 18),
              label: Text(isEditing ? 'Save' : 'Create'),
              style: TextButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            children: [
              // Overlap Warning Banner
              if (overlapping != null) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade900.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amberAccent),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.amberAccent, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Schedule Overlap: Coincides with "${overlapping.title}" (${overlapping.formattedTimeRange}) on shared days.',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Routine Title Field
              _buildSectionTitle('ROUTINE TITLE'),
              TextFormField(
                controller: _titleController,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'e.g., Breakfast, Office Work, Gym Workout, Sleep Prep',
                  hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                  filled: true,
                  fillColor: AppColors.cardSurface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter a routine title';
                  }
                  if (val.trim().length < 2) {
                    return 'Title must be at least 2 characters';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 24),

              // Category Selector
              _buildSectionTitle('CATEGORY'),
              Wrap(
                spacing: 8,
                runSpacing: 10,
                children: RoutineCategory.values.map((cat) {
                  final isSelected = _selectedCategory == cat;
                  return ChoiceChip(
                    avatar: Icon(
                      cat.icon,
                      size: 16,
                      color: isSelected ? Colors.black : cat.defaultColor,
                    ),
                    label: Text(cat.label),
                    selected: isSelected,
                    selectedColor: cat.defaultColor,
                    backgroundColor: AppColors.cardSurface,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.black : Colors.white,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      fontSize: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: isSelected ? cat.defaultColor : AppColors.border,
                      ),
                    ),
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedCategory = cat;
                          // If gym or sleep, suggest audible alarm default
                          if (cat == RoutineCategory.gym || cat == RoutineCategory.sleep) {
                            _alarmType = 'alarm';
                          }
                        });
                      }
                    },
                  );
                }).toList(),
              ),

              // Optional Food Details Section (for Meals category)
              if (_selectedCategory == RoutineCategory.meals) ...[
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildSectionTitle('FOOD DETAILS & MEAL NUTRITION'),
                    const Text('Optional & Editable', style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                  ],
                ),
                TextFormField(
                  controller: _foodDetailsController,
                  maxLines: 2,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'e.g., Rice / roti, lentils/dal, boiled eggs, banana, chicken breast...',
                    hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    filled: true,
                    fillColor: AppColors.cardSurface,
                    contentPadding: const EdgeInsets.all(14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _commonFoodSuggestions.map((suggestion) {
                    return ActionChip(
                      label: Text(suggestion, style: const TextStyle(fontSize: 11, color: Colors.white)),
                      backgroundColor: AppColors.surfaceElevated,
                      side: const BorderSide(color: AppColors.border),
                      onPressed: () {
                        setState(() {
                          if (_foodDetailsController.text.trim().isEmpty) {
                            _foodDetailsController.text = suggestion;
                          } else {
                            _foodDetailsController.text += ', $suggestion';
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ],

              // Gym Workout Dinner Recommendation Hint
              if (_selectedCategory == RoutineCategory.gym) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.restaurant_rounded, color: AppColors.primary, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Tip: Dinner will be suggested 15 minutes after gym completion (${_formatTime(_endTime)}).',
                          style: const TextStyle(color: Colors.white, fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Time Selection
              _buildSectionTitle('TIME & DURATION'),
              Row(
                children: [
                  Expanded(
                    child: _buildTimePickerCard(
                      label: 'Start Time',
                      time: _startTime,
                      onTap: _pickStartTime,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildTimePickerCard(
                      label: 'End Time',
                      time: _endTime,
                      onTap: _pickEndTime,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Overnight Banner and Duration Info
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _isOvernight
                      ? const Color(0xFF6C5CE7).withValues(alpha: 0.15)
                      : AppColors.cardSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isOvernight
                        ? const Color(0xFF6C5CE7).withValues(alpha: 0.4)
                        : AppColors.border,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isOvernight ? Icons.nightlight_round : Icons.timelapse_rounded,
                      size: 18,
                      color: _isOvernight ? const Color(0xFFB388FF) : AppColors.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _isOvernight
                            ? 'Overnight Schedule: Crosses midnight into next morning ($_durationLabel)'
                            : 'Total Duration: $_durationLabel',
                        style: TextStyle(
                          color: _isOvernight ? const Color(0xFFB388FF) : AppColors.textMain,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Repeat Days Selector
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildSectionTitle('REPEAT DAYS'),
                  Row(
                    children: [
                      _buildPresetTextBtn('All', () => _applyPresetDays([1, 2, 3, 4, 5, 6, 7])),
                      const SizedBox(width: 8),
                      _buildPresetTextBtn('Weekdays', () => _applyPresetDays([1, 2, 3, 4, 5])),
                      const SizedBox(width: 8),
                      _buildPresetTextBtn('Weekends', () => _applyPresetDays([6, 7])),
                    ],
                  ),
                ],
              ),
              Wrap(
                spacing: 6,
                runSpacing: 8,
                children: dayNames.entries.map((entry) {
                  final isSelected = _repeatDays.contains(entry.key);
                  return FilterChip(
                    label: Text(entry.value),
                    selected: isSelected,
                    selectedColor: AppColors.primary,
                    checkmarkColor: Colors.black,
                    backgroundColor: AppColors.cardSurface,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.black : Colors.white,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      fontSize: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: isSelected ? AppColors.primary : AppColors.border,
                      ),
                    ),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _repeatDays.add(entry.key);
                          _repeatDays.sort();
                        } else {
                          if (_repeatDays.length > 1) {
                            _repeatDays.remove(entry.key);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('At least one day must be selected'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          }
                        }
                      });
                    },
                  );
                }).toList(),
              ),

              const SizedBox(height: 24),

              // Alarm vs Notification Mode Selector
              _buildSectionTitle('ALERT TYPE (ALARM VS NOTIFICATION)'),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.cardSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildAlarmTypeOption(
                            label: 'Audible Alarm',
                            type: 'alarm',
                            icon: Icons.alarm_rounded,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildAlarmTypeOption(
                            label: 'Notification',
                            type: 'notification',
                            icon: Icons.notifications_none_rounded,
                            color: Colors.cyanAccent,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildAlarmTypeOption(
                            label: 'Silent / Off',
                            type: 'none',
                            icon: Icons.notifications_off_rounded,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    if (_alarmType == 'alarm') ...[
                      const Divider(color: AppColors.border, height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Alarm Sound', style: TextStyle(color: Colors.white, fontSize: 13)),
                          DropdownButton<String>(
                            value: _soundName,
                            dropdownColor: AppColors.surfaceElevated,
                            underline: const SizedBox(),
                            style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.bold),
                            items: _soundOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                            onChanged: (val) {
                              if (val != null) setState(() => _soundName = val);
                            },
                          ),
                        ],
                      ),
                      const Divider(color: AppColors.border, height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Vibrate during alarm', style: TextStyle(color: Colors.white, fontSize: 13)),
                          Switch(
                            value: _isVibrationEnabled,
                            activeThumbColor: AppColors.primary,
                            onChanged: (val) => setState(() => _isVibrationEnabled = val),
                          ),
                        ],
                      ),
                      const Divider(color: AppColors.border, height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Snooze Duration', style: TextStyle(color: Colors.white, fontSize: 13)),
                          DropdownButton<int>(
                            value: _snoozeMinutes,
                            dropdownColor: AppColors.surfaceElevated,
                            underline: const SizedBox(),
                            style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.bold),
                            items: const [
                              DropdownMenuItem(value: 5, child: Text('5 minutes')),
                              DropdownMenuItem(value: 10, child: Text('10 minutes')),
                              DropdownMenuItem(value: 15, child: Text('15 minutes')),
                              DropdownMenuItem(value: 20, child: Text('20 minutes')),
                            ],
                            onChanged: (val) {
                              if (val != null) setState(() => _snoozeMinutes = val);
                            },
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Active / Enabled Status
              _buildSectionTitle('STATUS'),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.cardSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Enable Routine',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _isEnabled
                              ? 'Active and scheduled on selected days'
                              : 'Paused — will not appear on daily schedule',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                    Switch(
                      value: _isEnabled,
                      activeThumbColor: AppColors.primary,
                      onChanged: (val) => setState(() => _isEnabled = val),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Notes Input Field
              _buildSectionTitle('OPTIONAL NOTES'),
              TextFormField(
                controller: _notesController,
                maxLines: 3,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Specific cues, focus items, reading pages...',
                  hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  filled: true,
                  fillColor: AppColors.cardSurface,
                  contentPadding: const EdgeInsets.all(14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Bottom Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: const BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _isSaving ? null : _saveRoutine,
                      child: Text(
                        isEditing ? 'Save Changes' : 'Create Routine',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAlarmTypeOption({
    required String label,
    required String type,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = _alarmType == type;

    return InkWell(
      onTap: () => setState(() => _alarmType = type),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.18) : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? color : AppColors.border,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: isSelected ? color : Colors.grey),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSelected ? Colors.white : AppColors.textSecondary,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildTimePickerCard({
    required String label,
    required TimeOfDay time,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.access_time_rounded, color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                Text(
                  _formatTime(time),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetTextBtn(String text, VoidCallback onPressed) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: AppColors.primary,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
