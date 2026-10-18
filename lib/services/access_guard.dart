/// Thrown by a write entry point when the app is locked (no subscription).
class AccessLockedException implements Exception {
  const AccessLockedException();
  @override
  String toString() => 'RepTrack is locked: a subscription is required.';
}

/// Defence in depth behind the root gate: write entry points (start a workout,
/// save a plan/routine/exercise, manual log) call [ensureWritable] so a locked
/// user can never change data even if some screen were reachable.
///
/// Reads, exports and already scheduled alarms are never blocked, and locking
/// never deletes or modifies existing data.
class AccessGuard {
  /// Installed by `CloudServices` at start-up. Default: nothing is locked, so
  /// unit tests and tools that do not install it behave as before.
  static bool Function() isLocked = () => false;

  static bool get locked => isLocked();

  static void ensureWritable() {
    if (isLocked()) throw const AccessLockedException();
  }
}
