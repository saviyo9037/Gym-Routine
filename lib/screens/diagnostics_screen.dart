import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/access_config.dart';
import '../core/app_info.dart';
import '../core/clock.dart';
import '../core/media_config.dart';
import '../data/db_helper.dart';
import '../services/alarm_service.dart';
import '../services/cloud_config.dart';
import '../services/cloud_services.dart';
import '../services/mock_billing.dart';

/// DEBUG-ONLY diagnostics. Not reachable in release builds: the Settings entry
/// is behind `kDebugMode` and [build] renders nothing when it is false.
/// The copied bug report contains counts, versions and states only - never
/// emails, tokens, workout contents or routine names.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  static const _countTables = [
    'exercises',
    'muscle_groups',
    'workout_plans',
    'planned_exercises',
    'workout_sessions',
    'workout_sets',
    'routines',
    'routine_completions',
    'training_plans',
    'training_plan_days',
    'training_plan_day_exercises',
    'media_attachments',
    'active_sessions',
    'sync_tombstones',
    'sync_conflicts',
  ];

  Map<String, String> _sections = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _collect();
  }

  Future<String> _guard(Future<String> Function() body) async {
    try {
      return await body();
    } catch (e) {
      return 'unavailable (${e.runtimeType})';
    }
  }

  Future<void> _collect() async {
    final out = <String, String>{};

    out['App'] = [
      'version: $kAppVersion',
      'mode: ${kDebugMode ? 'debug' : 'release'}',
      'bundled videos enabled: $kBundledVideosEnabled',
      'now: ${AppClock.now().toIso8601String()}',
    ].join('\n');

    out['Database'] = await _guard(() async {
      final db = await DatabaseHelper.instance.database;
      final v = await db.rawQuery('PRAGMA user_version');
      final lines = <String>[
        'db version: ${v.first.values.first} (code expects ${DatabaseHelper.schemaVersion})',
      ];
      for (final t in _countTables) {
        try {
          final r = await db.rawQuery('SELECT COUNT(*) AS c FROM $t');
          lines.add('$t: ${r.first['c']}');
        } catch (_) {
          lines.add('$t: (missing)');
        }
      }
      return lines.join('\n');
    });

    out['Scheduled alarms'] = await _guard(() async {
      final list = await AlarmService().getScheduledAlarms();
      if (list.isEmpty) return 'none';
      final f = DateFormat('EEE d MMM HH:mm');
      return list
          .map(
            (a) =>
                '#${a.routineId}: alarm ${a.nextAlarm == null ? '-' : f.format(a.nextAlarm!)}'
                ' | reminder ${a.nextReminder == null ? '-' : f.format(a.nextReminder!)}',
          )
          .join('\n');
    });

    out['Permissions'] = await _guard(() async {
      final s = await AlarmService().checkPermissions();
      return [
        'notifications: ${s.notificationsEnabled}',
        'exact alarms: ${s.canScheduleExactAlarms}',
        'full-screen intent: ${s.canUseFullScreenIntent}',
        'battery optimisation ignored: ${s.isBatteryOptimizationIgnored}',
        'DND access: ${s.isDndAccessGranted}',
        'manufacturer: ${s.manufacturer}',
      ].join('\n');
    });

    out['Sync'] = await _guard(() async {
      final sync = CloudServices.sync;
      final pending = await sync.pendingChanges();
      return [
        'state: ${sync.state.name}',
        'queue (dirty rows + tombstones): $pending',
        'last synced: ${sync.lastSyncedAt?.toIso8601String() ?? 'never'}',
        'last error: ${sync.lastError == null ? 'none' : 'yes (see app logs)'}',
      ].join('\n');
    });

    out['Cloud / subscription'] = await _guard(() async {
      final p = CloudServices.premium;
      return [
        'supabase configured: ${CloudConfig.supabaseConfigured}',
        'revenuecat configured: ${CloudConfig.revenueCatConfigured}',
        'google configured: ${CloudConfig.googleConfigured}',
        'signed in: ${CloudServices.auth.isSignedIn}',
        'store available: ${p.storeAvailable}',
        'mock billing: ${MockBilling.enabled}',
        'entitlement state: ${p.entitlementState.name}',
        'access tier: ${p.tier.name}',
        'trial videos locked: ${AccessConfig.trialVideosLocked}',
        'videos allowed: ${p.videosAllowed}',
        'premium: ${p.isPremium}',
      ].join('\n');
    });

    if (!mounted) return;
    setState(() {
      _sections = out;
      _loading = false;
    });
  }

  String get _report {
    final b = StringBuffer('RepTrack diagnostics\n');
    _sections.forEach((k, v) => b.write('\n== $k ==\n$v\n'));
    return b.toString();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _report));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bug report copied to the clipboard')),
    );
  }

  /// Force an entitlement state (only exists with MOCK_BILLING=true).
  Widget _mockBillingCard() {
    final mock = CloudServices.premium.mock!;
    return Container(
      key: const ValueKey('mock_billing_card'),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFF8A00)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'MOCK BILLING (TEST MODE, no real payment)',
            style: TextStyle(
              color: Color(0xFFFF8A00),
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'current: ${mock.state.label} | tier: '
            '${CloudServices.premium.tier.name}',
            key: const ValueKey('mock_tier_line'),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in MockBillingState.values)
                OutlinedButton(
                  key: ValueKey('mock_state_${s.name}'),
                  onPressed: () async {
                    await mock.setState(s);
                    await Future<void>.delayed(Duration.zero);
                    if (mounted) _collect();
                  },
                  child: Text(s.label),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics (debug only)'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              setState(() => _loading = true);
              _collect();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                ElevatedButton.icon(
                  onPressed: _copy,
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Copy bug report'),
                ),
                const SizedBox(height: 12),
                if (CloudServices.premium.mock != null) _mockBillingCard(),
                for (final e in _sections.entries) ...[
                  Text(
                    e.key.toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xFFFF8A00),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141414),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SelectableText(
                      e.value,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
              ],
            ),
    );
  }
}
