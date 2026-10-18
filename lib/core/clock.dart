import 'package:intl/intl.dart';

/// Single source of "now" for date-sensitive logic so tests can pin the clock
/// (midnight rollover, week boundaries, DST). Always device-local time.
class AppClock {
  static DateTime Function() _now = DateTime.now;

  static DateTime now() => _now();

  static void setForTesting(DateTime Function() clock) => _now = clock;

  static void reset() => _now = DateTime.now;

  /// Local calendar date as yyyy-MM-dd.
  static String dateKey(DateTime dt) => DateFormat('yyyy-MM-dd').format(dt);

  static String todayKey() => dateKey(now());

  static String tomorrowKey() {
    final n = now();
    return dateKey(DateTime(n.year, n.month, n.day + 1));
  }

  /// Monday (or Sunday when [weekStartsOnSunday]) of the week containing [dt],
  /// at local midnight. Uses calendar arithmetic, so DST shifts cannot move it.
  static DateTime weekStart(DateTime dt, {bool weekStartsOnSunday = false}) {
    final day = DateTime(dt.year, dt.month, dt.day);
    final offset = weekStartsOnSunday
        ? day.weekday %
              7 // Sunday(7) -> 0, Monday -> 1 ...
        : day.weekday - DateTime.monday;
    return DateTime(day.year, day.month, day.day - offset);
  }
}
