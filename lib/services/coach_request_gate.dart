class CoachRequestGate {
  CoachRequestGate({this.debounce = const Duration(milliseconds: 700)});

  final Duration debounce;
  bool _inFlight = false;
  String? _lastMessage;
  DateTime? _lastAcceptedAt;

  bool get isInFlight => _inFlight;

  bool tryStart(String message, {DateTime? now}) {
    final trimmed = message.trim();
    if (trimmed.isEmpty || _inFlight) return false;

    final currentTime = now ?? DateTime.now();
    final isRepeatedTap =
        _lastMessage == trimmed &&
        _lastAcceptedAt != null &&
        currentTime.difference(_lastAcceptedAt!) < debounce;
    if (isRepeatedTap) return false;

    _inFlight = true;
    _lastMessage = trimmed;
    _lastAcceptedAt = currentTime;
    return true;
  }

  void complete() {
    _inFlight = false;
  }
}
