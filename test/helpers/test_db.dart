import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/data/db_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

bool _ffiReady = false;

/// Opens a fresh in-memory database through the production create/upgrade
/// callbacks and installs it as the app database.
Future<Database> openTestDatabase() async {
  if (!_ffiReady) {
    sqfliteFfiInit();
    _ffiReady = true;
  }
  final db = await DatabaseHelper.instance.openForTesting(
    databaseFactoryFfi,
    inMemoryDatabasePath,
  );
  DatabaseHelper.instance.useDatabaseForTesting(db);
  return db;
}

Future<void> closeTestDatabase(Database db) async {
  DatabaseHelper.instance.useDatabaseForTesting(null);
  await db.close();
}

/// Stubs the native plugins used by media widgets (audio player/recorder,
/// wakelock, video) so widget tests do not hit MissingPluginException.
void mockPlatformPlugins() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const methodChannels = [
    'com.llfbandit.record/messages',
    'xyz.luan/audioplayers',
    'xyz.luan/audioplayers.global',
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
    'flutter.baseflow.com/permissions/methods',
  ];
  for (final name in methodChannels) {
    messenger.setMockMethodCallHandler(
      MethodChannel(name),
      (call) async => null,
    );
  }
  const eventChannels = [
    'xyz.luan/audioplayers.global/events',
    'com.llfbandit.record/events',
    'com.llfbandit.record/eventsRecord',
  ];
  for (final name in eventChannels) {
    messenger.setMockMethodCallHandler(
      MethodChannel(name),
      (call) async => null,
    );
  }
}

/// Ignores MissingPluginException reported by media plugins that have no
/// native side under flutter_test (per-player audio event channels use random
/// ids and cannot be mocked by name). Restores the handler after the test.
void ignoreMissingPluginErrors() {
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exception is MissingPluginException) return;
    original?.call(details);
  };
  addTearDown(() => FlutterError.onError = original);
}

/// Drops the app's database reference without closing it (for tests that
/// already closed the database themselves).
void resetTestDatabaseReference() =>
    DatabaseHelper.instance.useDatabaseForTesting(null);
