import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small app preferences stored with SharedPreferences (course topic:
/// key-value persistence). Only lightweight UI settings live here —
/// user fitness data stays in Firestore.
class AppPreferences {
  AppPreferences._(this._prefs);

  static const String _themeModeKey = 'theme_mode';
  static const String _lastTabIndexKey = 'last_tab_index';
  static const String _dailyWaterGoalKey = 'daily_water_goal_ml';

  static const int defaultWaterGoalMl = 2500;

  static AppPreferences? _instance;

  static AppPreferences get instance {
    final current = _instance;
    if (current == null) {
      throw StateError('AppPreferences.init() must be called before use.');
    }
    return current;
  }

  /// Loads the preference store once at app launch.
  static Future<void> init() async {
    _instance ??= AppPreferences._(await SharedPreferences.getInstance());
  }

  final SharedPreferences _prefs;

  ThemeMode get themeMode {
    return switch (_prefs.getString(_themeModeKey)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setThemeMode(ThemeMode mode) {
    return _prefs.setString(_themeModeKey, mode.name);
  }

  int get lastTabIndex {
    final stored = _prefs.getInt(_lastTabIndexKey) ?? 0;
    return stored.clamp(0, 4);
  }

  Future<void> setLastTabIndex(int index) {
    return _prefs.setInt(_lastTabIndexKey, index);
  }

  int get dailyWaterGoalMl {
    final stored = _prefs.getInt(_dailyWaterGoalKey) ?? defaultWaterGoalMl;
    return stored > 0 ? stored : defaultWaterGoalMl;
  }

  Future<void> setDailyWaterGoalMl(int goalMl) {
    return _prefs.setInt(_dailyWaterGoalKey, goalMl);
  }
}
