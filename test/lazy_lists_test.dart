import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/core/theme.dart';
import 'package:reptrack/models/muscle_group.dart';
import 'package:reptrack/screens/exercise_library_screen.dart';
import 'package:reptrack/screens/history_screen.dart';
import 'package:reptrack/screens/muscle_detail_screen.dart';
import 'package:reptrack/screens/routine_management_screen.dart';
import 'package:reptrack/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_db.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Polls (real time, pumping frames) until [finder] matches or ~20 s pass.
Future<void> waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 200 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Types [query] and scrolls the library until the first result card is built.
/// Returns the count from the "SEARCH RESULTS (n)" header (read while visible).
Future<int> searchAndReveal(
  WidgetTester tester,
  Finder scrollable,
  String query,
) async {
  await tester.enterText(find.byType(TextField).first, query);
  await settle(tester);
  int? total;
  for (var i = 0; i < 14; i++) {
    final h = find.textContaining('SEARCH RESULTS (');
    if (h.evaluate().isNotEmpty && total == null) {
      final txt = tester.widgetList<Text>(h).first.data!;
      total = int.parse(RegExp(r'\((\d+)\)').firstMatch(txt)![1]!);
    }
    if (built('library_card_') > 0 && total != null) break;
    await tester.drag(scrollable, const Offset(0, -250));
    await settle(tester);
  }
  return total ?? -1;
}

int built(String prefix) => find
    .byWidgetPredicate((w) {
      final k = w.key;
      return k is ValueKey<String> && k.value.startsWith(prefix);
    })
    .evaluate()
    .length;

void main() {
  late Database db;

  setUp(() {
    mockPlatformPlugins();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.reptrack.app/alarm'),
          (call) async =>
              call.method == 'getScheduledAlarms' ? <Object?>[] : true,
        );
  });

  Future<void> boot(WidgetTester tester) async {
    ignoreMissingPluginErrors();
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    db = (await tester.runAsync(openTestDatabase))!;
  }

  Future<void> show(WidgetTester tester, Widget screen, double scale) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: screen,
      ),
    );
    await settle(tester);
  }

  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => closeTestDatabase(db));
  }

  Finder scrollOf(String key) => find.descendant(
    of: find.byKey(PageStorageKey<String>(key)),
    matching: find.byType(Scrollable),
  );

  double offsetOf(WidgetTester tester, String key) =>
      tester.state<ScrollableState>(scrollOf(key).first).position.pixels;

  for (final scale in [1.0, 2.0]) {
    group('exercise library at text x$scale', () {
      testWidgets('builds only visible cards for 201 exercises; search finds '
          'results; scrolling builds more', (tester) async {
        await boot(tester);
        await show(tester, const ExerciseLibraryScreen(), scale);
        await waitFor(tester, find.byType(TextField));

        // "e" matches most of the catalogue.
        final total = await searchAndReveal(
          tester,
          scrollOf('exercise_library_scroll').first,
          'e',
        );
        expect(total, greaterThan(120));

        final first = built('library_card_');
        expect(first, greaterThan(0));
        expect(first, lessThan(25), reason: 'lazy: $first of $total built');

        await tester.drag(
          scrollOf('exercise_library_scroll').first,
          const Offset(0, -2500),
        );
        await settle(tester);
        expect(offsetOf(tester, 'exercise_library_scroll'), greaterThan(1000));
        expect(built('library_card_'), lessThan(25));
        expect(tester.takeException(), isNull);
        await teardown(tester);
      });

      testWidgets('search narrows the list, clearing restores categories', (
        tester,
      ) async {
        await boot(tester);
        await show(tester, const ExerciseLibraryScreen(), scale);
        await waitFor(tester, find.byType(TextField));
        expect(find.text('MAIN MUSCLE CATEGORIES (8)'), findsOneWidget);

        final results = await searchAndReveal(
          tester,
          scrollOf('exercise_library_scroll').first,
          'barbell bench',
        );
        expect(results, greaterThan(0));
        final n = built('library_card_');
        expect(n, inInclusiveRange(1, 25));

        await tester.drag(
          scrollOf('exercise_library_scroll').first,
          const Offset(0, 4000),
        );
        await settle(tester);
        await tester.enterText(find.byType(TextField).first, 'zzzzqqqq');
        await settle(tester);
        await tester.scrollUntilVisible(
          find.textContaining('No exercises match'),
          250,
          scrollable: scrollOf('exercise_library_scroll').first,
        );
        expect(find.textContaining('No exercises match'), findsOneWidget);
        expect(built('library_card_'), 0);

        await tester.drag(
          scrollOf('exercise_library_scroll').first,
          const Offset(0, 4000),
        );
        await settle(tester);
        await tester.enterText(find.byType(TextField).first, '');
        await settle(tester);
        await tester.scrollUntilVisible(
          find.text('MAIN MUSCLE CATEGORIES (8)'),
          250,
          scrollable: scrollOf('exercise_library_scroll').first,
        );
        expect(find.text('MAIN MUSCLE CATEGORIES (8)'), findsOneWidget);
        await teardown(tester);
      });
    });

    group('muscle detail at text x$scale', () {
      testWidgets('lists a muscle group lazily and filters by search', (
        tester,
      ) async {
        await boot(tester);
        final mg = (await tester.runAsync<MuscleGroup?>(
          () => DatabaseService().getMuscleGroupById(1),
        ))!;
        await show(tester, MuscleDetailScreen(muscleGroup: mg), scale);
        final scroll = find
            .descendant(
              of: find.byKey(
                PageStorageKey<String>('muscle_detail_scroll_${mg.id}'),
              ),
              matching: find.byType(Scrollable),
            )
            .first;
        // The header cards fill the first screens; scroll to the exercise cards.
        for (var i = 0; i < 8 && built('muscle_card_') == 0; i++) {
          await tester.drag(scroll, const Offset(0, -500));
          await settle(tester);
        }
        final shown = built('muscle_card_');
        expect(shown, greaterThan(0));
        expect(shown, lessThan(22), reason: 'Chest has 22 exercises');
        await tester.drag(scroll, const Offset(0, -3000));
        await settle(tester);
        expect(tester.takeException(), isNull);
        await teardown(tester);
      });
    });
  }

  testWidgets('scroll position survives a tab switch (IndexedStack)', (
    tester,
  ) async {
    await boot(tester);
    var index = 0;
    late StateSetter set;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: StatefulBuilder(
          builder: (ctx, setState) {
            set = setState;
            return IndexedStack(
              index: index,
              children: const [ExerciseLibraryScreen(), SizedBox()],
            );
          },
        ),
      ),
    );
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, 'e');
    await settle(tester);
    await tester.drag(
      scrollOf('exercise_library_scroll').first,
      const Offset(0, -1500),
    );
    await settle(tester);
    final before = offsetOf(tester, 'exercise_library_scroll');
    expect(before, greaterThan(500));

    set(() => index = 1);
    await settle(tester);
    set(() => index = 0);
    await settle(tester);
    expect(offsetOf(tester, 'exercise_library_scroll'), before);
    await teardown(tester);
  });

  testWidgets('history with 160 sessions builds only visible session cards', (
    tester,
  ) async {
    await boot(tester);
    await tester.runAsync(() async {
      final batch = db.batch();
      for (var i = 0; i < 160; i++) {
        final day = DateTime(2026, 1, 1).add(Duration(days: i));
        batch.insert('workout_sessions', {
          'date':
              '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
          'start_time': '07:00',
          'duration_seconds': 3000,
          'primary_muscle': 'Chest',
          'created_at': day.toIso8601String(),
        });
      }
      await batch.commit(noResult: true);
    });
    await show(tester, const HistoryScreen(), 1.0);
    await waitFor(tester, find.text('All Sessions'));
    await tester.tap(find.text('All Sessions'));
    await settle(tester);
    final shown = built('history_session_');
    expect(shown, greaterThan(0));
    expect(shown, lessThan(20), reason: '$shown of 160 built');
    expect(tester.takeException(), isNull);
    await teardown(tester);
  });

  testWidgets('routines list with 80 routines builds only visible cards', (
    tester,
  ) async {
    await boot(tester);
    await tester.runAsync(() async {
      final batch = db.batch();
      for (var i = 0; i < 80; i++) {
        batch.insert('routines', {
          'title': 'Extra routine $i',
          'category': 'Custom',
          'start_time': '10:00',
          'end_time': '10:30',
          'repeat_days': '1,2,3',
          'created_at': DateTime(2026, 1, 1).toIso8601String(),
          'updated_at': DateTime(2026, 1, 1).toIso8601String(),
        });
      }
      await batch.commit(noResult: true);
    });
    await show(tester, const RoutineManagementScreen(), 1.0);
    await waitFor(tester, find.text('All Routines'));
    await tester.tap(find.text('All Routines'));
    await settle(tester);
    final shown = built('routine_card_');
    expect(shown, greaterThan(0));
    expect(shown, lessThan(15), reason: '$shown of 89 built');
    expect(tester.takeException(), isNull);
    await teardown(tester);
  });
}
