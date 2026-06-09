import 'package:flutter/material.dart';

import '../models/workout.dart';
import '../services/fitness_repository.dart';
import '../services/workout_reminder_service.dart';
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
                    '${workout.reminderAt == null ? '' : '\nReminder: ${formatDateTime(workout.reminderAt!)}'}'
                    '${workout.notes.isEmpty ? '' : '\n${workout.notes}'}',
                  ),
                  isThreeLine: true,
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) {
                      if (action == 'reminder') {
                        _setWorkoutReminder(context, workout);
                      } else if (action == 'delete') {
                        _deleteWorkout(context, workout);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'reminder',
                        child: Text('Set reminder'),
                      ),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
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

  Future<void> _setWorkoutReminder(
    BuildContext context,
    Workout workout,
  ) async {
    final reminderAt = await _pickReminderDateTime(context);
    if (reminderAt == null) return;

    try {
      await _repository.updateWorkoutReminder(workout.id, reminderAt);
      WorkoutReminderService.scheduleWorkoutReminder(
        workoutId: workout.id,
        activityType: workout.activityType,
        reminderAt: reminderAt,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Reminder set for ${formatDateTime(reminderAt)}'),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not set reminder: $error')));
    }
  }

  Future<DateTime?> _pickReminderDateTime(BuildContext context) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );
    if (date == null || !context.mounted) return null;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(minutes: 5))),
    );
    if (time == null) return null;

    final reminderAt = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    if (reminderAt.isBefore(now)) {
      if (!context.mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a future reminder time.')),
      );
      return null;
    }

    return reminderAt;
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
  DateTime? _reminderAt;
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
      final workout = await widget.repository.addWorkout(
        activityType: _activityType,
        durationMinutes: duration,
        caloriesBurned: calories,
        notes: _notesController.text.trim(),
        reminderAt: _reminderAt,
      );
      if (_reminderAt != null) {
        WorkoutReminderService.scheduleWorkoutReminder(
          workoutId: workout.id,
          activityType: workout.activityType,
          reminderAt: _reminderAt!,
        );
      }
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

  Future<void> _pickReminder() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(minutes: 5))),
    );
    if (time == null) return;

    final selected = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    if (selected.isBefore(now)) {
      _showError('Choose a future reminder time.');
      return;
    }

    setState(() => _reminderAt = selected);
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
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isSaving ? null : _pickReminder,
              icon: const Icon(Icons.notifications_active_outlined),
              label: Text(
                _reminderAt == null
                    ? 'Set reminder (optional)'
                    : 'Reminder: ${formatDateTime(_reminderAt!)}',
              ),
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
