import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/core/theme.dart';
import 'package:reptrack/services/backup_service.dart';
import 'package:reptrack/widgets/backup_import_dialog.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_db.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late Database db;

  setUp(mockPlatformPlugins);

  Future<(BackupFile, bool?)> pumpFlow(
    WidgetTester tester,
    Future<void> Function() act,
  ) async {
    ignoreMissingPluginErrors();
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    db = (await tester.runAsync(openTestDatabase))!;
    final svc = BackupService();
    // A backup that differs from the live data: delete a routine afterwards.
    final json = (await tester.runAsync(svc.exportJson))!;
    final file = svc.parse(json);
    await tester.runAsync(() => db.delete('routines', where: 'id = 1'));

    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async =>
                    result = await BackupImportFlow.run(ctx, file),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await settle(tester);
    await act();
    return (file, result);
  }

  testWidgets('cancel imports nothing', (tester) async {
    await pumpFlow(tester, () async {
      expect(find.text('Import backup'), findsOneWidget);
      expect(find.textContaining('Nothing is deleted'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
    });
    final n = (await tester.runAsync(
      () => db.query('routines', where: 'id = 1'),
    ))!;
    expect(n, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => closeTestDatabase(db));
  });

  testWidgets('merge restores the missing row and deletes nothing', (
    tester,
  ) async {
    await pumpFlow(tester, () async {
      await tester.tap(find.text('Merge'));
      await settle(tester);
    });
    // Ids are remapped by the merge, so compare by content, not by id.
    final titles = (await tester.runAsync(() => db.query('routines')))!
        .map((r) => r['title'])
        .toList();
    expect(titles.length, 9);
    expect(titles, contains('Wake up & Morning Preparation'));
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => closeTestDatabase(db));
  });

  testWidgets('replace needs a second confirmation', (tester) async {
    await pumpFlow(tester, () async {
      await tester.tap(find.text('Replace…'));
      await settle(tester);
      expect(find.text('Replace all data?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
    });
    final n = (await tester.runAsync(
      () => db.query('routines', where: 'id = 1'),
    ))!;
    expect(n, isEmpty, reason: 'cancelled at the second prompt: untouched');
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => closeTestDatabase(db));
  });
}
