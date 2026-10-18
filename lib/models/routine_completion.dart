import '../core/safe_cast.dart';

enum RoutineCompletionStatus {
  upcoming('Upcoming'),
  inProgress('In Progress'),
  completed('Completed'),
  skipped('Skipped');

  final String label;
  const RoutineCompletionStatus(this.label);
}

class RoutineCompletion {
  final int? id;
  final int routineId;
  final String date; // 'yyyy-MM-dd'
  final String status; // 'completed' | 'skipped'
  final String? notes;
  final String completedAt;

  RoutineCompletion({
    this.id,
    required this.routineId,
    required this.date,
    required this.status,
    this.notes,
    String? completedAt,
  }) : completedAt = completedAt ?? DateTime.now().toIso8601String();

  bool get isCompleted => status.toLowerCase() == 'completed';
  bool get isSkipped => status.toLowerCase() == 'skipped';

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'routine_id': routineId,
      'date': date,
      'status': status,
      'notes': notes,
      'completed_at': completedAt,
    };
  }

  factory RoutineCompletion.fromMap(Map<String, dynamic> map) {
    return RoutineCompletion(
      id: asInt(map['id']),
      routineId: asInt(map['routine_id']) ?? 0,
      date: asStr(map['date']) ?? '',
      status: asStr(map['status']) ?? 'completed',
      notes: asStr(map['notes']),
      completedAt: asStr(map['completed_at']),
    );
  }
}
