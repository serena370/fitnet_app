import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../main.dart' show notificationsPlugin;

class WorkoutReminderService {
  static final Map<int, Timer> _timers = {};

  static void scheduleWorkoutReminder({
    required String workoutId,
    required String activityType,
    required DateTime reminderAt,
  }) {
    final delay = reminderAt.difference(DateTime.now());
    if (delay.isNegative) return;

    final notificationId = workoutId.hashCode & 0x7fffffff;
    _timers[notificationId]?.cancel();

    // App-session timer keeps this small and avoids exact-alarm Android setup.
    _timers[notificationId] = Timer(delay, () {
      notificationsPlugin.show(
        notificationId,
        'Workout Reminder',
        'Time for your $activityType workout.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'workout_reminder_channel',
            'Workout Reminders',
            channelDescription: 'Reminders for planned workouts',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
      );
      _timers.remove(notificationId);
    });
  }
}
