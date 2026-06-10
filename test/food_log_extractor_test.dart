import 'package:fitnet_scale_app1/models/food_log_draft.dart';
import 'package:fitnet_scale_app1/services/food_log_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'man2ouche breakfast creates a valid estimated food log draft',
    () async {
      final extractor = FoodLogExtractor();

      final draft = await extractor.extract('I ate a man2ouche for breakfast');

      expect(draft.intent, FoodLogIntent.logFood);
      expect(draft.isReadyToSave, isTrue);
      expect(draft.mealType, MealType.breakfast);
      expect(draft.foodName, 'Man2ouche');
      expect(draft.quantity, 1);
      expect(draft.unit, 'piece');
      expect(draft.calories, greaterThan(0));
      expect(draft.caloriesEstimated, isTrue);
      expect(draft.shortDescription, '1 man2ouche');
      expect(draft.shortDescription.length, lessThanOrEqualTo(80));
    },
  );

  test('eggs lunch creates a lunch food log draft', () async {
    final extractor = FoodLogExtractor();

    final draft = await extractor.extract('I ate eggs for lunch');

    expect(draft.intent, FoodLogIntent.logFood);
    expect(draft.isReadyToSave, isTrue);
    expect(draft.mealType, MealType.lunch);
    expect(draft.foodName, 'Eggs');
    expect(draft.calories, greaterThan(0));
  });

  test('lahme bi ajin breakfast creates a breakfast food log draft', () async {
    final extractor = FoodLogExtractor();

    final draft = await extractor.extract('I ate a lahme bi ajin as breakfast');

    expect(draft.intent, FoodLogIntent.logFood);
    expect(draft.isReadyToSave, isTrue);
    expect(draft.mealType, MealType.breakfast);
    expect(draft.foodName, 'Lahm Bi Ajin');
    expect(draft.calories, greaterThan(0));
    expect(draft.shortDescription.length, lessThanOrEqualTo(80));
  });

  test('progress analysis is not treated as food logging', () {
    final extractor = FoodLogExtractor();

    final intent = extractor.classifyIntent('Analysis of my progress');

    expect(intent, FoodLogIntent.progressAnalysis);
    expect(intent, isNot(FoodLogIntent.logFood));
  });
}
