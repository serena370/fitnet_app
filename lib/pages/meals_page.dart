import 'package:flutter/material.dart';

import '../models/meal.dart';
import '../routes/app_routes.dart';
import '../services/fitness_repository.dart';
import '../utils/date_time_format.dart';
import '../widgets/empty_state.dart';
import '../widgets/friendly_error.dart';

/// Source-of-truth UI for meal history: list, manual add, edit, delete,
/// and AI photo/text scan. Quick logging also happens in the AI Coach, but
/// every entry lands here through the same [FitnessRepository].
class MealsPage extends StatelessWidget {
  MealsPage({super.key});

  final FitnessRepository _repository = FitnessRepository();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meals & Calories'),
        actions: [
          IconButton(
            tooltip: 'Scan a meal (photo or text)',
            icon: const Icon(Icons.camera_alt_outlined),
            onPressed: () => _openScanner(context),
          ),
        ],
      ),
      body: StreamBuilder<List<Meal>>(
        stream: _repository.watchMeals(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            // Firestore unreachable: fall back to the local SQLite cache so
            // recent history stays visible offline.
            return _CachedMealsFallback(
              repository: _repository,
              error: snapshot.error,
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final meals = snapshot.data ?? [];
          if (meals.isEmpty) {
            return EmptyState(
              icon: Icons.restaurant,
              message:
                  'No meals yet. Add one manually, scan a photo, or tell '
                  'the AI Coach what you ate.',
              actionLabel: 'Add meal',
              onAction: () => _openAddDialog(context),
            );
          }

          return Column(
            children: [
              _TodaySummaryCard(meals: meals),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                  itemCount: meals.length,
                  itemBuilder: (context, index) {
                    final meal = meals[index];
                    return _MealCard(
                      meal: meal,
                      onEdit: () => showDialog<void>(
                        context: context,
                        builder: (_) =>
                            _AddMealDialog(repository: _repository, meal: meal),
                      ),
                      onDelete: () => _deleteMeal(context, meal),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Add meal'),
      ),
    );
  }

  void _openAddDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => _AddMealDialog(repository: _repository),
    );
  }

  Future<void> _openScanner(BuildContext context) async {
    final logged = await Navigator.pushNamed(context, AppRoutes.mealScan);
    if (logged == true && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Meal logged from scan.')));
    }
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
      logDebugError('Delete meal failed', error);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't delete this meal. Please try again."),
        ),
      );
    }
  }
}

class _TodaySummaryCard extends StatelessWidget {
  const _TodaySummaryCard({required this.meals});

  final List<Meal> meals;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayMeals = meals.where((meal) {
      return !meal.date.isBefore(todayStart) &&
          meal.date.isBefore(todayStart.add(const Duration(days: 1)));
    }).toList();
    final todayCalories = todayMeals.fold<int>(
      0,
      (sum, meal) => sum + meal.calories,
    );

    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(
              Icons.local_fire_department_outlined,
              color: Colors.orange,
              size: 36,
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Eaten today', style: TextStyle(color: Colors.grey[600])),
                Text(
                  '$todayCalories kcal',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              '${todayMeals.length} meal${todayMeals.length == 1 ? '' : 's'}',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}

class _MealCard extends StatelessWidget {
  const _MealCard({
    required this.meal,
    required this.onEdit,
    required this.onDelete,
  });

  final Meal meal;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  (IconData, String) get _sourceBadge {
    return switch (meal.source) {
      'coach' => (Icons.psychology_outlined, 'AI Coach'),
      'photo' => (Icons.camera_alt_outlined, 'Scan'),
      _ => (Icons.edit_outlined, 'Manual'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (sourceIcon, sourceLabel) = _sourceBadge;
    final macros = meal.hasMacros
        ? 'P: ${meal.protein ?? '-'}g | C: ${meal.carbs ?? '-'}g | F: ${meal.fats ?? '-'}g'
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(child: Icon(sourceIcon)),
        title: Text(
          meal.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${meal.mealType} - ${meal.calories} kcal'
              '${meal.caloriesEstimated ? ' (estimated)' : ''}',
            ),
            if (macros != null)
              Text(macros, style: const TextStyle(fontSize: 12)),
            Text(
              '${formatDateTime(meal.date)} - $sourceLabel'
              '${meal.notes.isEmpty ? '' : '\n${meal.notes}'}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        isThreeLine: true,
        onTap: onEdit,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Edit meal',
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEdit,
            ),
            IconButton(
              tooltip: 'Delete meal',
              icon: const Icon(Icons.delete_outline),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

/// Read-only offline view backed by the SQLite meal cache.
class _CachedMealsFallback extends StatelessWidget {
  const _CachedMealsFallback({required this.repository, this.error});

  final FitnessRepository repository;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    logDebugError('Meals stream failed', error);
    return FutureBuilder<List<Meal>>(
      future: repository.loadCachedMeals(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final cached = snapshot.data ?? [];
        if (cached.isEmpty) {
          return const FriendlyErrorState();
        }

        return Column(
          children: [
            Container(
              width: double.infinity,
              color: Colors.orange.withValues(alpha: 0.15),
              padding: const EdgeInsets.all(10),
              child: const Text(
                "You're offline — showing locally cached meals.",
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: cached.length,
                itemBuilder: (context, index) {
                  final meal = cached[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.restaurant),
                      ),
                      title: Text(
                        meal.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '${meal.mealType} - ${meal.calories} kcal\n'
                        '${formatDateTime(meal.date)}',
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AddMealDialog extends StatefulWidget {
  const _AddMealDialog({required this.repository, this.meal});

  final FitnessRepository repository;
  final Meal? meal;

  @override
  State<_AddMealDialog> createState() => _AddMealDialogState();
}

class _AddMealDialogState extends State<_AddMealDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _caloriesController;
  late final TextEditingController _notesController;
  late String _mealType;
  bool _isSaving = false;

  bool get _isEditing => widget.meal != null;

  static const _mealTypes = ['Breakfast', 'Lunch', 'Dinner', 'Snack'];

  @override
  void initState() {
    super.initState();
    final meal = widget.meal;
    _nameController = TextEditingController(text: meal?.name ?? '');
    _caloriesController = TextEditingController(
      text: meal == null ? '' : meal.calories.toString(),
    );
    _notesController = TextEditingController(text: meal?.notes ?? '');
    // Older entries may use a meal type outside the dropdown options.
    _mealType = _mealTypes.contains(meal?.mealType)
        ? meal!.mealType
        : 'Breakfast';
  }

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
      if (_isEditing) {
        final meal = widget.meal!;
        await widget.repository.updateMeal(
          mealId: meal.id,
          name: name,
          mealType: _mealType,
          calories: calories,
          notes: _notesController.text.trim(),
          quantity: meal.quantity,
          unit: meal.unit,
          caloriesEstimated: meal.caloriesEstimated,
          protein: meal.protein,
          carbs: meal.carbs,
          fats: meal.fats,
        );
      } else {
        await widget.repository.addMeal(
          name: name,
          mealType: _mealType,
          calories: calories,
          notes: _notesController.text.trim(),
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (error) {
      logDebugError('Save meal failed', error);
      _showError("Couldn't save this meal. Please try again.");
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
      title: Text(_isEditing ? 'Edit meal' : 'Add meal'),
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
              items: _mealTypes
                  .map(
                    (type) => DropdownMenuItem(value: type, child: Text(type)),
                  )
                  .toList(),
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
              : Text(_isEditing ? 'Update' : 'Save'),
        ),
      ],
    );
  }
}
