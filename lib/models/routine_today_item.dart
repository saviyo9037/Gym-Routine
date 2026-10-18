import '../core/clock.dart';
import 'routine.dart';
import 'routine_completion.dart';

class RoutineTodayItem {
  final Routine routine;
  final RoutineCompletion? completion;
  final DateTime date;

  RoutineTodayItem({
    required this.routine,
    this.completion,
    required this.date,
  });

  /// Computes the exact start DateTime for this item's scheduled date
  DateTime get startDateTime {
    final parts = routine.startTime.split(':');
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  /// Computes the exact end DateTime for this item's scheduled date (handling overnight cross-midnight)
  DateTime get endDateTime {
    final parts = routine.endTime.split(':');
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    if (routine.isOvernight) {
      // End time is on the next day
      return DateTime(date.year, date.month, date.day + 1, hour, minute);
    } else {
      return DateTime(date.year, date.month, date.day, hour, minute);
    }
  }

  /// Determines current lifecycle status: Upcoming, In Progress, Completed, Skipped
  RoutineCompletionStatus get status {
    if (completion != null) {
      if (completion!.isCompleted) return RoutineCompletionStatus.completed;
      if (completion!.isSkipped) return RoutineCompletionStatus.skipped;
    }

    // In progress whenever "now" falls inside [start, end). This also covers the
    // after-midnight tail of an overnight routine that started yesterday.
    final now = AppClock.now();
    if (now.isAfter(startDateTime) && now.isBefore(endDateTime)) {
      return RoutineCompletionStatus.inProgress;
    }

    return RoutineCompletionStatus.upcoming;
  }

  bool get isCompleted => status == RoutineCompletionStatus.completed;
  bool get isSkipped => status == RoutineCompletionStatus.skipped;
  bool get isInProgress => status == RoutineCompletionStatus.inProgress;
  bool get isUpcoming => status == RoutineCompletionStatus.upcoming;
}
