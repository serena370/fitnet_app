enum FoodLogIntent {
  logFood('log_food'),
  chat('chat'),
  progressAnalysis('progress_analysis'),
  unknown('unknown');

  const FoodLogIntent(this.value);

  final String value;

  static FoodLogIntent fromValue(Object? value) {
    return FoodLogIntent.values.firstWhere(
      (intent) => intent.value == value,
      orElse: () => FoodLogIntent.unknown,
    );
  }
}

enum MealType {
  breakfast('breakfast', 'Breakfast'),
  lunch('lunch', 'Lunch'),
  dinner('dinner', 'Dinner'),
  snack('snack', 'Snack'),
  unknown('unknown', 'Unknown');

  const MealType(this.value, this.label);

  final String value;
  final String label;

  static MealType fromValue(Object? value) {
    final lower = value?.toString().toLowerCase();
    return MealType.values.firstWhere(
      (mealType) => mealType.value == lower,
      orElse: () => MealType.unknown,
    );
  }
}

class FoodLogDraft {
  const FoodLogDraft({
    required this.intent,
    required this.mealType,
    required this.foodName,
    required this.quantity,
    required this.unit,
    required this.calories,
    required this.caloriesEstimated,
    required this.confidence,
    required this.shortDescription,
    required this.needsConfirmation,
  });

  final FoodLogIntent intent;
  final MealType mealType;
  final String foodName;
  final double quantity;
  final String unit;
  final int calories;
  final bool caloriesEstimated;
  final double confidence;
  final String shortDescription;
  final bool needsConfirmation;

  bool get isReadyToSave {
    return intent == FoodLogIntent.logFood &&
        !needsConfirmation &&
        foodName.trim().isNotEmpty &&
        mealType != MealType.unknown &&
        calories > 0 &&
        shortDescription.trim().isNotEmpty &&
        shortDescription.length <= 80;
  }

  String get displayQuantity {
    return quantity == quantity.roundToDouble()
        ? quantity.toStringAsFixed(0)
        : quantity.toStringAsFixed(1);
  }

  FoodLogDraft copyWith({
    FoodLogIntent? intent,
    MealType? mealType,
    String? foodName,
    double? quantity,
    String? unit,
    int? calories,
    bool? caloriesEstimated,
    double? confidence,
    String? shortDescription,
    bool? needsConfirmation,
  }) {
    return FoodLogDraft(
      intent: intent ?? this.intent,
      mealType: mealType ?? this.mealType,
      foodName: foodName ?? this.foodName,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      calories: calories ?? this.calories,
      caloriesEstimated: caloriesEstimated ?? this.caloriesEstimated,
      confidence: confidence ?? this.confidence,
      shortDescription: shortDescription ?? this.shortDescription,
      needsConfirmation: needsConfirmation ?? this.needsConfirmation,
    );
  }

  factory FoodLogDraft.fromJson(Map<String, dynamic> json) {
    return FoodLogDraft(
      intent: FoodLogIntent.fromValue(json['intent']),
      mealType: MealType.fromValue(json['mealType']),
      foodName: (json['foodName'] as String? ?? '').trim(),
      quantity: _readDouble(json['quantity'], fallback: 1),
      unit: (json['unit'] as String? ?? 'serving').trim(),
      calories: _readInt(json['calories']),
      caloriesEstimated: json['caloriesEstimated'] == true,
      confidence: _readDouble(json['confidence']),
      shortDescription: _normalizeShortDescription(
        json['shortDescription'] as String? ?? '',
      ),
      needsConfirmation: json['needsConfirmation'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'intent': intent.value,
      'mealType': mealType.value,
      'foodName': foodName,
      'quantity': quantity,
      'unit': unit,
      'calories': calories,
      'caloriesEstimated': caloriesEstimated,
      'confidence': confidence,
      'shortDescription': shortDescription,
      'needsConfirmation': needsConfirmation,
    };
  }

  static int _readInt(Object? value) {
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _readDouble(Object? value, {double fallback = 0}) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static String _normalizeShortDescription(String value) {
    final singleLine = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return singleLine.length <= 80 ? singleLine : singleLine.substring(0, 80);
  }
}
