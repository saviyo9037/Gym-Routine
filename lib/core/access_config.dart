import 'package:flutter/foundation.dart';

import '../services/cloud_config.dart';

/// How the app is monetised.
///  * [subscriptionRequired] (default): the app is locked until the user has an
///    active subscription or a store-managed trial. Nothing is free.
///  * [freemium]: the previous model (free core, premium extras).
enum AccessModel { subscriptionRequired, freemium }

/// Single place that reads the access model.
///
/// Precedence (highest first):
///  1. [debugOverride] (tests only);
///  2. the REMOTE override from the admin panel's app config ([setRemote]),
///     with two safety rules:
///       * a remote value can never open a **release** build that has no
///         RevenueCat key (such a build stays locked whatever the server says);
///       * an unknown remote value fails CLOSED (subscription required);
///  3. the build-time value: `--dart-define=ACCESS_MODEL=subscription_required|freemium`
///     (default `subscription_required`).
class AccessConfig {
  static const String _define = String.fromEnvironment(
    'ACCESS_MODEL',
    defaultValue: 'subscription_required',
  );

  static AccessModel parse(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'freemium':
        return AccessModel.freemium;
      default:
        // Unknown values fail CLOSED (subscription required), never open.
        return AccessModel.subscriptionRequired;
    }
  }

  /// Trial users get everything except exercise videos while this is true
  /// (default). Build with `--dart-define=TRIAL_VIDEOS_LOCKED=false` to open
  /// videos during the trial; the server has the matching secret
  /// `TRIAL_VIDEOS_LOCKED=false` for the `video-url` function.
  static const bool _trialVideosLockedDefine = bool.fromEnvironment(
    'TRIAL_VIDEOS_LOCKED',
    defaultValue: true,
  );

  static bool? _trialVideosOverride;

  /// Test hook; pass null to restore the build-time value.
  @visibleForTesting
  static set trialVideosLockedOverride(bool? value) {
    _trialVideosOverride = value;
    revision.value++;
  }

  static bool get trialVideosLocked =>
      _trialVideosOverride ?? _trialVideosLockedDefine;

  static AccessModel? _override;
  static AccessModel? _remote;

  /// Bumped whenever the effective model may have changed, so listeners
  /// (PremiumService, the root gate) can re-evaluate.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Test hook; pass null to restore the build-time value.
  @visibleForTesting
  static set debugOverride(AccessModel? model) {
    _override = model;
    revision.value++;
  }

  /// Applies (or clears, with null) the remote override. Called by the app
  /// config service after it has validated a config.
  static void setRemote(AccessModel? model) {
    if (_remote == model) return;
    _remote = model;
    revision.value++;
  }

  @visibleForTesting
  static AccessModel? get remote => _remote;

  /// Whether the remote layer may currently relax the build's model.
  /// [releaseMode] / [revenueCatConfigured] are injectable for tests.
  static bool remoteMayOpen({bool? releaseMode, bool? revenueCatConfigured}) {
    final release = releaseMode ?? kReleaseMode;
    final rc = revenueCatConfigured ?? CloudConfig.revenueCatConfigured;
    return !(release && !rc);
  }

  static AccessModel get model {
    final o = _override;
    if (o != null) return o;
    final r = _remote;
    if (r != null) {
      if (r == AccessModel.freemium && !remoteMayOpen()) {
        return AccessModel.subscriptionRequired;
      }
      return r;
    }
    return parse(_define);
  }

  static bool get subscriptionRequired =>
      model == AccessModel.subscriptionRequired;
}
