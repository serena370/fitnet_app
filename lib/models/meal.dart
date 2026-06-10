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
    this.quantity = 1,
    this.unit = '',
    this.caloriesEstimated = false,
    this.source = 'manual',
    this.protein,
    this.carbs,
    this.fats,
  });

  final String id;
  final String userId;
  final String name;
  final String mealType;
  final int calories;
  final DateTime date;
  final String notes;
  final double quantity;
  final String unit;
  final bool caloriesEstimated;

  /// Where the entry came from: 'manual', 'coach', or 'photo'.
  final String source;

  /// Macros are nullable on purpose: coach/manual entries usually do not
  /// estimate them, and showing fake "P:0 C:0 F:0" would be misleading.
  final int? protein;
  final int? carbs;
  final int? fats;

  bool get hasMacros => protein != null || carbs != null || fats != null;

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      // 'name' is the canonical field; 'mealName' is kept for backward
      // compatibility with older documents and readers.
      'name': name,
      'mealName': name,
      'mealType': mealType,
      'calories': calories,
      'date': Timestamp.fromDate(date),
      'timestamp': FieldValue.serverTimestamp(),
      'notes': notes,
      'quantity': quantity,
      'unit': unit,
      'caloriesEstimated': caloriesEstimated,
      'source': source,
      if (protein != null) 'protein': protein,
      if (carbs != null) 'carbs': carbs,
      if (fats != null) 'fats': fats,
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
      quantity: (data['quantity'] as num?)?.toDouble() ?? 1,
      unit: data['unit'] as String? ?? '',
      caloriesEstimated: data['caloriesEstimated'] as bool? ?? false,
      source: data['source'] as String? ?? 'manual',
      protein: (data['protein'] as num?)?.toInt(),
      carbs: (data['carbs'] as num?)?.toInt(),
      fats: (data['fats'] as num?)?.toInt(),
    );
  }
}
