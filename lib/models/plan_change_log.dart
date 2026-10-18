import '../core/safe_cast.dart';

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
      id: asInt(map['id']),
      planId: asInt(map['plan_id']) ?? 0,
      planDate: asStr(map['plan_date']) ?? '',
      changeDescription: asStr(map['change_description']) ?? '',
      reason: asStr(map['reason']) ?? '',
      changedAt: asStr(map['changed_at']),
    );
  }
}
