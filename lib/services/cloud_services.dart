import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/db_helper.dart';
import 'access_guard.dart';
import 'account_switch.dart';
import 'auth_service.dart';
import 'catalogue_sync_service.dart';
import 'cloud_config.dart';
import 'premium_service.dart';
import 'routine_service.dart';
import 'secure_auth_storage.dart';
import 'supabase_sync_remote.dart';
import 'sync_service.dart';
import 'video_access_service.dart';
import '../core/dev_log.dart';

/// Tells the root gate when the store customer has been linked to the signed
/// in account, so a previous account's entitlement can never be shown to the
/// next one for even a moment.
class AccountBinding extends ChangeNotifier {
  String? _boundFor;
  bool _inProgress = false;

  bool get inProgress => _inProgress;

  /// True when the entitlement belongs to [auth]'s current user (or nobody is
  /// signed in / cloud is off, in which case there is nothing to link).
  bool isReady(AuthService auth) {
    if (!auth.isConfigured || !auth.isSignedIn) return true;
    return !_inProgress && _boundFor == auth.user!.id;
  }

  void begin() {
    _inProgress = true;
    notifyListeners();
  }

  void finish(String? userId) {
    _boundFor = userId;
    _inProgress = false;
    notifyListeners();
  }

  void reset() {
    _boundFor = null;
    _inProgress = false;
  }
}

/// Process-wide holder of the optional cloud features.
///
/// Before [initialize] (and in tests) every member is the safe "cloud not
/// configured" implementation, so any screen can read them without checks and
/// the app behaves exactly like the fully local app.
class CloudServices {
  static AuthService auth = NoCloudAuthService();
  static PremiumService premium = PremiumService(
    source: NoStoreEntitlementSource(),
    store: MemorySettingsStore(),
  );
  static SyncService sync = SyncService(
    auth: auth,
    premium: premium,
    remoteFactory: (_) => throw StateError('cloud not configured'),
  );
  static CatalogueSyncService? catalogue;
  static final AccountBinding binding = AccountBinding();
  static AccountSwitch accountSwitch = AccountSwitch();

  static bool _initialised = false;
  static String? _lastSeenUser;
  static AuthService? _attached;

  /// Wires [a] as the live auth service: whenever the signed-in identity
  /// changes the store customer is re-linked, and when an account LEAVES
  /// (sign-out or switch) the account-bound caches (protected videos and the
  /// local entitlement cache) are cleared. Workout data is never touched.
  /// Safe to call again with another service (tests).
  static void attachAuth(AuthService a) {
    _attached?.removeListener(_onAuthChanged);
    _generation++;
    _busy = false;
    _again = false;
    auth = a;
    _attached = a;
    _lastSeenUser = null;
    binding.reset();
    a.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  static bool _busy = false;
  static bool _again = false;
  static int _generation = 0;

  static Future<void> _onAuthChanged() async {
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    final gen = _generation;
    try {
      do {
        _again = false;
        final id = auth.user?.id;
        if (id == _lastSeenUser) continue;
        final previous = _lastSeenUser;
        _lastSeenUser = id;
        binding.begin();
        if (previous != null) await clearAccountCaches();
        if (gen != _generation) return; // auth service was replaced meanwhile
        if (auth.isConfigured) await premium.bindUser(id);
        if (gen != _generation) return;
        binding.finish(id);
      } while (_again && gen == _generation);
    } finally {
      if (gen == _generation) _busy = false;
    }
  }

  /// Deletes what belongs to the account that left: downloaded protected
  /// videos and the cached entitlement. NEVER touches workout data.
  static Future<void> clearAccountCaches() async {
    try {
      await VideoAccessService.instance.clearCache();
    } catch (e) {
      devLog('Video cache clear failed: ${e.runtimeType}');
    }
    try {
      final db = await DatabaseHelper.instance.database;
      await db.delete(
        'user_settings',
        where: 'key = ?',
        whereArgs: [PremiumService.cacheKey],
      );
    } catch (e) {
      devLog('Entitlement cache clear failed: ${e.runtimeType}');
    }
  }

  /// Connects the write-entry-point guard to the live [premium] service:
  /// when the app is locked (subscription required, none active) services
  /// refuse to create or change data. Safe to call repeatedly.
  static void installAccessGuard() {
    AccessGuard.isLocked = () => premium.isLocked;
  }

  /// Never throws: a failure leaves the app in local-only mode.
  static Future<void> initialize() async {
    installAccessGuard();
    if (_initialised) return;
    _initialised = true;
    try {
      premium = await PremiumService.create();
      await premium.initialize();
    } catch (e) {
      devLog('Premium init failed: ${e.runtimeType}');
    }

    SupabaseClient? client;
    if (CloudConfig.supabaseConfigured) {
      try {
        await Supabase.initialize(
          url: CloudConfig.supabaseUrl,
          // ignore: deprecated_member_use
          anonKey: CloudConfig.supabaseAnonKey,
          // Session + PKCE verifier live in the Android Keystore, never in
          // plain SharedPreferences.
          authOptions: FlutterAuthClientOptions(
            localStorage: SecureLocalStorage(const FlutterSecureKeyValue()),
            pkceAsyncStorage: SecureGotrueAsyncStorage(
              const FlutterSecureKeyValue(),
            ),
          ),
        );
        client = Supabase.instance.client;
        auth = SupabaseAuthService(client);
        catalogue = CatalogueSyncService(SupabaseCatalogueRemote(client));
      } catch (e) {
        devLog('Supabase init failed: ${e.runtimeType}');
        client = null;
      }
    }

    final c = client;
    sync = SyncService(
      auth: auth,
      premium: premium,
      remoteFactory: (_) => SupabaseSyncRemote(c!),
      onApplied: () => RoutineService().rescheduleAllRoutines(),
    );
    await sync.loadLastSynced();

    // Keep the store customer linked to the signed-in account and clear the
    // account-bound caches when an account leaves.
    attachAuth(auth);

    // Protected demonstration videos live in a private cache that must not
    // outlive the entitlement or the signed-in account.
    void syncVideoCache() {
      if (premium.accessLevel == AccessLevel.checking) return;
      final entitled = premium.videosAllowed && auth.isSignedIn;
      VideoAccessService.instance.onEntitlementChanged(entitled).catchError((
        Object e,
      ) {
        devLog('Video cache check failed: ${e.runtimeType}');
      });
    }

    premium.addListener(syncVideoCache);
    auth.addListener(syncVideoCache);
    syncVideoCache();
  }

  /// Called when the app returns to the foreground.
  static void onResume() {
    if (sync.canSync) sync.syncNow();
    if (catalogue != null) {
      catalogue!
          .sync()
          .then((r) {
            if (r.changed) devLog('Catalogue updated to v${r.toVersion}');
          })
          .catchError((Object e) {
            devLog('Catalogue sync skipped: ${e.runtimeType}');
            return null;
          });
    }
  }

  @visibleForTesting
  static void resetForTesting() {
    auth = NoCloudAuthService();
    premium = PremiumService(
      source: NoStoreEntitlementSource(),
      store: MemorySettingsStore(),
    );
    sync = SyncService(
      auth: auth,
      premium: premium,
      remoteFactory: (_) => throw StateError('cloud not configured'),
    );
    catalogue = null;
    _initialised = false;
    _attached?.removeListener(_onAuthChanged);
    _generation++;
    _busy = false;
    _again = false;
    _attached = null;
    _lastSeenUser = null;
    binding.reset();
    accountSwitch = AccountSwitch();
    AccessGuard.isLocked = () => false;
  }
}
