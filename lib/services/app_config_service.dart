import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/access_config.dart';
import '../core/dev_log.dart';
import 'cloud_config.dart';
import 'premium_service.dart' show DbSettingsStore, SettingsStore;

/// Remote app config (paywall copy, maintenance, minimum version, access-model
/// override) and announcements, edited in the admin panel (migration 0009).
///
/// SAFETY MODEL: the server is not trusted to be well-formed. Everything that
/// arrives is validated here against the same limits as the database, and any
/// field that fails is dropped to the built-in default. A bad or malicious
/// config can therefore never crash the app, blank the paywall or lock a user
/// out for longer than the config says. Offline / unconfigured / error =>
/// the last good config from the local cache, else the defaults.

/// Hard cap on what we are willing to parse at all (the real payload is < 3 KB).
const int kMaxConfigBytes = 20000;

final RegExp _semver = RegExp(r'^\d{1,4}\.\d{1,4}\.\d{1,4}(\+\d{1,6})?$');

/// Plain text only: no markup characters, no control characters, within [max].
String? _cleanText(Object? v, int max) {
  if (v is! String) return null;
  final t = v.trim();
  if (t.isEmpty || t.length > max) return null;
  if (t.contains('<') || t.contains('>')) return null;
  for (final c in t.codeUnits) {
    if (c < 0x20 || c == 0x7f) return null; // control characters
  }
  return t;
}

/// Compares "x.y.z[+build]" versions; the build number is only a tie-breaker.
/// Returns negative when [a] < [b]. Unparseable input compares as equal (so a
/// bad version never triggers "update required").
int compareVersions(String a, String b) {
  List<int>? parse(String s) {
    if (!_semver.hasMatch(s)) return null;
    final main = s.split('+');
    final parts = main[0].split('.').map(int.parse).toList();
    return [...parts, main.length > 1 ? int.parse(main[1]) : 0];
  }

  final pa = parse(a);
  final pb = parse(b);
  if (pa == null || pb == null) return 0;
  for (var i = 0; i < 4; i++) {
    if (pa[i] != pb[i]) return pa[i].compareTo(pb[i]);
  }
  return 0;
}

class AppConfig {
  const AppConfig({
    this.paywallTitle,
    this.paywallSubtitle,
    this.benefits = const [],
    this.badgeMonthly,
    this.badgeYearly,
    this.promoText,
    this.maintenanceMode = false,
    this.maintenanceMessage,
    this.minAppVersion,
    this.accessModelOverride,
  });

  /// Built-in defaults: every field null/empty = "use the app's own text".
  static const AppConfig defaults = AppConfig();

  static const String defaultMaintenanceMessage =
      'RepTrack is down for maintenance. Please try again in a little while. '
      'Your data on this phone is safe, and alarms you already set keep ringing.';

  final String? paywallTitle;
  final String? paywallSubtitle;
  final List<String> benefits;
  final String? badgeMonthly;
  final String? badgeYearly;
  final String? promoText;
  final bool maintenanceMode;
  final String? maintenanceMessage;
  final String? minAppVersion;

  /// null = no override. A present-but-unknown remote value is mapped to
  /// [AccessModel.subscriptionRequired] (fail closed) by [parse].
  final AccessModel? accessModelOverride;

  String get effectiveMaintenanceMessage =>
      maintenanceMessage ?? defaultMaintenanceMessage;

  String? badgeFor(bool yearly) => yearly ? badgeYearly : badgeMonthly;

  /// Strict, total parser: never throws, never trusts the input.
  static AppConfig parse(Object? raw) {
    try {
      Object? decoded = raw;
      if (raw is String) {
        if (raw.length > kMaxConfigBytes) return defaults;
        decoded = jsonDecode(raw);
      }
      if (decoded is! Map) return defaults;
      // Reject absurdly large payloads even when handed over as a Map.
      if (jsonEncode(decoded).length > kMaxConfigBytes) return defaults;
      final m = Map<String, Object?>.from(decoded);

      final benefits = <String>[];
      final rawBenefits = m['paywall_benefits'];
      if (rawBenefits is List) {
        for (final b in rawBenefits) {
          final t = _cleanText(b, 120);
          if (t != null) benefits.add(t);
          if (benefits.length >= 8) break;
        }
      }

      String? badge(String key) {
        final b = m['plan_badges'];
        return b is Map ? _cleanText(b[key], 24) : null;
      }

      final mv = m['min_app_version'];
      final minVersion = mv is String && _semver.hasMatch(mv.trim())
          ? mv.trim()
          : null;

      AccessModel? override;
      final am = m['access_model_override'];
      if (am != null) {
        override = switch (am) {
          'freemium' => AccessModel.freemium,
          'subscription_required' => AccessModel.subscriptionRequired,
          // Unknown / wrong type: fail CLOSED.
          _ => AccessModel.subscriptionRequired,
        };
      }

      return AppConfig(
        paywallTitle: _cleanText(m['paywall_title'], 80),
        paywallSubtitle: _cleanText(m['paywall_subtitle'], 200),
        benefits: List.unmodifiable(benefits),
        badgeMonthly: badge('monthly'),
        badgeYearly: badge('yearly'),
        promoText: _cleanText(m['promo_text'], 200),
        maintenanceMode: m['maintenance_mode'] == true,
        maintenanceMessage: _cleanText(m['maintenance_message'], 300),
        minAppVersion: minVersion,
        accessModelOverride: override,
      );
    } catch (_) {
      return defaults;
    }
  }

  Map<String, Object?> toJson() => {
    'paywall_title': paywallTitle,
    'paywall_subtitle': paywallSubtitle,
    'paywall_benefits': benefits,
    'plan_badges': {
      if (badgeMonthly != null) 'monthly': badgeMonthly,
      if (badgeYearly != null) 'yearly': badgeYearly,
    },
    'promo_text': promoText,
    'maintenance_mode': maintenanceMode,
    'maintenance_message': maintenanceMessage,
    'min_app_version': minAppVersion,
    'access_model_override': switch (accessModelOverride) {
      AccessModel.freemium => 'freemium',
      AccessModel.subscriptionRequired => 'subscription_required',
      null => null,
    },
  };

  @override
  bool operator ==(Object other) =>
      other is AppConfig && jsonEncode(toJson()) == jsonEncode(other.toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

enum AnnouncementLevel { info, warning }

class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.level,
    required this.startsAt,
    this.endsAt,
  });

  final String id;
  final String title;
  final String body;
  final AnnouncementLevel level;
  final DateTime startsAt;
  final DateTime? endsAt;

  /// Inside its window (the server already filters, this is defence in depth
  /// and handles a stale cache).
  bool isLive(DateTime now) =>
      !startsAt.isAfter(now) && (endsAt == null || endsAt!.isAfter(now));

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'level': level.name,
    'starts_at': startsAt.toUtc().toIso8601String(),
    'ends_at': endsAt?.toUtc().toIso8601String(),
  };

  /// Null when the row is not valid (it is simply not shown).
  static Announcement? parse(Object? raw) {
    try {
      if (raw is! Map) return null;
      final id = raw['id'];
      if (id is! String || id.isEmpty || id.length > 64) return null;
      final title = _cleanText(raw['title'], 80);
      final body = _cleanText(raw['body'], 500);
      if (title == null || body == null) return null;
      final level = switch (raw['level']) {
        'warning' => AnnouncementLevel.warning,
        'info' => AnnouncementLevel.info,
        _ => null,
      };
      if (level == null) return null;
      final starts = DateTime.tryParse('${raw['starts_at']}');
      if (starts == null) return null;
      final endsRaw = raw['ends_at'];
      final ends = endsRaw == null ? null : DateTime.tryParse('$endsRaw');
      if (endsRaw != null && ends == null) return null;
      if (ends != null && !ends.isAfter(starts)) return null;
      return Announcement(
        id: id,
        title: title,
        body: body,
        level: level,
        startsAt: starts,
        endsAt: ends,
      );
    } catch (_) {
      return null;
    }
  }

  /// Parses a list; invalid rows are dropped, at most [max] kept.
  static List<Announcement> parseList(Object? raw, {int max = 10}) {
    if (raw is! List) return const [];
    final out = <Announcement>[];
    final seen = <String>{};
    for (final r in raw) {
      final a = parse(r);
      if (a != null && seen.add(a.id)) out.add(a);
      if (out.length >= max) break;
    }
    return out;
  }
}

/// Where the config comes from (Supabase in the app, fakes in tests).
abstract class AppConfigRemote {
  bool get isAvailable;
  Future<Map<String, dynamic>?> fetchConfig();
  Future<List<dynamic>> fetchAnnouncements();
}

class NoAppConfigRemote implements AppConfigRemote {
  @override
  bool get isAvailable => false;
  @override
  Future<Map<String, dynamic>?> fetchConfig() async => null;
  @override
  Future<List<dynamic>> fetchAnnouncements() async => const [];
}

/// Reads the two public tables with the anon/user session (RLS exposes only
/// non-sensitive columns and active announcements).
class SupabaseAppConfigRemote implements AppConfigRemote {
  @override
  bool get isAvailable => CloudConfig.supabaseConfigured;

  SupabaseClient get _client => Supabase.instance.client;

  @override
  Future<Map<String, dynamic>?> fetchConfig() async {
    final row = await _client
        .from('app_config')
        .select(
          'paywall_title, paywall_subtitle, paywall_benefits, plan_badges, '
          'promo_text, maintenance_mode, maintenance_message, '
          'min_app_version, access_model_override',
        )
        .eq('id', 1)
        .maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  @override
  Future<List<dynamic>> fetchAnnouncements() async {
    return await _client
        .from('announcements')
        .select('id, title, body, level, starts_at, ends_at')
        .order('starts_at', ascending: false)
        .limit(10);
  }
}

class AppConfigService extends ChangeNotifier {
  AppConfigService({
    AppConfigRemote? remote,
    SettingsStore? store,
    DateTime Function()? clock,
    this.fetchTimeout = const Duration(seconds: 6),
    this.minRefreshInterval = const Duration(minutes: 10),
  }) : _remote = remote ?? NoAppConfigRemote(),
       _store = store ?? DbSettingsStore(),
       _clock = clock ?? DateTime.now;

  /// Process-wide instance used by the app; replaced by [configureForApp].
  static AppConfigService instance = AppConfigService();

  static const String cacheKey = 'app_config_cache';
  static const String announcementsKey = 'app_config_announcements';
  static const String dismissedKey = 'announcements_dismissed';

  final AppConfigRemote _remote;
  final SettingsStore _store;
  final DateTime Function() _clock;
  final Duration fetchTimeout;
  final Duration minRefreshInterval;

  AppConfig _config = AppConfig.defaults;
  List<Announcement> _announcements = const [];
  Set<String> _dismissed = {};
  DateTime? _lastFetchAttempt;
  Future<bool>? _inFlight;
  bool _disposed = false;

  /// True when the last refresh could not reach the server (cache/defaults in use).
  bool lastRefreshFailed = false;

  AppConfig get config => _config;

  /// Live, not dismissed, newest first.
  List<Announcement> get visibleAnnouncements {
    final now = _clock();
    return _announcements
        .where((a) => a.isLive(now) && !_dismissed.contains(a.id))
        .toList();
  }

  /// Production start-up: builds the service, loads the cache, starts a
  /// background refresh. Safe to call without cloud keys (defaults only).
  static Future<void> configureForApp() async {
    instance = forApp();
    await instance.initialize();
  }

  /// Production wiring: Supabase when configured, otherwise defaults only.
  static AppConfigService forApp() => AppConfigService(
    remote: CloudConfig.supabaseConfigured
        ? SupabaseAppConfigRemote()
        : NoAppConfigRemote(),
  );

  /// Loads the cache (validated again: it may predate a stricter parser),
  /// applies it, then refreshes in the background. Never throws.
  Future<void> initialize() async {
    try {
      final raw = await _store.read(cacheKey);
      if (raw != null) _config = AppConfig.parse(raw);
    } catch (_) {
      _config = AppConfig.defaults;
    }
    try {
      final raw = await _store.read(announcementsKey);
      if (raw != null) {
        _announcements = Announcement.parseList(
          raw.length > kMaxConfigBytes ? null : jsonDecode(raw),
        );
      }
    } catch (_) {
      _announcements = const [];
    }
    try {
      final raw = await _store.read(dismissedKey);
      if (raw != null) {
        final d = jsonDecode(raw);
        if (d is List) {
          _dismissed = d.whereType<String>().take(200).toSet();
        }
      }
    } catch (_) {
      _dismissed = {};
    }
    _apply();
    unawaited(refresh());
  }

  /// Fetches the server config. Rate-limited to [minRefreshInterval] unless
  /// [force]. A call that arrives while a fetch is running joins it instead
  /// of being dropped. On any failure the last good config stays in force.
  Future<bool> refresh({bool force = false}) {
    if (_disposed || !_remote.isAvailable) return Future.value(false);
    final running = _inFlight;
    if (running != null) return running;
    final now = _clock();
    final last = _lastFetchAttempt;
    if (!force && last != null && now.difference(last) < minRefreshInterval) {
      return Future.value(false);
    }
    _lastFetchAttempt = now;
    final f = _fetch().whenComplete(() => _inFlight = null);
    _inFlight = f;
    return f;
  }

  Future<bool> _fetch() async {
    var ok = false;
    try {
      final row = await _remote.fetchConfig().timeout(fetchTimeout);
      final rows = await _remote.fetchAnnouncements().timeout(fetchTimeout);
      if (row != null) {
        final parsed = AppConfig.parse(row);
        _config = parsed;
        await _safeWrite(cacheKey, jsonEncode(parsed.toJson()));
      }
      _announcements = Announcement.parseList(rows);
      await _safeWrite(
        announcementsKey,
        jsonEncode(_announcements.map((a) => a.toJson()).toList()),
      );
      lastRefreshFailed = false;
      ok = true;
    } catch (e) {
      lastRefreshFailed = true;
      devLog('App config refresh failed: ${e.runtimeType}');
    }
    _apply();
    return ok;
  }

  Future<void> dismissAnnouncement(String id) async {
    _dismissed = {..._dismissed, id};
    await _safeWrite(dismissedKey, jsonEncode(_dismissed.toList()));
    if (!_disposed) notifyListeners();
  }

  Future<void> _safeWrite(String key, String value) async {
    try {
      await _store.write(key, value);
    } catch (_) {}
  }

  /// Pushes the validated override into [AccessConfig] and tells listeners.
  void _apply() {
    AccessConfig.setRemote(_config.accessModelOverride);
    if (!_disposed) notifyListeners();
  }

  /// Update-required: the installed version is below the configured minimum.
  bool updateRequired(String installedVersion) {
    final min = _config.minAppVersion;
    if (min == null) return false;
    return compareVersions(installedVersion, min) < 0;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
