import 'dart:convert';

import 'package:fitnet_scale_app1/services/gemini_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    '503 responses retry and then fall back to the secondary model',
    () async {
      final requests = <http.Request>[];
      final delays = <Duration>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.path.contains('primary-model')) {
          return http.Response(
            jsonEncode({
              'error': {
                'message': 'This model is currently experiencing high demand.',
              },
            }),
            503,
            headers: {'retry-after': '0'},
          );
        }
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'fallback reply'},
                  ],
                },
              },
            ],
          }),
          200,
        );
      });

      final service = GeminiService(
        client: client,
        apiKey: 'test-key',
        primaryModel: 'primary-model',
        fallbackModel: 'fallback-model',
        delay: (duration) async => delays.add(duration),
      );

      final response = await service.generateText(prompt: 'hello');

      expect(response.text, 'fallback reply');
      expect(
        requests.where((r) => r.url.path.contains('primary-model')),
        hasLength(4),
      );
      expect(
        requests.where((r) => r.url.path.contains('fallback-model')),
        hasLength(1),
      );
      expect(delays.map((duration) => duration.inSeconds), [1, 2, 4]);
      expect(requests.first.headers.containsKey('x-goog-api-key'), isTrue);
      expect(requests.first.url.query, isEmpty);
    },
  );

  test('exhausted Gemini errors surface only the friendly message', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'error': {
            'message': 'This model is currently experiencing high demand.',
          },
        }),
        503,
      );
    });

    final service = GeminiService(
      client: client,
      apiKey: 'test-key',
      primaryModel: 'primary-model',
      fallbackModel: 'fallback-model',
      retryCount: 0,
      delay: (_) async {},
    );

    expect(
      () => service.generateText(prompt: 'hello'),
      throwsA(
        isA<GeminiException>().having(
          (error) => error.message,
          'message',
          geminiFriendlyError,
        ),
      ),
    );
  });
}
