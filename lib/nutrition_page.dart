import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NutritionPage extends StatefulWidget {
  const NutritionPage({super.key});

  @override
  State<NutritionPage> createState() => _NutritionPageState();
}

class _NutritionPageState extends State<NutritionPage> {
  final TextEditingController _mealController = TextEditingController();
  File? _image;
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();

  // Using the API key from your google-services.json which is valid for Google Cloud services
  final String geminiKey = "YOUR_API_KEY";

  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await _picker.pickImage(source: source, imageQuality: 50);
    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
      });
    }
  }

  Future<void> _analyzeMeal() async {
    final String text = _mealController.text.trim();
    if (text.isEmpty && _image == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please describe your meal or take a photo")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Improved prompt to ensure strict JSON output
      String prompt = """
Analyze this meal and provide estimated nutritional values.
Return ONLY a raw JSON object with these exact keys:
"mealName" (string), "calories" (integer), "protein" (integer, grams),
"carbs" (integer, grams), "fats" (integer, grams).
Do not include any markdown formatting or extra text.
User description: $text
""";

      final url = Uri.parse(
          "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$geminiKey");

      Map<String, dynamic> requestBody;

      if (_image != null) {
        final imageBytes = await _image!.readAsBytes();
        final base64Image = base64Encode(imageBytes);

        requestBody = {
          "contents": [
            {
              "parts": [
                {"text": prompt},
                {
                  "inline_data": {
                    "mime_type": "image/jpeg",
                    "data": base64Image
                  }
                }
              ]
            }
          ]
        };
      } else {
        requestBody = {
          "contents": [
            {
              "parts": [
                {"text": prompt}
              ]
            }
          ]
        };
      }

      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(requestBody),
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        if (responseData["candidates"] == null || responseData["candidates"].isEmpty) {
          throw Exception("AI returned no results. Try a clearer description.");
        }

        String resultText = responseData["candidates"][0]["content"]["parts"][0]["text"];
        
        // Better JSON extraction
        int firstBrace = resultText.indexOf('{');
        int lastBrace = resultText.lastIndexOf('}');
        if (firstBrace == -1 || lastBrace == -1) {
          throw Exception("Could not read nutritional data. Try again.");
        }
        
        String jsonString = resultText.substring(firstBrace, lastBrace + 1);
        final mealData = jsonDecode(jsonString);

        await _saveMeal(mealData);
        
        if (mounted) {
          _showResultDialog(mealData);
          _mealController.clear();
          setState(() => _image = null);
        }
      } else {
        // Show specific API error for debugging
        String errorMsg = responseData["error"]?["message"] ?? "Status ${response.statusCode}";
        throw Exception("API Error: $errorMsg");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error: ${e.toString().replaceAll('Exception: ', '')}"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveMeal(Map<String, dynamic> data) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection('meals').add({
      'userId': user.uid,
      'mealName': data['mealName'] ?? "Unknown Meal",
      'calories': data['calories'] ?? 0,
      'protein': data['protein'] ?? 0,
      'carbs': data['carbs'] ?? 0,
      'fats': data['fats'] ?? 0,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  void _showResultDialog(Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(data['mealName'] ?? "Meal Analysis", style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildNutrientRow("🔥 Calories", "${data['calories']} kcal", Colors.orange),
            _buildNutrientRow("🍗 Protein", "${data['protein']}g", Colors.red),
            _buildNutrientRow("🍞 Carbs", "${data['carbs']}g", Colors.blue),
            _buildNutrientRow("🥑 Fats", "${data['fats']}g", Colors.green),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CLOSE", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildNutrientRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 16)),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("AI Nutrition Scanner", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Colors.orange.shade700, Colors.orange.shade400]),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.orange.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 5))],
              ),
              child: const Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.restaurant, color: Colors.white, size: 30),
                      SizedBox(width: 15),
                      Text("What are you eating?", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  SizedBox(height: 10),
                  Text(
                    "Describe your meal or snap a photo. Our AI will estimate the nutrition for you!",
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            TextField(
              controller: _mealController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: "E.g., I had 2 boiled eggs and a small glass of orange juice...",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark ? Colors.grey[900] : Colors.grey[100],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildActionButton(
                  icon: Icons.camera_alt,
                  label: "Camera",
                  onTap: () => _pickImage(ImageSource.camera),
                ),
                _buildActionButton(
                  icon: Icons.photo_library,
                  label: "Gallery",
                  onTap: () => _pickImage(ImageSource.gallery),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_image != null)
              Stack(
                alignment: Alignment.topRight,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: Image.file(_image!, height: 200, width: double.infinity, fit: BoxFit.cover),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _image = null),
                    icon: const CircleAvatar(backgroundColor: Colors.red, child: Icon(Icons.close, color: Colors.white)),
                  ),
                ],
              ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _analyzeMeal,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("Analyze & Log Meal 🚀", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 40),
            _buildRecentMeals(),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Column(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: Colors.orange.withValues(alpha: 0.1),
            child: Icon(icon, color: Colors.orange.shade700, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildRecentMeals() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('meals')
          .where('userId', isEqualTo: user.uid)
          .orderBy('timestamp', descending: true)
          .limit(10)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text("Error loading meals"));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const SizedBox();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Recent Meals", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            ...snapshot.data!.docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return Dismissible(
                key: Key(doc.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (direction) {
                  FirebaseFirestore.instance.collection('meals').doc(doc.id).delete();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Meal deleted")),
                  );
                },
                child: Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: const CircleAvatar(backgroundColor: Colors.orangeAccent, child: Icon(Icons.lunch_dining, color: Colors.white)),
                    title: Text(data['mealName'] ?? "Unknown Meal", style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("${data['calories']} kcal | P: ${data['protein']}g | C: ${data['carbs']}g | F: ${data['fats']}g"),
                    trailing: Text(
                      data['timestamp'] != null ? (data['timestamp'] as Timestamp).toDate().toString().substring(11, 16) : "",
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}
