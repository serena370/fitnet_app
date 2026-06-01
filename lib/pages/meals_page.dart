import 'package:flutter/material.dart';

import '../models/meal.dart';
import '../services/fitness_repository.dart';
import '../utils/date_time_format.dart';

class MealsPage extends StatelessWidget {
  MealsPage({super.key});

  final FitnessRepository _repository = FitnessRepository();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Meals & Calories')),
      body: StreamBuilder<List<Meal>>(
        stream: _repository.watchMeals(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final meals = snapshot.data ?? [];
          if (meals.isEmpty) {
            return const _EmptyState();
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: meals.length,
            itemBuilder: (context, index) {
              final meal = meals[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.restaurant)),
                  title: Text(
                    meal.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '${meal.mealType} - ${meal.calories} kcal\n'
                    '${formatDateTime(meal.date)}'
                    '${meal.notes.isEmpty ? '' : '\n${meal.notes}'}',
                  ),
                  isThreeLine: true,
                  trailing: IconButton(
                    tooltip: 'Delete meal',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteMeal(context, meal),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => _AddMealDialog(repository: _repository),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add meal'),
      ),
    );
  }

  Future<void> _deleteMeal(BuildContext context, Meal meal) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete meal?'),
        content: Text('Remove ${meal.name} from your meal history?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete != true) return;

    try {
      await _repository.deleteMeal(meal.id);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not delete meal: $error')));
    }
  }
}

class _AddMealDialog extends StatefulWidget {
  const _AddMealDialog({required this.repository});

  final FitnessRepository repository;

  @override
  State<_AddMealDialog> createState() => _AddMealDialogState();
}

class _AddMealDialogState extends State<_AddMealDialog> {
  final _nameController = TextEditingController();
  final _caloriesController = TextEditingController();
  final _notesController = TextEditingController();
  String _mealType = 'Breakfast';
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _caloriesController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final calories = int.tryParse(_caloriesController.text);
    if (name.isEmpty || calories == null || calories < 0) {
      _showError('Enter a meal name and a valid calorie amount.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      await widget.repository.addMeal(
        name: name,
        mealType: _mealType,
        calories: calories,
        notes: _notesController.text.trim(),
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      _showError('Could not save meal: $error');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add meal'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Meal name'),
            ),
            DropdownButtonFormField<String>(
              initialValue: _mealType,
              decoration: const InputDecoration(labelText: 'Meal type'),
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
            TextField(
              controller: _caloriesController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Calories'),
            ),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.restaurant, size: 56, color: Colors.blue),
            SizedBox(height: 16),
            Text(
              'No meals yet. Start tracking your calorie intake.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
