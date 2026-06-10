import 'package:flutter/material.dart';

import '../history_page.dart';
import '../measurement_page.dart';
import '../nearby_gyms_page.dart';
import '../pages/goals_page.dart';
import '../pages/meal_scan_page.dart';
import '../pages/meals_page.dart';
import '../pages/settings_page.dart';
import '../pages/workouts_page.dart';
import '../profile_page.dart';
import '../water_page.dart';

/// Named routes (course topic: navigation between screens).
///
/// Screens still communicate through constructor arguments and
/// `Navigator.pop` return values — for example [ProfilePage] pops `true`
/// after saving so callers can refresh, and [MealScanPage] pops `true`
/// after logging a meal.
class AppRoutes {
  AppRoutes._();

  static const String profile = '/profile';
  static const String settings = '/settings';
  static const String fitnessGoals = '/fitness-goals';
  static const String workouts = '/workouts';
  static const String nearbyGyms = '/nearby-gyms';
  static const String meals = '/meals';
  static const String mealScan = '/meal-scan';
  static const String weightHistory = '/weight-history';
  static const String water = '/water';
  static const String measurements = '/measurements';

  static Map<String, WidgetBuilder> get table => {
    profile: (_) => ProfilePage(),
    settings: (_) => const SettingsPage(),
    fitnessGoals: (_) => GoalsPage(),
    workouts: (_) => WorkoutsPage(),
    nearbyGyms: (_) => const NearbyGymsPage(),
    meals: (_) => MealsPage(),
    mealScan: (_) => const MealScanPage(),
    weightHistory: (_) => const HistoryPage(),
    water: (_) => const WaterPage(),
    measurements: (_) => const MeasurementsPage(),
  };
}
