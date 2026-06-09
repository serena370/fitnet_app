import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'nutrition_page.dart';
import 'services/fitness_repository.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  ChatMessage({required this.text, required this.isUser});
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
  List<ChatMessage> messages = [];
  bool isTyping = false;
  bool isSavingPlan = false;

  // 🔑 Gemini API Configuration
  final String geminiKey = "YOUR_API_KEY";

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

    // Summarize recent meals for the AI
    String mealHistory = meals.isEmpty
        ? "No meals logged today."
        : meals
              .map((m) {
                final d = m.data() as Map<String, dynamic>;
                return "- ${d['mealName']}: ${d['calories']}kcal (P:${d['protein']}g, C:${d['carbs']}g, F:${d['fats']}g)";
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
    if (text.trim().isEmpty) return;

    setState(() {
      messages.add(ChatMessage(text: text, isUser: true));
      isTyping = true;
    });
    _scrollToBottom();

    try {
      final response = await http.post(
        Uri.parse(
          "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$geminiKey",
        ),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "systemInstruction": {
            "parts": [
              {"text": systemContext},
            ],
          },
          "contents": [
            {
              "role": "user",
              "parts": [
                {"text": text},
              ],
            },
          ],
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data["candidates"] != null) {
        String reply = data["candidates"][0]["content"]["parts"][0]["text"];
        setState(() {
          messages.add(ChatMessage(text: reply, isUser: false));
          isTyping = false;
        });
      } else {
        String error = data["error"]?["message"] ?? "API Error";
        setState(() {
          messages.add(ChatMessage(text: "Coach Error: $error", isUser: false));
          isTyping = false;
        });
      }
    } catch (e) {
      setState(() {
        messages.add(ChatMessage(text: "Connection Error: $e", isUser: false));
        isTyping = false;
      });
    }
    _scrollToBottom();
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
              onPressed: () => setState(() => messages.clear()),
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
                        if (!userSnap.hasData ||
                            !weightSnap.hasData ||
                            !mealSnap.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        final userData =
                            userSnap.data!.data() as Map<String, dynamic>? ??
                            {};
                        final weights = weightSnap.data!.docs;
                        final meals = mealSnap.data!.docs;
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
            color: Colors.blue.withOpacity(0.2),
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
                icon: const Icon(Icons.restaurant, color: Colors.white),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const NutritionPage(),
                  ),
                ),
                tooltip: "Log a meal",
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
                onPressed: () => sendMessage(s, context),
                backgroundColor: Colors.blue.withOpacity(0.05),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildChatBubble(ChatMessage msg) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final canSavePlan = !msg.isUser && _looksLikeWorkoutPlan(msg.text);
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
            if (canSavePlan) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: isSavingPlan ? null : () => _saveWorkoutPlan(msg),
                icon: const Icon(Icons.save_alt, size: 18),
                label: Text(isSavingPlan ? 'Saving...' : 'Save as Workout'),
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

  Future<void> _saveWorkoutPlan(ChatMessage msg) async {
    setState(() => isSavingPlan = true);
    try {
      await _fitnessRepository.saveAiWorkoutPlan(msg.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI workout plan saved to Workouts.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save workout plan: $error')),
      );
    } finally {
      if (mounted) setState(() => isSavingPlan = false);
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
            color: Colors.black.withOpacity(0.05),
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
                final text = chatController.text;
                chatController.clear();
                sendMessage(text, systemContext);
              },
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: Colors.blue,
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white, size: 20),
              onPressed: () {
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
