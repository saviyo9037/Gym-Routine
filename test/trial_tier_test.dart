// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/core/access_config.dart';
import 'package:reptrack/core/strings.dart';
import 'package:reptrack/core/theme.dart';
import 'package:reptrack/screens/diagnostics_screen.dart';
import 'package:reptrack/screens/paywall_screen.dart';
import 'package:reptrack/services/access_guard.dart';
import 'package:reptrack/services/auth_service.dart';
import 'package:reptrack/services/cloud_services.dart';
import 'package:reptrack/services/comp_grant_source.dart';
import 'package:reptrack/services/exercise_media_service.dart';
import 'package:reptrack/services/mock_billing.dart';
import 'package:reptrack/services/premium_service.dart';
import 'package:reptrack/services/sync_service.dart';
import 'package:reptrack/services/video_access_service.dart';
import 'package:reptrack/widgets/exercise_demonstration_player.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'helpers/cloud_fakes.dart';
import 'helpers/fake_sync_remote.dart';
import 'helpers/test_db.dart';
import 'helpers/video_fakes.dart';

// MOCK-ONLY: the store, the comp source, the signed-URL backend and the downloader
// are fakes. PremiumService (tier), the media service, the cache and the player
// widget are the real code. The server side is covered by
// backend/supabase/tests/video_access.test.sql (real Postgres in PGlite) and
// backend/supabase/functions/_shared/video_url.test.ts.

final _now = DateTime(2026, 10, 20, 12);

class _Comp implements CompGrantSource {
  _Comp(this.grant);
  @override
  String? userId = 'user-a';
  CompGrant? grant;
  @override
  Future<CompGrant?> fetch() async => grant;
}

/// Counts every attempt to create a native video player.
class _SpyVideoPlatform extends VideoPlayerPlatform {
  int creates = 0;
  @override
  Future<void> init() async {}
  @override
  Future<void> dispose(int playerId) async {}
  @override
  // ignore: deprecated_member_use
  Future<int?> create(DataSource dataSource) async {
    creates++;
    throw UnsupportedError('spy');
  }

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    creates++;
    throw UnsupportedError('spy');
  }
}

Future<(PremiumService, MockEntitlementSource)> mockPremium(
  MockBillingState s,
) async {
  final src = MockEntitlementSource(clock: () => _now);
  await src.setState(s);
  final p = PremiumService(
    source: src,
    store: MemorySettingsStore(),
    clock: () => _now,
  );
  await p.initialize();
  return (p, src);
}

Future<void> settle(WidgetTester tester, {int rounds = 12}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    AccessConfig.debugOverride = null; // subscription required (default)
    AccessConfig.trialVideosLockedOverride = null;
  });
  tearDown(() {
    AccessConfig.debugOverride = null;
    AccessConfig.trialVideosLockedOverride = null;
  });

  group('tier is computed in PremiumService', () {
    const expected = {
      MockBillingState.noAccess: AccessTier.locked,
      MockBillingState.trial: AccessTier.trial,
      MockBillingState.premium: AccessTier.full,
      MockBillingState.expired: AccessTier.locked,
      MockBillingState.grace: AccessTier.full,
      MockBillingState.refunded: AccessTier.locked,
    };
    for (final e in expected.entries) {
      test('${e.key.label} -> ${e.value.name}', () async {
        final (p, _) = await mockPremium(e.key);
        expect(p.tier, e.value);
        p.dispose();
      });
    }

    test('a stale offline cache (older than 14 days) is locked', () async {
      final cached = MemorySettingsStore();
      final old = FakeEntitlementSource(
        active: true,
        expiresAt: _now.add(const Duration(days: 60)),
        now: _now.subtract(const Duration(days: 30)),
      );
      final p1 = PremiumService(source: old, store: cached, clock: () => _now);
      await p1.initialize();
      p1.dispose();
      final offline = FakeEntitlementSource(now: _now)..failFetch = true;
      final p2 = PremiumService(
        source: offline,
        store: cached,
        clock: () => _now,
        fetchTimeout: const Duration(milliseconds: 50),
      );
      await p2.initialize();
      expect(p2.tier, AccessTier.locked);
      p2.dispose();
    });

    test('not initialised yet is locked (never a trial/full flash)', () {
      final p = PremiumService(
        source: MockEntitlementSource(clock: () => _now),
        store: MemorySettingsStore(),
        clock: () => _now,
      );
      expect(p.tier, AccessTier.locked);
      p.dispose();
    });

    test('a valid comp grant is full, also next to a store trial', () async {
      final src = FakeEntitlementSource(
        active: true,
        expiresAt: _now.add(const Duration(days: 1)),
        now: _now,
      )..trial = true;
      final p = PremiumService(
        source: src,
        store: MemorySettingsStore(),
        clock: () => _now,
        compSource: _Comp(
          CompGrant(
            isActive: true,
            expiresAt: _now.add(const Duration(days: 9)),
          ),
        ),
      );
      await p.initialize();
      expect(p.decision.state, EntitlementState.trial);
      expect(p.tier, AccessTier.full);
      expect(p.videosAllowed, isTrue);
      p.dispose();
    });

    test(
      'comp alone (no store entitlement) is full; a revoked grant is locked',
      () async {
        Future<AccessTier> tierFor(CompGrant? g) async {
          final p = PremiumService(
            source: FakeEntitlementSource(now: _now),
            store: MemorySettingsStore(),
            clock: () => _now,
            compSource: _Comp(g),
          );
          await p.initialize();
          final t = p.tier;
          p.dispose();
          return t;
        }

        expect(
          await tierFor(
            CompGrant(
              isActive: true,
              expiresAt: _now.add(const Duration(days: 3)),
            ),
          ),
          AccessTier.full,
        );
        expect(
          await tierFor(const CompGrant(isActive: false)),
          AccessTier.locked,
        );
        expect(await tierFor(null), AccessTier.locked);
      },
    );
  });

  group('tier x feature matrix', () {
    // trial == full for everything except videos.
    final matrix = <MockBillingState, ({AccessTier tier, bool videos})>{
      MockBillingState.noAccess: (tier: AccessTier.locked, videos: false),
      MockBillingState.trial: (tier: AccessTier.trial, videos: false),
      MockBillingState.premium: (tier: AccessTier.full, videos: true),
    };

    for (final e in matrix.entries) {
      test(
        '${e.value.tier.name}: videos / plans / routines / stats / sync / export',
        () async {
          final (p, _) = await mockPremium(e.key);
          final open = e.value.tier != AccessTier.locked;
          expect(p.tier, e.value.tier);

          // videos: the ONLY difference between trial and full
          expect(p.videosAllowed, e.value.videos, reason: 'videos');

          // plans
          expect(p.canCreatePlan(0), open, reason: 'plans (0 existing)');
          expect(p.canCreatePlan(50), open, reason: 'plans (50 existing)');

          // routines / alarms / history / workout writes go through the guard
          AccessGuard.isLocked = () => p.isLocked;
          addTearDown(() => AccessGuard.isLocked = () => false);
          if (open) {
            expect(
              AccessGuard.ensureWritable,
              returnsNormally,
              reason: 'routines',
            );
          } else {
            expect(
              AccessGuard.ensureWritable,
              throwsA(isA<AccessLockedException>()),
              reason: 'routines',
            );
          }
          expect(p.hasFullAccess, open, reason: 'app access');

          // stats / charts
          expect(p.canUse(PremiumFeature.advancedStats), open, reason: 'stats');

          // sync
          expect(p.canUse(PremiumFeature.cloudSync), open, reason: 'sync flag');
          final auth = FakeAuthService(
            signedIn: const CloudUser(id: 'u1', email: 'a@b.c'),
          );
          final sync = SyncService(
            auth: auth,
            premium: p,
            remoteFactory: (_) => FakeSyncRemote(),
          );
          expect(sync.canSync, open, reason: 'SyncService.canSync');

          // export
          expect(p.canUse(PremiumFeature.exportData), open, reason: 'export');
          p.dispose();
        },
      );
    }

    test('videos are the ONLY thing trial differs from full in', () async {
      final (trial, _) = await mockPremium(MockBillingState.trial);
      final (full, _) = await mockPremium(MockBillingState.premium);
      expect(trial.accessLevel, full.accessLevel);
      expect(trial.hasFullAccess, full.hasFullAccess);
      expect(trial.isPremium, full.isPremium);
      for (final f in PremiumFeature.values) {
        expect(trial.canUse(f), full.canUse(f), reason: '$f');
      }
      expect(trial.canCreatePlan(99), full.canCreatePlan(99));
      expect(trial.videosAllowed, isNot(full.videosAllowed));
      trial.dispose();
      full.dispose();
    });
  });

  group('TRIAL_VIDEOS_LOCKED switch', () {
    test('defaults to true', () {
      expect(AccessConfig.trialVideosLocked, isTrue);
    });

    test('true: trial locks videos; false: trial may watch them', () async {
      final (p, _) = await mockPremium(MockBillingState.trial);
      AccessConfig.trialVideosLockedOverride = true;
      expect(p.videosAllowed, isFalse);
      expect(p.videosLockedForTrial, isTrue);
      AccessConfig.trialVideosLockedOverride = false;
      expect(p.videosAllowed, isTrue);
      expect(p.videosLockedForTrial, isFalse);
      p.dispose();
    });

    test('never changes full or locked users', () async {
      final (full, _) = await mockPremium(MockBillingState.premium);
      final (locked, _) = await mockPremium(MockBillingState.noAccess);
      for (final v in [true, false]) {
        AccessConfig.trialVideosLockedOverride = v;
        expect(full.videosAllowed, isTrue, reason: 'full, switch=$v');
        expect(locked.videosAllowed, isFalse, reason: 'locked, switch=$v');
      }
      full.dispose();
      locked.dispose();
    });

    test(
      'the switch lives in the one config file, strings in the strings file',
      () {
        final cfg = File('lib/core/access_config.dart').readAsStringSync();
        expect(cfg, contains("'TRIAL_VIDEOS_LOCKED'"));
        expect(cfg, contains('defaultValue: true'));
        final widget = File('lib/widgets/exercise_demonstration_player.dart')
            .readAsStringSync();
        expect(
          widget.contains('Videos unlock with a full subscription'),
          isFalse,
        );
        expect(
          File('lib/core/strings.dart').readAsStringSync(),
          contains('Videos unlock with a full subscription'),
        );
      },
    );
  });

  group('media source per tier', () {
    final svc = ExerciseMediaService.instance;
    late VideoTestRig rig;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      await svc.initialize();
    });
    setUp(() {
      rig = VideoTestRig();
      svc.videosEnabledForTesting = true;
    });
    tearDown(() {
      svc.accessForTesting = null;
      svc.videosEnabledForTesting = null;
      rig.dispose();
    });

    VideoAccessService serviceFor(PremiumService p) => VideoAccessService(
      canAccessVideos: () => p.videosAllowed,
      isTrialLocked: () => p.videosLockedForTrial,
      fetchSignedUrl: rig.backend.fetch,
      downloader: rig.downloader,
      cacheDirectory: () async => rig.cacheDir,
    );

    // 69 = Standing Dumbbell Curl (protected video), 1 = Barbell Bench Press (NO_VIDEO)
    Future<DemonstrationSourceType> typeFor(
      MockBillingState s,
      int id,
      String name,
    ) async {
      final (p, _) = await mockPremium(s);
      svc.accessForTesting = serviceFor(p);
      final src = await svc.resolveMediaSource(name, exerciseId: id);
      p.dispose();
      return src.type;
    }

    test(
      'trial: video exercise -> trialLockedPhoto, nothing requested',
      () async {
        expect(
          await typeFor(MockBillingState.trial, 69, 'Standing Dumbbell Curl'),
          DemonstrationSourceType.trialLockedPhoto,
        );
        expect(
          rig.backend.requested,
          isEmpty,
          reason: 'no signed URL for a trial',
        );
        expect(rig.downloader.calls, 0);
      },
    );

    test('trial: ensureDownloaded is refused before any request', () async {
      final (p, _) = await mockPremium(MockBillingState.trial);
      final access = serviceFor(p);
      await expectLater(
        access.ensureDownloaded(69),
        throwsA(
          isA<VideoAccessException>().having(
            (e) => e.kind,
            'kind',
            VideoAccessFailure.notEntitled,
          ),
        ),
      );
      expect(await access.cachedFile(69), isNull);
      expect(rig.backend.requested, isEmpty);
      p.dispose();
    });

    test(
      'trial: exercise WITHOUT a video keeps the plain photo (no lock)',
      () async {
        expect(
          await typeFor(MockBillingState.trial, 1, 'Barbell Bench Press'),
          DemonstrationSourceType.photoFallback,
        );
      },
    );

    test('locked: generic locked card (existing behaviour)', () async {
      expect(
        await typeFor(MockBillingState.noAccess, 69, 'Standing Dumbbell Curl'),
        DemonstrationSourceType.lockedPhoto,
      );
      expect(rig.backend.requested, isEmpty);
    });

    test('full: the video is downloaded on demand', () async {
      expect(
        await typeFor(MockBillingState.premium, 69, 'Standing Dumbbell Curl'),
        DemonstrationSourceType.protectedDownload,
      );
    });

    test('switch off: a trial user gets the same source as full', () async {
      AccessConfig.trialVideosLockedOverride = false;
      expect(
        await typeFor(MockBillingState.trial, 69, 'Standing Dumbbell Curl'),
        DemonstrationSourceType.protectedDownload,
      );
    });
  });

  group('player widget per tier', () {
    final svc = ExerciseMediaService.instance;
    late VideoTestRig rig;
    late _SpyVideoPlatform spy;
    late VideoPlayerPlatform previous;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      await svc.initialize();
    });
    setUp(() {
      mockPlatformPlugins();
      rig = VideoTestRig();
      svc.videosEnabledForTesting = true;
      previous = VideoPlayerPlatform.instance;
      spy = _SpyVideoPlatform();
      VideoPlayerPlatform.instance = spy;
    });
    tearDown(() {
      VideoPlayerPlatform.instance = previous;
      svc.accessForTesting = null;
      svc.videosEnabledForTesting = null;
      CloudServices.resetForTesting();
      rig.dispose();
    });

    Widget player(int id, String name) => MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: ExerciseDemonstrationPlayer(
          key: ValueKey('p_$id'),
          exerciseId: id,
          exerciseName: name,
          fallbackImagePath:
              'assets/images/exercises/standing_dumbbell_curl.jpg',
          height: 240,
        ),
      ),
    );

    Future<PremiumService> boot(WidgetTester tester, MockBillingState s) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      ignoreMissingPluginErrors();
      final (p, _) = (await tester.runAsync(() => mockPremium(s)))!;
      CloudServices.premium = p;
      svc.accessForTesting = VideoAccessService(
        canAccessVideos: () => p.videosAllowed,
        isTrialLocked: () => p.videosLockedForTrial,
        fetchSignedUrl: rig.backend.fetch,
        downloader: rig.downloader,
        cacheDirectory: () async => rig.cacheDir,
      );
      return p;
    }

    testWidgets(
      'TRIAL: blurred photo, lock, text, Subscribe; no controller, no URL',
      (tester) async {
        await boot(tester, MockBillingState.trial);
        await tester.pumpWidget(player(69, 'Standing Dumbbell Curl'));
        await settle(tester);

        expect(find.text(AppStrings.trialVideosLockedTitle), findsOneWidget);
        expect(
          find.text('Videos unlock with a full subscription'),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
        expect(find.byKey(const ValueKey('trial_locked_blur')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('trial_videos_subscribe')),
          findsOneWidget,
        );
        expect(find.text('Subscribe'), findsOneWidget);

        expect(
          spy.creates,
          0,
          reason: 'no VideoPlayerController may be created',
        );
        expect(
          rig.backend.requested,
          isEmpty,
          reason: 'no signed URL requested',
        );
        expect(rig.downloader.calls, 0);
        expect(find.textContaining('Downloading'), findsNothing);
        expect(find.text('Could not load demonstration video'), findsNothing);
        expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
        expect(find.text('No demonstration video yet'), findsNothing);
      },
    );

    testWidgets('TRIAL: Subscribe opens the paywall', (tester) async {
      await boot(tester, MockBillingState.trial);
      await tester.pumpWidget(player(69, 'Standing Dumbbell Curl'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('trial_videos_subscribe')));
      await settle(tester);
      expect(find.byType(PaywallScreen), findsOneWidget);
      expect(find.text(AppStrings.trialVideosPaywallReason), findsOneWidget);
      // the trial user sees why videos are locked, and no purchase request was made
      expect(find.byKey(const ValueKey('trial_videos_note')), findsOneWidget);
      expect(spy.creates, 0);
    });

    testWidgets(
      'TRIAL: exercise with no video keeps "No demonstration video yet"',
      (tester) async {
        await boot(tester, MockBillingState.trial);
        await tester.pumpWidget(player(1, 'Barbell Bench Press'));
        await settle(tester);
        expect(find.text('No demonstration video yet'), findsOneWidget);
        expect(find.byIcon(Icons.lock_rounded), findsNothing);
        expect(find.byKey(const ValueKey('trial_locked_blur')), findsNothing);
        expect(find.text('Subscribe'), findsNothing);
        expect(spy.creates, 0);
        expect(rig.backend.requested, isEmpty);
      },
    );

    testWidgets('LOCKED: the generic locked card, not the trial one', (
      tester,
    ) async {
      await boot(tester, MockBillingState.noAccess);
      await tester.pumpWidget(player(69, 'Standing Dumbbell Curl'));
      await settle(tester);
      expect(find.text('Video demonstration'), findsOneWidget);
      expect(find.text(AppStrings.trialVideosLockedTitle), findsNothing);
      expect(find.byKey(const ValueKey('trial_locked_blur')), findsNothing);
      expect(spy.creates, 0);
      expect(rig.backend.requested, isEmpty);
    });

    testWidgets('FULL: the video is requested and a controller IS created', (
      tester,
    ) async {
      await boot(tester, MockBillingState.premium);
      await tester.pumpWidget(player(69, 'Standing Dumbbell Curl'));
      await settle(tester, rounds: 60); // real file I/O of the fake download
      expect(rig.backend.requested, [69]);
      expect(
        spy.creates,
        greaterThan(0),
        reason: 'positive control for the spy',
      );
      expect(find.text(AppStrings.trialVideosLockedTitle), findsNothing);
    });

    testWidgets('switch off: a TRIAL user gets the video like full', (
      tester,
    ) async {
      AccessConfig.trialVideosLockedOverride = false;
      await boot(tester, MockBillingState.trial);
      await tester.pumpWidget(player(69, 'Standing Dumbbell Curl'));
      await settle(tester, rounds: 60);
      expect(rig.backend.requested, [69]);
      expect(spy.creates, greaterThan(0));
      expect(find.text(AppStrings.trialVideosLockedTitle), findsNothing);
    });

    testWidgets(
      'upgrading trial -> premium unlocks the area without a restart',
      (tester) async {
        final p = await boot(tester, MockBillingState.trial);
        await tester.pumpWidget(player(69, 'Standing Dumbbell Curl'));
        await settle(tester);
        expect(find.text(AppStrings.trialVideosLockedTitle), findsOneWidget);
        p.mock!.nextOutcome = null;
        await tester.runAsync(() => p.mock!.setState(MockBillingState.premium));
        await settle(tester);
        expect(p.tier, AccessTier.full);
        // A fresh player (re-opened exercise) now requests the video.
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(player(69, 'Standing Dumbbell Curl'));
        await settle(tester);
        expect(rig.backend.requested, [69]);
      },
    );
  });

  group('locked users keep their own tools; trial never hides them', () {
    late VideoTestRig rig;
    setUp(() {
      mockPlatformPlugins();
      rig = VideoTestRig();
    });
    tearDown(() {
      CloudServices.resetForTesting();
      rig.dispose();
    });

    testWidgets('locked paywall: restore, manage, export stay available', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      ignoreMissingPluginErrors();
      final (p, _) = (await tester.runAsync(
        () => mockPremium(MockBillingState.noAccess),
      ))!;
      CloudServices.premium = p;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const PaywallScreen(locked: true),
        ),
      );
      await settle(tester);
      expect(p.tier, AccessTier.locked);
      expect(find.text('Restore purchases'), findsOneWidget);
      expect(find.text('Manage subscription in Google Play'), findsOneWidget);
      expect(find.text('Export my data'), findsOneWidget);
    });

    test(
      'tier changes never touch stored data: only caches are cleared',
      () async {
        // The video cache (not user data) is cleared when videos stop being
        // allowed; the guard blocks writes but deletes nothing.
        final (p, _) = await mockPremium(MockBillingState.premium);
        final access = VideoAccessService(
          canAccessVideos: () => p.videosAllowed,
          fetchSignedUrl: rig.backend.fetch,
          downloader: rig.downloader,
          cacheDirectory: () async => rig.cacheDir,
        );
        await access.ensureDownloaded(69);
        expect(await access.cachedCount(), 1);
        await access.onEntitlementChanged(false);
        expect(await access.cachedCount(), 0);
        p.dispose();
      },
    );
  });

  group('Diagnostics shows the tier; mock billing drives it', () {
    late Database db;
    setUp(mockPlatformPlugins);

    testWidgets('Trial button -> tier trial, Premium button -> tier full', (
      tester,
    ) async {
      ignoreMissingPluginErrors();
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      db = (await tester.runAsync(openTestDatabase))!;
      CloudServices.resetForTesting();
      final (p, src) = (await tester.runAsync(
        () => mockPremium(MockBillingState.noAccess),
      ))!;
      CloudServices.premium = p;

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.darkTheme, home: const DiagnosticsScreen()),
      );
      await settle(tester);
      expect(find.textContaining('tier: locked'), findsWidgets);

      for (final (state, tier) in [
        (MockBillingState.trial, 'trial'),
        (MockBillingState.premium, 'full'),
        (MockBillingState.expired, 'locked'),
      ]) {
        final b = find.byKey(ValueKey('mock_state_${state.name}'));
        await tester.ensureVisible(b);
        await tester.tap(b);
        await settle(tester);
        expect(src.state, state);
        expect(
          find.textContaining('tier: $tier'),
          findsWidgets,
          reason: '${state.label} -> $tier',
        );
        expect(
          find.text('access tier: $tier', findRichText: true),
          findsNothing,
        );
      }

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => closeTestDatabase(db));
      CloudServices.resetForTesting();
    });
  });

  group('server side (source checks; behaviour is tested in the backend harness)', () {
    test(
      'migration 0010 refuses trials by default and the function wires the env',
      () {
        final sql = File(
          'backend/supabase/migrations/0010_trial_video_tier.sql',
        ).readAsStringSync();
        expect(sql, contains("'trial_locked'"));
        expect(sql, contains('p_allow_trial boolean default false'));
        final fn = File('backend/supabase/functions/video-url/index.ts')
            .readAsStringSync();
        expect(fn, contains('TRIAL_VIDEOS_LOCKED'));
        expect(fn, contains('=== "false"'));
        final logic = File('backend/supabase/functions/_shared/video_url.ts')
            .readAsStringSync();
        expect(logic, contains('trial_locked'));
      },
    );
  });
}
