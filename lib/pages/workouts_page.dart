import 'package:flutter/material.dart';

import '../models/workout.dart';
import '../services/fitness_repository.dart';
import '../utils/date_time_format.dart';

class WorkoutsPage extends StatelessWidget {
  WorkoutsPage({super.key});

  final FitnessRepository _repository = FitnessRepository();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Workouts')),
      body: StreamBuilder<List<Workout>>(
        stream: _repository.watchWorkouts(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final workouts = snapshot.data ?? [];
          if (workouts.isEmpty) {
            return const _EmptyState(
              icon: Icons.fitness_center,
              message: 'No workouts yet. Add your first activity.',
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: workouts.length,
            itemBuilder: (context, index) {
              final workout = workouts[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.fitness_center),
                  ),
                  title: Text(
                    workout.activityType,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '${workout.durationMinutes} min - '
                    '${workout.caloriesBurned} kcal\n'
                    '${formatDateTime(workout.date)}'
                    '${workout.notes.isEmpty ? '' : '\n${workout.notes}'}',
                  ),
                  isThreeLine: true,
                  trailing: IconButton(
                    tooltip: 'Delete workout',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteWorkout(context, workout),
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
          builder: (_) => _AddWorkoutDialog(repository: _repository),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add workout'),
      ),
    );
  }

  Future<void> _deleteWorkout(BuildContext context, Workout workout) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete workout?'),
        content: Text('Remove your ${workout.activityType} entry?'),
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
      await _repository.deleteWorkout(workout.id);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete workout: $error')),
      );
    }
  }
}

class _AddWorkoutDialog extends StatefulWidget {
  const _AddWorkoutDialog({required this.repository});

  final FitnessRepository repository;

  @override
  State<_AddWorkoutDialog> createState() => _AddWorkoutDialogState();
}

class _AddWorkoutDialogState extends State<_AddWorkoutDialog> {
  final _durationController = TextEditingController();
  final _caloriesController = TextEditingController();
  final _notesController = TextEditingController();
  String _activityType = 'Running';
  bool _isSaving = false;

  @override
  void dispose() {
    _durationController.dispose();
    _caloriesController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final duration = int.tryParse(_durationController.text);
    final calories = int.tryParse(_caloriesController.text);
    if (duration == null || duration <= 0 || calories == null || calories < 0) {
      _showError('Enter a valid duration and calorie amount.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      await widget.repository.addWorkout(
        activityType: _activityType,
        durationMinutes: duration,
        caloriesBurned: calories,
        notes: _notesController.text.trim(),
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      _showError('Could not save workout: $error');
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
      title: const Text('Add workout'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _activityType,
              decoration: const InputDecoration(labelText: 'Activity'),
              items: const [
                DropdownMenuItem(value: 'Running', child: Text('Running')),
                DropdownMenuItem(value: 'Gym', child: Text('Gym')),
                DropdownMenuItem(value: 'Cycling', child: Text('Cycling')),
                DropdownMenuItem(value: 'Walking', child: Text('Walking')),
                DropdownMenuItem(value: 'Other', child: Text('Other')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _activityType = value);
              },
            ),
            TextField(
              controller: _durationController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Duration (minutes)',
              ),
            ),
            TextField(
              controller: _caloriesController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Calories burned'),
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
  const _EmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Colors.blue),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
