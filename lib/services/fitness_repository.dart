import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/fitness_goal.dart';
import '../models/meal.dart';
import '../models/workout.dart';

class FitnessRepository {
  FitnessRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String get _userId {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('You must be logged in to manage fitness data.');
    }
    return user.uid;
  }

  Stream<List<Workout>> watchWorkouts() {
    return _firestore
        .collection('workouts')
        .where('userId', isEqualTo: _userId)
        .snapshots()
        .map((snapshot) {
          final workouts = snapshot.docs.map(Workout.fromFirestore).toList();
          workouts.sort((a, b) => b.date.compareTo(a.date));
          return workouts;
        });
  }

  Future<Workout> addWorkout({
    required String activityType,
    required int durationMinutes,
    required int caloriesBurned,
    String notes = '',
    DateTime? reminderAt,
  }) async {
    final workout = Workout(
      id: '',
      userId: _userId,
      activityType: activityType,
      durationMinutes: durationMinutes,
      caloriesBurned: caloriesBurned,
      date: DateTime.now(),
      notes: notes,
      reminderAt: reminderAt,
    );

    final document = await _firestore
        .collection('workouts')
        .add(workout.toFirestore());

    return Workout(
      id: document.id,
      userId: workout.userId,
      activityType: workout.activityType,
      durationMinutes: workout.durationMinutes,
      caloriesBurned: workout.caloriesBurned,
      date: workout.date,
      notes: workout.notes,
      reminderAt: workout.reminderAt,
    );
  }

  Future<Workout> saveAiWorkoutPlan(String planText) {
    return addWorkout(
      activityType: 'AI Plan',
      durationMinutes: 0,
      caloriesBurned: 0,
      notes: planText,
    );
  }

  Stream<List<Meal>> watchMeals() {
    return _firestore
        .collection('meals')
        .where('userId', isEqualTo: _userId)
        .snapshots()
        .map((snapshot) {
          final meals = snapshot.docs.map(Meal.fromFirestore).toList();
          meals.sort((a, b) => b.date.compareTo(a.date));
          return meals;
        });
  }

  Future<void> addMeal({
    required String name,
    required String mealType,
    required int calories,
    String notes = '',
  }) async {
    final meal = Meal(
      id: '',
      userId: _userId,
      name: name,
      mealType: mealType,
      calories: calories,
      date: DateTime.now(),
      notes: notes,
    );

    await _firestore.collection('meals').add(meal.toFirestore());
  }

  Stream<List<FitnessGoal>> watchGoals() {
    return _firestore
        .collection('goals')
        .where('userId', isEqualTo: _userId)
        .snapshots()
        .map((snapshot) {
          final goals = snapshot.docs.map(FitnessGoal.fromFirestore).toList();
          goals.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return goals;
        });
  }

  Future<void> addGoal({
    required String title,
    required double targetValue,
    required String unit,
    required String period,
  }) async {
    final goal = FitnessGoal(
      id: '',
      userId: _userId,
      title: title,
      targetValue: targetValue,
      currentValue: 0,
      unit: unit,
      period: period,
      createdAt: DateTime.now(),
      resetAt: _nextResetAt(period),
    );

    await _firestore.collection('goals').add(goal.toFirestore());
  }

  Future<void> updateGoalProgress(String goalId, double currentValue) async {
    await _updateOwnedDocument(
      collection: 'goals',
      documentId: goalId,
      values: {'currentValue': currentValue},
    );
  }

  Future<void> resetGoalProgress(FitnessGoal goal) async {
    await _updateOwnedDocument(
      collection: 'goals',
      documentId: goal.id,
      values: {
        'currentValue': 0,
        'createdAt': Timestamp.fromDate(DateTime.now()),
        'resetAt': Timestamp.fromDate(_nextResetAt(goal.period)),
      },
    );
  }

  Future<void> updateWorkoutReminder(
    String workoutId,
    DateTime reminderAt,
  ) async {
    await _updateOwnedDocument(
      collection: 'workouts',
      documentId: workoutId,
      values: {'reminderAt': Timestamp.fromDate(reminderAt)},
    );
  }

  Future<FitnessStats> loadDashboardStats() async {
    final userId = _userId;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final tomorrowStart = todayStart.add(const Duration(days: 1));
    final weekStart = todayStart.subtract(
      Duration(days: todayStart.weekday - 1),
    );
    final nextWeekStart = weekStart.add(const Duration(days: 7));

    final mealsSnapshot = await _firestore
        .collection('meals')
        .where('userId', isEqualTo: userId)
        .get();
    final workoutsSnapshot = await _firestore
        .collection('workouts')
        .where('userId', isEqualTo: userId)
        .get();
    final goalsSnapshot = await _firestore
        .collection('goals')
        .where('userId', isEqualTo: userId)
        .get();

    var caloriesEatenToday = 0;
    for (final doc in mealsSnapshot.docs) {
      final data = doc.data();
      final date = _readDate(data['date']) ?? _readDate(data['timestamp']);
      if (date != null &&
          !date.isBefore(todayStart) &&
          date.isBefore(tomorrowStart)) {
        caloriesEatenToday += (data['calories'] as num?)?.toInt() ?? 0;
      }
    }

    var workoutsThisWeek = 0;
    var caloriesBurnedThisWeek = 0;
    for (final doc in workoutsSnapshot.docs) {
      final data = doc.data();
      final date = _readDate(data['date']) ?? _readDate(data['timestamp']);
      if (date != null &&
          !date.isBefore(weekStart) &&
          date.isBefore(nextWeekStart)) {
        workoutsThisWeek += 1;
        caloriesBurnedThisWeek +=
            (data['caloriesBurned'] as num?)?.toInt() ?? 0;
      }
    }

    var activeGoals = 0;
    var completedGoals = 0;
    for (final doc in goalsSnapshot.docs) {
      final goal = FitnessGoal.fromFirestore(doc);
      if (goal.isComplete) {
        completedGoals += 1;
      } else if (!goal.isExpired) {
        activeGoals += 1;
      }
    }

    return FitnessStats(
      caloriesEatenToday: caloriesEatenToday,
      workoutsThisWeek: workoutsThisWeek,
      caloriesBurnedThisWeek: caloriesBurnedThisWeek,
      activeGoals: activeGoals,
      completedGoals: completedGoals,
    );
  }

  Future<void> deleteWorkout(String workoutId) {
    return _deleteOwnedDocument('workouts', workoutId);
  }

  Future<void> deleteMeal(String mealId) {
    return _deleteOwnedDocument('meals', mealId);
  }

  Future<void> deleteGoal(String goalId) {
    return _deleteOwnedDocument('goals', goalId);
  }

  Future<void> _deleteOwnedDocument(
    String collection,
    String documentId,
  ) async {
    final reference = _firestore.collection(collection).doc(documentId);
    final snapshot = await reference.get();
    if (snapshot.data()?['userId'] != _userId) {
      throw StateError('This entry does not belong to the current user.');
    }
    await reference.delete();
  }

  Future<void> _updateOwnedDocument({
    required String collection,
    required String documentId,
    required Map<String, dynamic> values,
  }) async {
    final reference = _firestore.collection(collection).doc(documentId);
    final snapshot = await reference.get();
    if (snapshot.data()?['userId'] != _userId) {
      throw StateError('This entry does not belong to the current user.');
    }
    await reference.update(values);
  }

  DateTime _nextResetAt(String period) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    if (period == 'Weekly') {
      return todayStart.add(Duration(days: 8 - todayStart.weekday));
    }
    return todayStart.add(const Duration(days: 1));
  }

  DateTime? _readDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}

class FitnessStats {
  const FitnessStats({
    required this.caloriesEatenToday,
    required this.workoutsThisWeek,
    required this.caloriesBurnedThisWeek,
    required this.activeGoals,
    required this.completedGoals,
  });

  final int caloriesEatenToday;
  final int workoutsThisWeek;
  final int caloriesBurnedThisWeek;
  final int activeGoals;
  final int completedGoals;
}
