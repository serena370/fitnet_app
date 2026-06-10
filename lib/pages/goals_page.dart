import 'package:flutter/material.dart';

import '../models/fitness_goal.dart';
import '../services/fitness_repository.dart';
import '../widgets/empty_state.dart';
import '../widgets/friendly_error.dart';

/// Daily/weekly activity targets ("Fitness Goals"), distinct from the
/// smart-scale "Target Weight" set in the profile.
class GoalsPage extends StatefulWidget {
  const GoalsPage({super.key});

  @override
  State<GoalsPage> createState() => _GoalsPageState();
}

class _GoalsPageState extends State<GoalsPage> {
  final FitnessRepository _repository = FitnessRepository();
  String? _openingRecommendation;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fitness Goals')),
      body: StreamBuilder<List<FitnessGoal>>(
        stream: _repository.watchGoals(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return FriendlyErrorState(error: snapshot.error);
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final goals = snapshot.data ?? [];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _GoalRecommendationsSection(
                openingRecommendation: _openingRecommendation,
                onSelected: (recommendation) =>
                    _showRecommendedGoalDialog(context, recommendation),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => _showCustomGoalDialog(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Custom Goal'),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Your Goals',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (goals.isEmpty)
                const EmptyState(
                  icon: Icons.flag_outlined,
                  message:
                      'No fitness goals yet. Add a daily or weekly target.',
                )
              else
                for (final goal in goals) _GoalCard(goal: goal, page: this),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCustomGoalDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Custom Goal'),
      ),
    );
  }

  Future<void> _showCustomGoalDialog(BuildContext context) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _AddGoalDialog(repository: _repository),
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Fitness goal saved.')));
    }
  }

  Future<void> _showRecommendedGoalDialog(
    BuildContext context,
    _GoalRecommendation recommendation,
  ) async {
    if (_openingRecommendation != null) return;
    setState(() => _openingRecommendation = recommendation.title);
    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (_) => _AddGoalDialog(
          repository: _repository,
          recommendation: recommendation,
        ),
      );
      if (saved == true && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${recommendation.title} goal saved.')),
        );
      }
    } finally {
      if (mounted) setState(() => _openingRecommendation = null);
    }
  }

  Future<void> _showProgressDialog(
    BuildContext context,
    FitnessGoal goal,
  ) async {
    final controller = TextEditingController(
      text: _formatNumber(goal.currentValue),
    );
    final value = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Update goal progress'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Current ${goal.unit}'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final progress = double.tryParse(controller.text);
              if (progress != null && progress >= 0) {
                Navigator.pop(dialogContext, progress);
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (value == null) return;

    try {
      await _repository.updateGoalProgress(goal.id, value);
    } catch (error) {
      logDebugError('Update goal failed', error);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't update this goal. Please try again."),
        ),
      );
    }
  }

  Future<void> _resetGoal(BuildContext context, FitnessGoal goal) async {
    try {
      await _repository.resetGoalProgress(goal);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${goal.title} progress reset.')));
    } catch (error) {
      logDebugError('Reset goal failed', error);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't reset this goal. Please try again."),
        ),
      );
    }
  }

  Future<void> _deleteGoal(BuildContext context, FitnessGoal goal) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete goal?'),
        content: Text('Remove "${goal.title}"?'),
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
      await _repository.deleteGoal(goal.id);
    } catch (error) {
      logDebugError('Delete goal failed', error);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't delete this goal. Please try again."),
        ),
      );
    }
  }

  String _formatNumber(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal, required this.page});

  final FitnessGoal goal;
  final _GoalsPageState page;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  goal.isComplete ? Icons.check_circle : Icons.flag_outlined,
                  color: goal.isComplete ? Colors.green : Colors.blue,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    goal.title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (action) {
                    if (action == 'progress') {
                      page._showProgressDialog(context, goal);
                    } else if (action == 'reset') {
                      page._resetGoal(context, goal);
                    } else if (action == 'delete') {
                      page._deleteGoal(context, goal);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'progress',
                      child: Text('Update progress'),
                    ),
                    PopupMenuItem(
                      value: 'reset',
                      child: Text('Reset progress'),
                    ),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Chip(
                  label: Text('${goal.period}: ${goal.periodLabel}'),
                  visualDensity: VisualDensity.compact,
                ),
                Chip(
                  label: Text(goal.statusLabel),
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(
                    goal.isComplete
                        ? Icons.check
                        : goal.isExpired
                        ? Icons.refresh
                        : Icons.play_arrow,
                    size: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${goal.period} goal: '
              '${page._formatNumber(goal.currentValue)} / '
              '${page._formatNumber(goal.targetValue)} ${goal.unit}',
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: goal.progress),
          ],
        ),
      ),
    );
  }
}

class _GoalRecommendation {
  const _GoalRecommendation({
    required this.title,
    required this.targetValue,
    required this.unit,
    required this.period,
    required this.icon,
  });

  final String title;
  final double targetValue;
  final String unit;
  final String period;
  final IconData icon;
}

const List<_GoalRecommendation> _goalRecommendations = [
  _GoalRecommendation(
    title: 'Walk 8,000 steps',
    targetValue: 8000,
    unit: 'steps',
    period: 'Daily',
    icon: Icons.directions_walk,
  ),
  _GoalRecommendation(
    title: 'Drink 2L of water',
    targetValue: 2,
    unit: 'L',
    period: 'Daily',
    icon: Icons.water_drop_outlined,
  ),
  _GoalRecommendation(
    title: 'Burn 300 calories',
    targetValue: 300,
    unit: 'kcal',
    period: 'Daily',
    icon: Icons.local_fire_department_outlined,
  ),
  _GoalRecommendation(
    title: 'Exercise 30 minutes',
    targetValue: 30,
    unit: 'minutes',
    period: 'Daily',
    icon: Icons.timer_outlined,
  ),
  _GoalRecommendation(
    title: 'Log all meals today',
    targetValue: 3,
    unit: 'meals',
    period: 'Daily',
    icon: Icons.restaurant_menu,
  ),
  _GoalRecommendation(
    title: 'Sleep 8 hours',
    targetValue: 8,
    unit: 'hours',
    period: 'Daily',
    icon: Icons.bedtime_outlined,
  ),
  _GoalRecommendation(
    title: 'Workout 4 times this week',
    targetValue: 4,
    unit: 'workouts',
    period: 'Weekly',
    icon: Icons.fitness_center,
  ),
  _GoalRecommendation(
    title: 'Run 10 km this week',
    targetValue: 10,
    unit: 'km',
    period: 'Weekly',
    icon: Icons.directions_run,
  ),
  _GoalRecommendation(
    title: 'Lose 0.5 kg this week',
    targetValue: 0.5,
    unit: 'kg',
    period: 'Weekly',
    icon: Icons.monitor_weight_outlined,
  ),
  _GoalRecommendation(
    title: 'Complete 3 strength sessions',
    targetValue: 3,
    unit: 'sessions',
    period: 'Weekly',
    icon: Icons.sports_gymnastics,
  ),
  _GoalRecommendation(
    title: 'Complete 2 cardio sessions',
    targetValue: 2,
    unit: 'sessions',
    period: 'Weekly',
    icon: Icons.directions_bike,
  ),
  _GoalRecommendation(
    title: 'Stay under calorie target 5 days',
    targetValue: 5,
    unit: 'days',
    period: 'Weekly',
    icon: Icons.check_circle_outline,
  ),
];

class _GoalRecommendationsSection extends StatelessWidget {
  const _GoalRecommendationsSection({
    required this.openingRecommendation,
    required this.onSelected,
  });

  final String? openingRecommendation;
  final ValueChanged<_GoalRecommendation> onSelected;

  @override
  Widget build(BuildContext context) {
    final daily = _goalRecommendations
        .where((recommendation) => recommendation.period == 'Daily')
        .toList();
    final weekly = _goalRecommendations
        .where((recommendation) => recommendation.period == 'Weekly')
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick Add Goals', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _GoalRecommendationGroup(
          title: 'Daily',
          recommendations: daily,
          openingRecommendation: openingRecommendation,
          onSelected: onSelected,
        ),
        const SizedBox(height: 12),
        _GoalRecommendationGroup(
          title: 'Weekly',
          recommendations: weekly,
          openingRecommendation: openingRecommendation,
          onSelected: onSelected,
        ),
      ],
    );
  }
}

class _GoalRecommendationGroup extends StatelessWidget {
  const _GoalRecommendationGroup({
    required this.title,
    required this.recommendations,
    required this.openingRecommendation,
    required this.onSelected,
  });

  final String title;
  final List<_GoalRecommendation> recommendations;
  final String? openingRecommendation;
  final ValueChanged<_GoalRecommendation> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final recommendation in recommendations)
              ActionChip(
                avatar: openingRecommendation == recommendation.title
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(recommendation.icon, size: 18),
                label: Text(recommendation.title),
                onPressed: openingRecommendation == null
                    ? () => onSelected(recommendation)
                    : null,
              ),
          ],
        ),
      ],
    );
  }
}

class _AddGoalDialog extends StatefulWidget {
  const _AddGoalDialog({required this.repository, this.recommendation});

  final FitnessRepository repository;
  final _GoalRecommendation? recommendation;

  @override
  State<_AddGoalDialog> createState() => _AddGoalDialogState();
}

class _AddGoalDialogState extends State<_AddGoalDialog> {
  final _titleController = TextEditingController();
  final _targetController = TextEditingController();
  final _unitController = TextEditingController();
  String _period = 'Daily';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final recommendation = widget.recommendation;
    if (recommendation != null) {
      _titleController.text = recommendation.title;
      _targetController.text = recommendation.targetValue.toString();
      _unitController.text = recommendation.unit;
      _period = recommendation.period;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _targetController.dispose();
    _unitController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    final target = double.tryParse(_targetController.text);
    final unit = _unitController.text.trim();
    if (title.isEmpty || target == null || target <= 0 || unit.isEmpty) {
      _showError('Enter a title, positive target, and unit.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      await widget.repository.addGoal(
        title: title,
        targetValue: target,
        unit: unit,
        period: _period,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      logDebugError('Save goal failed', error);
      _showError("Couldn't save this goal. Please try again.");
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
      title: Text(
        widget.recommendation == null ? 'Add fitness goal' : 'Confirm goal',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Goal title',
                hintText: 'Example: Drink water',
              ),
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
              decoration: const InputDecoration(
                labelText: 'Unit',
                hintText: 'Example: steps, km, glasses',
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
