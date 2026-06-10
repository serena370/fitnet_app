class CoachActionClassifier {
  const CoachActionClassifier._();

  static bool isRemoveLastFoodLog(String message) {
    final lower = message.toLowerCase().trim();
    if (lower.isEmpty) return false;

    final mentionsMistake = RegExp(
      r'\b(mistake|wrong|accident|accidentally|mislog|mislogged)\b',
    ).hasMatch(lower);
    final wantsRemoval = RegExp(
      r'\b(remove|delete|undo|cancel|clear|take off|take it off)\b',
    ).hasMatch(lower);
    final pointsToRecentLog = RegExp(
      r'\b(it|that|this|last|recent|meal|food|log|entry|breakfast|lunch|dinner|snack)\b',
    ).hasMatch(lower);

    return wantsRemoval && (mentionsMistake || pointsToRecentLog);
  }
}
