import 'package:fitnet_scale_app1/services/coach_action_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detects removing an accidental last food log', () {
    expect(
      CoachActionClassifier.isRemoveLastFoodLog(
        'wait it was by mistake, remove it',
      ),
      isTrue,
    );
  });

  test('does not treat normal coaching questions as removal commands', () {
    expect(
      CoachActionClassifier.isRemoveLastFoodLog(
        'Should I remove sugar from my diet?',
      ),
      isFalse,
    );
  });
}
