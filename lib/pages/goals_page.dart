import 'package:flutter/material.dart';

import '../models/fitness_goal.dart';
import '../services/fitness_repository.dart';

class GoalsPage extends StatelessWidget {
  GoalsPage({super.key});

  final FitnessRepository _repository = FitnessRepository();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Daily & Weekly Goals')),
      body: StreamBuilder<List<FitnessGoal>>(
        stream: _repository.watchGoals(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final goals = snapshot.data ?? [];
          if (goals.isEmpty) {
            return const _EmptyState();
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: goals.length,
            itemBuilder: (context, index) {
              final goal = goals[index];
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
                            goal.isComplete
                                ? Icons.check_circle
                                : Icons.flag_outlined,
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
                                _showProgressDialog(context, goal);
                              } else if (action == 'delete') {
                                _deleteGoal(context, goal);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'progress',
                                child: Text('Update progress'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${goal.period} goal: '
                        '${_formatNumber(goal.currentValue)} / '
                        '${_formatNumber(goal.targetValue)} ${goal.unit}',
                      ),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(value: goal.progress),
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
          builder: (_) => _AddGoalDialog(repository: _repository),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add goal'),
      ),
    );
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
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not update goal: $error')));
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
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not delete goal: $error')));
    }
  }

  String _formatNumber(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
  }
}

class _AddGoalDialog extends StatefulWidget {
  const _AddGoalDialog({required this.repository});

  final FitnessRepository repository;

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
      if (mounted) Navigator.pop(context);
    } catch (error) {
      _showError('Could not save goal: $error');
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
      title: const Text('Add fitness goal'),
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
            Icon(Icons.flag_outlined, size: 56, color: Colors.blue),
            SizedBox(height: 16),
            Text(
              'No goals yet. Add a daily or weekly fitness target.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
