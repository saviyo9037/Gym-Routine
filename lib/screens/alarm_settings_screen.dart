import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/routine.dart';
import '../services/alarm_service.dart';
import '../services/routine_service.dart';
import 'alarm_ringing_screen.dart';

class AlarmSettingsScreen extends StatefulWidget {
  const AlarmSettingsScreen({super.key});

  @override
  State<AlarmSettingsScreen> createState() => _AlarmSettingsScreenState();
}

class _AlarmSettingsScreenState extends State<AlarmSettingsScreen> {
  final AlarmService _alarmService = AlarmService();
  final RoutineService _routineService = RoutineService();

  bool _isLoading = true;
  bool _masterAlarmEnabled = true;
  String _defaultSound = 'Digital Beep';
  bool _defaultVibration = true;
  int _defaultSnooze = 10;

  AlarmPermissionStatus? _permissionStatus;
  List<Routine> _routines = [];

  final List<String> _soundOptions = [
    'Digital Beep',
    'Sunrise Bell',
    'Gym Siren',
    'Energetic Pulse',
    'Gentle Chime',
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final status = await _alarmService.checkPermissions();
    final allRoutines = await _routineService.getAllRoutines();

    if (mounted) {
      setState(() {
        _permissionStatus = status;
        _routines = allRoutines;
        _isLoading = false;
      });
    }
  }

  Future<void> _triggerTestAlarm() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Triggering real test alarm in 2 seconds...'),
        backgroundColor: AppColors.primary,
        duration: Duration(seconds: 2),
      ),
    );

    await _alarmService.testAlarm(
      title: 'RepTrack Test Alarm',
      category: 'Gym',
      delaySeconds: 2,
      isAudible: true,
    );

    // Also navigate directly to alarm ringing screen after 2 seconds to demo live UI
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const AlarmRingingScreen(
            routineId: 99999,
            title: 'RepTrack Test Alarm',
            category: 'Gym',
            scheduledTime: 'Now',
            snoozeMinutes: 10,
          ),
        ),
      );
    }
  }

  Future<void> _toggleRoutineAlarm(Routine routine) async {
    if (routine.id == null) return;
    final updated = routine.copyWith(
      isAlarmEnabled: !routine.isAlarmEnabled,
      alarmType: !routine.isAlarmEnabled ? 'alarm' : 'notification',
    );
    await _routineService.updateRoutine(updated);
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Alarm Settings',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
            tooltip: 'Refresh Status',
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              children: [
                // Live Test Alarm Action Banner
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary.withValues(alpha: 0.2),
                        AppColors.cardSurface,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.alarm_on_rounded,
                          color: Colors.black,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Test Real Alarm Engine',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Wakes screen, rings audio alarm stream, and vibrates.',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: _triggerTestAlarm,
                        child: const Text(
                          'Test',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 22),

                // Android Permissions & System Checklist
                _buildSectionHeader('ANDROID SYSTEM & PERMISSION STATUS'),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      _buildChecklistRow(
                        title: 'Exact Alarm Scheduling',
                        subtitle: 'Allows triggering at exact minute without Android Doze delay',
                        isGranted:
                            _permissionStatus?.canScheduleExactAlarms ?? true,
                        onFix: () async {
                          await _alarmService.requestExactAlarmPermission();
                          await _loadData();
                        },
                      ),
                      const Divider(color: AppColors.border, height: 20),
                      _buildChecklistRow(
                        title: 'Notification Permission',
                        subtitle: 'Displays high-priority full-screen banner and controls',
                        isGranted:
                            _permissionStatus?.notificationsEnabled ?? true,
                        onFix: _loadData,
                      ),
                      const Divider(color: AppColors.border, height: 20),
                      _buildChecklistRow(
                        title: 'Battery Optimization Exemption',
                        subtitle: 'Prevents Android system from killing alarms during deep sleep',
                        isGranted:
                            _permissionStatus?.isBatteryOptimizationIgnored ??
                            false,
                        onFix: () async {
                          await _alarmService
                              .requestBatteryOptimizationExemption();
                          await _loadData();
                        },
                      ),
                      const Divider(color: AppColors.border, height: 20),
                      _buildChecklistRow(
                        title: 'Silent & Do Not Disturb (DND) Access',
                        subtitle: 'Alarms use Android USAGE_ALARM stream to bypass standard silent mode',
                        isGranted:
                            _permissionStatus?.isDndAccessGranted ?? false,
                        onFix: () async {
                          await _alarmService.openDndSettings();
                          await _loadData();
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 22),

                // Master Alarm Settings
                _buildSectionHeader('GLOBAL ALARM CONFIGURATION'),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Master Alarm System',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Enable audible alarms across all routines',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                          Switch(
                            value: _masterAlarmEnabled,
                            activeThumbColor: AppColors.primary,
                            onChanged: (val) {
                              setState(() => _masterAlarmEnabled = val);
                            },
                          ),
                        ],
                      ),
                      const Divider(color: AppColors.border, height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Default Alarm Sound',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          DropdownButton<String>(
                            value: _defaultSound,
                            dropdownColor: AppColors.surfaceElevated,
                            underline: const SizedBox(),
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                            items: _soundOptions.map((s) {
                              return DropdownMenuItem(value: s, child: Text(s));
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _defaultSound = val);
                              }
                            },
                          ),
                        ],
                      ),
                      const Divider(color: AppColors.border, height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Vibration on Alarm',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Switch(
                            value: _defaultVibration,
                            activeThumbColor: AppColors.primary,
                            onChanged: (val) =>
                                setState(() => _defaultVibration = val),
                          ),
                        ],
                      ),
                      const Divider(color: AppColors.border, height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Default Snooze Duration',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          DropdownButton<int>(
                            value: _defaultSnooze,
                            dropdownColor: AppColors.surfaceElevated,
                            underline: const SizedBox(),
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 5,
                                child: Text('5 minutes'),
                              ),
                              DropdownMenuItem(
                                value: 10,
                                child: Text('10 minutes'),
                              ),
                              DropdownMenuItem(
                                value: 15,
                                child: Text('15 minutes'),
                              ),
                              DropdownMenuItem(
                                value: 20,
                                child: Text('20 minutes'),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _defaultSnooze = val);
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 22),

                // Per-Routine Alarm Toggles
                _buildSectionHeader('PER-ROUTINE ALARM / NOTIFICATION TYPE'),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _routines.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: AppColors.border, height: 1),
                    itemBuilder: (context, index) {
                      final routine = _routines[index];
                      final isAlarm = routine.isAudibleAlarm;

                      return ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: routine.color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            isAlarm
                                ? Icons.alarm_rounded
                                : Icons.notifications_none_rounded,
                            color: isAlarm ? AppColors.primary : Colors.grey,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          routine.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          '${routine.startTime} • ${isAlarm ? "Audible Alarm" : "Standard Notification"}',
                          style: TextStyle(
                            color: isAlarm
                                ? AppColors.primary
                                : AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                        trailing: Switch(
                          value: isAlarm,
                          activeThumbColor: AppColors.primary,
                          onChanged: (_) => _toggleRoutineAlarm(routine),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 40),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
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

  Widget _buildChecklistRow({
    required String title,
    required String subtitle,
    required bool isGranted,
    required VoidCallback onFix,
  }) {
    return Row(
      children: [
        Icon(
          isGranted ? Icons.check_circle_rounded : Icons.error_outline_rounded,
          color: isGranted ? const Color(0xFF00B894) : Colors.orangeAccent,
          size: 22,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        if (!isGranted)
          TextButton(
            onPressed: onFix,
            child: const Text(
              'Fix',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }
}
