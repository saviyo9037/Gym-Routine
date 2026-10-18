import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/db_helper.dart';
import 'auth_service.dart';
import 'premium_service.dart';
import 'sync_engine.dart';
import 'sync_remote.dart';
import '../core/dev_log.dart';

enum SyncState {
  /// Build has no cloud configuration.
  notConfigured,
  signedOut,
  needsPremium,
  idle,
  syncing,
  error,

  /// Some tables synced, others failed; data is safe, a retry will continue.
  partial,

  /// This device's data was last synced with another account; the user must
  /// confirm before it is uploaded to the current one.
  needsAccountLink,
}

/// Decides WHEN sync may run and exposes its status to the UI.
/// Sync only runs when configured + signed in + premium; every failure leaves
/// local data untouched and is reported as [SyncState.error].
class SyncService extends ChangeNotifier {
  SyncService({
    required this._auth,
    required this._premium,
    required this._remoteFactory,
    DatabaseHelper? helper,
    this.onApplied,
  }) : _helper = helper ?? DatabaseHelper.instance {
    _auth.addListener(_onDependencyChanged);
    _premium.addListener(_onDependencyChanged);
  }

  final AuthService _auth;
  final PremiumService _premium;
  final SyncRemote Function(CloudUser user) _remoteFactory;
  final DatabaseHelper _helper;

  /// Called after remote changes were written locally (reschedule alarms...).
  final Future<void> Function()? onApplied;

  bool _running = false;
  bool _syncing = false;
  String? lastError;
  SyncReport? lastReport;
  DateTime? lastSyncedAt;
  bool _accountMismatch = false;
  bool _partial = false;

  SyncState get state {
    if (!_auth.isConfigured) return SyncState.notConfigured;
    if (!_auth.isSignedIn) return SyncState.signedOut;
    if (!_premium.canUse(PremiumFeature.cloudSync)) {
      return SyncState.needsPremium;
    }
    if (_syncing) return SyncState.syncing;
    if (_accountMismatch) return SyncState.needsAccountLink;
    if (_partial) return SyncState.partial;
    if (lastError != null) return SyncState.error;
    return SyncState.idle;
  }

  bool get canSync =>
      _auth.isConfigured &&
      _auth.isSignedIn &&
      _premium.canUse(PremiumFeature.cloudSync);

  Future<void> loadLastSynced() async {
    try {
      final db = await _helper.database;
      final v = await SyncEngine.getMeta(db, 'last_synced_at');
      lastSyncedAt = v == null ? null : DateTime.tryParse(v)?.toLocal();
      notifyListeners();
    } catch (_) {}
  }

  void _onDependencyChanged() {
    if (!_auth.isSignedIn) {
      _accountMismatch = false;
      _partial = false;
    }
    notifyListeners();
  }

  /// User confirmed: re-upload this device's data to the current account.
  Future<void> linkLocalDataToCurrentAccount() async {
    final user = _auth.user;
    if (user == null) return;
    await SyncEngine.linkAccount(_helper, user.id);
    _accountMismatch = false;
    lastError = null;
    notifyListeners();
    await syncNow();
  }

  /// Forget the cloud account (after account deletion): every row is marked
  /// for upload again so a future account receives this device's data.
  Future<void> forgetAccount() async {
    await SyncEngine.linkAccount(_helper, null);
    lastSyncedAt = null;
    _accountMismatch = false;
    _partial = false;
    lastError = null;
    notifyListeners();
  }

  /// Local changes not uploaded yet (for the diagnostics screen).
  Future<int> pendingChanges() async {
    final db = await _helper.database;
    return SyncEngine.pendingChanges(db);
  }

  /// Runs one sync pass if allowed. Safe to call from anywhere, any time.
  Future<void> syncNow() async {
    if (_running || !canSync) {
      notifyListeners();
      return;
    }
    final user = _auth.user!;
    _running = true;
    _syncing = true;
    lastError = null;
    _partial = false;
    notifyListeners();
    try {
      final engine = SyncEngine(remote: _remoteFactory(user), userId: user.id);
      final report = await engine.run(shouldCancel: () => !canSync);
      lastReport = report;
      if (report.applied > 0 || report.removedLocal > 0) {
        try {
          await onApplied?.call();
        } catch (_) {}
      }
      await loadLastSynced();
      _accountMismatch = false;
    } on SyncAccountMismatch {
      _accountMismatch = true;
      lastError =
          'This device was synced with a different account. '
          'Confirm to upload this device data to the current account.';
    } on SyncPartialFailure catch (e) {
      _partial = true;
      lastReport = e.report;
      lastError =
          'Some data could not be synced yet. Nothing was lost; '
          'it will be retried.';
    } on SocketException {
      lastError = 'You are offline. Your data is safe and will sync later.';
    } catch (e) {
      lastError = 'Sync failed. Your local data is unchanged. Try again later.';
      // Only the exception type is logged: messages can contain user data.
      devLog('Sync error: ${e.runtimeType}');
    } finally {
      _syncing = false;
      _running = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _auth.removeListener(_onDependencyChanged);
    _premium.removeListener(_onDependencyChanged);
    super.dispose();
  }
}
