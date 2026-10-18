/// Build-time cloud configuration. Values come ONLY from `--dart-define`
/// (see `.env.example`); nothing is stored in the repository. With none of
/// them set the app runs in "local only" mode: no accounts, no sync, no store
/// purchases, and every free feature works exactly the same.
class CloudConfig {
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );
  static const String revenueCatAndroidKey = String.fromEnvironment(
    'REVENUECAT_ANDROID_API_KEY',
  );
  static const String googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
  );

  /// Hosted legal pages (you must host them; no URL is built in). When empty
  /// the matching link is hidden in the app.
  static const String privacyPolicyUrl = String.fromEnvironment(
    'PRIVACY_POLICY_URL',
  );
  static const String termsUrl = String.fromEnvironment('TERMS_URL');

  /// Only https links are ever opened.
  static Uri? legalUri(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return null;
    final u = Uri.tryParse(v);
    if (u == null || u.scheme != 'https' || u.host.isEmpty) return null;
    return u;
  }

  static Uri? get privacyUri => legalUri(privacyPolicyUrl);
  static Uri? get termsUri => legalUri(termsUrl);

  static bool get supabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
  static bool get revenueCatConfigured => revenueCatAndroidKey.isNotEmpty;
  static bool get googleConfigured => googleWebClientId.isNotEmpty;

  /// Google Play's own subscription management page (public, fixed URL).
  static const String playSubscriptionsUrl =
      'https://play.google.com/store/account/subscriptions';
}
