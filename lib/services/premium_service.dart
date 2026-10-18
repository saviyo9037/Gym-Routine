import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../core/access_config.dart';
import 'cloud_config.dart';
import 'comp_grant_source.dart';
import 'database_service.dart';
import 'mock_billing.dart';
import '../core/dev_log.dart';

/// Features that need the "premium" entitlement.
///
/// Deliberately NOT in this list (they are free forever and must never be
/// paywalled): workout logging, the exercise library, basic history, routines
/// and alarms/reminders, local backup.
enum PremiumFeature { cloudSync, advancedStats, unlimitedPlans, exportData }

enum BillingPeriod { monthly, yearly, other }

/// Builds a [TrialInfo] from store data; null when the length is not usable.
TrialInfo? trialFromParts(String unit, int value) {
  if (value <= 0) return null;
  const known = {'day', 'week', 'month', 'year'};
  if (!known.contains(unit)) return null;
  return TrialInfo(value, unit);
}

/// Length of a store-managed trial, exactly as the Play offer defines it.
/// Never hard-coded anywhere: it is read from the RevenueCat/Play offer.
class TrialInfo {
  const TrialInfo(this.value, this.unit);

  /// Number of [unit]s, > 0.
  final int value;

  /// 'day' | 'week' | 'month' | 'year'.
  final String unit;

  /// "1 day", "7 days", "1 month".
  String get label => '$value $unit${value == 1 ? '' : 's'}';

  @override
  bool operator ==(Object other) =>
      other is TrialInfo && other.value == value && other.unit == unit;

  @override
  int get hashCode => Object.hash(value, unit);

  @override
  String toString() => label;
}

class PremiumOffer {
  const PremiumOffer({
    required this.id,
    required this.title,
    required this.priceString,
    required this.period,
    this.trial,
    this.handle,
  });
  final String id;
  final String title;
  final String priceString;
  final BillingPeriod period;

  /// Trial that comes with this offer, or null when the offer has none.
  final TrialInfo? trial;

  /// Opaque store object (RevenueCat `Package`).
  final Object? handle;
}

class PremiumSnapshot {
  const PremiumSnapshot({
    required this.isActive,
    this.expiresAt,
    this.willRenew = false,
    this.productId,
    this.billingIssue = false,
    this.isTrial = false,
    required this.checkedAt,
  });

  final bool isActive;

  /// The entitlement is in its store-managed trial period.
  final bool isTrial;
  final DateTime? expiresAt;
  final bool willRenew;
  final String? productId;

  /// The store reported a failed renewal payment (Google "grace period" /
  /// "account hold" lead-in). RevenueCat keeps the entitlement active during
  /// the grace period.
  final bool billingIssue;
  final DateTime checkedAt;

  Map<String, dynamic> toJson() => {
    'a': isActive,
    'e': expiresAt?.toUtc().toIso8601String(),
    'r': willRenew,
    'p': productId,
    'b': billingIssue,
    't': isTrial,
    'c': checkedAt.toUtc().toIso8601String(),
  };

  static PremiumSnapshot? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    final checked = DateTime.tryParse('${j['c']}');
    if (checked == null) return null;
    return PremiumSnapshot(
      isActive: j['a'] == true,
      expiresAt: j['e'] == null ? null : DateTime.tryParse('${j['e']}'),
      willRenew: j['r'] == true,
      productId: j['p'] as String?,
      billingIssue: j['b'] == true,
      isTrial: j['t'] == true,
      checkedAt: checked,
    );
  }
}

/// Where entitlement truth comes from (RevenueCat in the app, fakes in tests).
abstract class EntitlementSource {
  bool get isAvailable;
  Future<PremiumSnapshot> fetch();
  Stream<PremiumSnapshot> get updates;
  Future<List<PremiumOffer>> offerings();
  Future<PremiumSnapshot> purchase(PremiumOffer offer);
  Future<PremiumSnapshot> restore();
  Future<void> logIn(String appUserId);
  Future<void> logOut();
}

class PremiumException implements Exception {
  const PremiumException(this.message, {this.cancelled = false});
  final String message;
  final bool cancelled;
  @override
  String toString() => message;
}

/// Simple key/value persistence (user_settings in SQLite in the app).
abstract class SettingsStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class DbSettingsStore implements SettingsStore {
  DbSettingsStore([DatabaseService? db]) : _db = db ?? DatabaseService();
  final DatabaseService _db;

  @override
  Future<String?> read(String key) async {
    final v = await _db.getSetting(key, defaultValue: '');
    return v.isEmpty ? null : v;
  }

  @override
  Future<void> write(String key, String value) => _db.setSetting(key, value);
}

class MemorySettingsStore implements SettingsStore {
  final Map<String, String> data = {};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
}

/// Used when no store is configured: everyone is on the free plan.
class NoStoreEntitlementSource implements EntitlementSource {
  @override
  bool get isAvailable => false;
  @override
  Future<PremiumSnapshot> fetch() async =>
      PremiumSnapshot(isActive: false, checkedAt: DateTime.now());
  @override
  Stream<PremiumSnapshot> get updates => const Stream.empty();
  @override
  Future<List<PremiumOffer>> offerings() async => const [];
  @override
  Future<PremiumSnapshot> purchase(PremiumOffer offer) async =>
      throw const PremiumException('Purchases are not set up in this build.');
  @override
  Future<PremiumSnapshot> restore() async =>
      throw const PremiumException('Purchases are not set up in this build.');
  @override
  Future<void> logIn(String appUserId) async {}
  @override
  Future<void> logOut() async {}
}

/// RevenueCat implementation (Google Play Billing). Entitlement id: "premium".
class RevenueCatEntitlementSource implements EntitlementSource {
  RevenueCatEntitlementSource._();

  static const entitlementId = 'premium';
  final _controller = StreamController<PremiumSnapshot>.broadcast();

  static Future<RevenueCatEntitlementSource> configure(String apiKey) async {
    await Purchases.configure(PurchasesConfiguration(apiKey));
    final s = RevenueCatEntitlementSource._();
    Purchases.addCustomerInfoUpdateListener(
      (info) => s._controller.add(_snapshot(info)),
    );
    return s;
  }

  /// Trial of a store product as the offer defines it (Google base-plan offer
  /// free phase, or a zero-price introductory price). Null = no trial.
  static TrialInfo? trialOf(StoreProduct product) {
    final free = product.defaultOption?.freePhase?.billingPeriod;
    if (free != null && free.value > 0) {
      return trialFromParts(free.unit.name, free.value);
    }
    final intro = product.introductoryPrice;
    if (intro != null && intro.price == 0 && intro.periodNumberOfUnits > 0) {
      return trialFromParts(
        intro.periodUnit.name,
        intro.periodNumberOfUnits * (intro.cycles < 1 ? 1 : intro.cycles),
      );
    }
    return null;
  }

  static PremiumSnapshot _snapshot(CustomerInfo info) {
    final e = info.entitlements.active[entitlementId];
    return PremiumSnapshot(
      isActive: e?.isActive ?? false,
      expiresAt: e?.expirationDate == null
          ? null
          : DateTime.tryParse(e!.expirationDate!),
      willRenew: e?.willRenew ?? false,
      productId: e?.productIdentifier,
      billingIssue: e?.billingIssueDetectedAt != null,
      isTrial: e?.periodType == PeriodType.trial,
      checkedAt: DateTime.now(),
    );
  }

  @override
  bool get isAvailable => true;

  @override
  Future<PremiumSnapshot> fetch() async =>
      _snapshot(await Purchases.getCustomerInfo());

  @override
  Stream<PremiumSnapshot> get updates => _controller.stream;

  @override
  Future<List<PremiumOffer>> offerings() async {
    final offerings = await Purchases.getOfferings();
    final current = offerings.current;
    if (current == null) return const [];
    final out = <PremiumOffer>[];
    for (final p in current.availablePackages) {
      final period = switch (p.packageType) {
        PackageType.monthly => BillingPeriod.monthly,
        PackageType.annual => BillingPeriod.yearly,
        _ => BillingPeriod.other,
      };
      if (period == BillingPeriod.other) continue;
      out.add(
        PremiumOffer(
          id: p.identifier,
          title: p.storeProduct.title,
          priceString: p.storeProduct.priceString,
          period: period,
          trial: trialOf(p.storeProduct),
          handle: p,
        ),
      );
    }
    out.sort((a, b) => a.period.index.compareTo(b.period.index));
    return out;
  }

  @override
  Future<PremiumSnapshot> purchase(PremiumOffer offer) async {
    final pkg = offer.handle;
    if (pkg is! Package) {
      throw const PremiumException('This plan is not available right now.');
    }
    try {
      final res = await Purchases.purchase(PurchaseParams.package(pkg));
      return _snapshot(res.customerInfo);
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        throw const PremiumException('Purchase cancelled.', cancelled: true);
      }
      throw const PremiumException(
        'The purchase could not be completed. You were not charged.',
      );
    }
  }

  @override
  Future<PremiumSnapshot> restore() async {
    try {
      return _snapshot(await Purchases.restorePurchases());
    } on PlatformException {
      throw const PremiumException(
        'Could not restore purchases. Check your connection and try again.',
      );
    }
  }

  @override
  Future<void> logIn(String appUserId) async {
    await Purchases.logIn(appUserId);
  }

  @override
  Future<void> logOut() async {
    try {
      await Purchases.logOut();
    } on PlatformException {
      // Already anonymous.
    }
  }
}

enum PremiumStatus { unknown, free, premium }

/// Every state an entitlement can be in. Only [active], [trial],
/// [cancelledActive] and [gracePeriod] grant access.
enum EntitlementState {
  /// Not loaded yet.
  unknown,

  /// Never subscribed (or the entitlement is gone).
  free,

  /// Paid and renewing.
  active,

  /// Inside the store-managed free trial (full access, will convert unless
  /// cancelled before it ends).
  trial,

  /// Cancelled (will not renew) but paid up until [PremiumSnapshot.expiresAt].
  cancelledActive,

  /// A renewal payment failed; the store keeps access during its grace period.
  gracePeriod,

  /// Ended: expired, refunded or revoked (the store cannot tell the app why).
  expired,

  /// The cached entitlement could not be re-verified for too long (or the
  /// phone clock was moved back): treated as free until verified again.
  staleOffline,

  /// No paid subscription, but RepTrack staff granted free ("comp") access
  /// that is still valid (not revoked, not expired).
  comp,
}

class EntitlementDecision {
  const EntitlementDecision(
    this.state, {
    this.isPremium = false,
    this.offline = false,
  });
  final EntitlementState state;
  final bool isPremium;

  /// True when this answer comes from the cached snapshot (no verification
  /// succeeded in this app session).
  final bool offline;

  @override
  String toString() => '$state premium=$isPremium offline=$offline';
}

/// The ONE pure rule that turns a snapshot into an entitlement state.
///
///  * a cached "active" is trusted for [offlineGrace] after the last
///    successful check, never longer; a snapshot "from the future" (phone
///    clock moved back) is not trusted;
///  * past `expiresAt` access ends, except for a billing problem where the
///    store's grace period is honoured for at most [maxGraceAfterExpiry];
///  * cancelled-but-paid stays premium until `expiresAt`;
///  * refunds/revocations arrive as an inactive entitlement and are `expired`.
EntitlementDecision deriveEntitlement({
  required PremiumSnapshot? snapshot,
  required DateTime now,
  required bool verifiedThisSession,
  bool initialised = true,
  Duration offlineGrace = const Duration(days: 14),
  Duration maxGraceAfterExpiry = const Duration(days: 16),
}) {
  if (!initialised) return const EntitlementDecision(EntitlementState.unknown);
  final s = snapshot;
  if (s == null) return const EntitlementDecision(EntitlementState.free);

  final exp = s.expiresAt;
  final offline = !verifiedThisSession;

  if (!s.isActive) {
    final ended = exp != null && !exp.isAfter(now);
    return EntitlementDecision(
      ended ? EntitlementState.expired : EntitlementState.free,
      offline: offline,
    );
  }

  late EntitlementState state;
  if (exp != null && !exp.isAfter(now)) {
    final inGrace =
        s.billingIssue && now.difference(exp) <= maxGraceAfterExpiry;
    state = inGrace ? EntitlementState.gracePeriod : EntitlementState.expired;
  } else if (s.billingIssue) {
    state = EntitlementState.gracePeriod;
  } else if (s.isTrial) {
    state = EntitlementState.trial;
  } else if (!s.willRenew) {
    state = EntitlementState.cancelledActive;
  } else {
    state = EntitlementState.active;
  }
  if (state == EntitlementState.expired) {
    return EntitlementDecision(state, offline: offline);
  }

  if (offline) {
    final age = now.difference(s.checkedAt);
    final fromFuture = s.checkedAt.isAfter(now.add(const Duration(minutes: 5)));
    if (fromFuture || age > offlineGrace) {
      return const EntitlementDecision(
        EntitlementState.staleOffline,
        offline: true,
      );
    }
  }
  return EntitlementDecision(state, isPremium: true, offline: offline);
}

/// What the app lets the user do. The single answer behind the root gate.
enum AccessLevel {
  /// Entitlement not known yet (cold start): show a loader, never the paywall.
  checking,

  /// Trial / subscription / valid offline cache (or freemium mode).
  full,

  /// No valid entitlement: only the locked screen is reachable.
  locked,
}

/// The three access tiers. Everything works the same in [trial] and [full]
/// (plans, routines, alarms, history, stats, charts, sync, export) EXCEPT
/// exercise videos, which [trial] locks while `TRIAL_VIDEOS_LOCKED` is true.
enum AccessTier {
  /// No active entitlement (or not determined yet): the locked screen.
  locked,

  /// Inside a store-managed free trial.
  trial,

  /// Paid entitlement, comp grant or store billing grace period.
  full,
}

/// The ONLY place that decides what is premium and, through [accessLevel], the
/// AccessGate for the subscription-required model.
class PremiumService extends ChangeNotifier {
  PremiumService({
    required this._source,
    required this._store,
    DateTime Function()? clock,
    this.fetchTimeout = const Duration(seconds: 8),
    this.retryBase = const Duration(seconds: 20),
    this.retryMax = const Duration(minutes: 10),
    this._compSource,
  }) : _clock = clock ?? DateTime.now {
    _sub = _source.updates.listen(_apply);
    // A remote access-model change must re-evaluate the gate immediately.
    AccessConfig.revision.addListener(_onAccessConfigChanged);
  }

  void _onAccessConfigChanged() {
    if (!_disposed) notifyListeners();
  }

  /// How long a store check may take before it counts as "unavailable".
  final Duration fetchTimeout;

  /// First retry delay after a failed check; doubles up to [retryMax].
  final Duration retryBase;
  final Duration retryMax;
  Timer? _retryTimer;
  int _retryAttempt = 0;
  bool _firstAnswer = false;
  bool _disposed = false;

  /// Plans a free user may keep (creating more needs premium).
  static const int freePlanLimit = 2;

  /// How long a cached "premium" is trusted without a successful check.
  static const Duration offlineGrace = Duration(days: 14);
  static const String cacheKey = 'premium_snapshot';

  final EntitlementSource _source;
  final SettingsStore _store;
  final DateTime Function() _clock;
  StreamSubscription<PremiumSnapshot>? _sub;

  PremiumSnapshot? _snapshot;
  bool _verifiedThisSession = false;
  bool _initialised = false;
  String? lastError;

  // ---- comp ("manual premium") access granted by staff ----------------------
  final CompGrantSource? _compSource;
  static const String compCacheKey = 'comp_snapshot';
  PremiumSnapshot? _comp; // isActive/expiresAt of the signed-in user's comp row
  String? _compUser; // account the cached comp row belongs to
  bool _compVerifiedThisSession = false;
  bool _compInFlight = false;

  bool get storeAvailable => _source.isAvailable;

  /// The mock billing source (debug builds with MOCK_BILLING=true), else null.
  /// Guarded by the const `kDebugMode` so release builds never expose it.
  MockEntitlementSource? get mock {
    if (!kDebugMode) return null;
    final s = _source;
    return s is MockEntitlementSource ? s : null;
  }

  EntitlementDecision get decision => deriveEntitlement(
    snapshot: _snapshot,
    now: _clock(),
    verifiedThisSession: _verifiedThisSession,
    initialised: _initialised,
    offlineGrace: offlineGrace,
  );

  /// Same pure rule as for the subscription, applied to the comp row: access
  /// ends at its expiry (no grace), a revoked/inactive grant never counts, and
  /// a cached grant that has not been re-verified for more than the offline
  /// window (or whose check is from the future) is not trusted.
  EntitlementDecision get compDecision => deriveEntitlement(
    snapshot: _comp,
    now: _clock(),
    verifiedThisSession: _compVerifiedThisSession,
    initialised: _initialised,
    offlineGrace: offlineGrace,
  );

  bool get hasCompAccess => _compSource != null && compDecision.isPremium;

  /// Paid/trial state; when that gives no access but comp access is valid the
  /// state is [EntitlementState.comp].
  EntitlementState get entitlementState {
    final d = decision;
    if (d.isPremium) return d.state;
    if (hasCompAccess) return EntitlementState.comp;
    return d.state;
  }

  bool get isPremium => decision.isPremium || hasCompAccess;

  /// Debug builds without a store key (local development) are not locked, so
  /// the app stays usable. Release builds without a key stay locked.
  bool get _devOpen =>
      AccessConfig.subscriptionRequired &&
      !_source.isAvailable &&
      !kReleaseMode;

  /// THE access decision (see [AccessLevel]).
  AccessLevel get accessLevel {
    if (!AccessConfig.subscriptionRequired) return AccessLevel.full;
    if (!_initialised) return AccessLevel.checking;
    if (isPremium || _devOpen) return AccessLevel.full;
    if (_source.isAvailable && !_firstAnswer && _snapshot == null) {
      return AccessLevel.checking;
    }
    // A comp grant may still be on its way (first launch after the grant).
    if (_compInFlight && _comp == null) return AccessLevel.checking;
    return AccessLevel.locked;
  }

  /// THE tier (see [AccessTier]); the single source for the video lock.
  /// Entitlement-based, so a freemium build still reports `locked` for a
  /// user without one (videos stay behind the entitlement in every model).
  AccessTier get tier {
    if (_devOpen) return AccessTier.full; // debug build without a store key
    if (!_initialised) return AccessTier.locked;
    // A valid comp grant is a full entitlement even beside a store trial.
    if (hasCompAccess) return AccessTier.full;
    switch (decision.state) {
      case EntitlementState.active:
      case EntitlementState.cancelledActive:
      case EntitlementState.gracePeriod:
        return AccessTier.full;
      case EntitlementState.trial:
        return AccessTier.trial;
      case EntitlementState
          .comp: // never produced by [decision]; kept exhaustive
        return AccessTier.full;
      case EntitlementState.unknown:
      case EntitlementState.free:
      case EntitlementState.expired:
      case EntitlementState.staleOffline:
        return AccessTier.locked;
    }
  }

  /// Exercise videos may be requested / played. False for [AccessTier.locked]
  /// and, while `TRIAL_VIDEOS_LOCKED` is true, for [AccessTier.trial].
  bool get videosAllowed =>
      tier == AccessTier.full ||
      (tier == AccessTier.trial && !AccessConfig.trialVideosLocked);

  /// The user is in a trial and videos are locked for trials: the video area
  /// shows the blurred photo + Subscribe, and no signed URL is ever requested.
  bool get videosLockedForTrial =>
      tier == AccessTier.trial && AccessConfig.trialVideosLocked;

  bool get hasFullAccess => accessLevel == AccessLevel.full;
  bool get isLocked => accessLevel == AccessLevel.locked;
  bool get isChecking => accessLevel == AccessLevel.checking;

  /// The store could not be reached and nothing verified this session.
  bool get verificationFailed => lastError != null && !_verifiedThisSession;

  /// True while the user is in the store-managed trial.
  bool get isTrial => decision.state == EntitlementState.trial;

  PremiumStatus get status => !_initialised
      ? PremiumStatus.unknown
      : (isPremium ? PremiumStatus.premium : PremiumStatus.free);

  DateTime? get expiresAt => _snapshot?.expiresAt;
  bool get willRenew => _snapshot?.willRenew ?? false;

  bool canUse(PremiumFeature feature) {
    switch (feature) {
      case PremiumFeature.cloudSync:
      case PremiumFeature.advancedStats:
      case PremiumFeature.unlimitedPlans:
      case PremiumFeature.exportData:
        return isPremium || _devOpen;
    }
  }

  /// Subscription-required: everyone with access has unlimited plans.
  /// Freemium: creating a new plan is blocked once a free user has
  /// [freePlanLimit]. Existing plans are never removed or locked.
  bool canCreatePlan(int existingPlans) {
    if (AccessConfig.subscriptionRequired) return hasFullAccess;
    return isPremium || existingPlans < freePlanLimit;
  }

  Future<void> initialize() async {
    try {
      final raw = await _store.read(cacheKey);
      if (raw != null) {
        _snapshot = PremiumSnapshot.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      }
    } catch (_) {
      _snapshot = null; // corrupt cache: behave as free until verified
    }
    await _loadCompCache();
    _initialised = true;
    _firstAnswer = _snapshot != null;
    notifyListeners();
    await refresh();
  }

  Future<void> _loadCompCache() async {
    final source = _compSource;
    if (source == null) return;
    try {
      final raw = await _store.read(compCacheKey);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final user = j['u'] as String?;
      // A cached grant is valid for ONE account only.
      if (user == null || user != source.userId) {
        await _store.write(compCacheKey, '');
        return;
      }
      _comp = PremiumSnapshot.fromJson(j['s'] as Map<String, dynamic>?);
      _compUser = _comp == null ? null : user;
    } catch (_) {
      _comp = null; // corrupt cache: no comp until verified
      _compUser = null;
    }
  }

  /// Fetches the signed-in user's comp grant. Never throws: on failure the
  /// cache stays (and ages out under the offline rule). A server answer of
  /// "no row" clears it.
  Future<void> _refreshComp() async {
    final source = _compSource;
    if (source == null) return;
    final uid = source.userId;
    if (uid == null) {
      await _clearComp();
      return;
    }
    if (_compUser != null && _compUser != uid) await _clearComp();
    _compInFlight = true;
    try {
      final g = await source.fetch().timeout(fetchTimeout);
      if (source.userId != uid) return; // account switched while waiting
      _comp = g == null
          ? null
          : PremiumSnapshot(
              isActive: g.isActive,
              expiresAt: g.expiresAt,
              checkedAt: _clock(),
            );
      _compUser = g == null ? null : uid;
      _compVerifiedThisSession = true;
      try {
        await _store.write(
          compCacheKey,
          _comp == null ? '' : jsonEncode({'u': uid, 's': _comp!.toJson()}),
        );
      } catch (_) {}
    } catch (_) {
      // Offline / server error: keep whatever is cached.
    } finally {
      _compInFlight = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _clearComp() async {
    final had = _comp != null;
    _comp = null;
    _compUser = null;
    _compVerifiedThisSession = false;
    try {
      await _store.write(compCacheKey, '');
    } catch (_) {}
    if (had && !_disposed) notifyListeners();
  }

  /// Re-checks with the store. On failure (no network, store unavailable, or
  /// no answer within [fetchTimeout]) the cached state is kept, an automatic
  /// retry with exponential backoff is scheduled and nothing hard-fails.
  Future<void> refresh() async {
    final comp = _compSource == null ? Future<void>.value() : _refreshComp();
    try {
      _apply(await _source.fetch().timeout(fetchTimeout));
      lastError = null;
      _retryAttempt = 0;
      _retryTimer?.cancel();
    } catch (e) {
      lastError = 'Could not verify your subscription - retry.';
      _firstAnswer = true; // stop showing the loader; show the retry state
      _scheduleRetry();
      if (!_disposed) notifyListeners();
    }
    await comp;
  }

  void _scheduleRetry() {
    if (_disposed || !_source.isAvailable) return;
    _retryTimer?.cancel();
    var delay = retryBase * (1 << (_retryAttempt > 10 ? 10 : _retryAttempt));
    if (delay > retryMax) delay = retryMax;
    _retryAttempt++;
    _retryTimer = Timer(delay, () => unawaited(refresh()));
  }

  void _apply(PremiumSnapshot s) {
    _snapshot = s;
    _verifiedThisSession = true;
    _initialised = true;
    _firstAnswer = true;
    lastError = null;
    unawaited(_persist(s));
    notifyListeners();
  }

  Future<void> _persist(PremiumSnapshot s) async {
    try {
      await _store.write(cacheKey, jsonEncode(s.toJson()));
    } catch (_) {}
  }

  Future<List<PremiumOffer>> offerings() => _source.offerings();

  Future<void> purchase(PremiumOffer offer) async {
    _apply(await _source.purchase(offer));
  }

  Future<void> restore() async {
    _apply(await _source.restore());
  }

  /// Link the store customer to the signed-in account (and back).
  Future<void> bindUser(String? userId) async {
    // Comp access belongs to one account: drop it on sign-out / account switch.
    if (_compSource != null && (userId == null || userId != _compUser)) {
      await _clearComp();
    }
    try {
      if (userId == null) {
        await _source.logOut();
      } else {
        await _source.logIn(userId);
      }
      await refresh();
    } catch (_) {
      // Linking is best effort; entitlements stay as last known.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    AccessConfig.revision.removeListener(_onAccessConfigChanged);
    _retryTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  /// Production factory: RevenueCat when configured, otherwise free-only.
  static Future<PremiumService> create() async {
    EntitlementSource source = NoStoreEntitlementSource();
    final store = DbSettingsStore();
    if (MockBilling.enabled) {
      // DEBUG-ONLY (const-false in release builds): fake offers, no RevenueCat.
      source = MockEntitlementSource(store: store);
    } else if (CloudConfig.revenueCatConfigured) {
      try {
        source = await RevenueCatEntitlementSource.configure(
          CloudConfig.revenueCatAndroidKey,
        );
      } catch (e) {
        devLog('RevenueCat configure failed: ${e.runtimeType}');
      }
    }
    return PremiumService(
      source: source,
      store: store,
      compSource: CloudConfig.supabaseConfigured
          ? SupabaseCompGrantSource()
          : null,
    );
  }
}
