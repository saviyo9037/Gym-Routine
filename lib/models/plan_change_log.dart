class PlanChangeLog {
  final int? id;
  final int planId;
  final String planDate;
  final String changeDescription;
  final String reason;
  final String changedAt;

  PlanChangeLog({
    this.id,
    required this.planId,
    required this.planDate,
    required this.changeDescription,
    this.reason = 'Trainer recommendation',
    String? changedAt,
  }) : changedAt = changedAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'plan_id': planId,
      'plan_date': planDate,
      'change_description': changeDescription,
      'reason': reason,
      'changed_at': changedAt,
    };
  }

  factory PlanChangeLog.fromMap(Map<String, dynamic> map) {
    return PlanChangeLog(
      id: map['id'] as int?,
      planId: map['plan_id'] as int? ?? 0,
      planDate: map['plan_date'] as String? ?? '',
      changeDescription: map['change_description'] as String? ?? '',
      reason: map['reason'] as String? ?? '',
      changedAt: map['changed_at'] as String?,
    );
  }
}
