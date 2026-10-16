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
      id: map['id'] as int?,
      routineId: map['routine_id'] as int? ?? 0,
      date: map['date'] as String? ?? '',
      status: map['status'] as String? ?? 'completed',
      notes: map['notes'] as String?,
      completedAt: map['completed_at'] as String?,
    );
  }
}
