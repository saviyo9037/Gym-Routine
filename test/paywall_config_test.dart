import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/core/access_config.dart';
import 'package:reptrack/core/theme.dart';
import 'package:reptrack/screens/paywall_screen.dart';
import 'package:reptrack/services/app_config_service.dart';
import 'package:reptrack/services/cloud_services.dart';
import 'package:reptrack/services/premium_service.dart';

import 'helpers/cloud_fakes.dart';

// MOCK-ONLY: fake store offers and a fake config remote. Proves that remote
// COPY (title/subtitle/benefits/badges/promo) is shown with fallbacks, and that
// price and trial text still come only from the store offers.

final _now = DateTime(2026, 10, 20, 12);

class _Remote implements AppConfigRemote {
  _Remote(this.config);
  Map<String, dynamic>? config;
  @override
  bool get isAvailable => true;
  @override
  Future<Map<String, dynamic>?> fetchConfig() async => config;
  @override
  Future<List<dynamic>> fetchAnnouncements() async => const [];
}

_Remote? _lastRemote;

List<PremiumOffer> offers({
  TrialInfo? trial,
  String monthly = r'$4.99',
  String yearly = r'$39.99',
}) => [
  PremiumOffer(
    id: 'm',
    title: 'Monthly',
    priceString: monthly,
    period: BillingPeriod.monthly,
    trial: trial,
  ),
  PremiumOffer(
    id: 'y',
    title: 'Yearly',
    priceString: yearly,
    period: BillingPeriod.yearly,
    trial: trial,
  ),
];

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() => AccessConfig.debugOverride = AccessModel.subscriptionRequired);
  tearDown(() {
    AccessConfig.debugOverride = null;
    CloudServices.resetForTesting();
    AppConfigService.instance = AppConfigService();
  });

  Future<AppConfigService> pump(
    WidgetTester tester, {
    Map<String, dynamic>? config,
    List<PremiumOffer>? offerList,
    double textScale = 1.0,
    Size? size,
  }) async {
    if (size != null) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }
    final src = FakeEntitlementSource(now: _now)
      ..offers = offerList ?? offers();
    final p = PremiumService(
      source: src,
      store: MemorySettingsStore(),
      clock: () => _now,
    );
    CloudServices.premium = p;
    _lastRemote = _Remote(config);
    final cfg = AppConfigService(
      remote: _lastRemote,
      store: MemorySettingsStore(),
      clock: () => _now,
    );
    AppConfigService.instance = cfg;
    await tester.runAsync(() async {
      await p.initialize();
      await cfg.initialize();
      await cfg.refresh(force: true);
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const PaywallScreen(locked: true),
      ),
    );
    await settle(tester);
    return cfg;
  }

  testWidgets('no remote copy: the built-in wording is used', (tester) async {
    await pump(tester);
    expect(find.text('RepTrack needs a subscription'), findsOneWidget);
    expect(
      find.textContaining('Choose a plan to use RepTrack'),
      findsOneWidget,
    );
    expect(find.text('Weekly plans and active workouts'), findsOneWidget);
    expect(find.byKey(const ValueKey('paywall_promo')), findsNothing);
    expect(find.byKey(const ValueKey('badge_yearly')), findsNothing);
  });

  testWidgets(
    'remote title, subtitle, benefits, badge and promo replace the defaults',
    (tester) async {
      await pump(
        tester,
        config: {
          'paywall_title': 'Train smarter',
          'paywall_subtitle': 'Plan, log, repeat.',
          'paywall_benefits': ['Weekly plans', 'Offline first'],
          'plan_badges': {'yearly': 'Best value'},
          'promo_text': 'Launch week offer',
        },
      );
      expect(find.text('Train smarter'), findsOneWidget);
      expect(find.text('RepTrack needs a subscription'), findsNothing);
      expect(find.text('Plan, log, repeat.'), findsOneWidget);
      expect(find.text('Weekly plans'), findsOneWidget);
      expect(find.text('Offline first'), findsOneWidget);
      expect(find.text('Weekly plans and active workouts'), findsNothing);
      expect(find.text('Best value'), findsOneWidget);
      expect(find.byKey(const ValueKey('badge_monthly')), findsNothing);
      expect(find.text('Launch week offer'), findsOneWidget);
    },
  );

  testWidgets(
    'prices come ONLY from the store offers, whatever the remote copy says',
    (tester) async {
      await pump(
        tester,
        config: {
          'paywall_title': r'Only $0.99 today',
          'promo_text': r'Just $1!',
        },
        offerList: offers(monthly: r'$7.77', yearly: r'$70.07'),
      );
      expect(find.textContaining(r'$7.77'), findsWidgets);
      expect(find.textContaining(r'$70.07'), findsWidgets);
      // The remote text is only text: the displayed plan prices are the store's.
      expect(find.textContaining(r'$4.99'), findsNothing);
    },
  );

  testWidgets(
    'the trial line uses the length of the store offer, never a fixed one',
    (tester) async {
      await pump(
        tester,
        config: {'paywall_subtitle': 'Plan, log, repeat.'},
        offerList: offers(trial: const TrialInfo(1, 'day')),
      );
      expect(find.byKey(const ValueKey('paywall_trial_line')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('paywall_trial_line')))
            .data,
        contains('1 day trial from Google Play'),
      );
    },
  );

  testWidgets('a different store trial changes the text (7 days)', (
    tester,
  ) async {
    await pump(
      tester,
      config: {'paywall_subtitle': 'Plan, log, repeat.'},
      offerList: offers(trial: const TrialInfo(7, 'day')),
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('paywall_trial_line')))
          .data,
      contains('7 days trial from Google Play'),
    );
    expect(find.textContaining('1 day trial'), findsNothing);
  });

  testWidgets(
    'no trial in the offer: no trial wording at all, even with remote copy',
    (tester) async {
      await pump(
        tester,
        config: {
          'paywall_subtitle': 'Plan, log, repeat.',
          'promo_text': 'Launch',
        },
      );
      expect(find.byKey(const ValueKey('paywall_trial_line')), findsNothing);
      expect(find.textContaining('trial'), findsNothing);
    },
  );

  testWidgets('hostile remote copy is ignored: the built-in text shows', (
    tester,
  ) async {
    await pump(
      tester,
      config: {
        'paywall_title': '<script>alert(1)</script>',
        'paywall_subtitle': 'x' * 500,
        'paywall_benefits': ['<b>bold</b>', 'y' * 300],
        'plan_badges': {'yearly': '<i>x</i>'},
        'promo_text': '<a href=x>click</a>',
      },
    );
    expect(find.text('RepTrack needs a subscription'), findsOneWidget);
    expect(
      find.textContaining('Choose a plan to use RepTrack'),
      findsOneWidget,
    );
    expect(find.text('Weekly plans and active workouts'), findsOneWidget);
    expect(find.byKey(const ValueKey('paywall_promo')), findsNothing);
    expect(find.byKey(const ValueKey('badge_yearly')), findsNothing);
  });

  testWidgets('a config change while the paywall is open updates it', (
    tester,
  ) async {
    final cfg = await pump(tester);
    expect(find.text('RepTrack needs a subscription'), findsOneWidget);
    _lastRemote!.config = {'paywall_title': 'Fresh copy'};
    await tester.runAsync(() => cfg.refresh(force: true));
    await tester.pump();
    expect(find.text('Fresh copy'), findsOneWidget);
  });

  testWidgets('maximum-length remote copy fits 360x640 at 2.0x text', (
    tester,
  ) async {
    await pump(
      tester,
      config: {
        'paywall_title': 'T' * 80,
        'paywall_subtitle': 'S' * 200,
        'paywall_benefits': List.generate(8, (i) => 'B$i ' * 29),
        'plan_badges': {'monthly': 'M' * 24, 'yearly': 'Y' * 24},
        'promo_text': 'P' * 200,
      },
      offerList: offers(trial: const TrialInfo(1, 'day')),
      textScale: 2.0,
      size: const Size(360, 640),
    );
    expect(tester.takeException(), isNull);
  });
}
