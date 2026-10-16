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
import 'screens/alarm_ringing_screen.dart';
import 'services/alarm_service.dart';
import 'services/exercise_media_service.dart';
import 'data/db_helper.dart';

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
    debugPrint('Database init error: $e');
  }

  // Initialize Exercise Demonstration Media Service
  try {
    await ExerciseMediaService.instance.initialize();
  } catch (e) {
    debugPrint('Media service init error: $e');
  }

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
      home: const MainNavigationShell(),
    );
  }
}

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell>
    with WidgetsBindingObserver {
  int _currentIndex = 0;
  Key _homeKey = UniqueKey();
  Key _routineKey = UniqueKey();
  Key _planKey = UniqueKey();
  Key _historyKey = UniqueKey();

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
      debugPrint('[MainNavigationShell] Error checking triggered alarm: $e');
    }
  }

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
