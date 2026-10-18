import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/core/access_config.dart';
import 'package:reptrack/core/app_info.dart';
import 'package:reptrack/core/theme.dart';
import 'package:reptrack/screens/announcement_banner.dart';
import 'package:reptrack/services/app_config_service.dart';
import 'package:reptrack/services/premium_service.dart';
import 'package:reptrack/widgets/app_config_gate.dart';

// MOCK-ONLY where a fake remote / fake clock is used: nothing here talks to a
// real Supabase. The parser tests are pure.

class FakeRemote implements AppConfigRemote {
  FakeRemote({this.config, this.announcements = const []});
  Map<String, dynamic>? config;
  List<dynamic> announcements;
  bool available = true;
  bool fail = false;
  bool hang = false;
  int configCalls = 0;

  @override
  bool get isAvailable => available;

  @override
  Future<Map<String, dynamic>?> fetchConfig() async {
    configCalls++;
    if (hang) return Completer<Map<String, dynamic>?>().future;
    if (fail) throw Exception('offline');
    return config;
  }

  @override
  Future<List<dynamic>> fetchAnnouncements() async {
    if (fail) throw Exception('offline');
    return announcements;
  }
}

final _t0 = DateTime.utc(2026, 10, 20, 12);

Map<String, dynamic> goodConfig() => {
  'paywall_title': 'Train smarter',
  'paywall_subtitle': 'Plan, log, repeat.',
  'paywall_benefits': ['Weekly plans', 'Offline first'],
  'plan_badges': {'yearly': 'Best value'},
  'promo_text': 'Launch week',
  'maintenance_mode': false,
  'maintenance_message': null,
  'min_app_version': '1.0.0',
  'access_model_override': null,
};

Map<String, dynamic> ann(
  String id, {
  String level = 'info',
  DateTime? starts,
  DateTime? ends,
}) => {
  'id': id,
  'title': 'Title $id',
  'body': 'Body $id',
  'level': level,
  'starts_at': (starts ?? _t0.subtract(const Duration(days: 1)))
      .toIso8601String(),
  'ends_at': ends?.toIso8601String(),
};

void main() {
  tearDown(() {
    AccessConfig.setRemote(null);
    AccessConfig.debugOverride = null;
  });

  group('AppConfig.parse (pure)', () {
    test('valid config is accepted field by field', () {
      final c = AppConfig.parse(goodConfig());
      expect(c.paywallTitle, 'Train smarter');
      expect(c.paywallSubtitle, 'Plan, log, repeat.');
      expect(c.benefits, ['Weekly plans', 'Offline first']);
      expect(c.badgeYearly, 'Best value');
      expect(c.badgeMonthly, isNull);
      expect(c.promoText, 'Launch week');
      expect(c.maintenanceMode, isFalse);
      expect(c.minAppVersion, '1.0.0');
      expect(c.accessModelOverride, isNull);
    });

    test('null, wrong types and empty input give the defaults', () {
      for (final bad in <Object?>[
        null,
        5,
        'x',
        '[]',
        [],
        <String, Object?>{},
        true,
      ]) {
        expect(AppConfig.parse(bad), AppConfig.defaults, reason: '$bad');
      }
      expect(AppConfig.parse('{not json'), AppConfig.defaults);
    });

    test('over-long, empty, markup and control-character strings fall back to default', () {
      final c = AppConfig.parse({
        'paywall_title': 'x' * 81,
        'paywall_subtitle': '   ',
        'promo_text': '<b>buy now</b>',
        'maintenance_message': 'line\u0000break',
        'plan_badges': {'monthly': 'y' * 25, 'yearly': '<i>x</i>'},
      });
      expect(c.paywallTitle, isNull);
      expect(c.paywallSubtitle, isNull);
      expect(c.promoText, isNull);
      expect(c.maintenanceMessage, isNull);
      expect(c.badgeMonthly, isNull);
      expect(c.badgeYearly, isNull);
    });

    test('benefits: non-list ignored, invalid lines dropped, capped at 8, 120 chars', () {
      expect(
        AppConfig.parse({'paywall_benefits': 'a string'}).benefits,
        isEmpty,
      );
      expect(
        AppConfig.parse({
          'paywall_benefits': {'a': 1},
        }).benefits,
        isEmpty,
      );
      final c = AppConfig.parse({
        'paywall_benefits': [
          1,
          null,
          '',
          'ok',
          '<script>',
          'z' * 121,
          ...List.generate(20, (i) => 'line $i'),
        ],
      });
      expect(c.benefits.length, 8);
      expect(c.benefits.first, 'ok');
      expect(
        c.benefits.every((b) => !b.contains('<') && b.length <= 120),
        isTrue,
      );
    });

    test('badges: only monthly and yearly are read', () {
      final c = AppConfig.parse({
        'plan_badges': {'weekly': 'Hot', 'monthly': 'Flexible'},
      });
      expect(c.badgeMonthly, 'Flexible');
      expect(c.badgeYearly, isNull);
      expect(AppConfig.parse({'plan_badges': 'x'}).badgeMonthly, isNull);
    });

    test('min version must be semver, otherwise it is ignored', () {
      for (final v in [
        '1.2',
        'v1.2.3',
        'latest',
        '1.2.3-beta',
        '99999.0.0',
        5,
        '',
      ]) {
        expect(
          AppConfig.parse({'min_app_version': v}).minAppVersion,
          isNull,
          reason: '$v',
        );
      }
      expect(
        AppConfig.parse({'min_app_version': '2.0.1+7'}).minAppVersion,
        '2.0.1+7',
      );
    });

    test('maintenance_mode is true only for the literal boolean true', () {
      for (final v in <Object?>['true', 1, 'yes', null, 'TRUE']) {
        expect(
          AppConfig.parse({'maintenance_mode': v}).maintenanceMode,
          isFalse,
          reason: '$v',
        );
      }
      final on = AppConfig.parse({'maintenance_mode': true});
      expect(on.maintenanceMode, isTrue);
      expect(
        on.effectiveMaintenanceMessage,
        AppConfig.defaultMaintenanceMessage,
      );
    });

    test('access model override: known values, null = none, anything else FAILS CLOSED', () {
      expect(
        AppConfig.parse({'access_model_override': 'freemium'})
            .accessModelOverride,
        AccessModel.freemium,
      );
      expect(
        AppConfig.parse({'access_model_override': 'subscription_required'})
            .accessModelOverride,
        AccessModel.subscriptionRequired,
      );
      expect(
        AppConfig.parse({'access_model_override': null}).accessModelOverride,
        isNull,
      );
      for (final v in <Object?>['free', 'FREEMIUM', 5, true, '']) {
        expect(
          AppConfig.parse({'access_model_override': v}).accessModelOverride,
          AccessModel.subscriptionRequired,
          reason: '$v',
        );
      }
    });

    test('a huge payload is rejected as a whole (string and map)', () {
      final huge = jsonEncode({
        'paywall_title': 'ok',
        'junk': 'x' * (kMaxConfigBytes + 10),
      });
      expect(AppConfig.parse(huge), AppConfig.defaults);
      expect(AppConfig.parse(jsonDecode(huge)), AppConfig.defaults);
    });

    test('fuzz: random hostile structures never throw and never produce invalid output', () {
      final rnd = Random(42);
      Object? junk(int depth) {
        switch (rnd.nextInt(depth > 3 ? 5 : 8)) {
          case 0:
            return null;
          case 1:
            return rnd.nextInt(1 << 30) - (1 << 29);
          case 2:
            return String.fromCharCodes(
              List.generate(rnd.nextInt(300), (_) => rnd.nextInt(0x2fff)),
            );
          case 3:
            return rnd.nextBool();
          case 4:
            return rnd.nextDouble() * 1e12;
          case 5:
            return List.generate(rnd.nextInt(12), (_) => junk(depth + 1));
          default:
            return {
              for (var i = 0; i < rnd.nextInt(6); i++)
                [
                  'paywall_title',
                  'plan_badges',
                  'paywall_benefits',
                  'min_app_version',
                  'access_model_override',
                  'maintenance_mode',
                  'x$i',
                ][rnd.nextInt(7)]: junk(
                  depth + 1,
                ),
            };
        }
      }

      for (var i = 0; i < 400; i++) {
        final c = AppConfig.parse(junk(0));
        expect(c.benefits.length, lessThanOrEqualTo(8));
        for (final t in [
          c.paywallTitle,
          c.paywallSubtitle,
          c.promoText,
          c.maintenanceMessage,
          c.badgeMonthly,
          c.badgeYearly,
          ...c.benefits,
        ]) {
          if (t != null) {
            expect(t.contains('<') || t.contains('>'), isFalse);
            expect(t.isNotEmpty && t.length <= 300, isTrue);
          }
        }
        if (c.minAppVersion != null) {
          expect(
            c.minAppVersion,
            matches(RegExp(r'^\d{1,4}\.\d{1,4}\.\d{1,4}(\+\d{1,6})?$')),
          );
        }
      }
    });

    test('toJson/parse round trip is stable', () {
      final c = AppConfig.parse(goodConfig());
      expect(AppConfig.parse(c.toJson()), c);
    });
  });

  group('Announcement.parse', () {
    test('valid, and each rule rejects the row', () {
      expect(Announcement.parse(ann('a'))!.title, 'Title a');
      final bad = <Map<String, dynamic>>[
        {...ann('a'), 'id': ''},
        {...ann('a'), 'title': ''},
        {...ann('a'), 'title': '<b>x</b>'},
        {...ann('a'), 'body': 'x' * 501},
        {...ann('a'), 'level': 'critical'},
        {...ann('a'), 'starts_at': 'nope'},
        {...ann('a'), 'ends_at': 'nope'},
        ann('a', starts: _t0, ends: _t0.subtract(const Duration(hours: 1))),
      ];
      for (final b in bad) {
        expect(Announcement.parse(b), isNull, reason: '$b');
      }
      expect(Announcement.parse('x'), isNull);
      expect(Announcement.parse(null), isNull);
    });

    test('parseList drops invalid rows, duplicates and caps the count', () {
      final list = Announcement.parseList([
        ann('a'),
        'junk',
        ann('a'),
        {...ann('b'), 'level': 'x'},
        ...List.generate(20, (i) => ann('n$i')),
      ]);
      expect(list.length, 10);
      expect(list.map((e) => e.id).toSet().length, 10);
      expect(Announcement.parseList('not a list'), isEmpty);
    });

    test('isLive follows the window', () {
      final a = Announcement.parse(
        ann('a', starts: _t0, ends: _t0.add(const Duration(hours: 1))),
      )!;
      expect(a.isLive(_t0.subtract(const Duration(seconds: 1))), isFalse);
      expect(a.isLive(_t0.add(const Duration(minutes: 30))), isTrue);
      expect(a.isLive(_t0.add(const Duration(hours: 2))), isFalse);
    });
  });

  group('compareVersions', () {
    test('orders versions and treats build numbers as tie-breakers', () {
      expect(compareVersions('1.0.0', '1.0.1'), lessThan(0));
      expect(compareVersions('1.2.0', '1.10.0'), lessThan(0));
      expect(compareVersions('2.0.0', '1.99.99'), greaterThan(0));
      expect(compareVersions('1.0.0+1', '1.0.0'), greaterThan(0));
      expect(compareVersions('1.0.0+1', '1.0.0+5'), lessThan(0));
      expect(compareVersions('1.0.0', '1.0.0'), 0);
    });
    test('garbage never means "update required"', () {
      expect(compareVersions('junk', '2.0.0'), 0);
      expect(compareVersions('1.0.0', 'junk'), 0);
    });
  });

  group('MOCK-ONLY AppConfigService', () {
    AppConfigService make(
      FakeRemote r,
      MemorySettingsStore s, {
      DateTime Function()? clock,
      Duration? timeout,
      Duration? interval,
    }) => AppConfigService(
      remote: r,
      store: s,
      clock: clock ?? () => _t0,
      fetchTimeout: timeout ?? const Duration(seconds: 2),
      minRefreshInterval: interval ?? const Duration(minutes: 10),
    );

    test(
      'starts with defaults, applies and caches the server config',
      () async {
        final store = MemorySettingsStore();
        final remote = FakeRemote(
          config: goodConfig(),
          announcements: [ann('a')],
        );
        final s = make(remote, store);
        await s.initialize();
        await s.refresh(force: true);
        expect(s.config.paywallTitle, 'Train smarter');
        expect(s.visibleAnnouncements.single.id, 'a');
        expect(store.data[AppConfigService.cacheKey], isNotEmpty);
      },
    );

    test('offline start uses the last good cached config', () async {
      final store = MemorySettingsStore();
      final first = make(FakeRemote(config: goodConfig()), store);
      await first.initialize();
      await first.refresh(force: true);

      final offline = FakeRemote()..fail = true;
      final second = make(offline, store);
      await second.initialize();
      await second.refresh(force: true);
      expect(second.lastRefreshFailed, isTrue);
      expect(second.config.paywallTitle, 'Train smarter');
    });

    test(
      'a failing refresh never replaces a good config; a hang times out',
      () async {
        final store = MemorySettingsStore();
        final remote = FakeRemote(config: goodConfig());
        final s = make(
          remote,
          store,
          timeout: const Duration(milliseconds: 50),
        );
        await s.initialize();
        await s.refresh(force: true);
        remote.hang = true;
        expect(await s.refresh(force: true), isFalse);
        expect(s.config.paywallTitle, 'Train smarter');
        remote.hang = false;
        remote.fail = true;
        expect(await s.refresh(force: true), isFalse);
        expect(s.config.paywallTitle, 'Train smarter');
      },
    );

    test('a malicious server config is sanitised, not trusted', () async {
      final remote = FakeRemote(
        config: {
          'paywall_title': '<script>alert(1)</script>',
          'paywall_benefits': List.filled(20, 'x' * 500),
          'min_app_version': 'rm -rf /',
          'maintenance_mode': 'true',
          'access_model_override': {'evil': true},
        },
      );
      final s = make(remote, MemorySettingsStore());
      await s.initialize();
      await s.refresh(force: true);
      expect(s.config.paywallTitle, isNull);
      expect(s.config.benefits, isEmpty);
      expect(s.config.minAppVersion, isNull);
      expect(s.config.maintenanceMode, isFalse);
      expect(
        s.config.accessModelOverride,
        AccessModel.subscriptionRequired,
      ); // fail closed
    });

    test('corrupt or oversized cache falls back to the defaults', () async {
      final store = MemorySettingsStore()
        ..data[AppConfigService.cacheKey] = '{{{{';
      final s = make(FakeRemote()..available = false, store);
      await s.initialize();
      expect(s.config, AppConfig.defaults);
      store.data[AppConfigService.cacheKey] = 'x' * (kMaxConfigBytes + 1);
      final s2 = make(FakeRemote()..available = false, store);
      await s2.initialize();
      expect(s2.config, AppConfig.defaults);
    });

    test('unconfigured remote: no calls, defaults, no crash', () async {
      final remote = FakeRemote()..available = false;
      final s = make(remote, MemorySettingsStore());
      await s.initialize();
      expect(await s.refresh(force: true), isFalse);
      expect(remote.configCalls, 0);
      expect(s.config, AppConfig.defaults);
    });

    test('refresh is rate limited unless forced', () async {
      var now = _t0;
      final remote = FakeRemote(config: goodConfig());
      final s = make(remote, MemorySettingsStore(), clock: () => now);
      await s.initialize(); // first (background) refresh
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final base = remote.configCalls;
      expect(await s.refresh(), isFalse);
      expect(remote.configCalls, base);
      now = now.add(const Duration(minutes: 11));
      expect(await s.refresh(), isTrue);
      expect(remote.configCalls, base + 1);
      expect(await s.refresh(force: true), isTrue);
    });

    test(
      'the remote access model reaches AccessConfig, and clears when removed',
      () async {
        final remote = FakeRemote(
          config: {...goodConfig(), 'access_model_override': 'freemium'},
        );
        final s = make(remote, MemorySettingsStore());
        await s.initialize();
        await s.refresh(force: true);
        expect(AccessConfig.remote, AccessModel.freemium);
        remote.config = goodConfig();
        await s.refresh(force: true);
        expect(AccessConfig.remote, isNull);
      },
    );

    test('updateRequired compares with the installed version', () async {
      final remote = FakeRemote(
        config: {...goodConfig(), 'min_app_version': '9.0.0'},
      );
      final s = make(remote, MemorySettingsStore());
      await s.initialize();
      await s.refresh(force: true);
      expect(s.updateRequired(kAppVersion), isTrue);
      expect(s.updateRequired('9.0.0'), isFalse);
      expect(s.updateRequired('10.0.0'), isFalse);
    });

    test('announcements: dismissal persists across restarts; expired and future are hidden', () async {
      final store = MemorySettingsStore();
      final remote = FakeRemote(
        announcements: [
          ann('live'),
          ann(
            'past',
            starts: _t0.subtract(const Duration(days: 3)),
            ends: _t0.subtract(const Duration(days: 1)),
          ),
          ann('future', starts: _t0.add(const Duration(days: 1))),
        ],
      );
      final s = make(remote, store);
      await s.initialize();
      await s.refresh(force: true);
      expect(s.visibleAnnouncements.map((a) => a.id), ['live']);
      await s.dismissAnnouncement('live');
      expect(s.visibleAnnouncements, isEmpty);

      final restarted = make(FakeRemote()..fail = true, store);
      await restarted.initialize();
      expect(
        restarted.visibleAnnouncements,
        isEmpty,
        reason: 'dismissal is remembered, cache still holds the row',
      );
    });
  });

  group('AccessConfig precedence and safety', () {
    test('remote layer sits between the build value and the test override', () {
      expect(
        AccessConfig.model,
        AccessModel.subscriptionRequired,
      ); // build default
      AccessConfig.setRemote(AccessModel.freemium);
      expect(AccessConfig.model, AccessModel.freemium);
      AccessConfig.debugOverride = AccessModel.subscriptionRequired;
      expect(
        AccessConfig.model,
        AccessModel.subscriptionRequired,
        reason: 'test override wins',
      );
      AccessConfig.debugOverride = null;
      AccessConfig.setRemote(null);
      expect(AccessConfig.model, AccessModel.subscriptionRequired);
    });

    test(
      'a release build without a RevenueCat key can never be opened remotely',
      () {
        expect(
          AccessConfig.remoteMayOpen(
            releaseMode: true,
            revenueCatConfigured: false,
          ),
          isFalse,
        );
        expect(
          AccessConfig.remoteMayOpen(
            releaseMode: true,
            revenueCatConfigured: true,
          ),
          isTrue,
        );
        expect(
          AccessConfig.remoteMayOpen(
            releaseMode: false,
            revenueCatConfigured: false,
          ),
          isTrue,
        );
      },
    );

    test(
      'changing the remote value bumps the revision (listeners re-evaluate)',
      () {
        final before = AccessConfig.revision.value;
        AccessConfig.setRemote(AccessModel.freemium);
        expect(AccessConfig.revision.value, before + 1);
        AccessConfig.setRemote(AccessModel.freemium); // no change
        expect(AccessConfig.revision.value, before + 1);
      },
    );

    test('kApplicationId matches the Gradle applicationId', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      final m = RegExp(r'applicationId\s*=\s*"([^"]+)"').firstMatch(gradle);
      expect(m, isNotNull);
      expect(kApplicationId, m!.group(1));
    });
  });

  group('MOCK-ONLY AppConfigGate', () {
    Future<AppConfigService> pumpGate(
      WidgetTester tester,
      FakeRemote remote, {
      String installed = '1.0.0+1',
      Future<bool> Function(Uri)? openStore,
    }) async {
      final s = AppConfigService(
        remote: remote,
        store: MemorySettingsStore(),
        clock: () => _t0,
      );
      await tester.runAsync(() async {
        await s.initialize();
        await s.refresh(force: true);
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: AppConfigGate(
            service: s,
            installedVersion: installed,
            openStore: openStore,
            child: const Scaffold(body: Center(child: Text('THE APP'))),
          ),
        ),
      );
      await tester.pump();
      return s;
    }

    testWidgets('normal config shows the app', (tester) async {
      await pumpGate(tester, FakeRemote(config: goodConfig()));
      expect(find.text('THE APP'), findsOneWidget);
    });

    testWidgets(
      'maintenance shows the message and hides the app; retry refreshes',
      (tester) async {
        final remote = FakeRemote(
          config: {
            ...goodConfig(),
            'maintenance_mode': true,
            'maintenance_message': 'Back at 10:00 UTC',
          },
        );
        final s = await pumpGate(tester, remote);
        expect(find.text('THE APP'), findsNothing);
        expect(find.text('Back at 10:00 UTC'), findsOneWidget);
        // Maintenance ends on the server; Retry brings the app back.
        remote.config = goodConfig();
        await tester.tap(find.text('Retry'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
        await tester.pump();
        expect(find.text('THE APP'), findsOneWidget);
        expect(s.config.maintenanceMode, isFalse);
      },
    );

    testWidgets('maintenance without a message shows the built-in message', (
      tester,
    ) async {
      await pumpGate(
        tester,
        FakeRemote(config: {...goodConfig(), 'maintenance_mode': true}),
      );
      expect(find.textContaining('down for maintenance'), findsOneWidget);
    });

    testWidgets(
      'update required shows the screen, uses the market link, and a failure is explained',
      (tester) async {
        final opened = <Uri>[];
        await pumpGate(
          tester,
          FakeRemote(config: {...goodConfig(), 'min_app_version': '2.0.0'}),
          openStore: (u) async {
            opened.add(u);
            return false;
          },
        );
        expect(find.text('THE APP'), findsNothing);
        expect(find.text('Update required'), findsOneWidget);
        await tester.tap(find.text('Open Google Play'));
        await tester.pump();
        expect(opened.single.toString(), 'market://details?id=$kApplicationId');
        expect(
          find.textContaining('Open Google Play and search'),
          findsOneWidget,
        );
      },
    );

    testWidgets('installed version at or above the minimum is not blocked', (
      tester,
    ) async {
      await pumpGate(
        tester,
        FakeRemote(config: {...goodConfig(), 'min_app_version': '1.0.0'}),
      );
      expect(find.text('THE APP'), findsOneWidget);
    });

    testWidgets('maintenance screen fits 360x640 at 2.0x text', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final remote = FakeRemote(
        config: {
          ...goodConfig(),
          'maintenance_mode': true,
          'maintenance_message': 'x ' * 140,
        },
      );
      final s = AppConfigService(
        remote: remote,
        store: MemorySettingsStore(),
        clock: () => _t0,
      );
      await tester.runAsync(() async {
        await s.initialize();
        await s.refresh(force: true);
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c)
                .copyWith(textScaler: const TextScaler.linear(2.0)),
            child: child!,
          ),
          home: AppConfigGate(service: s, child: const SizedBox()),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('MOCK-ONLY AnnouncementBanner', () {
    testWidgets(
      'shows live announcements, dismiss removes them, empty renders nothing',
      (tester) async {
        final remote = FakeRemote(
          announcements: [
            ann('a'),
            ann('b', level: 'warning'),
          ],
        );
        final s = AppConfigService(
          remote: remote,
          store: MemorySettingsStore(),
          clock: () => _t0,
        );
        await tester.runAsync(() async {
          await s.initialize();
          await s.refresh(force: true);
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: SingleChildScrollView(
                child: AnnouncementBanner(service: s),
              ),
            ),
          ),
        );
        expect(find.text('Title a'), findsOneWidget);
        expect(find.text('Title b'), findsOneWidget);
        await tester.tap(find.byTooltip('Dismiss announcement').first);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();
        expect(find.byTooltip('Dismiss announcement'), findsOneWidget);
        await tester.tap(find.byTooltip('Dismiss announcement'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();
        expect(find.byType(Card), findsNothing);
        expect(find.text('Title a'), findsNothing);
        expect(find.text('Title b'), findsNothing);
      },
    );
  });
}
