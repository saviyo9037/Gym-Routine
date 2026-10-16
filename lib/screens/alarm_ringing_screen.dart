import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/routine.dart';
import '../services/alarm_service.dart';
import 'active_workout_screen.dart';

class AlarmRingingScreen extends StatefulWidget {
  final int routineId;
  final String title;
  final String category;
  final String scheduledTime;
  final int snoozeMinutes;

  const AlarmRingingScreen({
    super.key,
    required this.routineId,
    required this.title,
    this.category = 'Routine',
    this.scheduledTime = '',
    this.snoozeMinutes = 10,
  });

  @override
  State<AlarmRingingScreen> createState() => _AlarmRingingScreenState();
}

class _AlarmRingingScreenState extends State<AlarmRingingScreen>
    with SingleTickerProviderStateMixin {
  final AlarmService _alarmService = AlarmService();
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _stopAlarm() async {
    await _alarmService.stopAlarm();
    await _alarmService.clearTriggeredAlarmData();
    if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _snoozeAlarm() async {
    await _alarmService.snoozeAlarm(
      widget.routineId,
      snoozeMinutes: widget.snoozeMinutes,
      title: widget.title,
    );
    await _alarmService.clearTriggeredAlarmData();
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Alarm snoozed for ${widget.snoozeMinutes} minutes'),
          backgroundColor: AppColors.cardSurface,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoryEnum = RoutineCategory.fromString(widget.category);
    final isGym = categoryEnum == RoutineCategory.gym;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _stopAlarm();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top header tag
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.alarm_on_rounded, size: 16, color: AppColors.primary),
                      SizedBox(width: 8),
                      Text(
                        'ROUTINE ALARM ACTIVE',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),

                // Center visual animation & routine details
                Column(
                  children: [
                    ScaleTransition(
                      scale: _pulseAnimation,
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary.withValues(alpha: 0.12),
                          border: Border.all(color: AppColors.primary, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.4),
                              blurRadius: 36,
                              spreadRadius: 8,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            categoryEnum.icon,
                            color: AppColors.primary,
                            size: 64,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 36),
                    Text(
                      widget.scheduledTime.isNotEmpty ? widget.scheduledTime : 'Scheduled Time',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: categoryEnum.defaultColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        widget.category.toUpperCase(),
                        style: TextStyle(
                          color: categoryEnum.defaultColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),

                // Bottom actions (Stop / Snooze / Gym Workout Link)
                Column(
                  children: [
                    if (isGym) ...[
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary, width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          minimumSize: const Size.fromHeight(50),
                        ),
                        icon: const Icon(Icons.fitness_center_rounded, size: 20),
                        label: const Text(
                          'Open Today\'s Workout Session',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        onPressed: () async {
                          await _stopAlarm();
                          if (context.mounted) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ActiveWorkoutScreen(),
                              ),
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                    ],

                    Row(
                      children: [
                        // Snooze Button
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: AppColors.border),
                              backgroundColor: AppColors.surfaceElevated,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            icon: const Icon(Icons.snooze_rounded, size: 20),
                            label: Text(
                              'Snooze (${widget.snoozeMinutes}m)',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                            ),
                            onPressed: _snoozeAlarm,
                          ),
                        ),
                        const SizedBox(width: 14),
                        // Stop Alarm Button
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              elevation: 6,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            icon: const Icon(Icons.stop_circle_rounded, size: 22),
                            label: const Text(
                              'STOP ALARM',
                              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 0.5),
                            ),
                            onPressed: _stopAlarm,
                          ),
                        ),
                      ],
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
}
