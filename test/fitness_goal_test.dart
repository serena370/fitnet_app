import 'package:fitnet_scale_app1/models/fitness_goal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('goal progress is capped when the target is exceeded', () {
    final goal = FitnessGoal(
      id: 'goal-1',
      userId: 'user-1',
      title: 'Walk more',
      targetValue: 10000,
      currentValue: 12000,
      unit: 'steps',
      period: 'Daily',
      createdAt: DateTime(2026, 6, 1),
    );

    expect(goal.progress, 1);
    expect(goal.isComplete, isTrue);
  });
}
