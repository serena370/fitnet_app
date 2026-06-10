import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/food_log_draft.dart';
import 'gemini_service.dart';

class FoodLogExtractor {
  FoodLogExtractor({GeminiService? geminiService})
    : _geminiService = geminiService ?? GeminiService.shared;

  final GeminiService _geminiService;

  FoodLogIntent classifyIntent(String message) {
    final lower = message.toLowerCase();
    if (RegExp(r'\b(progress|analysis|analyse|analyze)\b').hasMatch(lower) &&
        lower.contains('progress')) {
      return FoodLogIntent.progressAnalysis;
    }
    if (_looksFoodRelated(lower)) return FoodLogIntent.logFood;
    if (message.trim().isNotEmpty) return FoodLogIntent.chat;
    return FoodLogIntent.unknown;
  }

  Future<FoodLogDraft> extract(String message) async {
    final intent = classifyIntent(message);
    if (intent != FoodLogIntent.logFood) {
      return FoodLogDraft(
        intent: intent,
        mealType: MealType.unknown,
        foodName: '',
        quantity: 0,
        unit: '',
        calories: 0,
        caloriesEstimated: false,
        confidence: intent == FoodLogIntent.unknown ? 0 : 0.8,
        shortDescription: '',
        needsConfirmation: false,
      );
    }

    final localDraft = _extractLocal(message);
    if (localDraft != null) return localDraft;

    try {
      final response = await _geminiService.generateText(
        prompt: _structuredFoodPrompt(message),
        responseMimeType: 'application/json',
        responseSchema: foodLogDraftSchema,
      );
      final decoded = _decodeJsonObject(response.text);
      if (decoded == null) return _clarificationDraft(message);

      final draft = FoodLogDraft.fromJson(decoded);
      final normalized = _validateAndNormalize(draft, message);
      return normalized;
    } on GeminiException catch (error) {
      debugPrint('Food extraction Gemini failure: ${error.message}');
      return _clarificationDraft(message);
    } catch (error) {
      debugPrint('Food extraction parse failure: ${error.runtimeType}');
      return _clarificationDraft(message);
    }
  }

  FoodLogDraft? _extractLocal(String message) {
    final lower = message.toLowerCase();
    final mealType = detectMealType(message);
    final quantity = _detectQuantity(lower);

    for (final item in _localFoods) {
      if (item.pattern.hasMatch(lower)) {
        final calories = (item.caloriesPerUnit * quantity).round();
        final shortFood = item.shortName.toLowerCase();
        return FoodLogDraft(
          intent: FoodLogIntent.logFood,
          mealType: mealType,
          foodName: item.displayName,
          quantity: quantity,
          unit: item.unit,
          calories: calories,
          caloriesEstimated: true,
          confidence: mealType == MealType.unknown ? 0.7 : 0.92,
          shortDescription: _shortDescription(quantity, shortFood),
          needsConfirmation: mealType == MealType.unknown || calories <= 0,
        );
      }
    }

    return null;
  }

  FoodLogDraft _validateAndNormalize(FoodLogDraft draft, String message) {
    final mealType = draft.mealType == MealType.unknown
        ? detectMealType(message)
        : draft.mealType;
    final foodName = draft.foodName.trim();
    final quantity = draft.quantity <= 0 ? 1.0 : draft.quantity;
    final unit = draft.unit.trim().isEmpty ? 'serving' : draft.unit.trim();
    final calories = draft.calories;
    final shortDescription = _cleanShortDescription(
      draft.shortDescription.trim().isEmpty
          ? _shortDescription(quantity, foodName.toLowerCase())
          : draft.shortDescription,
    );
    final needsConfirmation =
        draft.needsConfirmation ||
        foodName.isEmpty ||
        mealType == MealType.unknown ||
        calories <= 0 ||
        shortDescription.isEmpty ||
        shortDescription.length > 80 ||
        (draft.confidence < 0.55 && calories <= 0);

    return draft.copyWith(
      mealType: mealType,
      foodName: foodName,
      quantity: quantity,
      unit: unit,
      shortDescription: shortDescription,
      needsConfirmation: needsConfirmation,
    );
  }

  FoodLogDraft _clarificationDraft(String message) {
    return FoodLogDraft(
      intent: FoodLogIntent.logFood,
      mealType: detectMealType(message),
      foodName: '',
      quantity: 1,
      unit: 'serving',
      calories: 0,
      caloriesEstimated: true,
      confidence: 0.25,
      shortDescription: '',
      needsConfirmation: true,
    );
  }

  bool _looksFoodRelated(String lower) {
    return RegExp(
      r'\b(i ate|i had|ate|had|eating|breakfast|lunch|dinner|snack|meal|food|calories|kcal)\b',
    ).hasMatch(lower);
  }

  double _detectQuantity(String lower) {
    final numeric = RegExp(r'\b(\d+(?:\.\d+)?)\b').firstMatch(lower);
    if (numeric != null) {
      return double.tryParse(numeric.group(1) ?? '') ?? 1;
    }
    const words = {
      'a': 1.0,
      'an': 1.0,
      'one': 1.0,
      'two': 2.0,
      'three': 3.0,
      'four': 4.0,
    };
    for (final entry in words.entries) {
      if (RegExp('\\b${entry.key}\\b').hasMatch(lower)) return entry.value;
    }
    return 1;
  }

  String _shortDescription(double quantity, String food) {
    final quantityText = quantity == quantity.roundToDouble()
        ? quantity.toStringAsFixed(0)
        : quantity.toStringAsFixed(1);
    return _cleanShortDescription('$quantityText $food');
  }

  String _cleanShortDescription(String value) {
    final cleaned = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned.length <= 80 ? cleaned : cleaned.substring(0, 80).trim();
  }

  Map<String, dynamic>? _decodeJsonObject(String text) {
    final trimmed = text.trim();
    final firstBrace = trimmed.indexOf('{');
    final lastBrace = trimmed.lastIndexOf('}');
    if (firstBrace == -1 || lastBrace == -1 || lastBrace <= firstBrace) {
      return null;
    }
    final decoded = jsonDecode(trimmed.substring(firstBrace, lastBrace + 1));
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  String _structuredFoodPrompt(String message) {
    return '''
Extract a food log from this user message.
Return ONLY a JSON object matching the schema.
Do not include markdown or explanation.

Rules:
- intent must be one of log_food, chat, progress_analysis, unknown.
- mealType must be breakfast, lunch, dinner, snack, or unknown.
- foodName must be concise.
- quantity must be numeric.
- calories must be a positive integer if you can reasonably estimate it.
- caloriesEstimated is true when estimated.
- confidence is 0.0 to 1.0.
- shortDescription must be 80 characters max and must not be a paragraph.
- needsConfirmation is true if calories or food identity are unclear.

User message: "$message"
''';
  }
}

MealType detectMealType(String message) {
  final lower = message.toLowerCase();
  if (RegExp(r'\bbreakfast\b').hasMatch(lower)) return MealType.breakfast;
  if (RegExp(r'\blunch\b').hasMatch(lower)) return MealType.lunch;
  if (RegExp(r'\bdinner\b').hasMatch(lower)) return MealType.dinner;
  if (RegExp(r'\bsnack\b').hasMatch(lower)) return MealType.snack;
  return MealType.unknown;
}

const Map<String, dynamic> foodLogDraftSchema = {
  'type': 'object',
  'properties': {
    'intent': {
      'type': 'string',
      'enum': ['log_food', 'chat', 'progress_analysis', 'unknown'],
    },
    'mealType': {
      'type': 'string',
      'enum': ['breakfast', 'lunch', 'dinner', 'snack', 'unknown'],
    },
    'foodName': {'type': 'string'},
    'quantity': {'type': 'number'},
    'unit': {'type': 'string'},
    'calories': {'type': 'integer'},
    'caloriesEstimated': {'type': 'boolean'},
    'confidence': {'type': 'number'},
    'shortDescription': {'type': 'string'},
    'needsConfirmation': {'type': 'boolean'},
  },
  'required': [
    'intent',
    'mealType',
    'foodName',
    'quantity',
    'unit',
    'calories',
    'caloriesEstimated',
    'confidence',
    'shortDescription',
    'needsConfirmation',
  ],
};

class _LocalFood {
  const _LocalFood({
    required this.pattern,
    required this.displayName,
    required this.shortName,
    required this.caloriesPerUnit,
    this.unit = 'piece',
  });

  final RegExp pattern;
  final String displayName;
  final String shortName;
  final int caloriesPerUnit;
  final String unit;
}

final List<_LocalFood> _localFoods = [
  _LocalFood(
    pattern: RegExp(r'\b(zaatar|zaatar) (man2ouche|manakish|manousheh)\b'),
    displayName: 'Zaatar Man2ouche',
    shortName: 'zaatar man2ouche',
    caloriesPerUnit: 300,
  ),
  _LocalFood(
    pattern: RegExp(r'\b(cheese|jebne) (man2ouche|manakish|manousheh)\b'),
    displayName: 'Cheese Man2ouche',
    shortName: 'cheese man2ouche',
    caloriesPerUnit: 450,
  ),
  _LocalFood(
    pattern: RegExp(
      r'\b(lahm bi ajin|lahme? bi ajin|lahme? b? ?ajin|meat (man2ouche|manakish|manousheh))\b',
    ),
    displayName: 'Lahm Bi Ajin',
    shortName: 'lahm bi ajin',
    caloriesPerUnit: 380,
  ),
  _LocalFood(
    pattern: RegExp(r'\b(man2ouche|manakish|manousheh|manouche|mankoushe)\b'),
    displayName: 'Man2ouche',
    shortName: 'man2ouche',
    caloriesPerUnit: 350,
  ),
  _LocalFood(
    pattern: RegExp(r'\beggs?\b'),
    displayName: 'Eggs',
    shortName: 'eggs',
    caloriesPerUnit: 140,
    unit: 'serving',
  ),
];
