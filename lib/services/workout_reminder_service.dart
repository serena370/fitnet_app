import 'reminder_scheduler.dart';

class WorkoutReminderService {
  static void scheduleWorkoutReminder({
    required String workoutId,
    required String activityType,
    required DateTime reminderAt,
  }) {
    final notificationId = workoutId.hashCode & 0x7fffffff;

    // OS-scheduled notification (with in-memory fallback) so the reminder
    // still fires if the app is closed before the chosen time.
    ReminderScheduler.schedule(
      notificationId: notificationId,
      title: 'Workout Reminder',
      body: 'Time for your $activityType workout.',
      reminderAt: reminderAt,
      channelId: 'workout_reminder_channel',
      channelName: 'Workout Reminders',
      channelDescription: 'Reminders for planned workouts',
    );
  }
}
