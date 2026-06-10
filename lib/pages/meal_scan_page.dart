import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/fitness_repository.dart';
import '../services/gemini_service.dart';
import '../widgets/friendly_error.dart';

const Map<String, dynamic> _nutritionSchema = {
  'type': 'object',
  'properties': {
    'mealName': {'type': 'string'},
    'calories': {'type': 'integer'},
    'protein': {'type': 'integer'},
    'carbs': {'type': 'integer'},
    'fats': {'type': 'integer'},
  },
  'required': ['mealName', 'calories', 'protein', 'carbs', 'fats'],
};

/// AI meal scanner (photo or text), merged into the Meals flow.
/// Saves through [FitnessRepository] with source 'photo' so the Meals page
/// stays the single source of truth for meal history.
class MealScanPage extends StatefulWidget {
  const MealScanPage({super.key});

  @override
  State<MealScanPage> createState() => _MealScanPageState();
}

class _MealScanPageState extends State<MealScanPage> {
  final TextEditingController _mealController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final GeminiService _geminiService = GeminiService.shared;
  final FitnessRepository _repository = FitnessRepository();

  File? _image;
  bool _isLoading = false;
  late String _mealType = _defaultMealTypeForNow();

  static String _defaultMealTypeForNow() {
    final hour = DateTime.now().hour;
    if (hour < 11) return 'Breakfast';
    if (hour < 16) return 'Lunch';
    if (hour < 21) return 'Dinner';
    return 'Snack';
  }

  @override
  void dispose() {
    _mealController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await _picker.pickImage(
      source: source,
      imageQuality: 50,
    );
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
        const SnackBar(
          content: Text('Please describe your meal or take a photo'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final prompt =
          """
Analyze this meal and provide estimated nutritional values.
Return ONLY a raw JSON object with these exact keys:
"mealName" (string), "calories" (integer), "protein" (integer, grams),
"carbs" (integer, grams), "fats" (integer, grams).
Do not include any markdown formatting or extra text.
User description: $text
""";

      final parts = <Map<String, dynamic>>[
        {'text': prompt},
      ];

      if (_image != null) {
        final imageBytes = await _image!.readAsBytes();
        final base64Image = base64Encode(imageBytes);

        parts.add({
          'inline_data': {'mime_type': 'image/jpeg', 'data': base64Image},
        });
      }

      final response = await _geminiService.generateText(
        prompt: prompt,
        parts: parts,
        responseMimeType: 'application/json',
        responseSchema: _nutritionSchema,
      );

      final mealData = _parseNutritionJson(response.text);
      if (mealData == null) {
        throw const GeminiException(geminiFriendlyError);
      }

      await _saveMeal(mealData);

      if (mounted) {
        await _showResultDialog(mealData);
      }
      if (mounted) {
        // Return true so the Meals page can confirm the new entry.
        Navigator.pop(context, true);
      }
    } catch (error) {
      logDebugError('Meal scan failed', error);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(geminiFriendlyError),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic>? _parseNutritionJson(String text) {
    try {
      final firstBrace = text.indexOf('{');
      final lastBrace = text.lastIndexOf('}');
      if (firstBrace == -1 || lastBrace == -1 || lastBrace <= firstBrace) {
        return null;
      }
      final decoded = jsonDecode(text.substring(firstBrace, lastBrace + 1));
      if (decoded is! Map<String, dynamic>) return null;
      final name = (decoded['mealName'] as String? ?? '').trim();
      final calories = (decoded['calories'] as num?)?.toInt() ?? 0;
      if (name.isEmpty || calories <= 0) return null;
      return decoded;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveMeal(Map<String, dynamic> data) {
    return _repository.addMeal(
      name: (data['mealName'] as String).trim(),
      mealType: _mealType,
      calories: (data['calories'] as num).toInt(),
      notes: 'AI photo/text scan',
      caloriesEstimated: true,
      source: 'photo',
      protein: (data['protein'] as num?)?.toInt(),
      carbs: (data['carbs'] as num?)?.toInt(),
      fats: (data['fats'] as num?)?.toInt(),
    );
  }

  Future<void> _showResultDialog(Map<String, dynamic> data) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          data['mealName'] ?? 'Meal Analysis',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Logged as $_mealType',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            _buildNutrientRow(
              '🔥 Calories',
              "${data['calories']} kcal",
              Colors.orange,
            ),
            _buildNutrientRow('🍗 Protein', "${data['protein']}g", Colors.red),
            _buildNutrientRow('🍞 Carbs', "${data['carbs']}g", Colors.blue),
            _buildNutrientRow('🥑 Fats', "${data['fats']}g", Colors.green),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'DONE',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
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
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Scan a Meal',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.orange.shade700, Colors.orange.shade400],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: const Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.restaurant, color: Colors.white, size: 30),
                      SizedBox(width: 15),
                      Expanded(
                        child: Text(
                          'What are you eating?',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Describe your meal or snap a photo. The AI estimates calories and macros and logs it to Meals.',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            DropdownButtonFormField<String>(
              initialValue: _mealType,
              decoration: InputDecoration(
                labelText: 'Meal type',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              items: const [
                DropdownMenuItem(value: 'Breakfast', child: Text('Breakfast')),
                DropdownMenuItem(value: 'Lunch', child: Text('Lunch')),
                DropdownMenuItem(value: 'Dinner', child: Text('Dinner')),
                DropdownMenuItem(value: 'Snack', child: Text('Snack')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _mealType = value);
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _mealController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText:
                    'E.g., I had 2 boiled eggs and a small glass of orange juice...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey[900]
                    : Colors.grey[100],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildActionButton(
                  icon: Icons.camera_alt,
                  label: 'Camera',
                  onTap: () => _pickImage(ImageSource.camera),
                ),
                _buildActionButton(
                  icon: Icons.photo_library,
                  label: 'Gallery',
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
                    child: Image.file(
                      _image!,
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _image = null),
                    icon: const CircleAvatar(
                      backgroundColor: Colors.red,
                      child: Icon(Icons.close, color: Colors.white),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _analyzeMeal,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'Analyze & Log Meal 🚀',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
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
}
