import 'package:cloud_firestore/cloud_firestore.dart';

class FitnessGoal {
  const FitnessGoal({
    required this.id,
    required this.userId,
    required this.title,
    required this.targetValue,
    required this.currentValue,
    required this.unit,
    required this.period,
    required this.createdAt,
    this.resetAt,
  });

  final String id;
  final String userId;
  final String title;
  final double targetValue;
  final double currentValue;
  final String unit;
  final String period;
  final DateTime createdAt;
  final DateTime? resetAt;

  bool get isComplete => currentValue >= targetValue;

  bool get isExpired {
    if (isComplete) return false;
    final deadline = resetAt ?? _defaultResetAt;
    return DateTime.now().isAfter(deadline);
  }

  String get statusLabel {
    if (isComplete) return 'Completed';
    if (isExpired) return 'Expired / Needs reset';
    return 'Active';
  }

  String get periodLabel {
    if (period == 'Weekly') return 'Current week';
    return 'Today';
  }

  double get progress {
    if (targetValue <= 0) return 0;
    return (currentValue / targetValue).clamp(0.0, 1.0).toDouble();
  }

  DateTime get _defaultResetAt {
    if (period == 'Weekly') {
      final startOfDay = DateTime(
        createdAt.year,
        createdAt.month,
        createdAt.day,
      );
      final daysUntilNextWeek = 8 - startOfDay.weekday;
      return startOfDay.add(Duration(days: daysUntilNextWeek));
    }
    return DateTime(
      createdAt.year,
      createdAt.month,
      createdAt.day,
    ).add(const Duration(days: 1));
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'title': title,
      'targetValue': targetValue,
      'currentValue': currentValue,
      'unit': unit,
      'period': period,
      'createdAt': Timestamp.fromDate(createdAt),
      'resetAt': Timestamp.fromDate(resetAt ?? _defaultResetAt),
    };
  }

  factory FitnessGoal.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? {};
    final timestamp = data['createdAt'];
    final resetTimestamp = data['resetAt'];

    return FitnessGoal(
      id: document.id,
      userId: data['userId'] as String? ?? '',
      title: data['title'] as String? ?? 'Fitness goal',
      targetValue: (data['targetValue'] as num?)?.toDouble() ?? 0,
      currentValue: (data['currentValue'] as num?)?.toDouble() ?? 0,
      unit: data['unit'] as String? ?? '',
      period: data['period'] as String? ?? 'Daily',
      createdAt: timestamp is Timestamp ? timestamp.toDate() : DateTime.now(),
      resetAt: resetTimestamp is Timestamp ? resetTimestamp.toDate() : null,
    );
  }
}
