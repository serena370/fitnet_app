import 'package:flutter/material.dart';

import '../models/workout.dart';
import '../services/fitness_repository.dart';
import '../services/workout_reminder_service.dart';
import '../utils/date_time_format.dart';
import '../widgets/empty_state.dart';
import '../widgets/friendly_error.dart';

class WorkoutsPage extends StatefulWidget {
  const WorkoutsPage({super.key});

  @override
  State<WorkoutsPage> createState() => _WorkoutsPageState();
}

class _WorkoutsPageState extends State<WorkoutsPage> {
  final FitnessRepository _repository = FitnessRepository();
  String? _openingRecommendation;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Workouts')),
      body: StreamBuilder<List<Workout>>(
        stream: _repository.watchWorkouts(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return FriendlyErrorState(error: snapshot.error);
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final workouts = snapshot.data ?? [];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _WorkoutRecommendationsSection(
                openingRecommendation: _openingRecommendation,
                onSelected: (recommendation) =>
                    _showRecommendedWorkoutDialog(context, recommendation),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => _showCustomWorkoutDialog(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Custom Workout'),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Workout History',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (workouts.isEmpty)
                const EmptyState(
                  icon: Icons.fitness_center,
                  message: 'No workouts yet. Add your first activity.',
                )
              else
                for (final workout in workouts)
                  Card(
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
                  ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCustomWorkoutDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Custom Workout'),
      ),
    );
  }

  Future<void> _showCustomWorkoutDialog(BuildContext context) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _AddWorkoutDialog(repository: _repository),
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Workout saved.')));
    }
  }

  Future<void> _showRecommendedWorkoutDialog(
    BuildContext context,
    _WorkoutRecommendation recommendation,
  ) async {
    if (_openingRecommendation != null) return;
    setState(() => _openingRecommendation = recommendation.activityType);
    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (_) => _AddWorkoutDialog(
          repository: _repository,
          recommendation: recommendation,
        ),
      );
      if (saved == true && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${recommendation.activityType} saved.')),
        );
      }
    } finally {
      if (mounted) setState(() => _openingRecommendation = null);
    }
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
      logDebugError('Delete workout failed', error);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't delete this workout. Please try again."),
        ),
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
      logDebugError('Set workout reminder failed', error);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't set this reminder. Please try again."),
        ),
      );
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

class _WorkoutRecommendation {
  const _WorkoutRecommendation({
    required this.group,
    required this.activityType,
    required this.durationMinutes,
    required this.caloriesBurned,
    required this.notes,
    required this.icon,
  });

  final String group;
  final String activityType;
  final int durationMinutes;
  final int caloriesBurned;
  final String notes;
  final IconData icon;
}

const List<_WorkoutRecommendation> _workoutRecommendations = [
  _WorkoutRecommendation(
    group: 'Cardio',
    activityType: 'Walking',
    durationMinutes: 30,
    caloriesBurned: 120,
    notes: 'Quick add recommendation',
    icon: Icons.directions_walk,
  ),
  _WorkoutRecommendation(
    group: 'Cardio',
    activityType: 'Running',
    durationMinutes: 20,
    caloriesBurned: 220,
    notes: 'Quick add recommendation',
    icon: Icons.directions_run,
  ),
  _WorkoutRecommendation(
    group: 'Cardio',
    activityType: 'Cycling',
    durationMinutes: 30,
    caloriesBurned: 240,
    notes: 'Quick add recommendation',
    icon: Icons.directions_bike,
  ),
  _WorkoutRecommendation(
    group: 'Cardio',
    activityType: 'Swimming',
    durationMinutes: 30,
    caloriesBurned: 260,
    notes: 'Quick add recommendation',
    icon: Icons.pool,
  ),
  _WorkoutRecommendation(
    group: 'Strength',
    activityType: 'Gym workout',
    durationMinutes: 45,
    caloriesBurned: 300,
    notes: 'Quick add recommendation',
    icon: Icons.fitness_center,
  ),
  _WorkoutRecommendation(
    group: 'Strength',
    activityType: 'Weight lifting',
    durationMinutes: 45,
    caloriesBurned: 280,
    notes: 'Quick add recommendation',
    icon: Icons.fitness_center,
  ),
  _WorkoutRecommendation(
    group: 'Strength',
    activityType: 'Push-ups',
    durationMinutes: 10,
    caloriesBurned: 60,
    notes: 'Quick add recommendation',
    icon: Icons.sports_gymnastics,
  ),
  _WorkoutRecommendation(
    group: 'Strength',
    activityType: 'Squats',
    durationMinutes: 12,
    caloriesBurned: 70,
    notes: 'Quick add recommendation',
    icon: Icons.accessibility_new,
  ),
  _WorkoutRecommendation(
    group: 'Strength',
    activityType: 'Plank',
    durationMinutes: 5,
    caloriesBurned: 25,
    notes: 'Quick add recommendation',
    icon: Icons.self_improvement,
  ),
  _WorkoutRecommendation(
    group: 'Sports',
    activityType: 'Football',
    durationMinutes: 45,
    caloriesBurned: 360,
    notes: 'Quick add recommendation',
    icon: Icons.sports_soccer,
  ),
  _WorkoutRecommendation(
    group: 'Sports',
    activityType: 'Basketball',
    durationMinutes: 45,
    caloriesBurned: 330,
    notes: 'Quick add recommendation',
    icon: Icons.sports_basketball,
  ),
  _WorkoutRecommendation(
    group: 'Flexibility',
    activityType: 'Yoga',
    durationMinutes: 30,
    caloriesBurned: 120,
    notes: 'Quick add recommendation',
    icon: Icons.self_improvement,
  ),
  _WorkoutRecommendation(
    group: 'Flexibility',
    activityType: 'Stretching',
    durationMinutes: 15,
    caloriesBurned: 50,
    notes: 'Quick add recommendation',
    icon: Icons.accessibility_new,
  ),
];

class _WorkoutRecommendationsSection extends StatelessWidget {
  const _WorkoutRecommendationsSection({
    required this.openingRecommendation,
    required this.onSelected,
  });

  final String? openingRecommendation;
  final ValueChanged<_WorkoutRecommendation> onSelected;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<_WorkoutRecommendation>>{};
    for (final recommendation in _workoutRecommendations) {
      groups.putIfAbsent(recommendation.group, () => []).add(recommendation);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Add Workouts',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        for (final entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 6),
            child: Text(
              entry.key,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final recommendation in entry.value)
                ActionChip(
                  avatar: openingRecommendation == recommendation.activityType
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(recommendation.icon, size: 18),
                  label: Text(
                    '${recommendation.activityType} '
                    '${recommendation.durationMinutes}m',
                  ),
                  onPressed: openingRecommendation == null
                      ? () => onSelected(recommendation)
                      : null,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _AddWorkoutDialog extends StatefulWidget {
  const _AddWorkoutDialog({required this.repository, this.recommendation});

  final FitnessRepository repository;
  final _WorkoutRecommendation? recommendation;

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
  void initState() {
    super.initState();
    final recommendation = widget.recommendation;
    if (recommendation != null) {
      _activityType = recommendation.activityType;
      _durationController.text = recommendation.durationMinutes.toString();
      _caloriesController.text = recommendation.caloriesBurned.toString();
      _notesController.text = recommendation.notes;
    }
  }

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
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      logDebugError('Save workout failed', error);
      _showError("Couldn't save this workout. Please try again.");
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
      title: Text(
        widget.recommendation == null ? 'Add workout' : 'Confirm workout',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _activityType,
              decoration: const InputDecoration(labelText: 'Activity'),
              items: const [
                DropdownMenuItem(value: 'Walking', child: Text('Walking')),
                DropdownMenuItem(value: 'Running', child: Text('Running')),
                DropdownMenuItem(value: 'Cycling', child: Text('Cycling')),
                DropdownMenuItem(
                  value: 'Gym workout',
                  child: Text('Gym workout'),
                ),
                DropdownMenuItem(
                  value: 'Weight lifting',
                  child: Text('Weight lifting'),
                ),
                DropdownMenuItem(value: 'Push-ups', child: Text('Push-ups')),
                DropdownMenuItem(value: 'Squats', child: Text('Squats')),
                DropdownMenuItem(value: 'Plank', child: Text('Plank')),
                DropdownMenuItem(value: 'Swimming', child: Text('Swimming')),
                DropdownMenuItem(value: 'Football', child: Text('Football')),
                DropdownMenuItem(
                  value: 'Basketball',
                  child: Text('Basketball'),
                ),
                DropdownMenuItem(value: 'Yoga', child: Text('Yoga')),
                DropdownMenuItem(
                  value: 'Stretching',
                  child: Text('Stretching'),
                ),
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
