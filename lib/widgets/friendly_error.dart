import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

const String friendlyErrorMessage =
    "Couldn't load this data right now. Please try again.";

/// Logs technical error detail in debug builds only, never in release.
void logDebugError(String context, Object? error) {
  if (kDebugMode) {
    debugPrint('$context: $error');
  }
}

/// Shared friendly error placeholder used instead of raw snapshot errors.
class FriendlyErrorState extends StatelessWidget {
  const FriendlyErrorState({
    super.key,
    this.message = friendlyErrorMessage,
    this.error,
    this.onRetry,
  });

  final String message;
  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    logDebugError('FriendlyErrorState', error);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 56, color: Colors.grey),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
