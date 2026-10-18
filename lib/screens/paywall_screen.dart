import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/access_config.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../services/app_config_service.dart';
import '../services/backup_service.dart';
import '../services/cloud_config.dart';
import '../services/cloud_services.dart';
import '../services/mock_billing.dart';
import '../services/premium_service.dart';
import '../widgets/mock_purchase_sheet.dart';
import 'account_screen.dart';

/// RepTrack subscription screen (Google Play Billing through RevenueCat).
///
/// * `ACCESS_MODEL=subscription_required` (default): the same screen is the
///   body of the locked state ([locked] = true). Prices and the trial text come
///   ONLY from the store offer; nothing here promises anything free.
/// * `freemium`: the previous screen (free core, premium extras).
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key, this.reason, this.locked = false});

  /// Optional line explaining what the user tried to open.
  final String? reason;

  /// Shown as the root of a locked app: no back button, extra "your data"
  /// actions (export, account deletion), never pops itself.
  final bool locked;

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  List<PremiumOffer> _offers = [];
  bool _loading = true;
  String? _error;
  String? _busy; // 'buy' | 'restore' | 'verify'
  PremiumOffer? _selected;

  PremiumService get _premium => CloudServices.premium;
  bool get _required => AccessConfig.subscriptionRequired;

  /// Remote copy from the admin panel (validated; built-in text when unset).
  /// Prices and trial text NEVER come from here: only from the store offers.
  AppConfigService get _configService => AppConfigService.instance;
  AppConfig get _cfg => _configService.config;

  @override
  void initState() {
    super.initState();
    _premium.addListener(_onPremiumChanged);
    _configService.addListener(_onPremiumChanged);
    _load();
  }

  @override
  void dispose() {
    _premium.removeListener(_onPremiumChanged);
    _configService.removeListener(_onPremiumChanged);
    super.dispose();
  }

  void _onPremiumChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final offers = await _premium.offerings();
      if (!mounted) return;
      setState(() {
        _offers = offers;
        _selected = offers.isEmpty
            ? null
            : offers.firstWhere(
                (o) => o.period == BillingPeriod.yearly,
                orElse: () => offers.first,
              );
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load the plans. Check your connection and retry.';
      });
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _buy() async {
    final offer = _selected;
    if (offer == null || _busy != null) return;
    final mock = _premium.mock; // null unless debug build + MOCK_BILLING=true
    if (mock != null) {
      final outcome = await showMockPurchaseSheet(context, offer);
      if (!mounted) return;
      mock.nextOutcome = outcome ?? MockOutcome.cancel;
    }
    setState(() => _busy = 'buy');
    try {
      await _premium.purchase(offer);
      if (!mounted) return;
      if (_premium.isPremium) {
        _toast(_required ? 'Welcome to RepTrack!' : 'Welcome to Premium!');
        if (!widget.locked) Navigator.pop(context, true);
      } else {
        _toast('Purchase pending. RepTrack unlocks when it is confirmed.');
      }
    } on PremiumException catch (e) {
      if (!e.cancelled) _toast(e.message);
    } catch (_) {
      _toast('Something went wrong. You were not charged.');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _restore() async {
    if (_busy != null) return;
    setState(() => _busy = 'restore');
    try {
      await _premium.restore();
      if (!mounted) return;
      _toast(
        _premium.isPremium
            ? 'Subscription restored.'
            : 'No active subscription was found for this Google account.',
      );
    } on PremiumException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Could not restore purchases. Try again later.');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _verifyAgain() async {
    if (_busy != null) return;
    setState(() => _busy = 'verify');
    try {
      await _premium.refresh();
      await _load();
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _manage() async {
    final ok = await launchUrl(
      Uri.parse(CloudConfig.playSubscriptionsUrl),
      mode: LaunchMode.externalApplication,
    ).catchError((_) => false);
    if (!ok) {
      _toast('Open Google Play > Payments & subscriptions > Subscriptions.');
    }
  }

  Future<void> _open(Uri uri) async {
    final ok = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    ).catchError((_) => false);
    if (!ok) _toast('Could not open the link.');
  }

  /// Read-only export of the user's existing local data. Works offline and
  /// while locked; it never changes anything.
  Future<void> _exportData() async {
    if (_busy != null) return;
    setState(() => _busy = 'export');
    try {
      final json = await BackupService().exportJson();
      final file = File(
        '${Directory.systemTemp.path}/reptrack_backup_${DateTime.now().millisecondsSinceEpoch}.json',
      );
      await file.writeAsString(json);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'RepTrack backup',
          text: 'RepTrack data export (JSON)',
        ),
      );
    } catch (_) {
      _toast('Export failed. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.locked,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          automaticallyImplyLeading: !widget.locked,
          title: Text(_required ? 'REPTRACK' : 'REPTRACK PREMIUM'),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (_required) _requiredHeader(),
            if (widget.reason != null) ...[
              Text(
                widget.reason!,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
            ],
            _featuresCard(),
            const SizedBox(height: 16),
            if (widget.locked && _premium.verificationFailed) ...[
              _verifyCard(),
              const SizedBox(height: 12),
            ],
            if (_premium.isPremium) _activeCard() else _plansArea(),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _manage,
              child: const Text('Manage subscription in Google Play'),
            ),
            ..._legalLinks(),
            const SizedBox(height: 4),
            if (!_required)
              const Text(
                'Free forever: workout logging, the exercise library, basic '
                'history, routines and alarms. Premium never locks them.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
              ),
            if (widget.locked) ..._lockedExtras(),
          ],
        ),
      ),
    );
  }

  Widget _requiredHeader() {
    final trial = _selected?.trial;
    final cfg = _cfg;
    const safe =
        'Your workouts and data on this phone are safe and are never deleted.';
    // Without remote copy the original wording is kept exactly; with remote
    // copy the subtitle is shown and the store-provided trial line is added
    // separately (the trial length is always the Play offer's own).
    final String body;
    final String? trialLine;
    if (cfg.paywallSubtitle != null) {
      body = cfg.paywallSubtitle!;
      trialLine = trial == null
          ? null
          : 'Start with the ${trial.label} trial from Google Play, then '
                'continue with the plan you choose.';
    } else {
      body = trial == null
          ? 'Choose a plan to use RepTrack. Your workouts and data on this '
                'phone are safe and are never deleted.'
          : 'Start with the ${trial.label} trial from Google Play, then '
                'continue with the plan you choose. Your data on this '
                'phone is safe and is never deleted.';
      trialLine = null;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            cfg.paywallTitle ?? 'RepTrack needs a subscription',
            key: const ValueKey('paywall_title'),
            style: const TextStyle(
              color: AppColors.textMain,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            key: const ValueKey('paywall_subtitle'),
            style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          if (trialLine != null) ...[
            const SizedBox(height: 6),
            Text(
              trialLine,
              key: const ValueKey('paywall_trial_line'),
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ],
          if (cfg.paywallSubtitle != null) ...[
            const SizedBox(height: 4),
            const Text(
              safe,
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
          if (cfg.promoText != null && !_premium.isPremium) ...[
            const SizedBox(height: 10),
            Container(
              key: const ValueKey('paywall_promo'),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.5),
                ),
              ),
              child: Text(
                cfg.promoText!,
                style: const TextStyle(
                  color: AppColors.textMain,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _legalLinks() {
    final privacy = CloudConfig.privacyUri;
    final terms = CloudConfig.termsUri;
    if (privacy == null && terms == null) return const [];
    return [
      Wrap(
        alignment: WrapAlignment.center,
        children: [
          if (privacy != null)
            TextButton(
              onPressed: () => _open(privacy),
              child: const Text('Privacy policy'),
            ),
          if (terms != null)
            TextButton(
              onPressed: () => _open(terms),
              child: const Text('Terms of use'),
            ),
        ],
      ),
    ];
  }

  List<Widget> _lockedExtras() {
    return [
      const SizedBox(height: 24),
      const Divider(color: AppColors.border),
      const SizedBox(height: 8),
      const Text(
        'YOUR DATA',
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
      const SizedBox(height: 6),
      const Text(
        'Everything you saved is still on this phone and was not changed. '
        'Alarms you already set keep ringing. You can export your data at any '
        'time.',
        style: TextStyle(color: AppColors.textSecondary, height: 1.4),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: _busy == null ? _exportData : null,
        icon: _busy == 'export'
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.ios_share_rounded, size: 18),
        label: const Text('Export my data'),
      ),
      if (CloudServices.auth.isSignedIn) ...[
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AccountScreen()),
          ),
          icon: const Icon(Icons.manage_accounts_rounded, size: 18),
          label: const Text('Account and delete account'),
        ),
      ],
    ];
  }

  Widget _verifyCard() {
    return Material(
      color: AppColors.warning.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.warning.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Could not verify your subscription - retry',
              style: TextStyle(
                color: AppColors.textMain,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Check your connection. RepTrack keeps trying automatically; if '
              'you already subscribed, your access returns as soon as Google '
              'Play answers.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
            ),
            const SizedBox(height: 6),
            ElevatedButton(
              onPressed: _busy == null ? _verifyAgain : null,
              child: _busy == 'verify'
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _featuresCard() {
    final remote = _cfg.benefits;
    final items = remote.isNotEmpty
        ? [for (final b in remote) (Icons.check_circle_rounded, b)]
        : _required
        ? const [
            (Icons.fitness_center_rounded, 'Weekly plans and active workouts'),
            (Icons.menu_book_rounded, 'Exercise library and history'),
            (Icons.alarm_rounded, 'Routines, reminders and alarms'),
            (Icons.cloud_sync_rounded, 'Cloud backup and sync across devices'),
            (Icons.show_chart_rounded, 'Advanced stats and progress charts'),
            (Icons.ios_share_rounded, 'Export your history (CSV / JSON)'),
          ]
        : const [
            (Icons.cloud_sync_rounded, 'Cloud backup & sync across devices'),
            (Icons.show_chart_rounded, 'Advanced stats and progress charts'),
            (Icons.all_inclusive_rounded, 'Unlimited training plans'),
            (Icons.ios_share_rounded, 'Export your history (CSV / JSON)'),
          ];
    return Material(
      color: AppColors.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _required ? 'INCLUDED' : 'PREMIUM INCLUDES',
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            for (final i in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(i.$1, color: AppColors.primary, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        i.$2,
                        style: const TextStyle(color: AppColors.textMain),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _activeCard() {
    final exp = _premium.expiresAt;
    final fmt = DateFormat.yMMMd();
    final trial = _premium.isTrial;
    return Material(
      color: AppColors.success.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.success),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              trial
                  ? 'Your trial is active'
                  : (_required
                        ? 'Your subscription is active'
                        : 'You have Premium'),
              style: const TextStyle(
                color: AppColors.textMain,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (_premium.videosLockedForTrial)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  AppStrings.trialVideosActiveCardNote,
                  key: ValueKey('trial_videos_note'),
                  style: TextStyle(color: AppColors.primary),
                ),
              ),
            if (exp != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  trial
                      ? (_premium.willRenew
                            ? 'The trial ends on ${fmt.format(exp.toLocal())}; the subscription then starts unless you cancel in Google Play before that.'
                            : 'The trial ends on ${fmt.format(exp.toLocal())} (will not renew).')
                      : (_premium.willRenew
                            ? 'Renews on ${fmt.format(exp.toLocal())}.'
                            : 'Ends on ${fmt.format(exp.toLocal())} (will not renew).'),
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _plansArea() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }
    if (_error != null) {
      return _message(_error!, action: ('Retry', _load));
    }
    if (_offers.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _message(
            _premium.storeAvailable
                ? 'No subscription plans are available right now. Please try again later.'
                : (_required
                      ? 'Subscriptions are not available in this build.'
                      : 'Subscriptions are not available in this build. Everything free keeps working.'),
            action: _premium.storeAvailable ? ('Retry', _load) : null,
          ),
          if (_premium.storeAvailable || widget.locked)
            TextButton(
              onPressed: _busy == null ? _restore : null,
              child: const Text('Restore purchases'),
            ),
        ],
      );
    }
    final trial = _selected?.trial;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final o in _offers) _offerTile(o),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: _busy == null && _selected != null ? _buy : null,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
          ),
          child: _busy == 'buy'
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  trial == null ? 'Subscribe' : 'Start ${trial.label} trial',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
        ),
        TextButton(
          onPressed: _busy == null ? _restore : null,
          child: _busy == 'restore'
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Restore purchases'),
        ),
        const SizedBox(height: 4),
        Text(
          _disclosure(),
          key: const ValueKey('paywall_disclosure'),
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 11.5,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  /// Trial wording exists only when the selected store offer has a trial, and
  /// its length is the offer's own.
  String _disclosure() {
    final o = _selected;
    final price = o == null ? '' : ' (${o.priceString} per ${_periodWord(o)})';
    final trial = o?.trial;
    final trialPart = trial == null
        ? ''
        : 'This plan starts with a ${trial.label} trial from Google Play. '
              'Cancel in Google Play before the trial ends and you are not '
              'charged; otherwise the subscription starts at '
              '${o!.priceString} per ${_periodWord(o)}. ';
    return '${trialPart}RepTrack is an auto-renewing subscription$price. '
        'Payment is charged to your Google Play account at confirmation '
        '${trial == null ? '' : '(after the trial) '}and the subscription '
        'renews automatically each period at the then-current price unless '
        'you cancel at least 24 hours before the period ends. Manage or '
        'cancel any time in Google Play > Subscriptions; you keep access until '
        'the end of the paid period. Prices include applicable taxes as shown '
        'by Google Play.';
  }

  String _periodWord(PremiumOffer o) =>
      o.period == BillingPeriod.yearly ? 'year' : 'month';

  Widget _offerTile(PremiumOffer o) {
    final selected = _selected?.id == o.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: true,
        selected: selected,
        label:
            '${o.period == BillingPeriod.yearly ? 'Yearly' : 'Monthly'} plan, ${o.priceString}'
            '${o.trial == null ? '' : ', ${o.trial!.label} trial'}',
        child: Material(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.12)
              : AppColors.cardSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _selected = o),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: selected ? AppColors.primary : AppColors.textMuted,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              o.period == BillingPeriod.yearly
                                  ? 'Yearly'
                                  : 'Monthly',
                              style: const TextStyle(
                                color: AppColors.textMain,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                            if (_cfg.badgeFor(
                                  o.period == BillingPeriod.yearly,
                                ) !=
                                null)
                              Container(
                                key: ValueKey('badge_${o.period.name}'),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _cfg.badgeFor(
                                    o.period == BillingPeriod.yearly,
                                  )!,
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (o.trial != null)
                          Text(
                            '${o.trial!.label} trial first',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '${o.priceString} / ${_periodWord(o)}',
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        color: AppColors.textMain,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _message(String text, {(String, VoidCallback)? action}) {
    return Material(
      color: AppColors.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            if (action != null)
              TextButton(onPressed: action.$2, child: Text(action.$1)),
          ],
        ),
      ),
    );
  }
}
