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
  });

  final String id;
  final String userId;
  final String title;
  final double targetValue;
  final double currentValue;
  final String unit;
  final String period;
  final DateTime createdAt;

  bool get isComplete => currentValue >= targetValue;

  double get progress {
    if (targetValue <= 0) return 0;
    return (currentValue / targetValue).clamp(0.0, 1.0).toDouble();
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
    };
  }

  factory FitnessGoal.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? {};
    final timestamp = data['createdAt'];

    return FitnessGoal(
      id: document.id,
      userId: data['userId'] as String? ?? '',
      title: data['title'] as String? ?? 'Fitness goal',
      targetValue: (data['targetValue'] as num?)?.toDouble() ?? 0,
      currentValue: (data['currentValue'] as num?)?.toDouble() ?? 0,
      unit: data['unit'] as String? ?? '',
      period: data['period'] as String? ?? 'Daily',
      createdAt: timestamp is Timestamp ? timestamp.toDate() : DateTime.now(),
    );
  }
}
