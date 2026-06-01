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

  Future<void> addWorkout({
    required String activityType,
    required int durationMinutes,
    required int caloriesBurned,
    String notes = '',
  }) async {
    final workout = Workout(
      id: '',
      userId: _userId,
      activityType: activityType,
      durationMinutes: durationMinutes,
      caloriesBurned: caloriesBurned,
      date: DateTime.now(),
      notes: notes,
    );

    await _firestore.collection('workouts').add(workout.toFirestore());
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
}
