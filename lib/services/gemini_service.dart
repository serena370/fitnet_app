import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

const String geminiApiKey = String.fromEnvironment(
  'GEMINI_API_KEY',
  defaultValue: 'AIzaSyAwLxF4HUJmgXEo3JTFTMbTc2qnXaF3MGg',
);

const String geminiPrimaryModel = String.fromEnvironment(
  'GEMINI_PRIMARY_MODEL',
  defaultValue: 'gemini-2.5-flash-lite',
);

const String geminiFallbackModel = String.fromEnvironment(
  'GEMINI_FALLBACK_MODEL',
  defaultValue: 'gemini-2.5-flash',
);

const String geminiFriendlyError =
    'The coach is temporarily busy. Please try again in a moment.';

typedef DelayCallback = Future<void> Function(Duration duration);

class GeminiService {
  GeminiService({
    http.Client? client,
    String? apiKey,
    String primaryModel = geminiPrimaryModel,
    String fallbackModel = geminiFallbackModel,
    Duration timeout = const Duration(seconds: 25),
    int retryCount = 3,
    Random? random,
    DelayCallback? delay,
  }) : _client = client ?? http.Client(),
       _apiKey = apiKey ?? geminiApiKey,
       _primaryModel = primaryModel,
       _fallbackModel = fallbackModel,
       _timeout = timeout,
       _retryCount = retryCount,
       _random = random ?? Random(),
       _delay = delay ?? Future.delayed;

  static final GeminiService shared = GeminiService();

  static void initializeOnAppLaunch() {
    final configured = geminiApiKey.trim().isNotEmpty;
    debugPrint(
      'Gemini service ready on app launch. '
      'configured=$configured primary=$geminiPrimaryModel fallback=$geminiFallbackModel',
    );
  }

  final http.Client _client;
  final String _apiKey;
  final String _primaryModel;
  final String _fallbackModel;
  final Duration _timeout;
  final int _retryCount;
  final Random _random;
  final DelayCallback _delay;

  Future<GeminiTextResponse> generateText({
    required String prompt,
    String? systemInstruction,
    List<Map<String, dynamic>>? parts,
    String? responseMimeType,
    Map<String, dynamic>? responseSchema,
  }) async {
    if (_apiKey.trim().isEmpty) {
      debugPrint('Gemini request failed: missing API key.');
      throw const GeminiException(geminiFriendlyError);
    }

    final requestParts =
        parts ??
        [
          {'text': prompt},
        ];
    final generationConfig = _buildGenerationConfig(
      responseMimeType: responseMimeType,
      responseSchema: responseSchema,
    );

    final body = <String, dynamic>{
      if (systemInstruction != null && systemInstruction.trim().isNotEmpty)
        'systemInstruction': {
          'parts': [
            {'text': systemInstruction},
          ],
        },
      'contents': [
        {'role': 'user', 'parts': requestParts},
      ],
      if (generationConfig.isNotEmpty) 'generationConfig': generationConfig,
    };

    final models = [
      _primaryModel,
      if (_fallbackModel.isNotEmpty && _fallbackModel != _primaryModel)
        _fallbackModel,
    ];

    GeminiTechnicalException? lastError;
    for (var i = 0; i < models.length; i++) {
      final model = models[i];
      try {
        return await _requestWithRetries(model: model, body: body);
      } on GeminiTechnicalException catch (error) {
        lastError = error;
        debugPrint(
          'Gemini request failed for model $model: '
          'status=${error.statusCode ?? 'none'} reason=${error.reason}',
        );
        if (!error.canFallback || i == models.length - 1) {
          break;
        }
      }
    }

    debugPrint(
      'Gemini request exhausted retries/fallbacks: '
      'status=${lastError?.statusCode ?? 'none'} reason=${lastError?.reason}',
    );
    throw const GeminiException(geminiFriendlyError);
  }

  Future<GeminiTextResponse> _requestWithRetries({
    required String model,
    required Map<String, dynamic> body,
  }) async {
    GeminiTechnicalException? lastError;
    for (var attempt = 0; attempt <= _retryCount; attempt++) {
      try {
        return await _requestOnce(model: model, body: body, attempt: attempt);
      } on GeminiTechnicalException catch (error) {
        lastError = error;
        if (!error.isRetryable || attempt == _retryCount) {
          rethrow;
        }
        await _delay(_retryDelay(attempt, error.retryAfter));
      }
    }
    throw lastError ??
        const GeminiTechnicalException(reason: 'unknown retry failure');
  }

  Map<String, dynamic> _buildGenerationConfig({
    required String? responseMimeType,
    required Map<String, dynamic>? responseSchema,
  }) {
    final config = <String, dynamic>{};
    if (responseMimeType != null) {
      config['responseMimeType'] = responseMimeType;
    }
    if (responseSchema != null) {
      config['responseSchema'] = responseSchema;
    }
    return config;
  }

  Future<GeminiTextResponse> _requestOnce({
    required String model,
    required Map<String, dynamic> body,
    required int attempt,
  }) async {
    final url = Uri.https(
      'generativelanguage.googleapis.com',
      '/v1beta/models/$model:generateContent',
    );

    http.Response response;
    try {
      response = await _client
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': _apiKey,
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw GeminiTechnicalException(
        reason: 'timeout after ${_timeout.inSeconds}s',
        canFallback: true,
      );
    } catch (error) {
      throw GeminiTechnicalException(
        reason: error.runtimeType.toString(),
        canFallback: true,
      );
    }

    final decoded = _decodeBody(response.body);
    if (response.statusCode == 200) {
      final text = _extractText(decoded);
      if (text == null || text.trim().isEmpty) {
        throw const GeminiTechnicalException(
          reason: 'empty response',
          canFallback: true,
        );
      }
      return GeminiTextResponse(
        text: text.trim(),
        model: model,
        attempt: attempt + 1,
      );
    }

    final message = _readErrorMessage(decoded) ?? 'HTTP ${response.statusCode}';
    throw GeminiTechnicalException(
      statusCode: response.statusCode,
      reason: _safeReason(message),
      retryAfter: _parseRetryAfter(response.headers['retry-after']),
      canFallback: response.statusCode == 503 || _looksHighDemand(message),
    );
  }

  Duration _retryDelay(int attempt, Duration? retryAfter) {
    if (retryAfter != null && retryAfter > Duration.zero) {
      return retryAfter;
    }

    final baseSeconds = switch (attempt) {
      0 => 1,
      1 => 2,
      _ => 4,
    };
    final jitterMs = _random.nextInt(250);
    return Duration(seconds: baseSeconds, milliseconds: jitterMs);
  }

  Map<String, dynamic>? _decodeBody(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String? _extractText(Map<String, dynamic>? decoded) {
    final candidates = decoded?['candidates'];
    if (candidates is! List || candidates.isEmpty) return null;
    final first = candidates.first;
    if (first is! Map<String, dynamic>) return null;
    final content = first['content'];
    if (content is! Map<String, dynamic>) return null;
    final parts = content['parts'];
    if (parts is! List || parts.isEmpty) return null;
    final text = parts
        .whereType<Map<String, dynamic>>()
        .map((part) => part['text'])
        .whereType<String>()
        .join('\n')
        .trim();
    return text.isEmpty ? null : text;
  }

  String? _readErrorMessage(Map<String, dynamic>? decoded) {
    final error = decoded?['error'];
    if (error is Map<String, dynamic>) {
      return error['message'] as String?;
    }
    return null;
  }

  Duration? _parseRetryAfter(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final seconds = int.tryParse(value.trim());
    if (seconds != null) return Duration(seconds: seconds);

    final date =
        DateTime.tryParse(value.trim()) ?? _parseHttpDate(value.trim());
    if (date == null) return null;
    final difference = date.toUtc().difference(DateTime.now().toUtc());
    return difference.isNegative ? null : difference;
  }

  DateTime? _parseHttpDate(String value) {
    final match = RegExp(
      r'^[A-Za-z]{3}, (\d{2}) ([A-Za-z]{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$',
    ).firstMatch(value);
    if (match == null) return null;

    const months = {
      'Jan': 1,
      'Feb': 2,
      'Mar': 3,
      'Apr': 4,
      'May': 5,
      'Jun': 6,
      'Jul': 7,
      'Aug': 8,
      'Sep': 9,
      'Oct': 10,
      'Nov': 11,
      'Dec': 12,
    };
    final month = months[match.group(2)];
    if (month == null) return null;

    return DateTime.utc(
      int.parse(match.group(3)!),
      month,
      int.parse(match.group(1)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6)!),
    );
  }

  bool _looksHighDemand(String message) {
    final lower = message.toLowerCase();
    return lower.contains('high demand') ||
        lower.contains('overloaded') ||
        lower.contains('unavailable') ||
        lower.contains('try again later');
  }

  String _safeReason(String message) {
    return message.length > 160 ? '${message.substring(0, 160)}...' : message;
  }
}

class GeminiTextResponse {
  const GeminiTextResponse({
    required this.text,
    required this.model,
    required this.attempt,
  });

  final String text;
  final String model;
  final int attempt;
}

class GeminiException implements Exception {
  const GeminiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class GeminiTechnicalException implements Exception {
  const GeminiTechnicalException({
    this.statusCode,
    required this.reason,
    this.retryAfter,
    this.canFallback = false,
  });

  final int? statusCode;
  final String reason;
  final Duration? retryAfter;
  final bool canFallback;

  bool get isRetryable =>
      statusCode == null ||
      statusCode == 429 ||
      statusCode == 500 ||
      statusCode == 503 ||
      statusCode == 504;
}
