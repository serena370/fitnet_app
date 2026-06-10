import 'package:fitnet_scale_app1/services/coach_request_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rapid repeated sends only allow one in-flight request', () {
    final gate = CoachRequestGate();
    final now = DateTime(2026, 6, 10, 10);

    expect(gate.tryStart('I ate eggs for lunch', now: now), isTrue);
    expect(
      gate.tryStart(
        'I ate eggs for lunch',
        now: now.add(const Duration(milliseconds: 50)),
      ),
      isFalse,
    );

    gate.complete();

    expect(
      gate.tryStart(
        'I ate eggs for lunch',
        now: now.add(const Duration(milliseconds: 100)),
      ),
      isFalse,
    );
    expect(
      gate.tryStart(
        'I ate eggs for lunch',
        now: now.add(const Duration(milliseconds: 800)),
      ),
      isTrue,
    );
  });
}
