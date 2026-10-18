import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../models/routine.dart';
import '../services/alarm_service.dart';
import '../services/routine_service.dart';
import 'alarm_ringing_screen.dart';

/// "Reminder reliability": shows what Android currently allows, lets the user
/// fix each item in context, lists the alarms that are really scheduled and
/// explains why a phone can still block them. Delivery is never guaranteed.
class AlarmSettingsScreen extends StatefulWidget {
  const AlarmSettingsScreen({super.key});

  @override
  State<AlarmSettingsScreen> createState() => _AlarmSettingsScreenState();
}

class _AlarmSettingsScreenState extends State<AlarmSettingsScreen>
    with WidgetsBindingObserver {
  final AlarmService _alarmService = AlarmService();
  final RoutineService _routineService = RoutineService();

  bool _isLoading = true;
  String? _error;
  AlarmPermissionStatus? _status;
  List<Routine> _routines = [];
  List<ScheduledAlarmInfo> _scheduled = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from a system settings page: show the new state.
    if (state == AppLifecycleState.resumed) _loadData(showSpinner: false);
  }

  Future<void> _loadData({bool showSpinner = true}) async {
    if (showSpinner) setState(() => _isLoading = true);
    try {
      final status = await _alarmService.checkPermissions();
      final routines = await _routineService.getAllRoutines();
      final scheduled = await _alarmService.getScheduledAlarms();
      if (!mounted) return;
      setState(() {
        _status = status;
        _routines = routines;
        _scheduled = scheduled;
        _isLoading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Could not read the alarm status.';
      });
    }
  }

  Future<void> _triggerTestAlarm() async {
    // 10 seconds: enough time to lock the phone and check it really wakes.
    final ok = await _alarmService.testAlarm(
      title: 'RepTrack Test Alarm',
      category: 'Gym',
      delaySeconds: 10,
      isAudible: true,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Test alarm in 10 seconds. Lock your phone to check it wakes the screen.'
              : 'Could not schedule the test alarm.',
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _toggleRoutineAlarm(Routine routine) async {
    if (routine.id == null) return;
    final becomesAlarm = !routine.isAudibleAlarm;
    final updated = routine.copyWith(
      isAlarmEnabled: becomesAlarm,
      alarmType: becomesAlarm ? 'alarm' : 'notification',
    );
    await _routineService.updateRoutine(updated);
    await _loadData(showSpinner: false);
  }

  ScheduledAlarmInfo? _scheduledFor(int? id) {
    for (final s in _scheduled) {
      if (s.routineId == id) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Reminder reliability'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
            tooltip: 'Refresh status',
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!),
                  TextButton(onPressed: _loadData, child: const Text('Retry')),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
              children: [
                _disclaimer(),
                const SizedBox(height: 16),
                _testCard(),
                const SizedBox(height: 22),
                _header('WHAT ANDROID ALLOWS'),
                _permissionsCard(),
                const SizedBox(height: 22),
                _header('NEXT SCHEDULED ALARMS'),
                _scheduledCard(),
                const SizedBox(height: 22),
                _header('PER-ROUTINE ALARM TYPE'),
                _routinesCard(),
                const SizedBox(height: 22),
                _header('IF A REMINDER DID NOT RING'),
                _oemCard(),
              ],
            ),
    );
  }

  Widget _disclaimer() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: const Text(
        'RepTrack uses the Android alarm clock, which is the most reliable '
        'method available. Some phones still stop alarms to save battery, '
        'and Android can delay or block them. We cannot guarantee delivery, '
        'so please do not rely on RepTrack for anything critical.',
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12.5,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _testCard() {
    return Material(
      color: AppColors.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
      ),
      child: ListTile(
        leading: const Icon(Icons.alarm_on_rounded, color: AppColors.primary),
        title: const Text(
          'Test the alarm',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: const Text(
          'Rings in 10 seconds. Lock the phone first to see if it wakes.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        trailing: ElevatedButton(
          onPressed: _triggerTestAlarm,
          child: const Text('Test'),
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const AlarmRingingScreen(
              routineId: 99999,
              title: 'RepTrack Test Alarm',
              category: 'Gym',
              scheduledTime: 'Preview',
              snoozeMinutes: 10,
            ),
          ),
        ),
      ),
    );
  }

  Widget _permissionsCard() {
    final s = _status!;
    return Material(
      color: AppColors.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            _row(
              title: 'Notifications',
              subtitle: 'Needed to show reminders and the alarm controls (Android 13+ asks once).',
              ok: s.notificationsEnabled,
              action: 'Allow',
              onFix: () async {
                await _alarmService.requestNotificationPermission();
                final after = await _alarmService.checkPermissions();
                if (!after.notificationsEnabled) {
                  await _alarmService.openNotificationSettings();
                }
                await _loadData(showSpinner: false);
              },
            ),
            const Divider(color: AppColors.border, height: 20),
            _row(
              title: 'Exact alarms',
              subtitle: 'Lets Android fire reminders at the exact minute instead of batching them.',
              ok: s.canScheduleExactAlarms,
              action: 'Open settings',
              onFix: () async {
                await _alarmService.requestExactAlarmPermission();
              },
            ),
            const Divider(color: AppColors.border, height: 20),
            _row(
              title: 'Full-screen alarms',
              subtitle: 'Wakes the screen and shows the ringing screen over the lock screen.',
              ok: s.canUseFullScreenIntent,
              action: 'Open settings',
              onFix: _alarmService.openFullScreenIntentSettings,
            ),
            const Divider(color: AppColors.border, height: 20),
            _row(
              title: 'Battery optimisation (recommended)',
              subtitle: 'Set RepTrack to "Unrestricted" or "Not optimised" so the phone does not stop it in deep sleep.',
              ok: s.isBatteryOptimizationIgnored,
              action: 'Open battery settings',
              onFix: _alarmService.requestBatteryOptimizationExemption,
              optional: true,
            ),
            const Divider(color: AppColors.border, height: 20),
            _row(
              title: 'Do Not Disturb access (optional)',
              subtitle: 'Alarms use the alarm sound channel; some phones still mute it in Do Not Disturb.',
              ok: s.isDndAccessGranted,
              action: 'Open settings',
              onFix: _alarmService.openDndSettings,
              optional: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _row({
    required String title,
    required String subtitle,
    required bool ok,
    required String action,
    required Future<void> Function() onFix,
    bool optional = false,
  }) {
    return Semantics(
      container: true,
      label: '$title, ${ok ? 'allowed' : 'not allowed'}',
      child: Row(
        children: [
          Icon(
            ok
                ? Icons.check_circle_rounded
                : (optional
                      ? Icons.info_outline_rounded
                      : Icons.error_outline_rounded),
            color: ok
                ? AppColors.success
                : (optional ? AppColors.textMuted : AppColors.warning),
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
                    color: AppColors.textMain,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          if (!ok)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: OutlinedButton(
                onPressed: onFix,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                child: Text(action, textAlign: TextAlign.center),
              ),
            ),
        ],
      ),
    );
  }

  Widget _scheduledCard() {
    final enabled = _routines.where((r) => r.isEnabled).toList();
    final rows = <Widget>[];
    for (final r in enabled) {
      final info = _scheduledFor(r.id);
      final fmt = DateFormat('EEE d MMM, HH:mm');
      final parts = <String>[
        if (info?.nextReminder != null)
          'reminder ${fmt.format(info!.nextReminder!)}',
        if (info?.nextAlarm != null) 'alarm ${fmt.format(info!.nextAlarm!)}',
      ];
      rows.add(
        ListTile(
          dense: true,
          title: Text(
            r.title,
            style: const TextStyle(
              color: AppColors.textMain,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            parts.isEmpty ? 'Nothing scheduled' : parts.join(' • '),
            style: TextStyle(
              color: parts.isEmpty
                  ? AppColors.textMuted
                  : AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
      );
    }
    return Material(
      color: AppColors.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: rows.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No enabled routines yet.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          : Column(children: rows),
    );
  }

  Widget _routinesCard() {
    if (_routines.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Text(
          'Create a routine to choose between an audible alarm and a quiet reminder.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    return Material(
      color: AppColors.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (final routine in _routines)
            SwitchListTile(
              secondary: Icon(
                routine.isAudibleAlarm
                    ? Icons.alarm_rounded
                    : Icons.notifications_none_rounded,
                color: routine.isAudibleAlarm
                    ? AppColors.primary
                    : AppColors.textMuted,
              ),
              activeThumbColor: AppColors.primary,
              title: Text(
                routine.title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '${routine.startTime} • ${routine.isAudibleAlarm ? 'Audible alarm' : 'Quiet reminder'}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              value: routine.isAudibleAlarm,
              onChanged: (_) => _toggleRoutineAlarm(routine),
            ),
        ],
      ),
    );
  }

  Widget _oemCard() {
    final maker = (_status?.manufacturer ?? '').trim();
    return Material(
      color: AppColors.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              maker.isEmpty
                  ? 'Many phone brands add their own battery managers.'
                  : 'Your phone: $maker. Many brands add their own battery managers.',
              style: const TextStyle(
                color: AppColors.textMain,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '• Allow RepTrack to run in the background / auto-start (names '
              'differ: "App launch", "Autostart", "Protected apps").\n'
              '• Set battery use for RepTrack to Unrestricted (or "No restrictions").\n'
              '• Do not swipe RepTrack away if your phone force-stops swiped apps.\n'
              '• Check that Do Not Disturb or a focus mode is not muting alarms.\n'
              '• After a reboot or update RepTrack restores your alarms by itself; '
              'open the app once if a phone blocks that.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _alarmService.requestBatteryOptimizationExemption,
                  icon: const Icon(
                    Icons.battery_charging_full_rounded,
                    size: 18,
                  ),
                  label: const Text('Battery settings'),
                ),
                OutlinedButton.icon(
                  onPressed: _alarmService.openAppSettings,
                  icon: const Icon(Icons.settings_rounded, size: 18),
                  label: const Text('App settings'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
