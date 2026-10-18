/// Next wall-clock occurrence of a repeating routine time. Mirrors the native
/// `NextOccurrence.kt` used for the real alarms, so the UI ("next alarm") and
/// the scheduler agree.
///
/// Times are local wall-clock ("07:15" on ISO weekdays 1=Mon..7=Sun). Dates
/// are built with the `DateTime(y, m, d + n, h, m)` constructor (calendar
/// arithmetic), never by adding 24-hour durations, so DST changes cannot shift
/// the wall-clock time.
class NextOccurrence {
  static (int, int) parseTime(String hhmm) {
    final parts = hhmm.trim().split(':');
    final h = int.tryParse(parts.first) ?? 0;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    return (h.clamp(0, 23), m.clamp(0, 59));
  }

  /// First occurrence strictly after [now], moved earlier by [leadMinutes];
  /// null when [repeatDays] is empty.
  static DateTime? compute(
    DateTime now,
    String hhmm,
    List<int> repeatDays, {
    int leadMinutes = 0,
  }) {
    if (repeatDays.isEmpty) return null;
    final (h, m) = parseTime(hhmm);
    for (var offset = 0; offset <= 8; offset++) {
      final start = DateTime(now.year, now.month, now.day + offset, h, m);
      if (!repeatDays.contains(start.weekday)) continue;
      final candidate = start.subtract(Duration(minutes: leadMinutes));
      if (candidate.isAfter(now)) return candidate;
    }
    return null;
  }
}
