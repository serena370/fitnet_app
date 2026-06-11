import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'models/food_log_draft.dart';
import 'routes/app_routes.dart';
import 'services/coach_action_classifier.dart';
import 'services/coach_request_gate.dart';
import 'services/fitness_repository.dart';
import 'services/food_log_extractor.dart';
import 'services/gemini_service.dart';
import 'widgets/friendly_error.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  const ChatMessage({required this.text, required this.isUser});
}

class _LastCoachFoodLog {
  const _LastCoachFoodLog({
    required this.id,
    required this.description,
    required this.mealType,
  });

  final String id;
  final String description;
  final String mealType;
}

class CoachPage extends StatefulWidget {
  const CoachPage({super.key});

  @override
  State<CoachPage> createState() => _CoachPageState();
}

class _CoachPageState extends State<CoachPage> {
  final TextEditingController chatController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  final FitnessRepository _fitnessRepository = FitnessRepository();
  final GeminiService _geminiService = GeminiService.shared;
  final FoodLogExtractor _foodLogExtractor = FoodLogExtractor();
  final CoachRequestGate _requestGate = CoachRequestGate();
  List<ChatMessage> messages = [];
  _LastCoachFoodLog? _lastCoachFoodLog;
  bool isTyping = false;
  bool isSavingPlan = false;
  bool isSavingEntry = false;

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _buildSystemPrompt(
    Map<String, dynamic> userData,
    List<QueryDocumentSnapshot> weights,
    List<QueryDocumentSnapshot> meals,
  ) {
    double currentWeight = weights.isNotEmpty
        ? (weights.first['weight'] as num).toDouble()
        : 0;
    double height = (userData['height'] ?? 1.70).toDouble();
    double bmi = (currentWeight > 0 && height > 0)
        ? currentWeight / (height * height)
        : 0;
    double goal = (userData['goalWeight'] ?? 0).toDouble();

    // Summarize recent meals for the AI. Macros are included only when they
    // were actually estimated — no misleading P:0 C:0 F:0 placeholders.
    String mealHistory = meals.isEmpty
        ? "No meals logged today."
        : meals
              .map((m) {
                final d = m.data() as Map<String, dynamic>;
                final mealName = d['name'] ?? d['mealName'] ?? 'Meal';
                final hasMacros =
                    d['protein'] != null ||
                    d['carbs'] != null ||
                    d['fats'] != null;
                final macros = hasMacros
                    ? " (P:${d['protein'] ?? '?'}g, C:${d['carbs'] ?? '?'}g, F:${d['fats'] ?? '?'}g)"
                    : "";
                return "- $mealName: ${d['calories']}kcal$macros";
              })
              .join("\\n");

    return "SYSTEM INSTRUCTION: You are 'FitNet AI', a professional health coach. "
        "User Data: Name: ${userData['firstName']}, Weight: $currentWeight kg, "
        "Height: $height m, BMI: ${bmi.toStringAsFixed(1)}, Goal: $goal kg. "
        "RECENT MEALS LOGGED: \\n$mealHistory\\n"
        "Use this nutrition data to give specific advice. If they ate too many calories, be firm but helpful. "
        "Keep responses helpful, short, and use emojis. Respond to the user's message below.\\n\\n";
  }

  Future<void> sendMessage(String text, String systemContext) async {
    final trimmed = text.trim();
    if (!_requestGate.tryStart(trimmed)) return;

    setState(() {
      messages.add(ChatMessage(text: trimmed, isUser: true));
      isTyping = true;
    });
    _scrollToBottom();

    try {
      final reply = await _handleCoachInput(trimmed, systemContext);
      if (!mounted) return;
      setState(() => messages.add(ChatMessage(text: reply, isUser: false)));
    } on GeminiException catch (error) {
      if (!mounted) return;
      setState(() {
        messages.add(ChatMessage(text: error.message, isUser: false));
      });
    } catch (error) {
      debugPrint('Coach request failed: ${error.runtimeType}');
      if (!mounted) return;
      setState(() {
        messages.add(
          const ChatMessage(text: geminiFriendlyError, isUser: false),
        );
      });
    } finally {
      _requestGate.complete();
      if (mounted) setState(() => isTyping = false);
    }
    _scrollToBottom();
  }

  Future<String> _handleCoachInput(String text, String systemContext) async {
    if (CoachActionClassifier.isRemoveLastFoodLog(text)) {
      return _handleRemoveLastFoodLog();
    }

    final intent = _foodLogExtractor.classifyIntent(text);
    return switch (intent) {
      FoodLogIntent.logFood => await _handleFoodLog(text),
      FoodLogIntent.progressAnalysis => await _handleProgressAnalysis(
        text,
        systemContext,
      ),
      _ => await _handleCoachChat(text, systemContext),
    };
  }

  Future<String> _handleFoodLog(String text) async {
    final draft = await _foodLogExtractor.extract(text);
    if (!draft.isReadyToSave) {
      return 'I can log that, but I need the meal type or an estimated calorie amount first.';
    }

    final mealId = await _fitnessRepository.addMeal(
      name: draft.foodName,
      mealType: draft.mealType.label,
      calories: draft.calories,
      notes: draft.shortDescription,
      quantity: draft.quantity,
      unit: draft.unit,
      caloriesEstimated: draft.caloriesEstimated,
      source: 'coach',
    );
    _lastCoachFoodLog = _LastCoachFoodLog(
      id: mealId,
      description: draft.shortDescription,
      mealType: draft.mealType.value,
    );

    final estimateText = draft.caloriesEstimated ? 'estimated ' : '';
    return 'Logged ${draft.mealType.value}: ${draft.shortDescription}, '
        '$estimateText${draft.calories} kcal.';
  }

  Future<String> _handleRemoveLastFoodLog() async {
    final lastFoodLog = _lastCoachFoodLog;
    if (lastFoodLog == null) {
      final removed = await _fitnessRepository.deleteMostRecentMeal();
      if (removed == null) {
        return "I couldn't find a meal log to remove.";
      }
      return 'Removed ${removed.mealType.toLowerCase()}: ${removed.notes.isEmpty ? removed.name : removed.notes}.';
    }

    try {
      await _fitnessRepository.deleteMeal(lastFoodLog.id);
      _lastCoachFoodLog = null;
      return 'Removed ${lastFoodLog.mealType}: ${lastFoodLog.description}.';
    } catch (error) {
      debugPrint('Coach meal id removal failed: ${error.runtimeType}');
      final removed = await _fitnessRepository.deleteMostRecentMeal();
      _lastCoachFoodLog = null;
      if (removed == null) {
        return "I couldn't find a meal log to remove.";
      }
      return 'Removed ${removed.mealType.toLowerCase()}: ${removed.notes.isEmpty ? removed.name : removed.notes}.';
    }
  }

  Future<String> _handleProgressAnalysis(
    String text,
    String systemContext,
  ) async {
    final response = await _geminiService.generateText(
      systemInstruction: systemContext,
      prompt:
          'Give a concise progress analysis only. Do not log food or save any meal. User request: $text',
    );
    return response.text;
  }

  Future<String> _handleCoachChat(String text, String systemContext) async {
    final response = await _geminiService.generateText(
      systemInstruction: systemContext,
      prompt: text,
    );
    return response.text;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Smart AI Coach",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () => setState(() {
                messages.clear();
                _lastCoachFoodLog = null;
              }),
            ),
        ],
      ),
      body: user == null
          ? const Center(child: Text("Please login"))
          : StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .snapshots(),
              builder: (context, userSnap) {
                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('weights')
                      .where('userId', isEqualTo: user.uid)
                      .orderBy('timestamp', descending: true)
                      .snapshots(),
                  builder: (context, weightSnap) {
                    return StreamBuilder<QuerySnapshot>(
                      // Also fetch recent meals to give context to the AI
                      stream: FirebaseFirestore.instance
                          .collection('meals')
                          .where('userId', isEqualTo: user.uid)
                          .orderBy('timestamp', descending: true)
                          .limit(10)
                          .snapshots(),
                      builder: (context, mealSnap) {
                        final isLoading =
                            userSnap.connectionState ==
                                ConnectionState.waiting &&
                            !userSnap.hasError &&
                            !userSnap.hasData;
                        if (isLoading) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        final userData =
                            userSnap.data?.data() as Map<String, dynamic>? ??
                            {};
                        final weights = weightSnap.hasError
                            ? <QueryDocumentSnapshot>[]
                            : weightSnap.data?.docs ?? [];
                        final meals = mealSnap.hasError
                            ? <QueryDocumentSnapshot>[]
                            : mealSnap.data?.docs ?? [];
                        final systemContext = _buildSystemPrompt(
                          userData,
                          weights,
                          meals,
                        );

                        return Column(
                          children: [
                            if (messages.isEmpty) _buildHeader(userData),
                            Expanded(
                              child: ListView.builder(
                                controller: scrollController,
                                padding: const EdgeInsets.all(16),
                                itemCount: messages.length + (isTyping ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (isTyping && index == messages.length) {
                                    return _buildTypingIndicator();
                                  }
                                  return _buildChatBubble(messages[index]);
                                },
                              ),
                            ),
                            if (messages.isEmpty)
                              _buildSuggestions(systemContext),
                            _buildInputArea(systemContext),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            ),
    );
  }

  Widget _buildHeader(Map<String, dynamic> userData) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade700, Colors.blue.shade400],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Hello, ${userData['firstName'] ?? 'User'}! 👋",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.camera_alt_outlined,
                  color: Colors.white,
                ),
                onPressed: () =>
                    Navigator.pushNamed(context, AppRoutes.mealScan),
                tooltip: "Scan a meal",
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            "I've analyzed your weight and your recent meals. How can I help you reach your goal today?",
            style: TextStyle(color: Colors.white70, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestions(String context) {
    final suggestions = [
      "How was my diet today?",
      "Check my BMI status",
      "Analysis of my progress",
      "Give me a workout",
      "Diet tips for weight loss",
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 8,
        children: suggestions
            .map(
              (s) => ActionChip(
                label: Text(s, style: const TextStyle(fontSize: 12)),
                onPressed: isTyping ? null : () => sendMessage(s, context),
                backgroundColor: Colors.blue.withValues(alpha: 0.05),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildChatBubble(ChatMessage msg) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final canSavePlan = !msg.isUser && _looksLikeWorkoutPlan(msg.text);
    final canSaveGoal = !msg.isUser && _looksLikeGoalSuggestion(msg.text);
    return Align(
      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: msg.isUser
              ? Colors.blue
              : (isDark ? Colors.grey[800] : Colors.grey[200]),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(msg.isUser ? 16 : 0),
            bottomRight: Radius.circular(msg.isUser ? 0 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              msg.text,
              style: TextStyle(
                color: msg.isUser || isDark ? Colors.white : Colors.black87,
              ),
            ),
            if (canSavePlan || canSaveGoal) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (canSavePlan)
                    OutlinedButton.icon(
                      onPressed: isSavingPlan
                          ? null
                          : () => _saveWorkoutPlan(msg),
                      icon: const Icon(Icons.fitness_center, size: 18),
                      label: Text(
                        isSavingPlan ? 'Saving...' : 'Save as Workout',
                      ),
                    ),
                  if (canSaveGoal)
                    OutlinedButton.icon(
                      onPressed: isSavingEntry ? null : () => _saveGoal(msg),
                      icon: const Icon(Icons.flag_outlined, size: 18),
                      label: const Text('Save as Goal'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _looksLikeWorkoutPlan(String text) {
    final lower = text.toLowerCase();
    return lower.contains('workout') ||
        lower.contains('exercise') ||
        lower.contains('sets') ||
        lower.contains('reps') ||
        lower.contains('running') ||
        lower.contains('cycling') ||
        lower.contains('gym');
  }

  bool _looksLikeGoalSuggestion(String text) {
    final lower = text.toLowerCase();
    return lower.contains('goal') ||
        lower.contains('target') ||
        lower.contains('daily') ||
        lower.contains('weekly') ||
        lower.contains('steps') ||
        lower.contains('km') ||
        lower.contains('minutes');
  }

  Future<void> _saveWorkoutPlan(ChatMessage msg) async {
    setState(() => isSavingPlan = true);
    try {
      await _fitnessRepository.saveAiWorkoutPlan(msg.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI workout plan saved to Workouts.')),
      );
    } catch (error) {
      logDebugError('Save workout plan failed', error);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't save the workout plan. Please try again."),
        ),
      );
    } finally {
      if (mounted) setState(() => isSavingPlan = false);
    }
  }

  Future<void> _saveGoal(ChatMessage msg) async {
    final draft = _GoalDraft.fromAiText(msg.text);
    final confirmed = await showDialog<_GoalDraft>(
      context: context,
      builder: (context) => _SaveGoalDialog(initialDraft: draft),
    );
    if (confirmed == null) return;

    setState(() => isSavingEntry = true);
    try {
      await _fitnessRepository.addGoal(
        title: confirmed.title,
        targetValue: confirmed.targetValue,
        unit: confirmed.unit,
        period: confirmed.period,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Goal saved from AI suggestion.')),
      );
    } catch (error) {
      logDebugError('Save goal failed', error);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't save the goal. Please try again."),
        ),
      );
    } finally {
      if (mounted) setState(() => isSavingEntry = false);
    }
  }

  Widget _buildTypingIndicator() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text(
            "AI Coach is thinking...",
            style: TextStyle(
              fontStyle: FontStyle.italic,
              color: Colors.grey,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea(String systemContext) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: chatController,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: "Ask your AI Coach...",
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey[900]
                    : Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
              ),
              onSubmitted: (val) {
                if (isTyping) return;
                final text = chatController.text;
                chatController.clear();
                sendMessage(text, systemContext);
              },
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: isTyping ? Colors.grey : Colors.blue,
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white, size: 20),
              onPressed: isTyping
                  ? null
                  : () {
                      final text = chatController.text;
                      chatController.clear();
                      sendMessage(text, systemContext);
                    },
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalDraft {
  const _GoalDraft({
    required this.title,
    required this.period,
    required this.targetValue,
    required this.unit,
  });

  final String title;
  final String period;
  final double targetValue;
  final String unit;

  factory _GoalDraft.fromAiText(String text) {
    final lower = text.toLowerCase();
    final targetMatch = RegExp(
      r'(\d+(?:\.\d+)?)\s*(steps?|km|kilometers?|kcal|calories|minutes?|mins?|glasses|liters?|l|workouts?|kg)',
      caseSensitive: false,
    ).firstMatch(text);

    return _GoalDraft(
      title: _firstUsefulLine(text, fallback: 'AI suggested goal'),
      period: lower.contains('week') || lower.contains('weekly')
          ? 'Weekly'
          : 'Daily',
      targetValue: double.tryParse(targetMatch?.group(1) ?? '') ?? 1,
      unit: _normalizeGoalUnit(targetMatch?.group(2) ?? 'times'),
    );
  }
}

class _SaveGoalDialog extends StatefulWidget {
  const _SaveGoalDialog({required this.initialDraft});

  final _GoalDraft initialDraft;

  @override
  State<_SaveGoalDialog> createState() => _SaveGoalDialogState();
}

class _SaveGoalDialogState extends State<_SaveGoalDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _targetController;
  late final TextEditingController _unitController;
  late String _period;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialDraft.title);
    _targetController = TextEditingController(
      text: _formatDraftNumber(widget.initialDraft.targetValue),
    );
    _unitController = TextEditingController(text: widget.initialDraft.unit);
    _period = widget.initialDraft.period;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _targetController.dispose();
    _unitController.dispose();
    super.dispose();
  }

  void _confirm() {
    final title = _titleController.text.trim();
    final target = double.tryParse(_targetController.text.trim());
    final unit = _unitController.text.trim();
    if (title.isEmpty || target == null || target <= 0 || unit.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a goal title, positive target, and unit.'),
        ),
      );
      return;
    }

    Navigator.pop(
      context,
      _GoalDraft(
        title: title,
        period: _period,
        targetValue: target,
        unit: unit,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Review AI Goal'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Goal title'),
            ),
            DropdownButtonFormField<String>(
              initialValue: _period,
              decoration: const InputDecoration(labelText: 'Period'),
              items: const [
                DropdownMenuItem(value: 'Daily', child: Text('Daily')),
                DropdownMenuItem(value: 'Weekly', child: Text('Weekly')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _period = value);
              },
            ),
            TextField(
              controller: _targetController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Target'),
            ),
            TextField(
              controller: _unitController,
              decoration: const InputDecoration(labelText: 'Unit'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _confirm, child: const Text('Save Goal')),
      ],
    );
  }
}

String _firstUsefulLine(String text, {required String fallback}) {
  for (final line in text.split('\n')) {
    final cleaned = line
        .replaceAll(RegExp(r'^[\s\-*#\d.)]+'), '')
        .replaceAll(RegExp(r'\*\*|__|`'), '')
        .trim();
    if (cleaned.length >= 3) {
      return cleaned.length > 48 ? '${cleaned.substring(0, 48)}...' : cleaned;
    }
  }
  return fallback;
}

String _normalizeGoalUnit(String unit) {
  final lower = unit.toLowerCase();
  if (lower == 'kilometer' || lower == 'kilometers') return 'km';
  if (lower == 'minute' || lower == 'minutes' || lower == 'mins') {
    return 'minutes';
  }
  if (lower == 'calorie' || lower == 'calories' || lower == 'kcal') {
    return 'kcal';
  }
  if (lower == 'step' || lower == 'steps') return 'steps';
  if (lower == 'workout' || lower == 'workouts') return 'workouts';
  if (lower == 'liter' || lower == 'liters') return 'liters';
  if (lower == 'l') return 'liters';
  return lower;
}

String _formatDraftNumber(double value) {
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
}
