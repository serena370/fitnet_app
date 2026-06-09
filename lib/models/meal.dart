import 'package:cloud_firestore/cloud_firestore.dart';

class Meal {
  const Meal({
    required this.id,
    required this.userId,
    required this.name,
    required this.mealType,
    required this.calories,
    required this.date,
    required this.notes,
  });

  final String id;
  final String userId;
  final String name;
  final String mealType;
  final int calories;
  final DateTime date;
  final String notes;

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'name': name,
      'mealType': mealType,
      'calories': calories,
      'date': Timestamp.fromDate(date),
      'notes': notes,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  factory Meal.fromFirestore(DocumentSnapshot<Map<String, dynamic>> document) {
    final data = document.data() ?? {};
    final timestamp = data['date'];

    return Meal(
      id: document.id,
      userId: data['userId'] as String? ?? '',
      name: data['name'] as String? ?? data['mealName'] as String? ?? 'Meal',
      mealType: data['mealType'] as String? ?? 'Other',
      calories: (data['calories'] as num?)?.toInt() ?? 0,
      date: timestamp is Timestamp
          ? timestamp.toDate()
          : data['timestamp'] is Timestamp
          ? (data['timestamp'] as Timestamp).toDate()
          : DateTime.now(),
      notes: data['notes'] as String? ?? '',
    );
  }
}
