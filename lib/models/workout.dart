import 'package:cloud_firestore/cloud_firestore.dart';

class Workout {
  const Workout({
    required this.id,
    required this.userId,
    required this.activityType,
    required this.durationMinutes,
    required this.caloriesBurned,
    required this.date,
    required this.notes,
  });

  final String id;
  final String userId;
  final String activityType;
  final int durationMinutes;
  final int caloriesBurned;
  final DateTime date;
  final String notes;

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'activityType': activityType,
      'durationMinutes': durationMinutes,
      'caloriesBurned': caloriesBurned,
      'date': Timestamp.fromDate(date),
      'notes': notes,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  factory Workout.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? {};
    final timestamp = data['date'];

    return Workout(
      id: document.id,
      userId: data['userId'] as String? ?? '',
      activityType: data['activityType'] as String? ?? 'Workout',
      durationMinutes: (data['durationMinutes'] as num?)?.toInt() ?? 0,
      caloriesBurned: (data['caloriesBurned'] as num?)?.toInt() ?? 0,
      date: timestamp is Timestamp ? timestamp.toDate() : DateTime.now(),
      notes: data['notes'] as String? ?? '',
    );
  }
}
