import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/core/theme.dart';
import 'package:reptrack/screens/diagnostics_screen.dart';
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

  testWidgets('shows the sections and copies a report without personal data', (
    tester,
  ) async {
    ignoreMissingPluginErrors();
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    db = (await tester.runAsync(openTestDatabase))!;

    final clipboard = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.darkTheme, home: const DiagnosticsScreen()),
    );
    await settle(tester);

    for (final t in [
      'APP',
      'DATABASE',
      'SCHEDULED ALARMS',
      'PERMISSIONS',
      'SYNC',
    ]) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.textContaining('db version'), findsOneWidget);

    await tester.tap(find.text('Copy bug report'));
    await settle(tester);
    expect(clipboard, hasLength(1));
    final report = clipboard.single;
    expect(report, contains('RepTrack diagnostics'));
    expect(report, contains('== Database =='));
    expect(report, isNot(contains('@')), reason: 'no email addresses');

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => closeTestDatabase(db));
  });
}
