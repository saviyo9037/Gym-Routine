/// Central user-facing strings for the access tiers (locked / trial / full).
/// Keep wording here, not inline in widgets.
class AppStrings {
  AppStrings._();

  // ---- exercise video area for TRIAL users (videos locked, all else open) ----
  static const String trialVideosLockedTitle =
      'Videos unlock with a full subscription';
  static const String trialVideosLockedSubscribe = 'Subscribe';
  static const String trialVideosLockedSemantics =
      'Exercise video locked. Videos unlock with a full subscription.';

  /// Shown at the top of the paywall when it was opened from the locked video
  /// area (never mentions a price or a trial length: those come from the store).
  static const String trialVideosPaywallReason =
      'Exercise videos unlock with a full subscription. Everything else in '
      'RepTrack already works during your trial.';

  /// Extra line on the "trial is active" card while videos are locked.
  static const String trialVideosActiveCardNote =
      'Exercise videos unlock when your trial becomes a full subscription.';

  // ---- exercises without any video: never a lock ----
  static const String noVideoYet = 'No demonstration video yet';
  static const String noVideoPhoto = 'Showing the exercise photo';

  // ---- tier names (Diagnostics) ----
  static const String tierLocked = 'locked';
  static const String tierTrial = 'trial';
  static const String tierFull = 'full';
}
