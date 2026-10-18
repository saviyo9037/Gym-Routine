import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/theme.dart';
import 'screens/home_screen.dart';
import 'screens/routine_management_screen.dart';
import 'screens/workout_plan_screen.dart';
import 'screens/exercise_library_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/add_edit_exercise_screen.dart';
import 'screens/access_root.dart';
import 'screens/alarm_ringing_screen.dart';
import 'services/alarm_service.dart';
import 'services/cloud_services.dart';
import 'services/app_config_service.dart';
import 'services/routine_service.dart';
import 'widgets/app_config_gate.dart';
import 'services/exercise_media_service.dart';
import 'services/exercise_terminology_service.dart';
import 'data/db_helper.dart';
import 'core/dev_log.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set system status and nav bar colors to match portfolio dark theme
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.background,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Initialize SQLite database instance eagerly
  try {
    await DatabaseHelper.instance.database;
  } catch (e) {
    devLog('Database init error: $e');
  }

  // Initialize Exercise Demonstration Media Service
  try {
    await ExerciseMediaService.instance.initialize();
  } catch (e) {
    devLog('Media service init error: $e');
  }

  // Initialize Exercise Terminology Service
  try {
    await ExerciseTerminologyService.instance.initialize();
  } catch (e) {
    devLog('Terminology service init error: $e');
  }

  // Re-arm every routine alarm from the database (source of truth). Failure
  // must never block app start.
  try {
    await RoutineService().rescheduleAllRoutines();
  } catch (e) {
    devLog('Alarm reschedule error: $e');
  }

  // Optional accounts / subscriptions / sync. Never throws; without cloud
  // configuration the app is exactly the local app.
  try {
    await CloudServices.initialize();
  } catch (e) {
    devLog('Cloud init error: $e');
  }

  // Remote config (maintenance, minimum version, paywall copy, announcements):
  // cached/default values when offline or unconfigured; never blocks start-up.
  try {
    await AppConfigService.configureForApp();
  } catch (e) {
    devLog('App config init error: ${e.runtimeType}');
  }

  CloudServices.installAccessGuard();
  runApp(const RepTrackApp());
}

class RepTrackApp extends StatelessWidget {
  const RepTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RepTrack',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const AppHost(),
    );
  }
}

/// Sits above the access gate so the app-level duties keep working in every
/// state (also while locked): showing a ringing alarm, re-arming alarms from
/// the database on resume, refreshing the subscription and cloud sync.
class AppHost extends StatefulWidget {
  const AppHost({super.key, this.child});

  /// Defaults to the tabbed app; tests pass a stub.
  final Widget? child;

  @override
  State<AppHost> createState() => _AppHostState();
}

class _AppHostState extends State<AppHost> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkTriggeredAlarm();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkTriggeredAlarm();
      CloudServices.onResume();
      final premium = CloudServices.premium;
      if (premium.isLocked || premium.verificationFailed) {
        // Re-check on return (for example the user subscribed or restored
        // elsewhere). Never throws.
        premium.refresh();
      }
      RoutineService().rescheduleAllRoutines().catchError((Object e) {
        devLog('Alarm reschedule error: $e');
      });
    }
  }

  Future<void> _checkTriggeredAlarm() async {
    try {
      final data = await AlarmService().getTriggeredAlarmData();
      if (data != null && data['isRinging'] == true && mounted) {
        final routineId = data['routineId'] as int? ?? 0;
        final title = data['title'] as String? ?? 'Routine';
        final category = data['category'] as String? ?? 'Routine';
        final time = data['time'] as String? ?? 'Now';

        await AlarmService().clearTriggeredAlarmData();
        if (!mounted) return;

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AlarmRingingScreen(
              routineId: routineId,
              title: title,
              category: category,
              scheduledTime: time,
            ),
          ),
        );
      }
    } catch (e) {
      devLog('[AppHost] Error checking triggered alarm: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Maintenance / minimum-version gate outermost, then the access flow:
    // onboarding -> sign in / register -> account checks -> paywall -> app.
    return AppConfigGate(
      child: AccessRoot(child: widget.child ?? const MainNavigationShell()),
    );
  }
}

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentIndex = 0;
  Key _homeKey = UniqueKey();
  Key _routineKey = UniqueKey();
  Key _planKey = UniqueKey();
  Key _historyKey = UniqueKey();

  void _onTabSelected(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  void _refreshAllTabs() {
    setState(() {
      _homeKey = UniqueKey();
      _routineKey = UniqueKey();
      _planKey = UniqueKey();
      _historyKey = UniqueKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(key: _homeKey, onNavigateToTab: _onTabSelected),
      RoutineManagementScreen(
        key: _routineKey,
        onBackToHome: () => _onTabSelected(0),
      ),
      WorkoutPlanScreen(key: _planKey),
      const ExerciseLibraryScreen(),
      HistoryScreen(key: _historyKey),
      SettingsScreen(onResetData: _refreshAllTabs),
    ];

    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _currentIndex != 0) {
          setState(() {
            _currentIndex = 0;
          });
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: IndexedStack(index: _currentIndex, children: screens),
        floatingActionButton: _currentIndex == 2 || _currentIndex == 3
            ? FloatingActionButton(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black,
                elevation: 4,
                shape: const CircleBorder(),
                onPressed: () async {
                  final res = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AddEditExerciseScreen(),
                    ),
                  );
                  if (res == true) _refreshAllTabs();
                },
                child: const Icon(Icons.add, size: 28),
              )
            : null,
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            color: AppColors.cardSurface,
            border: Border(top: BorderSide(color: AppColors.border, width: 1)),
          ),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: _onTabSelected,
            backgroundColor: AppColors.cardSurface,
            selectedItemColor: AppColors.primary,
            unselectedItemColor: AppColors.textSecondary,
            selectedFontSize: 10,
            unselectedFontSize: 10,
            selectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              letterSpacing: 0.2,
            ),
            type: BottomNavigationBarType.fixed,
            elevation: 0,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.home_outlined),
                activeIcon: Icon(Icons.home_rounded),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.schedule_outlined),
                activeIcon: Icon(Icons.alarm_on_rounded),
                label: 'Routine',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.calendar_today_outlined),
                activeIcon: Icon(Icons.calendar_month_rounded),
                label: 'Plan',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.fitness_center_outlined),
                activeIcon: Icon(Icons.fitness_center_rounded),
                label: 'Library',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.history_outlined),
                activeIcon: Icon(Icons.history_rounded),
                label: 'History',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.settings_outlined),
                activeIcon: Icon(Icons.settings_rounded),
                label: 'Settings',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
