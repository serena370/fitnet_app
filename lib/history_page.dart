import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'models/fitness_goal.dart';
import 'models/meal.dart';
import 'models/workout.dart';
import 'services/fitness_repository.dart';
import 'utils/date_time_format.dart';

class HistoryPage extends StatelessWidget {
  HistoryPage({super.key});

  final FitnessRepository _repository = FitnessRepository();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Fitness History'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Weight'),
              Tab(text: 'Workouts'),
              Tab(text: 'Meals'),
              Tab(text: 'Goals'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            const _WeightHistoryTab(),
            _WorkoutHistoryTab(repository: _repository),
            _MealHistoryTab(repository: _repository),
            _GoalHistoryTab(repository: _repository),
          ],
        ),
      ),
    );
  }
}

class _WeightHistoryTab extends StatelessWidget {
  const _WeightHistoryTab();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Please log in to see history'));
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('weights')
          .where('userId', isEqualTo: user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final sortedDocs = List.of(snapshot.data?.docs ?? []);
        sortedDocs.sort((a, b) {
          final firstTimestamp = a.data()['timestamp'];
          final secondTimestamp = b.data()['timestamp'];
          final firstDate = firstTimestamp is Timestamp
              ? firstTimestamp.toDate()
              : DateTime.now();
          final secondDate = secondTimestamp is Timestamp
              ? secondTimestamp.toDate()
              : DateTime.now();
          return firstDate.compareTo(secondDate);
        });

        if (sortedDocs.isEmpty) {
          return const Center(child: Text('No weight records found.'));
        }

        final weightSpots = <FlSpot>[];
        for (var index = 0; index < sortedDocs.length; index++) {
          final weight = sortedDocs[index].data()['weight'];
          if (weight is num) {
            weightSpots.add(FlSpot(index.toDouble(), weight.toDouble()));
          }
        }

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (weightSpots.isNotEmpty)
                SizedBox(
                  height: 250,
                  child: LineChart(
                    LineChartData(
                      gridData: const FlGridData(show: true),
                      borderData: FlBorderData(show: true),
                      lineBarsData: [
                        LineChartBarData(
                          spots: weightSpots,
                          isCurved: true,
                          barWidth: 4,
                          color: Colors.blue,
                          dotData: const FlDotData(show: true),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              Expanded(
                child: ListView.builder(
                  itemCount: sortedDocs.length,
                  itemBuilder: (context, index) {
                    final data = sortedDocs[sortedDocs.length - 1 - index]
                        .data();
                    final timestamp = data['timestamp'];
                    final weight = data['weight'];
                    final bmi = data['bmi'];

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.monitor_weight),
                        ),
                        title: Text(
                          '$weight kg',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          'BMI: ${bmi is num ? bmi.toStringAsFixed(1) : '--'}\n'
                          '${timestamp is Timestamp ? formatDateTime(timestamp.toDate()) : 'Saving...'}',
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WorkoutHistoryTab extends StatelessWidget {
  const _WorkoutHistoryTab({required this.repository});

  final FitnessRepository repository;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Workout>>(
      stream: repository.watchWorkouts(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final workouts = snapshot.data ?? [];
        if (workouts.isEmpty) {
          return const Center(child: Text('No workout history found.'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: workouts.length,
          itemBuilder: (context, index) {
            final workout = workouts[index];
            return Card(
              child: ListTile(
                leading: const Icon(Icons.fitness_center, color: Colors.blue),
                title: Text(workout.activityType),
                subtitle: Text(
                  '${workout.durationMinutes} min - '
                  '${workout.caloriesBurned} kcal\n'
                  '${formatDateTime(workout.date)}',
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _MealHistoryTab extends StatelessWidget {
  const _MealHistoryTab({required this.repository});

  final FitnessRepository repository;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Meal>>(
      stream: repository.watchMeals(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final meals = snapshot.data ?? [];
        if (meals.isEmpty) {
          return const Center(child: Text('No meal history found.'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: meals.length,
          itemBuilder: (context, index) {
            final meal = meals[index];
            return Card(
              child: ListTile(
                leading: const Icon(Icons.restaurant, color: Colors.blue),
                title: Text(meal.name),
                subtitle: Text(
                  '${meal.mealType} - ${meal.calories} kcal\n'
                  '${formatDateTime(meal.date)}',
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _GoalHistoryTab extends StatelessWidget {
  const _GoalHistoryTab({required this.repository});

  final FitnessRepository repository;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FitnessGoal>>(
      stream: repository.watchGoals(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final goals = snapshot.data ?? [];
        if (goals.isEmpty) {
          return const Center(child: Text('No goal history found.'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: goals.length,
          itemBuilder: (context, index) {
            final goal = goals[index];
            return Card(
              child: ListTile(
                leading: Icon(
                  goal.isComplete ? Icons.check_circle : Icons.flag_outlined,
                  color: goal.isComplete ? Colors.green : Colors.blue,
                ),
                title: Text(goal.title),
                subtitle: Text(
                  '${goal.period}: ${goal.currentValue} / '
                  '${goal.targetValue} ${goal.unit}',
                ),
              ),
            );
          },
        );
      },
    );
  }
}
