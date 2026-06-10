import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../main.dart' show notificationsPlugin;

/// Schedules reminders through the OS (course topic: background services).
///
/// Prefers `zonedSchedule`, so the notification fires even if the app is
/// closed. Uses the inexact Android schedule mode on purpose: it requires no
/// extra manifest permissions. If OS scheduling fails for any reason, it
/// falls back to the previous in-memory [Timer] behavior so reminders keep
/// working while the app is open.
///
/// This service is intentionally separate from the MQTT weight notification
/// logic in main.dart, which is left untouched.
class ReminderScheduler {
  ReminderScheduler._();

  static final Map<int, Timer> _fallbackTimers = {};

  /// Returns true when the reminder was handed to the OS, false when the
  /// in-memory fallback timer is being used instead.
  static Future<bool> schedule({
    required int notificationId,
    required String title,
    required String body,
    required DateTime reminderAt,
    required String channelId,
    required String channelName,
    required String channelDescription,
  }) async {
    final delay = reminderAt.difference(DateTime.now());
    if (delay.isNegative) return false;

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.max,
        priority: Priority.high,
      ),
    );

    await cancel(notificationId);

    try {
      // Scheduling "now + delay" keeps the absolute fire time correct even
      // though tz.local is not mapped to the device's named timezone.
      await notificationsPlugin.zonedSchedule(
        notificationId,
        title,
        body,
        tz.TZDateTime.now(tz.local).add(delay),
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      return true;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('OS reminder scheduling failed, using timer: $error');
      }
      _fallbackTimers[notificationId] = Timer(delay, () {
        notificationsPlugin.show(notificationId, title, body, details);
        _fallbackTimers.remove(notificationId);
      });
      return false;
    }
  }

  static Future<void> cancel(int notificationId) async {
    _fallbackTimers.remove(notificationId)?.cancel();
    try {
      await notificationsPlugin.cancel(notificationId);
    } catch (error) {
      if (kDebugMode) debugPrint('Reminder cancel skipped: $error');
    }
  }
}
